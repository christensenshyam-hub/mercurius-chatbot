'use strict';

/**
 * Lesson funnel starts come from lesson_events, not the wire thread (the
 * AUD-29 follow-up from PR #43's review).
 *
 * Since AUD-29 the iOS client keeps a cut-off reply in the thread, so a
 * student who answers a cut-off opener sends [opener, cut-off reply, answer].
 * The thread rule (turn 1, or no reply yet) logged that as a 'turn', so the
 * attempt never got a 'start', and on a retake the new 'complete' was dropped
 * as a repeat of the last attempt's.
 *
 * Boots the real server on the mock (no key) with its own SQLite file, which
 * this process also opens through db.js to read lesson_events.
 */

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');
const { waitFor } = require('./support/waitFor');

const dbPath = path.join(os.tmpdir(), `merc-lesson-start-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath; // before db.js is required
delete process.env.DATABASE_URL;
const db = require('../db');

let BASE;
let proc;
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const OPENER = '[CURRICULUM: Unit 1, Lesson 1] Teach me what a token is.';
const PARTIAL = 'A token is a small piece of';

before(async () => {
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    // The first reply is slow enough to leave after its first words.
    MOCK_STREAM_DELAY_MS: '20',
    SESSION_PER_MIN: '100',
  });
  proc = server.proc;
  ({ base: BASE } = await server.ready);
  await db.initSchema();
});

after(() => {
  if (proc) proc.kill('SIGKILL');
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

const rowsFor = async (s) => (await db.lessonEventsSince(0)).filter((r) => r.session_id === s);
// The rows are written after the reply, fire-and-forget: wait for the count,
// then a beat more so a stray extra row would show.
async function events(s, n) {
  await waitFor(() => rowsFor(s), (rows) => rows.length >= n);
  await sleep(150);
  return (await rowsFor(s)).map((r) => [r.event, r.turn_index]);
}

/** A streamed turn, read to the end, or left after the first delta. */
async function sse(s, messages, { leaveAfterFirstDelta = false } = {}) {
  const ac = new AbortController();
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sessionId: s, messages }),
    signal: ac.signal,
  });
  assert.equal(res.status, 200);
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let raw = '';
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      raw += decoder.decode(value, { stream: true });
      if (leaveAfterFirstDelta && raw.includes('"type":"delta"')) {
        ac.abort();
        break;
      }
    }
  } catch (e) {
    if (!leaveAfterFirstDelta) throw e;
  }
  const out = raw.split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  return out.find((e) => e.type === 'complete') || null;
}

// [opener, a, u, a, u, …] with `answers` user turns after the opener; the
// first assistant turn can be the cut-off one.
function thread(answers, { firstReply = 'Here is the first idea.' } = {}) {
  const m = [{ role: 'user', content: OPENER }];
  for (let i = 1; i <= answers; i++) {
    m.push({ role: 'assistant', content: i === 1 ? firstReply : 'Here is the next idea.' });
    m.push({ role: 'user', content: `Answer ${i}: a token is a chunk of text.` });
  }
  return m;
}

describe('lesson starts come from lesson_events', () => {
  test('answering a cut-off opener is the start (the PR #43 review case)', async () => {
    const s = sid();
    // The opener's reply is cut off after its first words: no row.
    await sse(s, thread(0), { leaveAfterFirstDelta: true });
    await sleep(300);
    assert.deepEqual(await rowsFor(s), [], 'a cut-off reply writes no funnel row');

    // The student types an answer under it: [opener, cut-off reply, answer].
    const answered = await sse(s, thread(1, { firstReply: PARTIAL }));
    assert.ok(answered, 'the answer got a reply');
    assert.deepEqual(await events(s, 1), [['start', 2]], 'it starts the attempt');

    // The next answer is a turn of that attempt.
    await sse(s, thread(2, { firstReply: PARTIAL }));
    assert.deepEqual(await events(s, 2), [['start', 2], ['turn', 3]]);
  });

  test("a retake after a pass starts again and its pass is counted, even when the retake's opener was cut off", async () => {
    const s = sid();
    await sse(s, thread(0));
    const passed = await sse(s, thread(4)); // the mock passes from the 5th user turn
    assert.equal(passed.lessonComplete, true);
    assert.deepEqual(await events(s, 3), [['start', 1], ['turn', 5], ['complete', 5]]);

    // The passed thread kept open: one more turn is not a new attempt.
    await sse(s, thread(5));
    assert.deepEqual((await events(s, 4)).slice(3), [['turn', 6]]);

    // A retake whose opener is cut off, answered under the cut-off reply.
    await sse(s, thread(0), { leaveAfterFirstDelta: true });
    await sleep(300);
    await sse(s, thread(1, { firstReply: PARTIAL }));
    assert.deepEqual((await events(s, 5)).slice(4), [['start', 2]], 'the retake starts');

    await sse(s, thread(2, { firstReply: PARTIAL }));
    await sse(s, thread(3, { firstReply: PARTIAL }));
    const retakePassed = await sse(s, thread(4, { firstReply: PARTIAL }));
    assert.equal(retakePassed.lessonComplete, true);
    assert.deepEqual(
      (await events(s, 9)).slice(4),
      [['start', 2], ['turn', 3], ['turn', 4], ['turn', 5], ['complete', 5]],
      "the retake's pass is its own, not a repeat of the first",
    );
  });

  test('the same answered opener sent twice (a Retry the server had already answered) is one start', async () => {
    const s = sid();
    await sse(s, thread(0));
    await sse(s, thread(0));
    assert.deepEqual(await events(s, 2), [['start', 1], ['turn', 1]]);
  });

  test('each lesson has its own attempt', async () => {
    const s = sid();
    await sse(s, thread(0));
    await sse(s, [{ role: 'user', content: '[CURRICULUM: Unit 1, Lesson 2] Teach me about context windows.' }]);
    const rows = await waitFor(() => rowsFor(s), (r) => r.length >= 2);
    assert.deepEqual(rows.map((r) => [r.event, r.lesson_id]).sort(), [['start', 'u1_l1'], ['start', 'u1_l2']]);
  });
});

describe('db.lastLessonMilestone', () => {
  test("the latest 'start' or 'complete' for that session and lesson, ties broken by insertion order", async () => {
    const s = sid();
    assert.equal(await db.lastLessonMilestone(s, 'u2_l1'), null);
    await db.recordLessonEvent({ ts: 1000, sessionId: s, lessonId: 'u2_l1', event: 'start', turnIndex: 1 });
    await db.recordLessonEvent({ ts: 2000, sessionId: s, lessonId: 'u2_l1', event: 'turn', turnIndex: 2 });
    assert.deepEqual(await db.lastLessonMilestone(s, 'u2_l1'), { event: 'start', turnIndex: 1, ts: 1000 }, "a 'turn' is not a milestone");
    await db.recordLessonEvent({ ts: 3000, sessionId: s, lessonId: 'u2_l1', event: 'start', turnIndex: 3 });
    await db.recordLessonEvent({ ts: 3000, sessionId: s, lessonId: 'u2_l1', event: 'complete', turnIndex: 3 });
    assert.deepEqual(await db.lastLessonMilestone(s, 'u2_l1'), { event: 'complete', turnIndex: 3, ts: 3000 });
    assert.equal(await db.lastLessonMilestone(s, 'u2_l2'), null, 'another lesson');
    assert.equal(await db.lastLessonMilestone(sid(), 'u2_l1'), null, 'another session');
  });
});
