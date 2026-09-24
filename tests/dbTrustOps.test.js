'use strict';

// Tests for the trust-rails db.js additions: report review-queue columns +
// helpers, the lesson_events funnel table, getAdminStats (DAU/WAU, lessons,
// cost, D1/D7 retention, abandoned detection), the retention purge helpers,
// and the add-column migration path for `reports`.
//
// Runs directly against a temp SQLite db (the local driver), like
// tests/dbAdditions.test.js, so it needs no live Postgres. The stats and purge
// fixtures live in fixed past eras (2020 / 2017 / 2014) so rows other tests
// stamp with Date.now() never fall inside their windows.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const tag = crypto.randomBytes(4).toString('hex');
const dbPath = path.join(os.tmpdir(), `merc-trust-${tag}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');

const DAY = 86400000;
function sid(prefix = 'test') { return `${prefix}_` + crypto.randomBytes(8).toString('hex'); }
function isoDay(dayIndex) { return new Date(dayIndex * DAY).toISOString().slice(0, 10); }
function close(a, b, msg) { assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} ≠ ${b}`); }

// Direct seeders: the public API stamps Date.now(), the fixtures need fixed
// timestamps.
async function seedSession(id, createdAt, lastActive = createdAt) {
  await db.queryRaw('INSERT INTO sessions (session_id, created_at, last_active) VALUES (?, ?, ?)', [id, createdAt, lastActive]);
}
async function seedMessage(id, role, ts, kind = 'chat') {
  await db.queryRaw('INSERT INTO messages (session_id, role, content, timestamp, kind) VALUES (?, ?, ?, ?, ?)', [id, role, `${role} at ${ts}`, ts, kind]);
}
async function count(sql, params = []) {
  const rows = await db.queryRaw(sql, params);
  return Number(rows[0].c);
}

before(async () => { await db.initSchema(); });
after(() => {
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

describe('schema', () => {
  test('reports carries the review-queue columns and the created_at index', async () => {
    const cols = (await db.queryRaw('PRAGMA table_info(reports)')).map((c) => c.name);
    for (const c of ['user_message', 'context', 'resolved_at', 'created_at', 'session_id']) assert.ok(cols.includes(c), `reports.${c}`);
    const idx = (await db.queryRaw('PRAGMA index_list(reports)')).map((i) => i.name);
    assert.ok(idx.includes('idx_reports_created'), `idx_reports_created (have: ${idx.join(', ')})`);
    assert.ok(idx.includes('idx_reports_session'), 'idx_reports_session');
  });

  test('lesson_events exists with its indexes and the event CHECK', async () => {
    const cols = (await db.queryRaw('PRAGMA table_info(lesson_events)')).map((c) => c.name);
    assert.deepEqual(cols, ['id', 'ts', 'session_id', 'unit', 'lesson', 'lesson_id', 'event', 'turn_index']);
    const idx = (await db.queryRaw('PRAGMA index_list(lesson_events)')).map((i) => i.name);
    assert.ok(idx.includes('idx_lesson_events_ts'));
    assert.ok(idx.includes('idx_lesson_events_session'));
    await assert.rejects(
      db.queryRaw("INSERT INTO lesson_events (ts, session_id, event) VALUES (1, 'x', 'bogus')"),
      /CHECK/i,
      'the CHECK constraint rejects an unknown event',
    );
  });
});

describe('reports', () => {
  test('saveReport round-trips content, user_message and JSON context; listReports is newest first', async () => {
    const s = sid();
    const t0 = 1_600_000_000_000; // 2020-09-13, isolated from Date.now() rows
    const context = { lessonId: 'u1_l3', model: 'claude-x', nested: { a: 1, b: [1, 2] } };

    const r1 = await db.saveReport({ sessionId: s, content: 'bad reply', reason: 'harmful', userMessage: 'what is a token?', context, createdAt: t0 + 1 });
    assert.equal(typeof r1.id, 'number', 'saveReport returns { id }');
    // Old 4-key caller shape (server.js today) still works.
    const r2 = await db.saveReport({ sessionId: s, content: 'plain', reason: null, createdAt: t0 + 2 });
    assert.ok(r2.id > r1.id, 'ids ascend');
    // A pre-serialized JSON string is stored verbatim and parses back.
    const r3 = await db.saveReport({ sessionId: s, content: 'stringctx', reason: 'other', context: JSON.stringify({ k: 'v' }), createdAt: t0 + 3 });
    // Unparseable context never breaks the listing — it reads back as null.
    const r4 = await db.saveReport({ sessionId: s, content: 'badctx', reason: 'other', context: '{not json', createdAt: t0 + 4 });

    const rows = await db.listReports({ since: t0 });
    assert.deepEqual(rows.map((r) => r.id), [r4.id, r3.id, r2.id, r1.id], 'newest first');
    const first = rows.find((r) => r.id === r1.id);
    assert.equal(first.session_id, s);
    assert.equal(first.content, 'bad reply');
    assert.equal(first.reason, 'harmful');
    assert.equal(first.user_message, 'what is a token?');
    assert.deepEqual(first.context, context, 'context parsed back to the same object');
    assert.equal(first.created_at, t0 + 1);
    assert.equal(first.resolved_at, null, 'open on creation');
    const second = rows.find((r) => r.id === r2.id);
    assert.equal(second.user_message, null);
    assert.equal(second.context, null);
    assert.equal(second.reason, null);
    assert.deepEqual(rows.find((r) => r.id === r3.id).context, { k: 'v' });
    assert.equal(rows.find((r) => r.id === r4.id).context, null);

    // Raw storage really is a JSON string (what the admin export sees).
    const raw = await db.queryRaw('SELECT context FROM reports WHERE id = ?', [r1.id]);
    assert.equal(raw[0].context, JSON.stringify(context));

    // Filters: limit, since.
    assert.deepEqual((await db.listReports({ since: t0, limit: 2 })).map((r) => r.id), [r4.id, r3.id]);
    assert.deepEqual((await db.listReports({ since: t0 + 3 })).map((r) => r.id), [r4.id, r3.id], 'since is inclusive');
    assert.deepEqual(await db.listReports({ since: t0 + 5 }), [], 'nothing after the window');
  });

  test('resolveReport flips resolved_at once; unresolvedOnly hides resolved rows', async () => {
    const s = sid();
    const t0 = 1_600_100_000_000;
    const a = await db.saveReport({ sessionId: s, content: 'a', createdAt: t0 + 1 });
    const b = await db.saveReport({ sessionId: s, content: 'b', createdAt: t0 + 2 });

    const before = Date.now();
    assert.equal(await db.resolveReport(a.id), true, 'first resolution updates the row');
    const rowsAll = await db.listReports({ since: t0, limit: 10 });
    const resolved = rowsAll.find((r) => r.id === a.id);
    assert.ok(typeof resolved.resolved_at === 'number' && resolved.resolved_at >= before, 'resolved_at stamped');
    assert.equal(rowsAll.find((r) => r.id === b.id).resolved_at, null);

    assert.deepEqual((await db.listReports({ since: t0, unresolvedOnly: true })).map((r) => r.id), [b.id], 'only the open report');
    assert.deepEqual((await db.listReports({ since: t0 })).map((r) => r.id), [b.id, a.id], 'default listing keeps resolved rows');

    assert.equal(await db.resolveReport(a.id), false, 'already resolved → false, first timestamp kept');
    const again = (await db.listReports({ since: t0 })).find((r) => r.id === a.id);
    assert.equal(again.resolved_at, resolved.resolved_at);
    assert.equal(await db.resolveReport(999_999_999), false, 'unknown id');
    assert.equal(await db.resolveReport('nope'), false, 'non-numeric id');
  });

  test('createdAt defaults to now and limit is clamped', async () => {
    const s = sid();
    const before = Date.now();
    const { id } = await db.saveReport({ sessionId: s, content: 'no ts' });
    const row = (await db.listReports({ since: before })).find((r) => r.id === id);
    assert.ok(row && row.created_at >= before);
    assert.ok((await db.listReports({ limit: 0 })).length <= 1, 'limit 0 clamps to 1');
    assert.ok((await db.listReports({ limit: 'abc' })).length <= 50, 'garbage limit → default');
  });
});

describe('lesson events', () => {
  test('recordLessonEvent derives lesson_id / unit / lesson either way; lessonEventsSince lists oldest first', async () => {
    const s = sid();
    const t0 = 1_600_200_000_000;
    await db.getOrCreateSession(s);
    assert.equal(await db.recordLessonEvent({ ts: t0 + 1, sessionId: s, unit: 1, lesson: 3, event: 'start', turnIndex: 0 }), true);
    assert.equal(await db.recordLessonEvent({ ts: t0 + 2, sessionId: s, lessonId: 'u2_l4', event: 'turn', turnIndex: 1 }), true);
    assert.equal(await db.recordLessonEvent({ ts: t0 + 3, sessionId: s, event: 'complete' }), true);

    const rows = (await db.lessonEventsSince(t0)).filter((r) => r.session_id === s);
    assert.equal(rows.length, 3);
    assert.deepEqual(rows.map((r) => r.event), ['start', 'turn', 'complete'], 'oldest first');
    assert.deepEqual(
      rows.map(({ ts, unit, lesson, lesson_id, turn_index }) => ({ ts, unit, lesson, lesson_id, turn_index })),
      [
        { ts: t0 + 1, unit: 1, lesson: 3, lesson_id: 'u1_l3', turn_index: 0 },
        { ts: t0 + 2, unit: 2, lesson: 4, lesson_id: 'u2_l4', turn_index: 1 },
        { ts: t0 + 3, unit: null, lesson: null, lesson_id: null, turn_index: null },
      ],
    );
    assert.ok(rows.every((r) => typeof r.id === 'number'));
    assert.equal((await db.lessonEventsSince(t0 + 3)).filter((r) => r.session_id === s).length, 1, 'since is inclusive');
  });

  test('recordLessonEvent never throws: bad event / missing session / broken table → false', async () => {
    const s = sid();
    assert.equal(await db.recordLessonEvent({ sessionId: s, event: 'bogus' }), false);
    assert.equal(await db.recordLessonEvent({ event: 'start' }), false, 'no sessionId');
    assert.equal(await db.recordLessonEvent(undefined), false, 'no row at all');
    await db.runRaw('ALTER TABLE lesson_events RENAME TO lesson_events_hidden');
    try {
      assert.equal(await db.recordLessonEvent({ sessionId: s, event: 'start' }), false);
      assert.equal(await db.purgeLessonEventsBefore(Date.now()), 0, 'purge helper swallows the error too');
    } finally {
      await db.runRaw('ALTER TABLE lesson_events_hidden RENAME TO lesson_events');
    }
    assert.equal(await db.recordLessonEvent({ sessionId: s, event: 'start' }), true, 'healthy again');
  });

  test('deleteSession cascades to lesson_events, and only for that session', async () => {
    const drop = sid(); const keep = sid();
    await db.getOrCreateSession(drop); await db.getOrCreateSession(keep);
    const t0 = 1_600_300_000_000;
    await db.recordLessonEvent({ ts: t0 + 1, sessionId: drop, lessonId: 'u1_l1', event: 'start' });
    await db.recordLessonEvent({ ts: t0 + 2, sessionId: drop, lessonId: 'u1_l1', event: 'turn', turnIndex: 1 });
    await db.recordLessonEvent({ ts: t0 + 3, sessionId: keep, lessonId: 'u1_l1', event: 'start' });

    const result = await db.deleteSession(drop);
    assert.equal(result.sessionExisted, true);
    assert.equal(result.deleted.lesson_events, 2);
    const remaining = await db.lessonEventsSince(t0);
    assert.equal(remaining.filter((r) => r.session_id === drop).length, 0);
    assert.equal(remaining.filter((r) => r.session_id === keep).length, 1, 'other session untouched');
  });
});

describe('getAdminStats', () => {
  // Fixed era: T = day index 18500 (2020-08-26 UTC); "now" is noon that day.
  const T = 18500;
  const NOW = T * DAY + 12 * 3600000;
  const at = (dayOffset, hours = 0) => (T + dayOffset) * DAY + Math.round(hours * 3600000);
  const S = {};
  for (const k of ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']) S[k] = sid(`stats${k}`);

  before(async () => {
    // Sessions: created_at drives newSessions + the retention cohorts.
    await seedSession(S.A, at(-6, 1));
    await seedSession(S.B, at(-5, 2));
    await seedSession(S.C, at(-8, 1));
    await seedSession(S.D, at(-10, 1));
    await seedSession(S.E, at(-9, 1));
    await seedSession(S.F, at(-14, 1));
    await seedSession(S.G, at(0, 10));
    await seedSession(S.H, at(-1, 1));
    await seedSession(S.I, at(-7, 5));

    // User messages (DAU/WAU + retention); assistant rows must never count.
    await seedMessage(S.A, 'user', at(-6, 2));
    await seedMessage(S.A, 'assistant', at(-6, 2.5));
    await seedMessage(S.A, 'user', at(-6, 3));
    await seedMessage(S.A, 'user', at(-5, 4));          // A: D+1 → d1 retained
    await seedMessage(S.A, 'user', at(0, 1));
    await seedMessage(S.B, 'user', at(-5, 3));          // B: same day as creation only → not d1 retained
    await seedMessage(S.B, 'assistant', at(-5, 3.1));
    await seedMessage(S.C, 'user', at(-1, 5));          // C: created T-8, message on T-1 = D+7 → d7 retained
    await seedMessage(S.D, 'user', at(-4, 2));          // D: created T-10, D+6 → not retained
    await seedMessage(S.D, 'assistant', at(-3, 2));     // D: D+7 but assistant → not retained
    await seedMessage(S.E, 'user', at(-1, 6));          // E: created T-9, D+8 → not retained
    await seedMessage(S.F, 'user', at(-7, 1));          // F: outside the window entirely
    await seedMessage(S.I, 'user', at(-6, 6), 'lesson'); // I: created T-7, D+1 → d1 retained (kind irrelevant)

    // Usage ledger (cost, errors, top lists). Boundary rows: exactly at the
    // window start (inside) and exactly at the window end (outside).
    const u = (ts, sessionId, route, status, costUsd, errorKind = null) =>
      db.recordUsage({ ts, sessionId, route, kind: 'x', status, costUsd, errorKind });
    await u(at(-6, 0), S.A, '/api/lesson', 'ok', 0.02);
    await u(at(-6, 1), S.A, '/api/chat', 'ok', 0.10);
    await u(at(-6, 2), S.A, '/api/lesson', 'ok', 0.05);
    await u(at(-5, 1), S.B, '/api/chat', 'error', 0, 'upstream_500');
    await u(at(-1, 1), S.C, '/api/lesson', 'ok', 0.20);
    await u(at(-1, 2), S.E, '/api/chat', 'refused', 0, 'kill_switch');
    await u(at(0, 1), S.A, '/api/chat', 'ok', 0.01);
    await u(at(-7, 1), S.F, '/api/chat', 'ok', 5.00);   // outside
    await u(at(1, 0), S.A, '/api/chat', 'ok', 9.00);    // exactly at window end → outside

    // Lesson funnel.
    const ev = (ts, sessionId, lessonId, event, turnIndex = null) => db.recordLessonEvent({ ts, sessionId, lessonId, event, turnIndex });
    await ev(at(-6, 1), S.A, 'u1_l1', 'start', 0);
    await ev(at(-6, 1.08), S.A, 'u1_l1', 'turn', 1);
    await ev(at(-6, 1.17), S.A, 'u1_l1', 'turn', 2);
    await ev(at(-6, 1.33), S.A, 'u1_l1', 'complete');       // finished → not abandoned
    await ev(at(-6, 3), S.I, 'u2_l1', 'start', 0);
    await ev(at(-5, 4), S.I, 'u2_l1', 'complete');          // 25 h later: completed, but abandoned by the 24 h rule
    await ev(at(-5, 2), S.B, 'u1_l1', 'start', 0);          // no turns ever → abandoned
    await ev(at(-5, 3), S.B, 'u1_l2', 'turn', 1);           // a turn on a DIFFERENT lesson must not rescue it
    await ev(at(-4, 1), S.D, 'u1_l1', 'start', 0);
    await ev(at(-4, 1), S.D, 'u1_l1', 'turn', 0);           // same-millisecond turn counts → not abandoned
    await ev(at(-1, 1), S.A, 'u1_l2', 'start', 0);
    await ev(at(-1, 1.5), S.A, 'u1_l2', 'turn', 1);         // in progress, not completed, not abandoned
    await ev(at(0, 11), S.G, 'u1_l1', 'start', 0);          // 1 h old: judgement window still open → not abandoned
    await ev(at(-7, 1), S.F, 'u1_l1', 'start', 0);          // outside the window
  });

  test('per-day DAU / messages / lessons / cost / errors, zero-filled and oldest first', async () => {
    const stats = await db.getAdminStats({ days: 7, now: NOW });
    assert.equal(stats.windowDays, 7);
    assert.equal(stats.generatedAt, NOW);
    assert.equal(stats.perDay.length, 7);
    assert.deepEqual(stats.perDay.map((d) => d.day), [-6, -5, -4, -3, -2, -1, 0].map((o) => isoDay(T + o)), 'oldest first, ISO days');

    const expect = [
      { dau: 2, userMessages: 3, lessonsStarted: 2, lessonsCompleted: 1, costUsd: 0.17, errors: 0 }, // T-6
      { dau: 2, userMessages: 2, lessonsStarted: 1, lessonsCompleted: 1, costUsd: 0,    errors: 1 }, // T-5
      { dau: 1, userMessages: 1, lessonsStarted: 1, lessonsCompleted: 0, costUsd: 0,    errors: 0 }, // T-4
      { dau: 0, userMessages: 0, lessonsStarted: 0, lessonsCompleted: 0, costUsd: 0,    errors: 0 }, // T-3 (assistant only)
      { dau: 0, userMessages: 0, lessonsStarted: 0, lessonsCompleted: 0, costUsd: 0,    errors: 0 }, // T-2 (nothing)
      { dau: 2, userMessages: 2, lessonsStarted: 1, lessonsCompleted: 0, costUsd: 0.20, errors: 1 }, // T-1
      { dau: 1, userMessages: 1, lessonsStarted: 1, lessonsCompleted: 0, costUsd: 0.01, errors: 0 }, // T
    ];
    stats.perDay.forEach((d, i) => {
      const e = expect[i];
      for (const k of ['dau', 'userMessages', 'lessonsStarted', 'lessonsCompleted', 'errors']) assert.equal(d[k], e[k], `${d.day}.${k}`);
      close(d.costUsd, e.costUsd, `${d.day}.costUsd`);
    });
  });

  test('window totals: WAU, cost, cost per WAU, lessons, new sessions, top lists', async () => {
    const stats = await db.getAdminStats({ days: 7, now: NOW });
    assert.equal(stats.wau, 6, 'A B C D E I (F outside, G/H silent)');
    close(stats.costUsdWindow, 0.38, 'costUsdWindow');
    close(stats.costPerWau, 0.38 / 6, 'costPerWau');
    assert.equal(stats.lessonsStarted, 6);
    assert.equal(stats.lessonsCompleted, 2);
    assert.equal(stats.lessonsAbandoned, 2, 'B (silent) and I (completed only after 24 h)');
    assert.equal(stats.newSessions, 4, 'A B G H');

    assert.deepEqual(
      stats.topErrors.map((e) => [e.route, e.error_kind, e.count]),
      [['/api/chat', 'kill_switch', 1], ['/api/chat', 'upstream_500', 1]],
      'count desc, then route, then error_kind',
    );
    assert.equal(stats.topRoutesByCost.length, 2);
    assert.equal(stats.topRoutesByCost[0].route, '/api/lesson', 'dearest route first');
    assert.equal(stats.topRoutesByCost[0].calls, 3);
    close(stats.topRoutesByCost[0].costUsd, 0.27, 'lesson cost');
    assert.equal(stats.topRoutesByCost[1].route, '/api/chat');
    assert.equal(stats.topRoutesByCost[1].calls, 4);
    close(stats.topRoutesByCost[1].costUsd, 0.11, 'chat cost');

    assert.equal(stats.reportsOpen, await count('SELECT COUNT(*) AS c FROM reports WHERE resolved_at IS NULL'), 'queue length, all-time');
  });

  test('retention: D1 and D7 cohorts against hand-computed values', async () => {
    const stats = await db.getAdminStats({ days: 7, now: NOW });
    // d1: return day D+1 ∈ [T-6, T-1] ⇒ cohort days D ∈ [T-7, T-2]:
    //   A (T-6) retained on T-5, B (T-5) not (only same-day messages),
    //   I (T-7) retained on T-6. H (T-1) and G (T) are too young.
    assert.deepEqual(stats.retention.d1, { cohortSize: 3, retained: 2, rate: 2 / 3 });
    // d7: return day D+7 ∈ [T-6, T-1] ⇒ cohort days D ∈ [T-13, T-8]:
    //   C (T-8) retained on T-1, D (T-10) not (user turn on D+6, assistant on
    //   D+7), E (T-9) not (D+8). F (T-14) and I (T-7) fall outside.
    assert.deepEqual(stats.retention.d7, { cohortSize: 3, retained: 1, rate: 1 / 3 });
  });

  test('the window moves with `now` and `days`', async () => {
    // A 1-day window on T-6: only that day's activity, and no complete return
    // day fits inside it, so both cohorts are empty (rate null, not NaN).
    const one = await db.getAdminStats({ days: 1, now: at(-6, 23) });
    assert.equal(one.perDay.length, 1);
    assert.equal(one.perDay[0].day, isoDay(T - 6));
    assert.equal(one.wau, 2);
    close(one.costUsdWindow, 0.17, 'one-day cost');
    assert.deepEqual(one.retention.d1, { cohortSize: 0, retained: 0, rate: null });
    assert.deepEqual(one.retention.d7, { cohortSize: 0, retained: 0, rate: null });
    assert.equal(one.lessonsAbandoned, 0, 'nothing 24 h old yet at T-6 23:00');

    // A 14-day window reaches F (T-14 creation is still outside, its T-7
    // message is inside) and widens the cohorts.
    const two = await db.getAdminStats({ days: 14, now: NOW });
    assert.equal(two.perDay.length, 14);
    assert.equal(two.wau, 7, 'F joins');
    close(two.costUsdWindow, 5.38, 'F\'s 5.00 joins');
    assert.equal(two.lessonsStarted, 7);
    assert.equal(two.lessonsAbandoned, 3, 'F\'s silent start joins');
    // d1 cohort D ∈ [T-14, T-2]: A B I retained as before, plus C D E F (none
    // retained on D+1) and H/G still too young → 7 / 2.
    assert.deepEqual(two.retention.d1, { cohortSize: 7, retained: 2, rate: 2 / 7 });
    // d7 cohort D ∈ [T-20, T-8]: C D E F → F's D+7 = T-7 has a user message.
    assert.deepEqual(two.retention.d7, { cohortSize: 4, retained: 2, rate: 2 / 4 });

    // An empty era: everything zero-filled, ratios null.
    const empty = await db.getAdminStats({ days: 3, now: 1_000_000_000_000 });
    assert.equal(empty.perDay.length, 3);
    assert.ok(empty.perDay.every((d) => d.dau === 0 && d.costUsd === 0 && d.lessonsStarted === 0));
    assert.equal(empty.wau, 0);
    assert.equal(empty.costPerWau, null);
    assert.equal(empty.newSessions, 0);
    assert.deepEqual(empty.topErrors, []);
    assert.deepEqual(empty.topRoutesByCost, []);
  });

  test('defaults and clamping never produce a broken window', async () => {
    const d = await db.getAdminStats();
    assert.equal(d.windowDays, 7);
    assert.equal(d.perDay.length, 7);
    assert.equal(d.perDay[6].day, new Date().toISOString().slice(0, 10), 'ends on today (UTC)');
    assert.equal((await db.getAdminStats({ days: 0 })).windowDays, 1);
    assert.equal((await db.getAdminStats({ days: 'nope' })).windowDays, 7);
    assert.equal((await db.getAdminStats({ days: 1000, now: NOW })).windowDays, 366);
  });
});

describe('retention purge helpers', () => {
  // 2017 era — older than every other fixture in this file, so a purge here
  // can never eat the stats rows, and vice versa.
  const BASE = 1_500_000_000_000;
  const CUT = BASE + 50;
  const s = sid('purge');
  let resolvedOld, openOld, resolvedNew;

  before(async () => {
    await seedSession(s, BASE, BASE);
    await seedMessage(s, 'user', BASE + 1);
    await seedMessage(s, 'assistant', BASE + 2);
    await seedMessage(s, 'user', BASE + 100);
    const img = (id, ts) => db.saveImage({ id, sessionId: s, contentType: 'image/png', fileName: null, sizeBytes: 1, data: Buffer.from([1]), createdAt: ts });
    await img('img_old_' + tag, BASE + 1);
    await img('img_new_' + tag, BASE + 100);
    resolvedOld = (await db.saveReport({ sessionId: s, content: 'r-old', createdAt: BASE + 1 })).id;
    await db.resolveReport(resolvedOld);
    openOld = (await db.saveReport({ sessionId: s, content: 'o-old', createdAt: BASE + 2 })).id;
    resolvedNew = (await db.saveReport({ sessionId: s, content: 'r-new', createdAt: BASE + 100 })).id;
    await db.resolveReport(resolvedNew);
    await db.recordUsage({ ts: BASE + 1, sessionId: s, route: 'r', kind: 'k', status: 'ok', costUsd: 0.01 });
    await db.recordUsage({ ts: BASE + 100, sessionId: s, route: 'r', kind: 'k', status: 'ok', costUsd: 0.01 });
    await db.recordLessonEvent({ ts: BASE + 1, sessionId: s, lessonId: 'u1_l1', event: 'start' });
    await db.recordLessonEvent({ ts: BASE + 100, sessionId: s, lessonId: 'u1_l1', event: 'turn', turnIndex: 1 });
  });

  test('each purge deletes only rows older than the cutoff and reports the count', async () => {
    assert.equal(await db.purgeMessagesBefore(CUT), 2);
    assert.equal(await count('SELECT COUNT(*) AS c FROM messages WHERE session_id = ?', [s]), 1, 'the newer message survives');
    assert.equal(await db.purgeMessagesBefore(CUT), 0, 'idempotent');

    assert.equal(await db.purgeImagesBefore(CUT), 1);
    assert.equal(await db.getImage('img_old_' + tag), null);
    assert.ok(await db.getImage('img_new_' + tag), 'the newer image survives');

    assert.equal(await db.purgeReportsBefore(CUT), 1, 'resolvedOnly by default: only the resolved old report');
    let ids = (await db.listReports({ since: BASE, limit: 10 })).filter((r) => r.session_id === s).map((r) => r.id);
    assert.deepEqual(ids.sort(), [openOld, resolvedNew].sort(), 'the open old report is kept as an unreviewed signal');
    assert.equal(await db.purgeReportsBefore(CUT, { resolvedOnly: false }), 1, 'explicit opt-in purges the open one too');
    ids = (await db.listReports({ since: BASE, limit: 10 })).filter((r) => r.session_id === s).map((r) => r.id);
    assert.deepEqual(ids, [resolvedNew]);

    assert.equal(await db.purgeUsageBefore(CUT), 1);
    assert.equal((await db.sessionUsageSince(s, BASE))[0].count, 1);

    assert.equal(await db.purgeLessonEventsBefore(CUT), 1);
    const left = (await db.lessonEventsSince(BASE)).filter((r) => r.session_id === s);
    assert.deepEqual(left.map((r) => r.event), ['turn']);
  });

  test('purges run in batches (more rows than one batch)', async () => {
    const OLD = 1_400_000_000_000; // 2014 era, older than everything else
    const b = sid('batch');
    await seedSession(b, OLD + 10_000, OLD + 10_000);
    const insert = db.queryRaw.bind(db);
    // 2500 rows > 2 × PURGE_BATCH (1000): exercises the loop-until-short-batch path.
    for (let i = 0; i < 2500; i++) {
      await insert('INSERT INTO messages (session_id, role, content, timestamp, kind) VALUES (?, ?, ?, ?, ?)', [b, 'user', 'bulk', OLD + i, 'chat']);
    }
    assert.equal(await db.purgeMessagesBefore(OLD + 2500), 2500);
    assert.equal(await count('SELECT COUNT(*) AS c FROM messages WHERE session_id = ?', [b]), 0);
    // The session itself is what the scheduler erases next; do it here so this
    // 2014-era row does not leak into the inactiveSessionIds fixture below.
    const erased = await db.deleteSession(b);
    assert.equal(erased.sessionExisted, true);
    assert.equal(erased.deleted.messages, 0, 'already purged');
  });

  test('inactiveSessionIds returns the least-recent sessions under the cutoff, honoring limit', async () => {
    const OLD = 1_400_500_000_000;
    const ids = [sid('inact'), sid('inact'), sid('inact')];
    await seedSession(ids[1], OLD, OLD + 2);
    await seedSession(ids[0], OLD, OLD + 1);
    await seedSession(ids[2], OLD, OLD + 3);
    const fresh = sid('inact');
    await seedSession(fresh, OLD, OLD + 100);

    assert.deepEqual(await db.inactiveSessionIds(OLD + 50), ids, 'ascending by last_active; the fresh one excluded');
    assert.deepEqual(await db.inactiveSessionIds(OLD + 50, 2), ids.slice(0, 2), 'limit');
    assert.deepEqual(await db.inactiveSessionIds(OLD + 1), [], 'strict <');
    assert.equal((await db.inactiveSessionIds(OLD + 50, 0)).length, 3, 'nonsense limit → default');

    // The scheduler's loop: deleteSession each id, then nothing is left.
    for (const id of ids) assert.equal((await db.deleteSession(id)).sessionExisted, true);
    assert.deepEqual(await db.inactiveSessionIds(OLD + 50), []);
  });

  test('purge helpers never throw on a broken table', async () => {
    await db.runRaw('ALTER TABLE usage RENAME TO usage_hidden');
    try {
      assert.equal(await db.purgeUsageBefore(Date.now()), 0);
    } finally {
      await db.runRaw('ALTER TABLE usage_hidden RENAME TO usage');
    }
    await db.runRaw('ALTER TABLE sessions RENAME TO sessions_hidden');
    try {
      assert.deepEqual(await db.inactiveSessionIds(Date.now()), []);
    } finally {
      await db.runRaw('ALTER TABLE sessions_hidden RENAME TO sessions');
    }
  });
});

describe('add-column migration (database created before the report review columns existed)', () => {
  const oldDbPath = path.join(os.tmpdir(), `merc-trust-old-${tag}.db`);
  const resultPath = path.join(os.tmpdir(), `merc-trust-old-${tag}.json`);
  after(() => {
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(oldDbPath + suffix, { force: true }); } catch { /* ignore */ }
    }
    try { fs.rmSync(resultPath, { force: true }); } catch { /* ignore */ }
  });

  test('initSchema adds user_message / context / resolved_at + the index; legacy rows read as open reports', () => {
    // 1. The OLD reports schema, exactly as db.js created it before this PR.
    const Database = require('better-sqlite3');
    const old = new Database(oldDbPath);
    const s = 'legacy_' + tag;
    const t0 = 1_700_000_000_000;
    old.exec(`
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        last_active INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0,
        topics TEXT DEFAULT '[]',
        student_name TEXT DEFAULT NULL,
        mode TEXT DEFAULT 'socratic',
        unlocked INTEGER DEFAULT 0,
        test_state TEXT DEFAULT NULL
      );
      CREATE TABLE reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        content TEXT NOT NULL,
        reason TEXT DEFAULT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX idx_reports_session ON reports(session_id);
    `);
    old.prepare('INSERT INTO sessions (session_id, created_at, last_active) VALUES (?, ?, ?)').run(s, t0, t0);
    old.prepare('INSERT INTO reports (session_id, content, reason, created_at) VALUES (?, ?, ?, ?)').run(s, 'legacy report', 'old-reason', t0 + 1);
    const beforeCols = old.prepare('PRAGMA table_info(reports)').all().map((c) => c.name);
    old.close();
    assert.ok(!beforeCols.includes('resolved_at'), 'sanity: hand-built schema predates the columns');

    // 2. initSchema (twice, for idempotency) in a child process, since db.js
    //    binds SQLITE_PATH at require time; then exercise the API on the file.
    const script = `
      const fs = require('node:fs');
      const db = require(${JSON.stringify(path.join(__dirname, '..', 'db.js'))});
      (async () => {
        await db.initSchema();
        await db.initSchema();
        const s = ${JSON.stringify(s)};
        const cols = await db.queryRaw('PRAGMA table_info(reports)');
        const indexes = (await db.queryRaw('PRAGMA index_list(reports)')).map((i) => i.name);
        const tables = (await db.queryRaw("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r.name);
        const legacy = await db.listReports({ since: 0, limit: 10 });
        const saved = await db.saveReport({ sessionId: s, content: 'new', reason: 'r', userMessage: 'um', context: { a: 1 }, createdAt: ${t0} + 2 });
        const resolved = await db.resolveReport(legacy[0].id);
        const afterRows = await db.listReports({ since: 0, limit: 10 });
        const open = await db.listReports({ since: 0, limit: 10, unresolvedOnly: true });
        const ev = await db.recordLessonEvent({ ts: ${t0}, sessionId: s, lessonId: 'u1_l1', event: 'start' });
        const events = await db.lessonEventsSince(0);
        fs.writeFileSync(${JSON.stringify(resultPath)}, JSON.stringify({ cols, indexes, tables, legacy, saved, resolved, afterRows, open, ev, events }));
      })().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
    `;
    const env = { ...process.env, SQLITE_PATH: oldDbPath };
    delete env.DATABASE_URL;
    try {
      execFileSync(process.execPath, ['-e', script], { env, cwd: path.join(__dirname, '..'), stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      assert.fail(`child initSchema failed:\n${String(e.stderr || e.message)}`);
    }
    const r = JSON.parse(fs.readFileSync(resultPath, 'utf8'));

    // 3. Columns + index exist exactly once after two runs.
    const names = r.cols.map((c) => c.name);
    for (const c of ['user_message', 'context', 'resolved_at']) {
      assert.equal(names.filter((n) => n === c).length, 1, `exactly one ${c} column`);
    }
    assert.ok(r.indexes.includes('idx_reports_created'), `idx_reports_created (have: ${r.indexes.join(', ')})`);
    assert.ok(r.tables.includes('lesson_events'), 'lesson_events created alongside');

    // 4. The legacy row reads back as an open report with no captured context,
    //    and the new API works on the migrated file.
    assert.equal(r.legacy.length, 1);
    assert.equal(r.legacy[0].content, 'legacy report');
    assert.equal(r.legacy[0].reason, 'old-reason');
    assert.equal(r.legacy[0].user_message, null);
    assert.equal(r.legacy[0].context, null);
    assert.equal(r.legacy[0].resolved_at, null);
    assert.equal(typeof r.saved.id, 'number');
    assert.equal(r.resolved, true);
    assert.deepEqual(r.afterRows.map((x) => x.id), [r.saved.id, r.legacy[0].id], 'newest first');
    assert.deepEqual(r.afterRows[0].context, { a: 1 });
    assert.equal(r.afterRows[0].user_message, 'um');
    assert.equal(typeof r.afterRows[1].resolved_at, 'number', 'legacy row resolvable');
    assert.deepEqual(r.open.map((x) => x.id), [r.saved.id]);
    assert.equal(r.ev, true);
    assert.equal(r.events.length, 1);
    assert.equal(r.events[0].lesson_id, 'u1_l1');
  });
});
