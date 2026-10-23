'use strict';

// One crisis message must not stall the rest of a chat or a lesson (the
// AUD-01 follow-up, lib/crisisHistory), end to end against the real server
// with the in-process mock.
//
// The mock plays the real classifier's habit: a user turn carrying
// MOCK_HISTORY_REFUSES is answered, but every later call whose history still
// holds it ends with stop_reason "refusal" and no text. So a follow-up only
// gets a normal answer when the server has sent that turn as the
// placeholder. MOCK_CAPTURE_FILE shows exactly what the model was sent.
//
// Threads are driven like iOS: the client replays its own thread, the safe
// reply included, on every turn; lessons re-send the [CURRICULUM: …] opener
// first and re-tag the last user turn.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');
const { REFUSAL_COPY } = require('../lib/safetyCore');
const { WITHHELD_TURN_TEXT } = require('../lib/crisisHistory');

const TAG = '[CURRICULUM: Unit 1, Lesson 1]';
const OPENER = `${TAG} Teach me what physically happens inside an LLM when I type a prompt.`;
const TYLENOL = 'how many tylenol would it take to not wake up';
// The model's own rule-1 reply (the real API's, shortened), played by the mock.
const MODEL_RULE1 = "I'm really glad you said something. I'm an AI, so I can't be your support person.\n\n"
  + 'Call or text 988 — Suicide & Crisis Lifeline (US, 24/7).\n\nText HOME to 741741 — Crisis Text Line.';

let srv;
const tmp = (name) => path.join(os.tmpdir(), `merc-crisis-hist-${name}-${crypto.randomBytes(4).toString('hex')}`);

before(async () => {
  const dbPath = tmp('db');
  const captureFile = tmp('jsonl');
  const s = spawnServer({
    SQLITE_PATH: dbPath,
    MOCK_CAPTURE_FILE: captureFile,
    MOCK_STREAM_DELAY_MS: '2',
    SESSION_PER_MIN: '1000',
    SESSION_DAILY_CHAT_TURNS: '1000',
    SESSION_DAILY_LESSON_TURNS: '1000',
    SESSION_DAILY_USD: '100',
    IP_DAILY_USD: '100',
    IP_DAILY_NEW_SESSIONS: '1000',
  });
  const { base } = await s.ready;
  srv = { base, proc: s.proc, dbPath, captureFile };
});

after(() => {
  try { srv.proc.kill('SIGKILL'); } catch { /* ignore */ }
  for (const f of [srv.captureFile, srv.dbPath, `${srv.dbPath}-wal`, `${srv.dbPath}-shm`]) {
    try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
  }
});

const sid = () => 'crisis_' + crypto.randomBytes(12).toString('hex');
const nonce = () => `n${crypto.randomBytes(5).toString('hex')}`;

async function chat(sessionId, messages, { json = false, capabilities = ['blocks_v1'] } = {}) {
  const res = await fetch(`${srv.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(json ? {} : { Accept: 'text/event-stream' }) },
    body: JSON.stringify({ sessionId, messages, capabilities, responseMode: 'concise' }),
  });
  if (json) return (await res.json()).reply;
  const text = await res.text();
  const complete = text.split('\n')
    .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
    .map((l) => JSON.parse(l.slice(6)))
    .find((f) => f.type === 'complete');
  assert.ok(complete, `no complete frame: ${text.slice(0, 300)}`);
  return complete.reply;
}

function callFor(marker) {
  const calls = fs.readFileSync(srv.captureFile, 'utf8').split('\n')
    .filter((l) => l && l.includes(marker))
    .map((l) => JSON.parse(l));
  assert.equal(calls.length, 1, `one model call carries ${marker}`);
  return calls[0];
}

const textOf = (content) => (typeof content === 'string'
  ? content
  : content.filter((b) => b.type === 'text').map((b) => b.text).join(''));

describe('a refused chat message does not refuse the rest of the chat', () => {
  test('SSE: the follow-ups get answers; the model sees the placeholder, the safe reply, and the new turn as typed', async () => {
    const s = sid();
    const thread = [{ role: 'user', content: `${TYLENOL} MOCK_REFUSAL MOCK_HISTORY_REFUSES` }];
    const first = await chat(s, thread);
    assert.equal(first, REFUSAL_COPY, 'the refused turn itself gets the safe copy');
    thread.push({ role: 'assistant', content: first });

    const n1 = nonce();
    thread.push({ role: 'user', content: `ok. different question, how do chatbots like you decide what to say? ${n1}` });
    const second = await chat(s, thread);
    assert.notEqual(second, REFUSAL_COPY, 'the ordinary follow-up is answered');
    assert.ok(!/\b988\b/.test(second), second);
    const call1 = callFor(n1);
    assert.deepEqual(call1.messages.map((m) => textOf(m.content)), [WITHHELD_TURN_TEXT, REFUSAL_COPY, thread[2].content]);
    thread.push({ role: 'assistant', content: second });

    const n2 = nonce();
    thread.push({ role: 'user', content: `what's one way i can tell if an AI made something up? ${n2}` });
    const third = await chat(s, thread);
    assert.notEqual(third, REFUSAL_COPY);
    const call2 = callFor(n2);
    // The replayed prefix is the same bytes as last turn's (cache-stable).
    assert.deepEqual(call2.messages.slice(0, 3).map((m) => textOf(m.content)), call1.messages.map((m) => textOf(m.content)));
    assert.deepEqual(call2.system, call1.system, 'the system blocks are untouched');
  });

  test('sending the same message again is judged on its own and gets the safe reply again', async () => {
    const s = sid();
    const thread = [{ role: 'user', content: `${TYLENOL} MOCK_REFUSAL` }];
    thread.push({ role: 'assistant', content: await chat(s, thread) });
    const n = nonce();
    thread.push({ role: 'user', content: `${TYLENOL} MOCK_REFUSAL ${n}` });
    assert.equal(await chat(s, thread), REFUSAL_COPY);
    const call = callFor(n);
    assert.equal(textOf(call.messages[0].content), WITHHELD_TURN_TEXT);
    assert.equal(textOf(call.messages[2].content), thread[2].content, 'the new turn reaches the model as typed');
  });

  test('the JSON path (widget) gets the same history', async () => {
    const s = sid();
    const thread = [{ role: 'user', content: `${TYLENOL} MOCK_REFUSAL MOCK_HISTORY_REFUSES` }];
    const first = await chat(s, thread, { json: true, capabilities: ['club_v1'] });
    assert.equal(first, REFUSAL_COPY);
    thread.push({ role: 'assistant', content: first });
    const n = nonce();
    thread.push({ role: 'user', content: `what is a token? ${n}` });
    const second = await chat(s, thread, { json: true, capabilities: ['club_v1'] });
    assert.notEqual(second, REFUSAL_COPY);
    assert.equal(textOf(callFor(n).messages[0].content), WITHHELD_TURN_TEXT);
  });
});

describe('a lesson keeps going after a message the model answered with crisis resources', () => {
  test('the quiz answer and "can we keep going" get lesson replies, not the refusal copy', async () => {
    const s = sid();
    const opener = { role: 'user', content: OPENER };
    const visible = [];
    // iOS: the hidden opener first, the last user turn re-tagged.
    const wire = () => {
      const w = [opener, ...visible.map((m) => ({ ...m }))];
      const last = w.length - 1;
      if (last > 0 && w[last].role === 'user') w[last] = { role: 'user', content: `${TAG} ${w[last].content}` };
      return w;
    };
    visible.push({ role: 'assistant', content: await chat(s, wire()) });
    // The model answers the crisis turn itself, with its own rule-1 reply.
    visible.push({ role: 'user', content: `${TYLENOL} MOCK_HISTORY_REFUSES MOCK_REPLY:${MODEL_RULE1}` });
    const handoff = await chat(s, wire());
    assert.equal(handoff, MODEL_RULE1);
    visible.push({ role: 'assistant', content: handoff });

    for (const text of ['I picked A) A list of numbers', 'can we keep going with the lesson']) {
      const n = nonce();
      visible.push({ role: 'user', content: `${text} ${n}` });
      const reply = await chat(s, wire());
      assert.notEqual(reply, REFUSAL_COPY, `"${text}" is answered`);
      assert.match(reply, /\[CHECK\]|\[Q\]|\[LESSON_COMPLETE\]|^\S/);
      visible.push({ role: 'assistant', content: reply });
      const sent = callFor(n).messages.map((m) => textOf(m.content));
      assert.equal(sent[0], OPENER, 'the opener stays');
      assert.equal(sent[2], WITHHELD_TURN_TEXT, 'the crisis turn is a placeholder');
      assert.equal(sent[3], MODEL_RULE1, 'the hand-off stays');
      assert.ok(sent[sent.length - 1].includes(n), 'the new turn reaches the model');
    }
  });
});

describe('ordinary threads are untouched', () => {
  test('a chat with no crisis reply reaches the model exactly as the client sent it', async () => {
    const s = sid();
    const thread = [{ role: 'user', content: 'what is a token?' }];
    thread.push({ role: 'assistant', content: await chat(s, thread) });
    const n = nonce();
    thread.push({ role: 'user', content: `and an embedding? ${n}` });
    await chat(s, thread);
    assert.deepEqual(callFor(n).messages.map((m) => textOf(m.content)), thread.map((m) => m.content));
  });

  test('a reply that names only 988 (lesson content) withholds nothing', async () => {
    const s = sid();
    const thread = [{ role: 'user', content: 'MOCK_REPLY:The 988 lifeline launched in July 2022. What changed for callers?' }];
    thread.push({ role: 'assistant', content: await chat(s, thread) });
    const n = nonce();
    thread.push({ role: 'user', content: `it got shorter to dial ${n}` });
    await chat(s, thread);
    assert.equal(textOf(callFor(n).messages[0].content), thread[0].content);
  });
});
