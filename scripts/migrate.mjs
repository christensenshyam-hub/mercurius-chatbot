#!/usr/bin/env node
/**
 * migrate.mjs — apply migrations/*.sql, once each, in filename order.
 *
 * Usage:
 *   node scripts/migrate.mjs            (npm run migrate) — DATABASE_URL target
 *   SQLITE_PATH=/tmp/x.db node scripts/migrate.mjs      — a local SQLite file
 *   node scripts/migrate.mjs --sqlite   — the default local mercurius.db
 *
 * Driver selection is db.js's: DATABASE_URL set → Postgres (production);
 * otherwise better-sqlite3 at SQLITE_PATH (default mercurius.db). The script
 * reuses db.js's connection through its runRaw/queryRaw escape hatches, so
 * the env handling can never drift from the server's.
 *
 * Target guard (runs BEFORE db.js is loaded, because loading it opens the
 * database): an EMPTY DATABASE_URL is refused unless SQLite was asked for
 * explicitly (SQLITE_PATH set, or --sqlite). Otherwise a mistyped
 * `DATABASE_URL=$UNSET_VAR npm run migrate` "succeeds" against a throwaway
 * local file and reports migrations as applied that never touched
 * production. SQLite is always refused under NODE_ENV=production, and
 * --sqlite together with a DATABASE_URL is refused as ambiguous. The chosen
 * target (driver + host/database, never the password) is printed first.
 *
 * Contract:
 *   1. The base schema is code-owned (db.initSchema, CREATE IF NOT EXISTS at
 *      server boot); migrations/*.sql are the operator-run deltas on top of
 *      it. On a FRESH database (no `sessions` table) the script bootstraps
 *      the base schema first so the deltas have their prerequisites (001's
 *      REFERENCES sessions(...) would otherwise fail on Postgres). On an
 *      existing database it deliberately does NOT re-run initSchema: a
 *      CREATE IF NOT EXISTS there could resurrect a table a recorded
 *      migration dropped, and the server boot already owns that step.
 *   2. schema_migrations(name TEXT PRIMARY KEY, applied_at BIGINT) is created
 *      if missing; a migration whose filename is already listed is skipped.
 *   3. Each remaining file is applied together with its schema_migrations row
 *      in ONE runRaw call — atomic on both drivers — so a failed migration is
 *      neither half-applied nor recorded. Migration files therefore must not
 *      contain their own BEGIN/COMMIT.
 *   4. A migration written with IF NOT EXISTS / IF EXISTS (all of ours) is a
 *      no-op against a database where an operator already ran it by hand; it
 *      is still recorded, which is how a pre-existing 001 gets bookkept.
 *
 * Exit code 0 when every migration is applied or already recorded, 1 on a
 * refused target, on a connection error, or on the first failed migration
 * (later files are not attempted). Output is the target line plus one line
 * per file on stdout; errors go to stderr.
 */

import { readdir, readFile } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// Decide (and describe) the target from the environment alone. Returns
// { ok: true, label } or { ok: false, reason }. Pure, so the refusal rules
// are testable without touching a database.
export function resolveTarget(env = process.env, argv = process.argv.slice(2)) {
  const url = (env.DATABASE_URL || '').trim();
  const wantSqlite = argv.includes('--sqlite');
  const sqlitePath = (env.SQLITE_PATH || '').trim();
  if (url) {
    if (wantSqlite) return { ok: false, reason: '--sqlite was given but DATABASE_URL is set; unset one of them' };
    let label = 'postgres (unparseable DATABASE_URL)';
    try {
      const u = new URL(url);
      label = `postgres @ ${u.hostname}${u.port ? ':' + u.port : ''}${u.pathname || ''}`;
    } catch { /* keep the generic label; never echo the raw URL (it holds the password) */ }
    return { ok: true, label };
  }
  if (env.NODE_ENV === 'production') {
    return { ok: false, reason: 'NODE_ENV=production and DATABASE_URL is empty; refusing to migrate a local SQLite file instead of Postgres' };
  }
  if (!sqlitePath && !wantSqlite) {
    return {
      ok: false,
      reason: 'DATABASE_URL is empty. Refusing to fall back to a local SQLite file silently. '
        + 'Point DATABASE_URL at the database to migrate, or pass --sqlite / set SQLITE_PATH to migrate a local SQLite file on purpose',
    };
  }
  return { ok: true, label: `sqlite ${sqlitePath || path.join(ROOT, 'mercurius.db')}` };
}

let db = null; // loaded in main(), after the target guard

const MIGRATIONS_DIR = path.join(ROOT, 'migrations');

// NNN_snake_name.sql — the same validated name is inlined into the
// schema_migrations INSERT, so the pattern doubles as the injection guard.
const MIGRATION_FILE = /^\d+_[A-Za-z0-9_-]+\.sql$/;

async function listMigrationFiles() {
  const entries = await readdir(MIGRATIONS_DIR);
  return entries.filter((f) => MIGRATION_FILE.test(f)).sort();
}

// True when the code-owned base schema is present (any driver): a probe of
// the root table. ONLY an undefined-table error means "fresh database"
// (Postgres SQLSTATE 42P01, SQLite "no such table"). Anything else — DNS
// failure (ENOTFOUND postgres.railway.internal from a laptop), refused
// connection, bad password, timeout — is rethrown so it fails loudly instead
// of being reported as "fresh database: bootstrapping".
export function isUndefinedTableError(err) {
  if (!err) return false;
  if (err.code === '42P01') return true;
  return /no such table/i.test(String(err.message || ''));
}

async function hasBaseSchema() {
  try {
    await db.queryRaw('SELECT 1 FROM sessions LIMIT 1');
    return true;
  } catch (err) {
    if (isUndefinedTableError(err)) return false;
    throw err;
  }
}

async function main() {
  const target = resolveTarget();
  if (!target.ok) {
    console.error(`migrate: REFUSED — ${target.reason}`);
    process.exit(1);
  }
  console.log(`migrate: target ${target.label}`);
  db = require('../db.js');

  if (!(await hasBaseSchema())) {
    console.log('fresh database: bootstrapping base schema (db.initSchema) before migrations');
    await db.initSchema();
  }
  await db.runRaw('CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at BIGINT NOT NULL)');

  const applied = new Set((await db.queryRaw('SELECT name FROM schema_migrations')).map((r) => r.name));
  const files = await listMigrationFiles();

  let appliedNow = 0;
  for (const name of files) {
    if (applied.has(name)) {
      console.log(`skip    ${name} (already applied)`);
      continue;
    }
    const sql = await readFile(path.join(MIGRATIONS_DIR, name), 'utf8');
    await db.runRaw(
      `${sql}\n` +
      `INSERT INTO schema_migrations (name, applied_at) VALUES ('${name}', ${Date.now()});`,
    );
    console.log(`applied ${name}`);
    appliedNow += 1;
  }
  console.log(`migrate: ${appliedNow} applied, ${files.length - appliedNow} already applied`);
}

// Run only as a script (node scripts/migrate.mjs), not when a test imports
// resolveTarget / isUndefinedTableError. Compare REAL paths: Node resolves
// symlinks for import.meta.url but not for argv[1] (macOS /tmp → /private/tmp),
// and a plain comparison would silently skip main() and exit 0.
function isMainModule() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}
if (isMainModule()) {
  main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(`migrate: FAILED — ${err && err.stack ? err.stack : err}`);
      process.exit(1);
    });
}
