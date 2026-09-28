'use strict';

// Tests for the ops-safety-rails db.js additions: settings key/value, the
// usage ledger + its aggregates, ping(), scrubLegacyNames(), the usage
// cascade in deleteSession(), the boot-time student_memory drop, and the
// production refusal to boot on SQLite.
//
// Runs directly against a temp SQLite db (the local driver), like
// tests/deleteSession.test.js, so it needs no live Postgres.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const dbPath = path.join(os.tmpdir(), `merc-additions-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }

// There is no name helper any more (nothing may write one); read the legacy
// column directly to observe the scrub.
async function displayNameOf(id) {
  const rows = await db.queryRaw('SELECT display_name FROM sessions WHERE session_id = ?', [id]);
  return rows[0] ? rows[0].display_name : null;
}

before(async () => { await db.initSchema(); });
after(() => {
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

describe('settings', () => {
  test('unset key reads as null', async () => {
    assert.equal(await db.getSetting('never_set_' + sid()), null);
  });

  test('set → get round-trips as a string, and set again overwrites', async () => {
    const key = 'k_' + sid();
    await db.setSetting(key, 'first');
    assert.equal(await db.getSetting(key), 'first');
    await db.setSetting(key, 'second');
    assert.equal(await db.getSetting(key), 'second');
    await db.setSetting(key, 42);
    assert.equal(await db.getSetting(key), '42', 'non-string values are stored via String()');
  });
});

describe('usage ledger', () => {
  test('recordUsage → sumCostSince / sessionUsageSince / usageSummarySince', async () => {
    const s = sid();
    const t0 = Date.now();
    // Everything here is stamped >= t0 so the window queries below see it.
    assert.equal(await db.recordUsage({ ts: t0 + 1, sessionId: s, route: '/api/chat', kind: 'chat', model: 'm', inputTokens: 100, outputTokens: 50, costUsd: 0.010, status: 'ok', durationMs: 120.6, traceId: 'tr1' }), true);
    assert.equal(await db.recordUsage({ ts: t0 + 2, sessionId: s, route: '/api/chat', kind: 'chat', costUsd: 0.020, status: 'ok' }), true);
    assert.equal(await db.recordUsage({ ts: t0 + 3, sessionId: s, route: '/api/quiz', kind: 'quiz', costUsd: 0.005, status: 'ok' }), true);
    assert.equal(await db.recordUsage({ ts: t0 + 4, sessionId: s, route: '/api/chat', kind: 'chat', costUsd: 0, status: 'error', errorKind: 'upstream_500' }), true);
    // snake_case keys are accepted too (matches the column names).
    assert.equal(await db.recordUsage({ ts: t0 + 5, session_id: sid(), route: '/api/chat', kind: 'chat', cost_usd: 0.100, status: 'refused', error_kind: 'kill_switch' }), true);

    const total = await db.sumCostSince(t0);
    assert.ok(Math.abs(total - 0.135) < 1e-9, `sumCostSince = ${total}`);
    assert.equal(await db.sumCostSince(t0 + 1000), 0, 'nothing after the window start');

    const perKind = await db.sessionUsageSince(s, t0);
    assert.deepEqual(perKind.map((r) => r.kind), ['chat', 'quiz'], 'ordered by kind');
    const chat = perKind.find((r) => r.kind === 'chat');
    assert.equal(chat.count, 3);
    assert.ok(Math.abs(chat.usd - 0.030) < 1e-9, `chat usd = ${chat.usd}`);
    assert.equal(perKind.find((r) => r.kind === 'quiz').count, 1);
    assert.deepEqual(await db.sessionUsageSince(sid(), t0), [], 'unknown session → empty');

    const summary = await db.usageSummarySince(t0);
    assert.equal(summary.calls, 5);
    assert.ok(Math.abs(summary.usd - 0.135) < 1e-9);
    assert.equal(summary.byRoute[0].route, '/api/chat', 'busiest route first');
    assert.equal(summary.byRoute[0].calls, 4);
    assert.equal(summary.byRoute[1].route, '/api/quiz');
    assert.equal(summary.byRoute[1].calls, 1);
    assert.deepEqual(
      summary.errors.map((e) => [e.route, e.error_kind, e.count]).sort(),
      [['/api/chat', 'kill_switch', 1], ['/api/chat', 'upstream_500', 1]],
      'every non-ok status is an error, grouped by (route, error_kind)',
    );
  });

  test('recordUsage fills defaults and never throws', async () => {
    const t0 = Date.now();
    // No ts/route/kind/status at all → defaults instead of a NOT NULL violation.
    assert.equal(await db.recordUsage({ sessionId: sid(), costUsd: 'nope' }), true);
    const summary = await db.usageSummarySince(t0);
    const unknown = summary.byRoute.find((r) => r.route === 'unknown');
    assert.ok(unknown && unknown.calls >= 1, 'route defaulted to unknown');
    assert.equal(unknown.usd, 0, 'unparseable cost → 0');

    // A genuinely broken database (table gone) makes the driver throw —
    // swallowed + logged, the caller's request is never failed by accounting.
    await db.runRaw('ALTER TABLE usage RENAME TO usage_hidden');
    try {
      assert.equal(await db.recordUsage({ sessionId: sid(), route: 'x', kind: 'y', status: 'ok' }), false);
    } finally {
      await db.runRaw('ALTER TABLE usage_hidden RENAME TO usage');
    }
    assert.equal(await db.recordUsage(undefined), true, 'no row at all is still not an exception');
  });
});

describe('ping', () => {
  test('answers true against a live database', async () => {
    assert.equal(await db.ping(), true);
  });
});

describe('scrubLegacyNames', () => {
  test('NULLs display_name / student_name and reports the row count', async () => {
    const named = sid(); const clean = sid();
    await db.getOrCreateSession(named);
    await db.getOrCreateSession(clean);
    // No helper writes names any more; seed the legacy column directly.
    await db.runRaw(`UPDATE sessions SET display_name = 'A Minor' WHERE session_id = '${named}'`);
    await db.queryRaw('UPDATE sessions SET student_name = ? WHERE session_id = ?', ['A Minor', named]);
    assert.equal(await displayNameOf(named), 'A Minor', 'seeded');

    assert.equal(await db.scrubLegacyNames(), 1, 'exactly the named row');
    assert.equal(await displayNameOf(named), null);
    const row = await db.queryRaw('SELECT student_name FROM sessions WHERE session_id = ?', [named]);
    assert.equal(row[0].student_name, null);
    assert.equal(await db.scrubLegacyNames(), 0, 'idempotent');
    assert.equal(await db.getSessionState(clean) !== null, true, 'other rows untouched');
  });

  test('initSchema runs the scrub', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.runRaw(`UPDATE sessions SET display_name = 'Left Behind' WHERE session_id = '${s}'`);
    await db.initSchema();
    assert.equal(await displayNameOf(s), null);
  });
});

describe('deleteSession cascade', () => {
  test('clears the usage ledger for the session, and only that session', async () => {
    const drop = sid(); const keep = sid();
    await db.getOrCreateSession(drop);
    await db.getOrCreateSession(keep);
    const t0 = Date.now();
    await db.recordUsage({ ts: t0 + 1, sessionId: drop, route: '/api/chat', kind: 'chat', costUsd: 0.01, status: 'ok' });
    await db.recordUsage({ ts: t0 + 2, sessionId: drop, route: '/api/chat', kind: 'chat', costUsd: 0.01, status: 'ok' });
    await db.recordUsage({ ts: t0 + 3, sessionId: keep, route: '/api/chat', kind: 'chat', costUsd: 0.01, status: 'ok' });

    const result = await db.deleteSession(drop);
    assert.equal(result.sessionExisted, true);
    assert.equal(result.deleted.usage, 2);
    assert.deepEqual(await db.sessionUsageSince(drop, t0), []);
    assert.equal((await db.sessionUsageSince(keep, t0))[0].count, 1, 'other session untouched');
  });
});

describe('initSchema drops the legacy student_memory table', () => {
  // Replaces the operator-run migrations/002 step: production drops it at
  // boot inside Railway's network, and a rollback that recreated it is
  // cleaned up again by the next boot.
  const exists = async () => (await db.queryRaw("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'student_memory'")).length === 1;

  test('a pre-removal table (with rows) is dropped, and a second boot is a no-op', async () => {
    await db.runRaw(`CREATE TABLE IF NOT EXISTS student_memory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      memory_type TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_memory_session ON student_memory(session_id, memory_type);
    INSERT INTO student_memory (session_id, memory_type, content, created_at) VALUES ('x', 'interest', 'likes chess', 1);`);
    assert.equal(await exists(), true, 'precondition');
    await db.initSchema();
    assert.equal(await exists(), false, 'dropped at boot');
    const idx = await db.queryRaw("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_memory_session'");
    assert.equal(idx.length, 0, 'its index went with it');
    await db.initSchema();
    assert.equal(await exists(), false, 'idempotent');
  });
});

describe('production refuses to boot without DATABASE_URL', () => {
  const ROOT = path.join(__dirname, '..');
  function load(env) {
    const file = path.join(os.tmpdir(), `merc-guard-${crypto.randomBytes(4).toString('hex')}.db`);
    const r = spawnSync(process.execPath, ['-e', "require('./db'); console.log('loaded')"], {
      cwd: ROOT,
      env: { ...process.env, SQLITE_PATH: file, ...env },
      encoding: 'utf8',
    });
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(file + suffix, { force: true }); } catch { /* ignore */ }
    }
    return r;
  }

  test('NODE_ENV=production + empty DATABASE_URL throws at require time with a clear message', () => {
    const r = load({ NODE_ENV: 'production', DATABASE_URL: '' });
    assert.notEqual(r.status, 0, 'non-zero exit');
    assert.match(r.stderr, /NODE_ENV=production but DATABASE_URL is empty/);
    assert.doesNotMatch(r.stdout, /loaded/);
  });

  test('on Railway (RAILWAY_ENVIRONMENT_NAME set) the guard holds even with NODE_ENV unset', () => {
    const r = load({ NODE_ENV: '', RAILWAY_ENVIRONMENT_NAME: 'production', DATABASE_URL: '' });
    assert.notEqual(r.status, 0, 'non-zero exit');
    assert.match(r.stderr, /running on Railway but DATABASE_URL is empty/);
    assert.doesNotMatch(r.stdout, /loaded/);
  });

  test('ALLOW_SQLITE_IN_PROD=1 is the explicit escape hatch', () => {
    const r = load({ NODE_ENV: 'production', DATABASE_URL: '', ALLOW_SQLITE_IN_PROD: '1' });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /loaded/);
  });

  test('the whole server exits instead of listening on ephemeral SQLite', () => {
    const r = spawnSync(process.execPath, ['server.js'], {
      cwd: ROOT,
      env: { ...process.env, NODE_ENV: 'production', DATABASE_URL: '', PORT: '0', ANTHROPIC_API_KEY: '' },
      encoding: 'utf8',
      timeout: 15000,
    });
    assert.notEqual(r.status, 0, `server must not boot (status ${r.status}, signal ${r.signal})`);
    assert.equal(r.signal, null, 'exited on its own, not killed by the timeout');
    assert.match(r.stderr, /DATABASE_URL is empty/);
  });

  test('outside production an empty DATABASE_URL still selects SQLite (dev + tests)', () => {
    for (const NODE_ENV of ['test', 'development', '']) {
      const r = load({ NODE_ENV, DATABASE_URL: '' });
      assert.equal(r.status, 0, `NODE_ENV=${NODE_ENV || '(unset)'}: ${r.stderr}`);
      assert.match(r.stdout, /loaded/);
    }
  });
});
