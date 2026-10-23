'use strict';

// Basics lessons are exempt from the Socratic homework machinery (merge of
// PR #44 into PR #54, 2026-10-22). A Basics practice turn has Merc write the
// learner's note, list or answer on purpose, so a Basics turn must get:
//
//   - no answer guard (no regeneration, no redaction, no held-back reply);
//   - no writing transforms (one question mark, menu cut, preamble drop);
//   - no adaptive thinking (its temperature and 2,048-token budget stay);
//   - no homework note (STEP CHECK, WRITING, NEXT MOVE …) in the dynamic
//     block, which holds only the Basics runtime note.
//
// The same learner text in free chat still gets all of them. Both halves run
// the real server with ANTHROPIC_MOCK=1 and MOCK_CAPTURE_FILE, in both
// USE_UNIFIED_PROMPT states; no model is called.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const { spawnServer } = require('./support/spawnServer');
const { reflowText } = require('../lib/airyReflow');
const { basicsVoiceText } = require('../lib/basicsVoice');
const systemBlocks = require('../lib/systemBlocks');
const { SAFETY_CORE } = require('../lib/safetyCore');
const {
  BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, basicsRuntimeBlock, platformFromCapabilities,
} = require('../lib/basicsGuide');

const BASICS_TAG = '[BASICS: Unit 1, Lesson 1]';
const CONTRACT = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.";
const OPENER = `${BASICS_TAG} Teach me what an AI chatbot is, in plain words. Keep it short, then let me try one.${CONTRACT}`;
const IOS_CAPS = ['blocks_v1', 'platform_ios'];
// Every homework note, and the guard's retry note, is headed "## NAME (…this
// reply only…)": STEP CHECK, ATOM COUNT, THEIR NUMBER, NEXT MOVE, WRITING,
// THEIR TEXT, THEIR WORDS, PHOTO, EXPLAIN MORE, ANSWER GUARD. (The Basics
// guide's own "## EXPLAIN MORE" note has no such heading.)
const HOMEWORK_HEADINGS = /## [A-Z ]+\([^)\n]*this reply only/;

const b64 = (t) => Buffer.from(t, 'utf8').toString('base64');
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');
const nonce = () => crypto.randomBytes(5).toString('hex');

// The Basics post-processing, and nothing else: the voice clean-up, then the
// 2-sentence reflow with keepQuotes and numberedLists.
const basicsShape = (text) => reflowText(basicsVoiceText(text), 2, { keepQuotes: true, numberedLists: true });

const servers = {};
const spawned = [];

async function boot(name, unified) {
  const tag = crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-basics-hw-${name}-${tag}.db`);
  const captureFile = path.join(os.tmpdir(), `merc-basics-hw-${name}-${tag}.jsonl`);
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    MOCK_CAPTURE_FILE: captureFile,
    USE_UNIFIED_PROMPT: unified ? '1' : '0',
    SESSION_PER_MIN: '1000',
    CHAT_IP_PER_MIN: '1000',
    IP_DAILY_NEW_SESSIONS: '1000',
  });
  spawned.push(server.proc);
  const { base } = await server.ready;
  return { base, dbPath, captureFile };
}

before(async () => {
  [servers.on, servers.off] = await Promise.all([boot('on', true), boot('off', false)]);
});

after(() => {
  for (const proc of spawned) proc.kill('SIGKILL');
  for (const s of Object.values(servers)) {
    for (const f of [s.captureFile, s.dbPath, s.dbPath + '-wal', s.dbPath + '-shm']) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

async function chatSse(server, body) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  assert.equal(res.status, 200, await res.clone().text());
  const frames = (await res.text()).split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  return { deltas: frames.filter((f) => f.type === 'delta').map((f) => f.text), complete: frames.find((f) => f.type === 'complete') };
}

async function chatJson(server, body) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  assert.equal(res.status, 200);
  return res.json();
}

function captured(server, marker) {
  if (!fs.existsSync(server.captureFile)) return [];
  return fs.readFileSync(server.captureFile, 'utf8').split('\n').filter((l) => l && l.includes(marker)).map((l) => JSON.parse(l));
}

/** The iOS Basics wire shape: the hidden opener, Merc's first reply, the
 *  visible thread `turns`, and the last user turn re-tagged with the
 *  opener's tag. */
function basicsBody(sessionId, turns) {
  const messages = [
    { role: 'user', content: OPENER },
    { role: 'assistant', content: 'A chatbot is a program you talk to by typing.\n\nTry asking me: "What should I cook tonight?"' },
    ...turns,
  ];
  const last = messages.length - 1;
  messages[last] = { role: 'user', content: `${BASICS_TAG} ${messages[last].content}` };
  return { sessionId, responseMode: 'concise', capabilities: IOS_CAPS, messages };
}

/** The same visible thread as free chat (no lesson tag). */
function chatBody(sessionId, turns) {
  return { sessionId, responseMode: 'concise', capabilities: IOS_CAPS, messages: turns };
}

/** A learner who sends an equation, then asks again ("idk") — in free chat
 *  that arms the answer guard, adds a homework note and turns thinking on. */
const equationThread = (n, reply) => [
  { role: 'user', content: `what is 3x+5 = 20 (${n})` },
  { role: 'assistant', content: 'What happens if you get the 3x by itself first?' },
  { role: 'user', content: `idk MOCK_SAY_B64:${b64(reply)}` },
];
const oneTurn = (text) => [{ role: 'user', content: text }];

/** One Basics call: the Basics prefix and runtime note only, its own
 *  temperature, the lesson budget, and no thinking. */
function assertBasicsCall(call) {
  assert.equal(call.thinking, undefined, 'no adaptive thinking');
  assert.equal(call.output_config, undefined, 'no effort setting');
  assert.equal(typeof call.temperature, 'number', 'keeps its temperature');
  assert.equal(call.max_tokens, 2048, 'the lesson budget, with no thinking headroom');
  assert.ok(Array.isArray(call.system) && call.system.length === 2, 'static + dynamic');
  assert.equal(call.system[0].text, systemBlocks.composeStaticWithAppFacts([BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, SAFETY_CORE]),
    'the Basics prefix, byte for byte');
  const date = /Today's date: (\d{4}-\d{2}-\d{2})\./.exec(call.system[1].text)[1];
  assert.equal(call.system[1].text, basicsRuntimeBlock({ currentDate: date, platform: platformFromCapabilities(IOS_CAPS), responseMode: 'concise' }),
    'the dynamic block is the Basics runtime note, nothing appended');
  assert.ok(!HOMEWORK_HEADINGS.test(call.system.map((b) => b.text).join('\n')), 'no homework note');
}

// A practice reply that would trip the answer guard in free chat (it states
// the answer to the learner's equation) and the writing transforms (two
// question marks).
const EQUATION_REPLY = 'Here is the answer to your sum: 3x + 5 = 20, so x = 5.\n\nWant me to show the steps? Or try another one?';
// A practice reply to "rewrite my note", Merc writing it for the learner as
// Basics teaches: in free chat this is a writing turn, held back and cut to
// one question mark.
const WRITING_REPLY = 'Here is a friendlier version:\n\n"Hi Sam, could you fix the sink today? Thank you so much!"\n\nDoes that sound like you? Want it shorter?';

for (const flag of ['on', 'off']) {
  describe(`Basics is exempt from the homework machinery, flag ${flag}`, () => {
    test('a Basics turn on an equation, with a reply that states its answer: one call, no thinking, no note, streamed, not rewritten', async () => {
      const n = nonce();
      const { deltas, complete } = await chatSse(servers[flag], basicsBody(sid(), equationThread(n, EQUATION_REPLY)));
      const calls = captured(servers[flag], n);
      assert.equal(calls.length, 1, 'no answer-guard retry');
      assertBasicsCall(calls[0]);
      assert.equal(complete.reply, basicsShape(EQUATION_REPLY), 'only the Basics voice and reflow touch it');
      assert.match(complete.reply, /x = 5/, 'never redacted');
      assert.equal((complete.reply.match(/\?/g) || []).length, 2, 'no one-question cut');
      assert.equal(deltas.join(''), complete.reply);
      assert.ok(deltas.length > 1, `streamed as it comes, not held back (${deltas.length} deltas)`);
    });

    test('the same thread in free chat: thinking, a homework note, the guard note on a retry, sent whole, redacted', async () => {
      const n = nonce();
      const { deltas, complete } = await chatSse(servers[flag], chatBody(sid(), equationThread(n, EQUATION_REPLY)));
      const calls = captured(servers[flag], n);
      assert.equal(calls.length, 2, 'the draft, then the guard retry');
      assert.deepEqual(calls[0].thinking, { type: 'adaptive' });
      assert.deepEqual(calls[0].output_config, { effort: 'low' });
      assert.equal(calls[0].temperature, undefined);
      assert.ok(calls[0].max_tokens >= 3000, `max_tokens ${calls[0].max_tokens}`);
      assert.match(calls[0].system.map((b) => b.text).join('\n'), HOMEWORK_HEADINGS, 'a homework note in the dynamic block');
      assert.match(calls[1].system.map((b) => b.text).join('\n'), /## ANSWER GUARD/);
      assert.ok(!/x = 5\b/.test(complete.reply), complete.reply);
      assert.equal(deltas.length, 1, 'held back and sent whole');
    });

    test('a Basics "rewrite my note" practice is not a writing turn; in free chat it is', async () => {
      const ask = 'Rewrite my note so it sounds friendlier: Fix the sink. It is broken. Come today.';
      const n = nonce();
      const basics = await chatSse(servers[flag], basicsBody(sid(), oneTurn(`${ask} (${n}) MOCK_SAY_B64:${b64(WRITING_REPLY)}`)));
      const [basicsCall, ...extra] = captured(servers[flag], n);
      assert.equal(extra.length, 0, 'no quote retry');
      assertBasicsCall(basicsCall);
      assert.equal(basics.complete.reply, basicsShape(WRITING_REPLY));
      assert.equal((basics.complete.reply.match(/\?/g) || []).length, 3, 'its questions kept (one is inside the note)');
      assert.ok(basics.deltas.length > 1, 'streamed, not held back');

      const m = nonce();
      const chat = await chatSse(servers[flag], chatBody(sid(), oneTurn(`${ask} (${m}) MOCK_SAY_B64:${b64(WRITING_REPLY)}`)));
      const [chatCall] = captured(servers[flag], m);
      assert.match(chatCall.system.map((b) => b.text).join('\n'), /## THEIR TEXT|## WRITING/, 'a writing note in free chat');
      assert.equal(chat.deltas.length, 1, 'a free-chat writing turn is held back');
      assert.ok((chat.complete.reply.match(/\?/g) || []).length < 3, 'and tidied');
    });

    test('the JSON path: a Basics reply is never guarded; the free-chat one is', async () => {
      const n = nonce();
      const basics = await chatJson(servers[flag], basicsBody(sid(), equationThread(n, EQUATION_REPLY)));
      const calls = captured(servers[flag], n);
      assert.equal(calls.length, 1);
      assertBasicsCall(calls[0]);
      assert.equal(basics.reply, basicsShape(EQUATION_REPLY));

      const m = nonce();
      const chat = await chatJson(servers[flag], chatBody(sid(), equationThread(m, EQUATION_REPLY)));
      assert.equal(captured(servers[flag], m).length, 2, 'the draft, then the guard retry');
      assert.ok(!/x = 5\b/.test(chat.reply), chat.reply);
    });
  });
}
