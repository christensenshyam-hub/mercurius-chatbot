'use strict';

// End-to-end (mocked Anthropic) for two prompt-assembly guarantees:
//
//   1. Every helper route that sends student text to the model ends its
//      system prompt with HELPER_CRISIS_RULE + SAFETY_CORE, and a crisis
//      disclosure gets the crisis resources instead of a grade, a quiz or a
//      fact-check: deterministically for a first-person unit-test answer or
//      claim (no model call), and via the model's hand-off otherwise (the
//      mock follows rule 1 in prose when the safety block is present).
//   2. The chat/lesson thread carries ONE message-level breakpoint, on the
//      last replayed message, and the prefix up to it is byte-identical on
//      the next turn, including the iOS lesson wire shape (hidden opener,
//      re-tagged last turn), so each turn reads back what the previous one
//      wrote. The widget's club material rides its own breakpoint; the app's
//      dynamic block does not change.
//
// Boots the real server twice (USE_UNIFIED_PROMPT on and off) with
// ANTHROPIC_MOCK=1, EVAL_EXPOSE_USAGE=1 (usage on the SSE 'complete' frame)
// and MOCK_CAPTURE_FILE (every model call's params as one JSON line). The
// club-site feeds are served from the repo's copies by a preload, so nothing
// here touches the network.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const { SAFETY_CORE, HELPER_CRISIS_RULE, CRISIS_COPY } = require('../lib/safetyCore');

const ROOT = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stubClubFeeds.js');
const OPENER_TAG = '[CURRICULUM: Unit 1, Lesson 1]';

const servers = {};

function nonce() { return crypto.randomBytes(6).toString('hex'); }
function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }

async function boot(name, unified) {
  const port = 9100 + Math.floor(Math.random() * 800);
  const tag = crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-prompt-${name}-${tag}.db`);
  const captureFile = path.join(os.tmpdir(), `merc-prompt-${name}-${tag}.jsonl`);
  const proc = spawn(process.execPath, ['--require', STUB, 'server.js'], {
    cwd: ROOT,
    env: {
      ...process.env,
      PORT: String(port),
      DATABASE_URL: '',
      SQLITE_PATH: dbPath,
      ANTHROPIC_MOCK: '1',
      ANTHROPIC_API_KEY: '',
      MOCK_CAPTURE_FILE: captureFile,
      EVAL_EXPOSE_USAGE: '1',
      USE_UNIFIED_PROMPT: unified ? '1' : '0',
      ALLOWED_ORIGIN: `http://localhost:${port}`,
      NODE_ENV: 'test',
      DISCORD_WEBHOOK_URL: '',
      SESSION_PER_MIN: '1000',
      CHAT_IP_PER_MIN: '1000',
      IP_DAILY_NEW_SESSIONS: '1000',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  await new Promise((resolve, reject) => {
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
  return { base: `http://localhost:${port}`, proc, dbPath, captureFile };
}

before(async () => {
  [servers.on, servers.off] = await Promise.all([boot('on', true), boot('off', false)]);
});

after(() => {
  for (const s of Object.values(servers)) {
    s.proc.kill('SIGKILL');
    for (const f of [s.captureFile, s.dbPath, s.dbPath + '-wal', s.dbPath + '-shm']) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

async function post(server, p, body) {
  const res = await fetch(`${server.base}${p}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

// POST /api/chat as SSE; returns the 'complete' frame (reply + usage).
async function chatSse(server, body) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  assert.equal(res.status, 200, await res.clone().text());
  const raw = await res.text();
  const frames = raw.split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  const complete = frames.find((f) => f.type === 'complete');
  assert.ok(complete, `no complete frame: ${raw.slice(0, 300)}`);
  return complete;
}

// Every captured model call whose params mention `marker`, in call order.
function captured(server, marker) {
  if (!fs.existsSync(server.captureFile)) return [];
  return fs.readFileSync(server.captureFile, 'utf8')
    .split('\n')
    .filter((l) => l && l.includes(marker))
    .map((l) => JSON.parse(l));
}

const textOf = (content) => (typeof content === 'string'
  ? content
  : content.filter((b) => b.type === 'text').map((b) => b.text).join(''));
const messageBreakpoints = (messages) => messages
  .map((m, i) => (Array.isArray(m.content) && m.content.some((b) => b.cache_control) ? i : -1))
  .filter((i) => i >= 0);
const endsWithSafety = (system) => typeof system === 'string' && system.endsWith(`${HELPER_CRISIS_RULE}\n\n${SAFETY_CORE}`);

// ---------------------------------------------------------------------------
// 1. Helper routes
// ---------------------------------------------------------------------------
describe('helper routes carry the safety block and hand off a crisis', () => {
  const grade = (server, s, answer) => post(server, '/api/unit-test/grade', {
    sessionId: s,
    unitId: 'unit_8',
    unitTitle: 'Unit 8: AI Tools and Agents',
    defensePrompt: 'Pick a real AI tool or agent you have seen. Name one impressive thing and one real risk.',
    answer,
  });

  // Two chat turns → four chat rows, enough for the history helpers.
  async function chatHistory(server, s, texts) {
    const thread = [];
    for (const text of texts) {
      thread.push({ role: 'user', content: text });
      const r = await post(server, '/api/chat', { sessionId: s, messages: thread });
      assert.equal(r.status, 200, JSON.stringify(r.json));
      thread.push({ role: 'assistant', content: r.json.reply });
    }
  }

  test('a normal unit-test answer is graded with SAFETY_CORE last in the grader prompt', async () => {
    const n = nonce();
    const r = await grade(servers.on, sid(), `ChatGPT can draft a clear essay outline in seconds (${n}), but it invents citations, so I would only trust it for brainstorming and check every source myself.`);
    assert.equal(r.status, 200);
    assert.deepEqual(Object.keys(r.json).sort(), ['feedback', 'grade', 'pass']);
    assert.match(r.json.grade, /^[A-D]$/);
    const [call] = captured(servers.on, n);
    assert.ok(endsWithSafety(call.system), 'grader system ends with HELPER_CRISIS_RULE + SAFETY_CORE');
    assert.ok(call.system.startsWith('You are Mercurius Ⅰ, grading'));
  });

  test('a first-person crisis answer gets the resources in the grade shape, with no model call', async () => {
    const n = nonce();
    const r = await grade(servers.on, sid(), `honestly i don't care about any of this, i want to die ${n}`);
    assert.equal(r.status, 200, 'a non-2xx would show the app a connection error');
    assert.deepEqual(r.json, { grade: '—', pass: false, feedback: CRISIS_COPY, crisis: true });
    assert.match(r.json.feedback, /Call or text 988/);
    assert.match(r.json.feedback, /Text HOME to 741741/);
    assert.equal(captured(servers.on, n).length, 0, 'answered before any model call');
  });

  test('an indirect crisis answer the model hands off in prose is mapped to the same shape, not a 500', async () => {
    const n = nonce();
    const r = await grade(servers.on, sid(), `There's no point answering this. I've been saving up my pills and I already wrote goodbye notes to my friends. ${n}`);
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.deepEqual(r.json, { grade: '—', pass: false, feedback: CRISIS_COPY, crisis: true });
    assert.equal(captured(servers.on, n).length, 1, 'this one needed the model');
  });

  test('a third-person answer about a real AI harm is still graded', async () => {
    const n = nonce();
    const r = await grade(servers.on, sid(), `Character.AI can hold a long, convincing conversation (${n}). A real risk: a lawsuit says a 14-year-old died by suicide after months of chats and the bot never pointed him to 988, so I would not rely on it for anything emotional.`);
    assert.equal(r.status, 200);
    assert.match(r.json.grade, /^[A-D]$/);
    assert.equal(r.json.crisis, undefined);
  });

  test('quiz, report card and concept map send SAFETY_CORE last and still return their JSON', async () => {
    const n = nonce();
    const s = sid();
    await chatHistory(servers.on, s, [`How do LLMs pick the next word? ${n}`, 'So it is all probability over tokens?']);
    const quiz = await post(servers.on, '/api/quiz', { sessionId: s });
    assert.equal(quiz.status, 200, JSON.stringify(quiz.json));
    assert.ok(Array.isArray(quiz.json.questions) && quiz.json.questions.length > 0);
    const report = await post(servers.on, '/api/report-card', { sessionId: s });
    assert.equal(report.status, 200);
    assert.equal(typeof report.json.overallGrade, 'string');
    const map = await post(servers.on, '/api/concept-map', { sessionId: s });
    assert.equal(map.status, 200);
    assert.ok(Array.isArray(map.json.nodes));
    const helperCalls = captured(servers.on, n).filter((c) => typeof c.system === 'string');
    assert.equal(helperCalls.length, 3);
    for (const call of helperCalls) assert.ok(endsWithSafety(call.system), call.system.slice(0, 80));
  });

  test('a quiz over a chat that disclosed a crisis returns the resources instead of a quiz', async () => {
    const n = nonce();
    const s = sid();
    await chatHistory(servers.on, s, [`i cut myself last night and i don't know what to do ${n}`, 'can we just do the quiz']);
    const quiz = await post(servers.on, '/api/quiz', { sessionId: s });
    // 503 + message is the one non-2xx the shipped iOS app shows verbatim; the
    // widgets show `message` whenever `error` is set, whatever the status.
    assert.equal(quiz.status, 503);
    assert.deepEqual(quiz.json, { error: 'crisis', message: CRISIS_COPY, crisis: true });
  });

  test('fact-check: SAFETY_CORE last; a first-person crisis claim is answered without a model call', async () => {
    const n = nonce();
    const ok = await post(servers.on, '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${n}` });
    assert.equal(ok.status, 200);
    assert.equal(typeof ok.json.verdict, 'string');
    assert.ok(endsWithSafety(captured(servers.on, n)[0].system));

    const m = nonce();
    const crisis = await post(servers.on, '/api/factcheck', { sessionId: sid(), claim: `is it true an AI can tell i want to kill myself ${m}` });
    assert.equal(crisis.status, 503);
    assert.deepEqual(crisis.json, { error: 'crisis', message: CRISIS_COPY, crisis: true });
    assert.equal(captured(servers.on, m).length, 0);
  });

  test('analyze: SAFETY_CORE last; a model hand-off is mapped, pasted text is never pattern-matched', async () => {
    const n = nonce();
    const ok = await post(servers.on, '/api/analyze', { sessionId: sid(), aiOutput: `As an AI, I can say with certainty that the moon landing was in 1969. ${n}` });
    assert.equal(ok.status, 200);
    assert.equal(typeof ok.json.overallAssessment, 'string');
    assert.ok(endsWithSafety(captured(servers.on, n)[0].system));

    const m = nonce();
    const handoff = await post(servers.on, '/api/analyze', { sessionId: sid(), aiOutput: `I asked it about the goodbye notes I wrote and it just summarized them. ${m}` });
    assert.equal(handoff.status, 503);
    assert.deepEqual(handoff.json, { error: 'crisis', message: CRISIS_COPY, crisis: true });
    assert.equal(captured(servers.on, m).length, 1, 'analyze has no deterministic pre-check');
  });

  test('pre-briefing ends its system prompt with SAFETY_CORE', async () => {
    const r = await fetch(`${servers.on.base}/api/pre-briefing?sessionId=${sid()}`);
    assert.equal(r.status, 200);
    const call = captured(servers.on, 'pre-meeting briefing').pop();
    assert.ok(call.system.endsWith(`\n\n${SAFETY_CORE}`));
    assert.match(call.system, /LIVE MEETING SCHEDULE/, 'meeting material stays ahead of the safety block');
  });
});

// ---------------------------------------------------------------------------
// 2. History breakpoint + widget club block, in both flag states
// ---------------------------------------------------------------------------
for (const flag of ['on', 'off']) {
  describe(`history breakpoint (USE_UNIFIED_PROMPT ${flag})`, () => {
    const server = () => servers[flag];

    // One message is "the same" across turns when role and text match; the
    // breakpoint turns a string into a one-block array, which the cache key
    // (and the mock) treat as identical.
    const plain = (messages) => messages.map((m) => ({ role: m.role, text: textOf(m.content) }));

    function assertByteStable(calls) {
      for (let t = 1; t < calls.length; t++) {
        const [prev, cur] = [calls[t - 1], calls[t]];
        const bp = messageBreakpoints(prev.messages);
        if (bp.length === 0) continue;
        assert.deepEqual(cur.system, prev.system, `turn ${t + 1}: system prefix drifted`);
        assert.deepEqual(plain(cur.messages).slice(0, bp[0] + 1), plain(prev.messages).slice(0, bp[0] + 1),
          `turn ${t + 1}: replayed thread drifted before the previous breakpoint`);
      }
    }

    // The mock rounds each bucket's chars / 3.8 separately, so allow 1 token.
    function assertReadsBack(usages, fromTurn) {
      for (let t = fromTurn; t <= usages.length; t++) {
        const [prev, cur] = [usages[t - 2], usages[t - 1]];
        const expected = prev.cache_read_input_tokens + prev.cache_creation_input_tokens;
        assert.ok(Math.abs(cur.cache_read_input_tokens - expected) <= 1,
          `turn ${t} reads back what turn ${t - 1} wrote: ${cur.cache_read_input_tokens} vs ${expected}`);
        assert.ok(cur.cache_read_input_tokens > prev.cache_read_input_tokens, `turn ${t} reads more than turn ${t - 1}`);
      }
    }

    test('iOS lesson wire shape: one breakpoint on the last replayed message, prefix byte-stable, read grows', async () => {
      const n = nonce();
      const s = sid();
      const opener = { role: 'user', content: `${OPENER_TAG} Teach me what happens inside an LLM (${n}).` };
      // ChatViewModel.runStream: the visible thread, capped (a leading
      // assistant turn is dropped), the hidden opener inserted at 0, and the
      // last user turn re-tagged on the wire only.
      const visible = [];
      const usages = [];
      for (let t = 1; t <= 5; t++) {
        if (t > 1) visible.push({ role: 'user', content: `student answer ${t}: tokens are pieces of words` });
        const wire = visible.slice();
        while (wire.length && wire[0].role === 'assistant') wire.shift();
        wire.unshift(opener);
        const last = wire.length - 1;
        if (!wire[last].content.startsWith('[CURRICULUM')) wire[last] = { role: 'user', content: `${OPENER_TAG} ${wire[last].content}` };
        const complete = await chatSse(server(), { sessionId: s, messages: wire });
        usages.push(complete.usage);
        visible.push({ role: 'assistant', content: complete.reply });
      }
      const calls = captured(server(), n);
      assert.equal(calls.length, 5);
      assert.deepEqual(messageBreakpoints(calls[0].messages), [], 'turn 1 has no history to mark');
      for (const call of calls.slice(1)) {
        assert.deepEqual(messageBreakpoints(call.messages), [call.messages.length - 2]);
        assert.equal(typeof call.messages.at(-1).content, 'string', 'the re-tagged latest turn never carries one');
      }
      assertByteStable(calls);
      assertReadsBack(usages, 3);
      assert.ok(usages[4].cache_read_input_tokens > usages[2].cache_read_input_tokens);
    });

    test('free chat: the same, and the app dynamic block carries no breakpoint', async () => {
      const n = nonce();
      const s = sid();
      const thread = [];
      const usages = [];
      for (const text of [`What is a token? ${n}`, 'So words get split up?', 'Why would that matter?', 'Does it change the cost?']) {
        thread.push({ role: 'user', content: text });
        const complete = await chatSse(server(), { sessionId: s, messages: thread });
        usages.push(complete.usage);
        thread.push({ role: 'assistant', content: complete.reply });
      }
      const calls = captured(server(), n);
      for (const call of calls) {
        assert.equal(call.system.filter((b) => b.cache_control).length, 1, 'only the static block is cached for the app');
      }
      for (const call of calls.slice(1)) assert.deepEqual(messageBreakpoints(call.messages), [call.messages.length - 2]);
      assertByteStable(calls);
      assertReadsBack(usages, 3);
    });

    test('no breakpoint once the next turn would slide the 20-message chat window', async () => {
      const n = nonce();
      const thread = [];
      for (let i = 0; i < 9; i++) thread.push({ role: 'user', content: `q${i} ${n}` }, { role: 'assistant', content: `a${i}` });
      thread.push({ role: 'user', content: 'q9' });                     // 19 messages: 19 + 2 > 20
      await chatSse(server(), { sessionId: sid(), messages: thread });
      const [call] = captured(server(), n);
      assert.deepEqual(messageBreakpoints(call.messages), []);
      thread.splice(0, 2);                                               // 17 messages: fits
      const m = nonce();
      thread[0] = { role: 'user', content: `q1 ${m}` };
      await chatSse(server(), { sessionId: sid(), messages: thread });
      const [fits] = captured(server(), m);
      assert.deepEqual(messageBreakpoints(fits.messages), [fits.messages.length - 2]);
    });

    test('widget (club_v1): the club material rides its own breakpoint, byte-identical across students', async () => {
      const calls = [];
      for (let i = 0; i < 2; i++) {
        const n = nonce();
        const thread = [{ role: 'user', content: `Tell me about the next club meeting ${n}` }];
        const first = await chatSse(server(), { sessionId: sid(), messages: thread, capabilities: ['club_v1'] });
        thread.push({ role: 'assistant', content: first.reply }, { role: 'user', content: 'What should I read first?' });
        await chatSse(server(), { sessionId: sid(), messages: thread, capabilities: ['club_v1'] });
        calls.push(...captured(server(), n));
      }
      for (const call of calls) {
        assert.equal(call.system.length, 2);
        assert.ok(call.system[1].cache_control, 'club block is a breakpoint');
        assert.match(call.system[1].text, /LIVE MEETING SCHEDULE/);
        assert.match(call.system[1].text, /BLOG LIBRARY/);
      }
      assert.equal(calls[2].system[1].text, calls[0].system[1].text, 'a second student gets the same bytes');
      // Breakpoints in play: static, club block, history. Under the API's 4.
      const total = calls[1].system.filter((b) => b.cache_control).length + messageBreakpoints(calls[1].messages).length;
      assert.equal(total, 3);
    });
  });
}
