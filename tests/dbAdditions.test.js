'use strict';

// Tests for the ops-safety-rails db.js additions: settings key/value, the
// usage ledger + its aggregates, ping(), scrubLegacyNames(), and the usage
// cascade in deleteSession().
//
// Runs directly against a temp SQLite db (the local driver), like
// tests/deleteSession.test.js, so it needs no live Postgres.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

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
