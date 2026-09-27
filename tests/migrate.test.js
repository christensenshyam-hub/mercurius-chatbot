'use strict';

// Tests for scripts/migrate.mjs: applies migrations/*.sql once each on a temp
// SQLite db, is idempotent on a second run, drops student_memory (002) and
// bookkeeps both files in schema_migrations. Also its target guard: an empty
// DATABASE_URL is refused unless SQLite is explicit, SQLite is refused under
// NODE_ENV=production, and a connection error is a failure, never "fresh
// database".
//
// The db is seeded through db.initSchema() so the student_memory table the
// migration targets really exists before the script runs; the script is
// spawned as a child process exactly the way `npm run migrate` would run it.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const dbPath = path.join(os.tmpdir(), `merc-migrate-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');

function runMigrate(env = {}, args = []) {
  return new Promise((resolve, reject) => {
    const proc = spawn(process.execPath, ['scripts/migrate.mjs', ...args], {
      cwd: ROOT,
      env: { ...process.env, DATABASE_URL: '', SQLITE_PATH: dbPath, NODE_ENV: 'test', ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = ''; let stderr = '';
    proc.stdout.on('data', (c) => { stdout += c.toString(); });
    proc.stderr.on('data', (c) => { stderr += c.toString(); });
    proc.on('error', reject);
    proc.on('exit', (code) => resolve({ code, stdout, stderr }));
  });
}

describe('scripts/migrate.mjs', () => {
  before(async () => {
    await db.initSchema();
    // initSchema no longer creates student_memory; stand in for a production
    // database that still carries the legacy table so 002 has something to drop.
    await db.runRaw(`CREATE TABLE IF NOT EXISTS student_memory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      memory_type TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )`);
    const seeded = await db.queryRaw("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'student_memory'");
    assert.equal(seeded.length, 1, 'precondition: legacy student_memory table present');
  });
  after(() => {
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('first run applies both migrations and records them', async () => {
    const r = await runMigrate();
    assert.equal(r.code, 0, `exit 0\n${r.stdout}\n${r.stderr}`);
    assert.equal(r.stdout.split('\n')[0], `migrate: target sqlite ${dbPath}`, 'target printed first');
    assert.match(r.stdout, /applied 001_gamification\.sql/);
    assert.match(r.stdout, /applied 002_drop_student_memory\.sql/);

    const tables = new Set((await db.queryRaw("SELECT name FROM sqlite_master WHERE type = 'table'")).map((t) => t.name));
    assert.ok(!tables.has('student_memory'), 'student_memory dropped');
    assert.ok(tables.has('progression') && tables.has('xp_ledger'), '001 tables present');
    assert.ok(tables.has('schema_migrations'));

    const applied = await db.queryRaw('SELECT name, applied_at FROM schema_migrations ORDER BY name');
    assert.deepEqual(applied.map((a) => a.name), ['001_gamification.sql', '002_drop_student_memory.sql']);
    for (const a of applied) assert.ok(Number(a.applied_at) > 0, 'applied_at stamped');
  });

  test('second run is idempotent: skips both, exit 0, nothing re-applied', async () => {
    const r = await runMigrate();
    assert.equal(r.code, 0, `exit 0\n${r.stdout}\n${r.stderr}`);
    assert.match(r.stdout, /skip\s+001_gamification\.sql/);
    assert.match(r.stdout, /skip\s+002_drop_student_memory\.sql/);
    assert.doesNotMatch(r.stdout, /^applied /m);

    const applied = await db.queryRaw('SELECT name FROM schema_migrations ORDER BY name');
    assert.deepEqual(applied.map((a) => a.name), ['001_gamification.sql', '002_drop_student_memory.sql']);
    const tables = new Set((await db.queryRaw("SELECT name FROM sqlite_master WHERE type = 'table'")).map((t) => t.name));
    assert.ok(!tables.has('student_memory'), 'still gone');
  });

  test('a pre-existing 001 (operator ran it by hand) is bookkept without failing', async () => {
    // Forget the bookkeeping but keep the tables: the next run must re-apply
    // 001's IF NOT EXISTS DDL as a no-op and record it again.
    await db.runRaw("DELETE FROM schema_migrations WHERE name = '001_gamification.sql'");
    const r = await runMigrate();
    assert.equal(r.code, 0, `exit 0\n${r.stdout}\n${r.stderr}`);
    assert.match(r.stdout, /applied 001_gamification\.sql/);
    assert.match(r.stdout, /skip\s+002_drop_student_memory\.sql/);
    const applied = await db.queryRaw('SELECT name FROM schema_migrations ORDER BY name');
    assert.deepEqual(applied.map((a) => a.name), ['001_gamification.sql', '002_drop_student_memory.sql']);
  });
});

describe('scripts/migrate.mjs target guard', () => {
  let resolveTarget, isUndefinedTableError;
  before(async () => {
    ({ resolveTarget, isUndefinedTableError } = await import('../scripts/migrate.mjs'));
  });

  test('resolveTarget: Postgres label never includes the password', () => {
    const t = resolveTarget({ DATABASE_URL: 'postgresql://postgres:s3cret@postgres.railway.internal:5432/railway' }, []);
    assert.deepEqual(t, { ok: true, label: 'postgres @ postgres.railway.internal:5432/railway' });
  });

  test('resolveTarget: empty DATABASE_URL is refused unless SQLite is explicit', () => {
    assert.equal(resolveTarget({ DATABASE_URL: '' }, []).ok, false);
    assert.equal(resolveTarget({}, []).ok, false);
    assert.equal(resolveTarget({ DATABASE_URL: '   ' }, []).ok, false, 'whitespace counts as empty');
    assert.deepEqual(resolveTarget({ SQLITE_PATH: '/tmp/a.db' }, []), { ok: true, label: 'sqlite /tmp/a.db' });
    const flag = resolveTarget({}, ['--sqlite']);
    assert.equal(flag.ok, true);
    assert.match(flag.label, /^sqlite .*mercurius\.db$/);
  });

  test('resolveTarget: SQLite is refused under NODE_ENV=production, and --sqlite + DATABASE_URL is ambiguous', () => {
    assert.equal(resolveTarget({ NODE_ENV: 'production', SQLITE_PATH: '/tmp/a.db' }, ['--sqlite']).ok, false);
    assert.equal(resolveTarget({ NODE_ENV: 'production', DATABASE_URL: 'postgres://h/db' }, []).ok, true);
    assert.equal(resolveTarget({ DATABASE_URL: 'postgres://h/db' }, ['--sqlite']).ok, false);
  });

  test('isUndefinedTableError: only a missing table means "fresh database"', () => {
    assert.equal(isUndefinedTableError({ code: '42P01', message: 'relation "sessions" does not exist' }), true);
    assert.equal(isUndefinedTableError(new Error('no such table: sessions')), true);
    assert.equal(isUndefinedTableError(Object.assign(new Error('getaddrinfo ENOTFOUND postgres.railway.internal'), { code: 'ENOTFOUND' })), false);
    assert.equal(isUndefinedTableError(Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' })), false);
    assert.equal(isUndefinedTableError({ code: '28P01', message: 'password authentication failed' }), false);
    assert.equal(isUndefinedTableError(null), false);
  });

  test('an empty DATABASE_URL with no SQLITE_PATH exits 1 and creates no local database file', async () => {
    const stray = path.join(ROOT, 'mercurius.db');
    const existed = fs.existsSync(stray);
    const r = await runMigrate({ DATABASE_URL: '', SQLITE_PATH: '' });
    assert.equal(r.code, 1, `exit 1\n${r.stdout}\n${r.stderr}`);
    assert.match(r.stderr, /migrate: REFUSED/);
    assert.doesNotMatch(r.stdout, /applied|fresh database/);
    if (!existed) assert.equal(fs.existsSync(stray), false, 'db.js was never loaded');
  });

  test('invoked through a symlinked path it still runs (and refuses), never a silent exit 0', async () => {
    const link = path.join(os.tmpdir(), `merc-migrate-link-${crypto.randomBytes(4).toString('hex')}`);
    fs.symlinkSync(ROOT, link, 'dir');
    try {
      const r = await new Promise((resolve, reject) => {
        const proc = spawn(process.execPath, [path.join(link, 'scripts', 'migrate.mjs')], {
          cwd: os.tmpdir(),
          env: { ...process.env, DATABASE_URL: '', SQLITE_PATH: '', NODE_ENV: 'test' },
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        let stderr = '';
        proc.stderr.on('data', (c) => { stderr += c.toString(); });
        proc.on('error', reject);
        proc.on('exit', (code) => resolve({ code, stderr }));
      });
      assert.equal(r.code, 1, r.stderr);
      assert.match(r.stderr, /migrate: REFUSED/);
    } finally {
      fs.rmSync(link, { force: true });
    }
  });

  test('an unreachable Postgres fails loudly instead of "fresh database: bootstrapping"', async () => {
    const r = await runMigrate({ DATABASE_URL: 'postgres://u:p@merc-test-no-such-host.invalid:5432/x?sslmode=disable', SQLITE_PATH: '' });
    assert.equal(r.code, 1, `exit 1\n${r.stdout}\n${r.stderr}`);
    assert.match(r.stdout, /migrate: target postgres @ merc-test-no-such-host\.invalid:5432\/x/);
    assert.doesNotMatch(r.stdout, /fresh database/);
    assert.match(r.stderr, /migrate: FAILED/);
    assert.doesNotMatch(r.stdout + r.stderr, /u:p@/, 'credentials never printed');
  });
});
