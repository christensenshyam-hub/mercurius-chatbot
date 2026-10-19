'use strict';

// The reply transforms end to end, against the real server with the
// in-process mock: a last user turn with MOCK_REPLY: makes the mock "write"
// an exact reply, streamed in 12-character chunks, so a [Q] block always
// arrives split across chunks. For each path the streamed deltas, the
// 'complete' frame's reply, the JSON reply and the saved assistant turn
// must be the same transformed text.
//
//   - AUD-18: blocks_v1 clients get each [Q] block's options in the
//     server's order with ANS rewritten; a malformed [Q] is untouched; a
//     client without blocks_v1 keeps the model's order (and its final reply
//     is scrubbed to prose, as before).
//   - AUD-17: a tight numbered list and a score rubric arrive whole.
//   - AUD-38: blocks_v1 clients get [SOURCE: label — url] as "Source: label
//     (domain)"; the widget (club_v1) keeps the tag for its source pill, and
//     a client without capabilities (iOS 2.0.0) gets the reply as before.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');
const { spawnServer } = require('./support/spawnServer');
const { transformReply } = require('../lib/replyPipeline');
const { parseQuizInterior } = require('../lib/blockMarkup');
const { blocks: REAL_BLOCKS } = require('./fixtures/quizBlocksAudit2026-10.json');

const dbPath = path.join(os.tmpdir(), `merc-transforms-${crypto.randomBytes(4).toString('hex')}.db`);
const LESSON_OPENER = '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt.';
const BLOCKS = ['blocks_v1'];

let BASE;
let proc;
const sid = () => 'xform_' + crypto.randomBytes(8).toString('hex');

before(async () => {
  // Widget turns fetch the club feeds; point them at a closed local port.
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    MOCK_STREAM_DELAY_MS: '1',
    CLUB_EVENTS_URL: 'http://127.0.0.1:1/events-data.json',
    CLUB_BLOG_URL: 'http://127.0.0.1:1/blog-content.json',
    CLUB_FEED_TIMEOUT_MS: '300',
  });
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
  const deltaFrames = frames.filter((f) => f.type === 'delta').map((f) => f.text);
  return {
    status: res.status,
    deltaFrames,
    deltas: deltaFrames.join(''),
    complete: frames.find((f) => f.type === 'complete'),
    text,
  };
}

async function postJson(sessionId, messages, extra = {}) {
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages, ...extra }),
  });
  return { status: res.status, body: await res.json() };
}

function savedReply(sessionId) {
  const db = new Database(dbPath, { readonly: true, fileMustExist: true });
  try {
    const row = db.prepare("SELECT content FROM messages WHERE session_id = ? AND role = 'assistant' ORDER BY id DESC LIMIT 1").get(sessionId);
    return row && row.content;
  } finally {
    db.close();
  }
}

const lessonTurn = (reply) => [{ role: 'user', content: `${LESSON_OPENER}\nMOCK_REPLY:\n${reply}` }];
const quizOf = (text) => {
  const m = /\[Q\]\n?([\s\S]*?)\[\/Q\]/.exec(text);
  return m ? parseQuizInterior(m[1]) : null;
};

const QUIZ_REPLY = `Good start. Tokens come first. Everything else builds on them. Here is why.\n\n${REAL_BLOCKS[0].block}`;

describe('[Q] options in the server order for blocks_v1 clients (AUD-18)', () => {
  test('streaming lesson turn: deltas, complete reply and saved turn are the reordered block', async () => {
    const s = sid();
    const out = await stream(s, lessonTurn(QUIZ_REPLY), { capabilities: BLOCKS });
    assert.equal(out.status, 200, out.text.slice(0, 300));
    const expected = transformReply(QUIZ_REPLY, { limit: 3, rewriteSources: true, shuffleQuiz: true });
    assert.equal(out.deltas, expected);
    assert.equal(out.complete.reply, expected);
    assert.equal(savedReply(s), expected);
    const before = quizOf(QUIZ_REPLY);
    const after = quizOf(out.complete.reply);
    assert.equal(after.wellFormed, true);
    assert.equal(after.options[after.answerIndex], before.options[before.answerIndex], 'ANS follows the right answer');
    assert.notEqual(after.answerIndex, before.answerIndex, 'this check moves off B');
    // The block was held until its [/Q]: no delta frame ever ends inside one.
    let sent = '';
    for (const f of out.deltaFrames) {
      sent += f;
      assert.equal(sent.split('[Q]').length, sent.split('[/Q]').length, 'no partial [Q] block on the wire');
    }
    assert.ok(out.deltaFrames.length > 3, 'the reply streamed in pieces');
  });

  test('JSON path: the same reordered reply, saved as sent', async () => {
    const s = sid();
    const out = await postJson(s, lessonTurn(QUIZ_REPLY), { capabilities: BLOCKS });
    assert.equal(out.status, 200, JSON.stringify(out.body));
    const expected = transformReply(QUIZ_REPLY, { limit: 3, rewriteSources: true, shuffleQuiz: true });
    assert.equal(out.body.reply, expected);
    assert.equal(savedReply(s), expected);
  });

  test('a malformed [Q] passes through untouched', async () => {
    const malformed = 'Quick check.\n\n[Q]\nWhat is a token?\nA) A word\nB) A chunk of text\n[/Q]';
    const out = await stream(sid(), lessonTurn(malformed), { capabilities: BLOCKS });
    assert.equal(out.complete.reply, malformed);
    assert.equal(out.deltas, malformed);
  });

  test('a client without blocks_v1 keeps the model order (and still gets the prose scrub)', async () => {
    const s = sid();
    const out = await stream(s, lessonTurn(QUIZ_REPLY));
    assert.equal(out.status, 200, out.text.slice(0, 300));
    // The live deltas are the model's text, reflowed only.
    assert.equal(out.deltas, transformReply(QUIZ_REPLY, { limit: 3 }));
    assert.ok(out.deltas.includes(REAL_BLOCKS[0].block), 'model order on the wire');
    // The final reply is the existing defense-in-depth scrub: no markers, no ANS.
    assert.ok(!out.complete.reply.includes('[Q]'));
    assert.ok(!out.complete.reply.includes('ANS:'));
    assert.ok(out.complete.reply.includes('A) A single word, always'), 'options in the model order');
    assert.equal(savedReply(s), out.complete.reply);
  });
});

describe('reflow end to end (AUD-17)', () => {
  test('a tight numbered list in free chat arrives whole', async () => {
    const list = 'Try it:\n\n1. Open the app\n2. Type the prompt\n3. Read the answer\n4. Check a source';
    const out = await stream(sid(), [{ role: 'user', content: `MOCK_REPLY:\n${list}` }], { capabilities: BLOCKS });
    assert.equal(out.complete.reply, list);
    assert.equal(out.deltas, list);
  });

  test('a score rubric arrives one whole line per score', async () => {
    const rubric = "Here's how your reasoning scored:\n\n**Claim Clarity: 3/5** — Broad — partial? final? both?\n" +
      '**Evidence: 1/5** — None yet.\n**Nuance: 2/5** — Some.\n**Logic: 3/5** — Plausible.\n**Originality: 3/5** — Solid.\n\n' +
      '**Overall: 12/25** — Grade: Solid. Add evidence. Then push.\n\nWho bears the risk?';
    const s = sid();
    const out = await postJson(s, [{ role: 'user', content: `MOCK_REPLY:\n${rubric}` }]);
    const expected = rubric.replace(/(\*\* — [^\n]*)\n(?=\*\*(?:Evidence|Nuance|Logic|Originality))/g, '$1  \n');
    assert.equal(out.body.reply, expected);
    assert.equal(savedReply(s), expected);
  });
});

const SOURCE_REPLY = 'Facial analysis erred far more on darker-skinned women. [SOURCE: Gender Shades — gendershades.org]\n\n' +
  'Lawyers cited cases that never existed [SOURCE: Mata v. Avianca — the case behind the lawyers story: courtlistener.com/docket/16708263/mata-v-avianca-inc] and were fined.\n\n' +
  'Who should have checked?';
const SOURCE_PLAIN = 'Facial analysis erred far more on darker-skinned women. Source: Gender Shades (gendershades.org)\n\n' +
  'Lawyers cited cases that never existed (Source: Mata v. Avianca — the case behind the lawyers story, courtlistener.com) and were fined.\n\n' +
  'Who should have checked?';

describe('[SOURCE] tags as plain text for blocks_v1 clients (AUD-38)', () => {
  test('streaming: deltas, complete reply and saved turn carry the plain source, no path', async () => {
    const s = sid();
    const out = await stream(s, [{ role: 'user', content: `MOCK_REPLY:\n${SOURCE_REPLY}` }], { capabilities: BLOCKS });
    assert.equal(out.status, 200, out.text.slice(0, 300));
    assert.equal(out.complete.reply, SOURCE_PLAIN);
    assert.equal(out.deltas, SOURCE_PLAIN);
    assert.equal(savedReply(s), SOURCE_PLAIN);
    let sent = '';
    for (const f of out.deltaFrames) {
      sent += f;
      assert.ok(!sent.includes('[S'), 'no raw tag text on the wire');
    }
  });

  test('JSON path: the same plain text', async () => {
    const s = sid();
    const out = await postJson(s, [{ role: 'user', content: `MOCK_REPLY:\n${SOURCE_REPLY}` }], { capabilities: BLOCKS });
    assert.equal(out.body.reply, SOURCE_PLAIN);
    assert.equal(savedReply(s), SOURCE_PLAIN);
  });

  test('inside a lesson, next to a [Q] check: both transforms apply', async () => {
    const reply = `Models predict text. [SOURCE: Attention Is All You Need — arxiv.org/abs/1706.03762]\n\n${REAL_BLOCKS[0].block}`;
    const out = await stream(sid(), lessonTurn(reply), { capabilities: BLOCKS });
    assert.ok(out.complete.reply.startsWith('Models predict text. Source: Attention Is All You Need (arxiv.org)\n\n[Q]\n'));
    assert.equal(out.complete.reply, transformReply(reply, { limit: 3, rewriteSources: true, shuffleQuiz: true }));
    assert.equal(out.deltas, out.complete.reply);
  });

  test('the widget (club_v1) keeps the tag for its source pill', async () => {
    const s = sid();
    const out = await postJson(s, [{ role: 'user', content: `MOCK_REPLY:\n${SOURCE_REPLY}` }], { capabilities: ['club_v1'] });
    assert.equal(out.status, 200, JSON.stringify(out.body));
    assert.equal(out.body.reply, transformReply(SOURCE_REPLY, { limit: 2 }));
    assert.ok(out.body.reply.includes('[SOURCE: Gender Shades — gendershades.org]'));
    assert.equal(savedReply(s), out.body.reply);
    // A widget that also declared blocks_v1 would still want its pill.
    const both = await postJson(sid(), [{ role: 'user', content: `MOCK_REPLY:\n${SOURCE_REPLY}` }], { capabilities: ['club_v1', 'blocks_v1'] });
    assert.ok(both.body.reply.includes('[SOURCE: Gender Shades — gendershades.org]'));
  });

  test('a client without capabilities (iOS 2.0.0) gets the reply as before', async () => {
    const out = await stream(sid(), [{ role: 'user', content: `MOCK_REPLY:\n${SOURCE_REPLY}` }]);
    assert.equal(out.complete.reply, transformReply(SOURCE_REPLY, { limit: 2 }));
    assert.ok(out.complete.reply.includes('[SOURCE: Gender Shades — gendershades.org]'));
  });
});
