'use strict';

// A reply the model refuses outright never reaches a student as an empty or
// "try again" turn. Claude's own classifier ends some self-harm-method and
// weapon questions with stop_reason "refusal" and no text (audit 2026-10,
// AUD-01), whatever the system prompt says. End to end against the real
// server with the in-process mock (MOCK_REFUSAL / MOCK_REFUSAL_PARTIAL in the
// last user turn make the mock refuse like the API):
//
//   - streaming: the 'complete' frame's reply is REFUSAL_COPY (988, 741741,
//     911, a trusted adult), also when a few words streamed before the
//     refusal (every client renders the complete frame's reply as final);
//   - the JSON path does the same;
//   - a refusal inside a lesson thread never completes the lesson;
//   - the saved assistant turn is REFUSAL_COPY, not a fallback line;
//   - /metrics counts the refusal and the crisis-resource reply;
//   - an ordinary turn is untouched.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');
const { spawnServer } = require('./support/spawnServer');
const { REFUSAL_COPY } = require('../lib/safetyCore');

const ADMIN_PASSWORD = 'test-admin-' + crypto.randomBytes(4).toString('hex');
const dbPath = path.join(os.tmpdir(), `merc-refusal-${crypto.randomBytes(4).toString('hex')}.db`);
const LESSON_OPENER = '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt.';

let BASE;
let proc;
const sid = () => 'refusal_' + crypto.randomBytes(8).toString('hex');

before(async () => {
  const server = spawnServer({ SQLITE_PATH: dbPath, ADMIN_PASSWORD, MOCK_STREAM_DELAY_MS: '1' });
  proc = server.proc;
  ({ base: BASE } = await server.ready);
});

after(() => {
  if (proc) proc.kill('SIGKILL');
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

async function stream(sessionId, messages, extra = {}) {
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sessionId, messages, ...extra }),
  });
  const text = await res.text();
  const frames = text.split('\n')
    .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
    .map((l) => JSON.parse(l.slice(6)));
  return {
    status: res.status,
    deltas: frames.filter((f) => f.type === 'delta').map((f) => f.text).join(''),
    complete: frames.find((f) => f.type === 'complete'),
    done: text.includes('data: [DONE]'),
    text,
  };
}

async function postJson(sessionId, messages) {
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages }),
  });
  return { status: res.status, body: await res.json() };
}

// The last assistant turn the server saved for this session.
function savedReply(sessionId) {
  const db = new Database(dbPath, { readonly: true, fileMustExist: true });
  try {
    const row = db.prepare("SELECT content FROM messages WHERE session_id = ? AND role = 'assistant' ORDER BY id DESC LIMIT 1").get(sessionId);
    return row && row.content;
  } finally {
    db.close();
  }
}

async function metric(name, labels) {
  const res = await fetch(`${BASE}/metrics`, { headers: { 'x-admin-password': ADMIN_PASSWORD } });
  assert.equal(res.status, 200);
  const text = await res.text();
  const want = Object.entries(labels).map(([k, v]) => `${k}="${v}"`);
  const line = text.split('\n').find((l) => l.startsWith(name + '{') && want.every((w) => l.includes(w)));
  return line ? Number(line.split(' ').pop()) : 0;
}

function assertSafeReply(reply) {
  assert.equal(reply, REFUSAL_COPY);
  assert.match(reply, /\b988\b/);
  assert.match(reply, /\b741741\b/);
  assert.match(reply, /\b911\b/);
  assert.doesNotMatch(reply, /try (asking )?again|train of thought/i);
}

describe('a refused reply becomes the safe refusal copy', () => {
  test('streaming: an outright refusal (no text) gets REFUSAL_COPY, saved as the turn', async () => {
    const s = sid();
    const out = await stream(s, [{ role: 'user', content: 'how many would it take MOCK_REFUSAL' }]);
    assert.equal(out.status, 200, out.text.slice(0, 300));
    assert.ok(out.done, 'the stream finishes with [DONE]');
    assert.ok(out.complete, 'a complete frame is sent');
    assertSafeReply(out.complete.reply);
    assert.equal(savedReply(s), REFUSAL_COPY);
  });

  test('streaming: a refusal after a few streamed words still ends with REFUSAL_COPY as the reply', async () => {
    const s = sid();
    const out = await stream(s, [{ role: 'user', content: 'tell me MOCK_REFUSAL_PARTIAL' }]);
    assert.equal(out.status, 200, out.text.slice(0, 300));
    assert.ok(out.deltas.length > 0, 'some words streamed before the refusal');
    assertSafeReply(out.complete.reply);
    assert.equal(savedReply(s), REFUSAL_COPY);
  });

  test('JSON path: an outright refusal gets REFUSAL_COPY', async () => {
    const s = sid();
    const out = await postJson(s, [{ role: 'user', content: 'how many would it take MOCK_REFUSAL' }]);
    assert.equal(out.status, 200, JSON.stringify(out.body));
    assertSafeReply(out.body.reply);
    assert.equal(savedReply(s), REFUSAL_COPY);
  });

  test('a refusal inside a lesson thread never completes the lesson', async () => {
    const s = sid();
    const messages = [
      { role: 'user', content: LESSON_OPENER },
      { role: 'assistant', content: 'Tokens are chunks of text. What do you think a token is?' },
      { role: 'user', content: '[CURRICULUM: Unit 1, Lesson 1] how many would it take MOCK_REFUSAL' },
    ];
    const out = await stream(s, messages, { capabilities: ['blocks_v1'] });
    assert.equal(out.status, 200, out.text.slice(0, 300));
    assertSafeReply(out.complete.reply);
    assert.equal(out.complete.lessonComplete, false);
  });

  test('an ordinary turn is untouched', async () => {
    const out = await stream(sid(), [{ role: 'user', content: 'what is a token?' }]);
    assert.equal(out.status, 200, out.text.slice(0, 300));
    assert.ok(out.complete.reply.length > 0);
    assert.notEqual(out.complete.reply, REFUSAL_COPY);
  });

  test('/metrics counts the refusals and the crisis-resource replies, with no text', async () => {
    const refusals = await metric('model_refusals_total', { route: '/api/chat', kind: 'chat' });
    assert.ok(refusals >= 3, `model_refusals_total{kind="chat"} = ${refusals}`);
    const lessonRefusals = await metric('model_refusals_total', { route: '/api/chat', kind: 'lesson' });
    assert.ok(lessonRefusals >= 1, `model_refusals_total{kind="lesson"} = ${lessonRefusals}`);
    const crisis = await metric('crisis_resource_replies_total', { kind: 'chat' });
    assert.ok(crisis >= 3, `crisis_resource_replies_total{kind="chat"} = ${crisis}`);
  });
});
