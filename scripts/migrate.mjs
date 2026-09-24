#!/usr/bin/env node
/**
 * migrate.mjs — apply migrations/*.sql, once each, in filename order.
 *
 * Usage:
 *   node scripts/migrate.mjs            (npm run migrate)
 *
 * Driver selection is db.js's: DATABASE_URL set → Postgres (production);
 * otherwise better-sqlite3 at SQLITE_PATH (default mercurius.db). The script
 * reuses db.js's connection through its runRaw/queryRaw escape hatches, so
 * the env handling can never drift from the server's.
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
 * Exit code 0 when every migration is applied or already recorded, 1 on the
 * first failure (later files are not attempted). Output is one line per file
 * on stdout; errors go to stderr.
 */

import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const db = require('../db.js');

const MIGRATIONS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');

// NNN_snake_name.sql — the same validated name is inlined into the
// schema_migrations INSERT, so the pattern doubles as the injection guard.
const MIGRATION_FILE = /^\d+_[A-Za-z0-9_-]+\.sql$/;

async function listMigrationFiles() {
  const entries = await readdir(MIGRATIONS_DIR);
  return entries.filter((f) => MIGRATION_FILE.test(f)).sort();
}

// True when the code-owned base schema is present (any driver): a probe of
// the root table. A missing table throws on both pg and better-sqlite3.
async function hasBaseSchema() {
  try {
    await db.queryRaw('SELECT 1 FROM sessions LIMIT 1');
    return true;
  } catch {
    return false;
  }
}

async function main() {
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

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(`migrate: FAILED — ${err && err.stack ? err.stack : err}`);
    process.exit(1);
  });
