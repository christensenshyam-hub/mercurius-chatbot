'use strict';

// Server-synced curriculum progress (Phase 3A):
//   db.getProgress / db.upsertProgress — forward-only merge (completed <
//     mastered, never a downgrade, never a delete), curriculum version only
//     rises, unknown session is empty, deleteSession cascades the table
//   ProgressSyncRequest — item ids, caps, strictness, the exported rank
//   GET/PUT /api/progress/:sessionId end to end against the real server
//     booted with ANTHROPIC_MOCK=1, including the chat handler's own
//     [LESSON_COMPLETE] write on BOTH the JSON and the SSE path, invalid
//     input 400s, and erasure through DELETE /api/session/:id.
//
// One temp SQLite file is shared by this process (through db.js) and the
// spawned server, like tests/adminTrust.test.js, so the HTTP cases can prove
// that a GET never creates a session row.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const PORT = 9960 + Math.floor(Math.random() * 40);
const BASE = `http://localhost:${PORT}`;
const dbPath = path.join(os.tmpdir(), `merc-progress-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');
const {
  ProgressSyncRequest,
  ProgressItem,
  ProgressStatus,
  PROGRESS_STATUS_RANK,
  _legacyErrorCode,
} = require('../lib/schemas');

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lesson = (id, status = 'completed') => ({ id, type: 'lesson', status });
const unit = (id, status = 'mastered') => ({ id, type: 'unit', status });

before(async () => { await db.initSchema(); });
after(() => {
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

// ---------------------------------------------------------------------------
// db.js
// ---------------------------------------------------------------------------
describe('db.getProgress / db.upsertProgress', () => {
  test('an unknown session is empty with a null version, and reading never creates a row', async () => {
    const s = sid();
    assert.deepEqual(await db.getProgress(s), { curriculumVersion: null, lessons: [], units: [] });
    assert.equal(await db.sessionExists(s), false);
  });

  test('lessons merge forward-only: completed → mastered upgrades, mastered → completed is ignored, updatedAt moves only on a change', async () => {
    const s = sid();
    let state = await db.upsertProgress(s, { curriculumVersion: 1, items: [lesson('u1_l1', 'completed')] }, 1000);
    assert.deepEqual(state, { curriculumVersion: 1, lessons: [{ id: 'u1_l1', status: 'completed', updatedAt: 1000 }], units: [] });

    // Same status again: nothing changes, including the timestamp.
    state = await db.upsertProgress(s, { curriculumVersion: 1, items: [lesson('u1_l1', 'completed')] }, 2000);
    assert.deepEqual(state.lessons, [{ id: 'u1_l1', status: 'completed', updatedAt: 1000 }]);

    state = await db.upsertProgress(s, { curriculumVersion: 1, items: [lesson('u1_l1', 'mastered')] }, 3000);
    assert.deepEqual(state.lessons, [{ id: 'u1_l1', status: 'mastered', updatedAt: 3000 }]);

    // The downgrade is silently ignored — the merged state still says mastered.
    state = await db.upsertProgress(s, { curriculumVersion: 1, items: [lesson('u1_l1', 'completed')] }, 4000);
    assert.deepEqual(state.lessons, [{ id: 'u1_l1', status: 'mastered', updatedAt: 3000 }]);
    assert.deepEqual(await db.getProgress(s), state, 'getProgress reads back what upsertProgress returned');
  });

  test('units merge forward-only the same way, and lessons and units are kept apart', async () => {
    const s = sid();
    let state = await db.upsertProgress(s, { curriculumVersion: 2, items: [unit('unit_1', 'mastered'), lesson('u1_l2')] }, 1000);
    assert.deepEqual(state.units, [{ id: 'unit_1', status: 'mastered', updatedAt: 1000 }]);
    assert.deepEqual(state.lessons, [{ id: 'u1_l2', status: 'completed', updatedAt: 1000 }]);

    state = await db.upsertProgress(s, { curriculumVersion: 2, items: [unit('unit_1', 'completed')] }, 2000);
    assert.deepEqual(state.units, [{ id: 'unit_1', status: 'mastered', updatedAt: 1000 }], 'unit not downgraded');

    // Nothing is ever deleted: a push that omits an item leaves it in place.
    state = await db.upsertProgress(s, { curriculumVersion: 2, items: [] }, 3000);
    assert.equal(state.units.length, 1);
    assert.equal(state.lessons.length, 1);
  });

  test('curriculumVersion only rises; omitted reuses the stored one, else 1', async () => {
    const s = sid();
    // No client version in hand (the chat handler's own write) → 1.
    let state = await db.upsertProgress(s, { items: [lesson('u1_l1')] }, 1000);
    assert.equal(state.curriculumVersion, 1);

    state = await db.upsertProgress(s, { curriculumVersion: 4, items: [lesson('u1_l2')] }, 2000);
    assert.equal(state.curriculumVersion, 4);

    // An older client cannot pull the version back down …
    state = await db.upsertProgress(s, { curriculumVersion: 2, items: [lesson('u1_l3')] }, 3000);
    assert.equal(state.curriculumVersion, 4);
    // … and a versionless write reuses the highest stored version, not 1.
    state = await db.upsertProgress(s, { items: [lesson('u1_l4')] }, 4000);
    assert.equal(state.curriculumVersion, 4);
    assert.deepEqual(state.lessons.map((l) => l.id), ['u1_l1', 'u1_l2', 'u1_l3', 'u1_l4']);
  });

  test('duplicates in one push: the highest rank wins regardless of order', async () => {
    const s = sid();
    const state = await db.upsertProgress(s, {
      curriculumVersion: 1,
      items: [lesson('u2_l1', 'mastered'), lesson('u2_l1', 'completed'), lesson('u2_l1', 'completed')],
    }, 1000);
    assert.deepEqual(state.lessons, [{ id: 'u2_l1', status: 'mastered', updatedAt: 1000 }]);
  });

  test('malformed items are skipped, never stored (the route schema is the real gate)', async () => {
    const s = sid();
    const state = await db.upsertProgress(s, {
      curriculumVersion: 1,
      items: [
        { id: 'u1_l1', type: 'lesson', status: 'in_progress' }, // not a synced status
        { id: 'lesson_1', type: 'lesson', status: 'completed' }, // bad id shape
        { id: 'u1_l1', type: 'thing', status: 'completed' },     // bad type
        { id: 'u' + '9'.repeat(70) + '_l1', type: 'lesson', status: 'completed' }, // too long
        null,
        'u1_l1',
        lesson('u3_l1'),                                          // the one good item
      ],
    }, 1000);
    assert.deepEqual(state, { curriculumVersion: 1, lessons: [{ id: 'u3_l1', status: 'completed', updatedAt: 1000 }], units: [] });
  });

  test('deleteSession cascades curriculum_progress and leaves other sessions alone', async () => {
    const drop = sid(); const keep = sid();
    await db.getOrCreateSession(drop);
    await db.upsertProgress(drop, { curriculumVersion: 1, items: [lesson('u1_l1'), lesson('u1_l2'), unit('unit_1')] });
    await db.upsertProgress(keep, { curriculumVersion: 1, items: [lesson('u1_l1')] });

    const result = await db.deleteSession(drop);
    assert.equal(result.sessionExisted, true);
    assert.equal(result.deleted.curriculum_progress, 3, 'the receipt counts the progress rows');
    assert.deepEqual(await db.getProgress(drop), { curriculumVersion: null, lessons: [], units: [] });
    assert.equal((await db.getProgress(keep)).lessons.length, 1, 'other session untouched');
  });
});

// ---------------------------------------------------------------------------
// lib/schemas.js
// ---------------------------------------------------------------------------
describe('ProgressSyncRequest', () => {
  test('accepts a well-formed push, including an empty items list', () => {
    const ok = ProgressSyncRequest.safeParse({ curriculumVersion: 3, items: [lesson('u1_l3'), unit('unit_1')] });
    assert.ok(ok.success, JSON.stringify(ok.error));
    assert.deepEqual(ok.data.items, [lesson('u1_l3'), unit('unit_1')]);
    assert.ok(ProgressSyncRequest.safeParse({ curriculumVersion: 1, items: [] }).success);
  });

  test('the exported rank is what the enum and db.js agree on: completed < mastered', () => {
    assert.deepEqual(Object.keys(PROGRESS_STATUS_RANK).sort(), ['completed', 'mastered']);
    assert.ok(PROGRESS_STATUS_RANK.completed < PROGRESS_STATUS_RANK.mastered);
    assert.deepEqual([...ProgressStatus.options].sort(), Object.keys(PROGRESS_STATUS_RANK).sort());
    assert.ok(!ProgressStatus.safeParse('in_progress').success, 'in-progress is device-local, never synced');
    assert.ok(!ProgressStatus.safeParse('notStarted').success);
  });

  test('ids: uN_lM and unit_N only, at most 64 chars, and the shape must match the declared type', () => {
    for (const good of [lesson('u1_l1'), lesson('u12_l5'), unit('unit_1'), unit('unit_12')]) {
      assert.ok(ProgressItem.safeParse(good).success, JSON.stringify(good));
    }
    for (const bad of [
      lesson('lesson_1'), lesson('u1-l1'), lesson('U1_L1'), lesson('u1_l'), lesson(''), lesson('u1_l1 '),
      unit('unit1'), unit('unit_'), unit('unit_a'),
      lesson('u' + '9'.repeat(70) + '_l1'),
      { id: 'unit_1', type: 'lesson', status: 'completed' },
      { id: 'u1_l1', type: 'unit', status: 'mastered' },
    ]) {
      assert.ok(!ProgressItem.safeParse(bad).success, `should reject ${JSON.stringify(bad)}`);
    }
  });

  test('caps: at most 200 items', () => {
    const items = Array.from({ length: 200 }, (_, i) => lesson(`u${Math.floor(i / 5) + 1}_l${(i % 5) + 1}`));
    assert.ok(ProgressSyncRequest.safeParse({ curriculumVersion: 1, items }).success);
    assert.ok(!ProgressSyncRequest.safeParse({ curriculumVersion: 1, items: [...items, lesson('u99_l1')] }).success);
  });

  test('strict: unknown keys at either level, a bad version, a bad status or type are all rejected', () => {
    const bad = [
      { curriculumVersion: 1, items: [], extra: true },
      { curriculumVersion: 1, items: [{ ...lesson('u1_l1'), updatedAt: 5 }] },
      { curriculumVersion: 0, items: [] },
      { curriculumVersion: -1, items: [] },
      { curriculumVersion: 1.5, items: [] },
      { curriculumVersion: '1', items: [] },
      { items: [] },
      { curriculumVersion: 1 },
      { curriculumVersion: 1, items: null },
      { curriculumVersion: 1, items: [lesson('u1_l1', 'in_progress')] },
      { curriculumVersion: 1, items: [{ id: 'u1_l1', type: 'module', status: 'completed' }] },
      { curriculumVersion: 1, items: [{ id: 'u1_l1', type: 'lesson' }] },
      null,
      [],
      'progress',
    ];
    for (const body of bad) {
      assert.ok(!ProgressSyncRequest.safeParse(body).success, `should reject ${JSON.stringify(body)}`);
    }
  });

  test('validation failures surface as the generic invalid_request code on the wire', () => {
    const r = ProgressSyncRequest.safeParse({ curriculumVersion: 1, items: [lesson('nope')] });
    assert.ok(!r.success);
    assert.equal(_legacyErrorCode(r.error.issues), 'invalid_request');
  });
});

// ---------------------------------------------------------------------------
// HTTP, against the real server (mocked Anthropic)
// ---------------------------------------------------------------------------
describe('GET / PUT /api/progress/:sessionId', () => {
  let proc;

  async function call(method, p, body, headers = {}) {
    const res = await fetch(`${BASE}${p}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, json: await res.json().catch(() => null) };
  }

  // A curriculum thread with `turns` user messages. The mock appends
  // [LESSON_COMPLETE] from the 5th user turn on.
  function thread(unitNo, lessonNo, turns = 5) {
    const msgs = [{ role: 'user', content: `[CURRICULUM: Unit ${unitNo}, Lesson ${lessonNo}] Teach me this lesson.` }];
    for (let i = 2; i <= turns; i++) {
      msgs.push({ role: 'assistant', content: 'Here is the next idea.' });
      msgs.push({ role: 'user', content: `Answer ${i}: I think it works like this.` });
    }
    return msgs;
  }

  async function chatSse(sessionId, messages) {
    const res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
      body: JSON.stringify({ sessionId, messages }),
    });
    const text = await res.text();
    const frames = text.split('\n')
      .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
      .map((l) => JSON.parse(l.slice(6)));
    return { status: res.status, frames, complete: frames.find((f) => f.type === 'complete') };
  }

  before(async () => {
    await new Promise((resolve, reject) => {
      proc = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: {
          ...process.env,
          PORT: String(PORT),
          DATABASE_URL: '',
          SQLITE_PATH: dbPath,
          ANTHROPIC_MOCK: '1',
          ANTHROPIC_API_KEY: '',
          ALLOWED_ORIGIN: `http://localhost:${PORT}`,
          NODE_ENV: 'test',
          DISCORD_WEBHOOK_URL: '',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let started = false;
      proc.stdout.on('data', (c) => {
        if (!started && c.toString().includes('Mercurius')) { started = true; setTimeout(resolve, 300); }
      });
      proc.stderr.on('data', (c) => {
        const t = c.toString();
        if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
      });
      proc.on('error', reject);
      proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
      setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
    });
  });

  after(() => { if (proc) proc.kill('SIGKILL'); });

  test('GET empty → PUT → GET merged → downgrade ignored → the chat handler marks the lesson itself → DELETE clears it', async () => {
    const s = sid();

    // GET for an id the server has never seen: empty, and no session row.
    let res = await call('GET', `/api/progress/${s}`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, { curriculumVersion: null, lessons: [], units: [] });
    assert.equal(await db.sessionExists(s), false, 'a read never creates a session row');

    // PUT: the merged state comes back, and the session now exists (so the
    // retention cascade covers the rows).
    res = await call('PUT', `/api/progress/${s}`, { curriculumVersion: 3, items: [lesson('u1_l1'), unit('unit_1')] });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.curriculumVersion, 3);
    assert.deepEqual(res.json.lessons.map((l) => [l.id, l.status]), [['u1_l1', 'completed']]);
    assert.deepEqual(res.json.units.map((u) => [u.id, u.status]), [['unit_1', 'mastered']]);
    assert.ok(Number.isInteger(res.json.lessons[0].updatedAt) && res.json.lessons[0].updatedAt > 0);
    assert.equal(await db.sessionExists(s), true);
    const afterPut = res.json;

    res = await call('GET', `/api/progress/${s}`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, afterPut, 'GET reads back exactly what PUT returned');

    // A downgrade (unit mastered → completed) and an older version are ignored.
    res = await call('PUT', `/api/progress/${s}`, { curriculumVersion: 2, items: [unit('unit_1', 'completed')] });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, afterPut, 'nothing moved: status, timestamp and version all kept');

    // Belt and braces, JSON path: five user turns → the mock emits
    // [LESSON_COMPLETE] → the server records u1_l2 itself, reusing the
    // session's stored curriculum version (3), not 1.
    res = await call('POST', '/api/chat', { sessionId: s, messages: thread(1, 2) });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.lessonComplete, true);
    await sleep(200); // the write is fire-and-forget
    res = await call('GET', `/api/progress/${s}`);
    assert.equal(res.json.curriculumVersion, 3);
    assert.deepEqual(res.json.lessons.map((l) => [l.id, l.status]), [['u1_l1', 'completed'], ['u1_l2', 'completed']]);

    // Same on the SSE path (the iOS client's path).
    const sse = await chatSse(s, thread(1, 3));
    assert.equal(sse.status, 200);
    assert.ok(sse.complete, 'a complete frame arrived');
    assert.equal(sse.complete.lessonComplete, true);
    await sleep(200);
    res = await call('GET', `/api/progress/${s}`);
    assert.deepEqual(res.json.lessons.map((l) => l.id), ['u1_l1', 'u1_l2', 'u1_l3']);

    // A thread that is NOT complete yet (2 turns) writes nothing.
    res = await call('POST', '/api/chat', { sessionId: s, messages: thread(1, 4, 2) });
    assert.equal(res.status, 200);
    assert.equal(res.json.lessonComplete, false);
    await sleep(200);
    res = await call('GET', `/api/progress/${s}`);
    assert.deepEqual(res.json.lessons.map((l) => l.id), ['u1_l1', 'u1_l2', 'u1_l3']);

    // Erasure clears it.
    res = await call('DELETE', `/api/session/${s}`);
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.deleted.curriculum_progress, 4, 'three lessons + one unit');
    res = await call('GET', `/api/progress/${s}`);
    assert.deepEqual(res.json, { curriculumVersion: null, lessons: [], units: [] });
  });

  test('the server-side write starts a fresh session at curriculum version 1 (JSON path, u1_l1)', async () => {
    const s = sid();
    const res = await call('POST', '/api/chat', { sessionId: s, messages: thread(1, 1) });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.lessonComplete, true);
    await sleep(200);
    const got = await call('GET', `/api/progress/${s}`);
    assert.equal(got.status, 200);
    assert.equal(got.json.curriculumVersion, 1);
    assert.deepEqual(got.json.lessons.map((l) => [l.id, l.status]), [['u1_l1', 'completed']]);
    assert.deepEqual(got.json.units, []);
    // Once more: the client keeps the passed thread open, so a later turn is
    // a no-op here (still one row, same timestamp).
    const first = got.json.lessons[0].updatedAt;
    await call('POST', '/api/chat', { sessionId: s, messages: thread(1, 1, 6) });
    await sleep(200);
    const again = await call('GET', `/api/progress/${s}`);
    assert.deepEqual(again.json.lessons, [{ id: 'u1_l1', status: 'completed', updatedAt: first }]);
  });

  test('invalid session ids and bodies are 400s, and nothing is stored', async () => {
    for (const bad of ['not%20valid', 'has.dot', 'x'.repeat(65)]) {
      const g = await call('GET', `/api/progress/${bad}`);
      assert.equal(g.status, 400, `GET ${bad} → ${g.status}`);
      assert.equal(g.json.error, 'invalid_session');
      const p = await call('PUT', `/api/progress/${bad}`, { curriculumVersion: 1, items: [] });
      assert.equal(p.status, 400, `PUT ${bad} → ${p.status}`);
      assert.equal(p.json.error, 'invalid_session');
    }

    const s = sid();
    const bodies = [
      { curriculumVersion: 1, items: [lesson('lesson_1')] },
      { curriculumVersion: 1, items: [{ id: 'unit_1', type: 'lesson', status: 'completed' }] },
      { curriculumVersion: 1, items: [lesson('u1_l1', 'in_progress')] },
      { curriculumVersion: 0, items: [] },
      { curriculumVersion: 1, items: [], extra: 1 },
      { curriculumVersion: 1, items: Array.from({ length: 201 }, (_, i) => lesson(`u1_l${i + 1}`)) },
      { items: [] },
    ];
    for (const body of bodies) {
      const res = await call('PUT', `/api/progress/${s}`, body);
      assert.equal(res.status, 400, `${JSON.stringify(body).slice(0, 80)} → ${res.status}`);
      assert.equal(res.json.error, 'invalid_request');
    }
    assert.equal(await db.sessionExists(s), false, 'a rejected PUT creates nothing');
    assert.deepEqual(await db.getProgress(s), { curriculumVersion: null, lessons: [], units: [] });
  });
});
