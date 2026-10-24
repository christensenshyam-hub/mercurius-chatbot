'use strict';

// TUTOR_MODEL / TUTOR_EFFORT end to end (lib/modelParams, docs/sonnet-5-5).
//
// Boots the real server with ANTHROPIC_MOCK=1 and MOCK_CAPTURE_FILE, which
// records every model call's params and their key order (`paramKeys`), and
// drives every route that runs on the tutor model:
//
//   - a free-chat turn (SSE and JSON), a homework problem turn (SSE and
//     JSON, and its answer-guard retry), a Deep-dive lesson turn, a Basics
//     lesson turn, the unit-test grader, fact-check, analyze, the prewarm;
//   - and, with MOCK_LEADING_THINKING=1 (every reply starts with an empty
//     thinking block), every route that reads a model reply, helpers too.
//
// TUTOR_MODEL=claude-sonnet-5-5: no call carries temperature / top_p /
// top_k (the mock would 400 it, like the API); a problem turn is adaptive at
// low effort with the 4.6 headroom; every other call is thinking
// between_tools at TUTOR_EFFORT; replies are read by block type, so the
// empty thinking block every adaptive Sonnet 5.5 reply starts with never
// reaches a student; the ledger prices the calls at the Sonnet 5.5 card.
// The tuning pass (A/B 2026-10-24): every reply budget is scaled for its
// tokenizer; its free-chat prefixes carry its model notes before the app
// facts and the safety core; calculus, statistics and "i got N" turns think;
// a rushed thread's right-answer note drops the AI tie-in. None of it
// reaches a Sonnet 4.6 request.
//
// TUTOR_MODEL unset: every request has exactly today's fields, values and
// key order, and the mock's summarized 4.6 thinking (MOCK_THINKING_TEXT)
// never reaches a reply either.
//
// A Sonnet 5.5 problem turn asks for summarized thinking, so a think longer
// than STREAM_IDLE_MS (MOCK_THINKING_MS) still streams and completes. An
// unverified TUTOR_MODEL (claude-sonnet-5) logs a boot warning and thinks
// explicitly, with headroom, on every call.
//
// Both USE_UNIFIED_PROMPT states for the turns; no model is called.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const { spawnServer } = require('./support/spawnServer');
const { waitFor } = require('./support/waitFor');
const { RESPONSE_MODE_BUDGETS } = require('../lib/responseQuality');
const { MOCK_THINKING_TEXT } = require('../lib/anthropicMock');
const { REFUSAL_COPY } = require('../lib/safetyCore');
const pricing = require('../lib/pricing');

const S46 = 'claude-sonnet-4-6';
const S55 = 'claude-sonnet-5-5';
const S5 = 'claude-sonnet-5'; // a 5.x model with no verified request rules here
const UNVERIFIED_WARNING = 'TUTOR_MODEL is not claude-sonnet-4-6 or claude-sonnet-5-5';
const ADMIN_PASSWORD = 'test-admin-pw-' + crypto.randomBytes(4).toString('hex');
const CONCISE = RESPONSE_MODE_BUDGETS.concise;
// Sonnet 5.5's reply budgets: the 4.6 budgets × 1.35, rounded up (its
// tokenizer counts more tokens for the same words: lib/modelParams
// TOKENIZER_SCALE). A problem turn's thinking room is scaled too (concise:
// max(338 + 2765, 4050)); the prewarm's 1 is not.
const S55_CAP = Object.freeze({ concise: 338, debate: 540, balanced: 810, lesson: 2765, grader: 540, helper: 945, problem: 4050 });
const LESSON_TAG = '[CURRICULUM: Unit 1, Lesson 1]';
const BASICS_TAG = '[BASICS: Unit 1, Lesson 1]';
const IOS_CAPS = ['blocks_v1', 'platform_ios'];
const SAMPLING = ['temperature', 'top_p', 'top_k'];

// Today's key orders (what JSON.stringify puts on the wire).
const KEYS_TEMPERATURE = ['model', 'max_tokens', 'temperature', 'system', 'messages'];
const KEYS_THINKING = ['model', 'max_tokens', 'thinking', 'output_config', 'system', 'messages'];
const KEYS_PLAIN = ['model', 'max_tokens', 'system', 'messages'];

const b64 = (t) => Buffer.from(t, 'utf8').toString('base64');
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');
const nonce = () => crypto.randomBytes(5).toString('hex');

const servers = {};
const spawned = [];

async function boot(name, env) {
  const tag = crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-tutor-${name}-${tag}.db`);
  const captureFile = path.join(os.tmpdir(), `merc-tutor-${name}-${tag}.jsonl`);
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    MOCK_CAPTURE_FILE: captureFile,
    ADMIN_PASSWORD,
    SESSION_PER_MIN: '1000',
    CHAT_IP_PER_MIN: '1000',
    IP_DAILY_NEW_SESSIONS: '1000',
    ...env,
  });
  spawned.push(server.proc);
  // Everything the server prints (its log lines need LOG_LEVEL in `env`:
  // NODE_ENV=test silences them otherwise).
  let out = '';
  server.proc.stdout.on('data', (chunk) => { if (out.length < 200_000) out += chunk; });
  const { base } = await server.ready;
  return { base, dbPath, captureFile, name, stdout: () => out };
}

// A think that streams nothing for THINK_MS would trip a STREAM_IDLE_MS
// watchdog; a summarized one sends a thinking_delta every THINK_MS / 5.
const IDLE_MS = 750;
const THINK_MS = 2000;

before(async () => {
  [servers.s46on, servers.s46off, servers.s55on, servers.s55off, servers.s55medium, servers.s55lead, servers.s55think] = await Promise.all([
    boot('46-on', { USE_UNIFIED_PROMPT: '1' }),
    boot('46-off', { USE_UNIFIED_PROMPT: '0' }),
    boot('55-on', { USE_UNIFIED_PROMPT: '1', TUTOR_MODEL: S55 }),
    boot('55-off', { USE_UNIFIED_PROMPT: '0', TUTOR_MODEL: S55 }),
    boot('55-medium', { USE_UNIFIED_PROMPT: '1', TUTOR_MODEL: S55, TUTOR_EFFORT: 'medium' }),
    boot('55-lead', { USE_UNIFIED_PROMPT: '1', TUTOR_MODEL: S55, MOCK_LEADING_THINKING: '1' }),
    boot('55-think', { USE_UNIFIED_PROMPT: '1', TUTOR_MODEL: S55, STREAM_IDLE_MS: String(IDLE_MS), MOCK_THINKING_MS: String(THINK_MS), LOG_LEVEL: 'warn' }),
  ]);
  [servers.s5, servers.s46warn] = await Promise.all([
    boot('5', { USE_UNIFIED_PROMPT: '1', TUTOR_MODEL: S5, LOG_LEVEL: 'warn' }),
    boot('46-warn', { USE_UNIFIED_PROMPT: '1', LOG_LEVEL: 'warn' }),
  ]);
});

after(() => {
  for (const proc of spawned) proc.kill('SIGKILL');
  for (const s of Object.values(servers)) {
    for (const f of [s.captureFile, s.dbPath, s.dbPath + '-wal', s.dbPath + '-shm']) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

async function post(server, p, body, headers = {}) {
  const res = await fetch(`${server.base}${p}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function chatSse(server, body) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  assert.equal(res.status, 200, await res.clone().text());
  const raw = await res.text();
  const frames = raw.split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  assert.ok(!frames.some((f) => f.type === 'error'), raw.slice(0, 400));
  const complete = frames.find((f) => f.type === 'complete');
  assert.ok(complete, `no complete frame: ${raw.slice(0, 400)}`);
  return { raw, deltas: frames.filter((f) => f.type === 'delta').map((f) => f.text), complete };
}

async function chatJson(server, body) {
  const r = await post(server, '/api/chat', body);
  assert.equal(r.status, 200, JSON.stringify(r.json));
  return r.json;
}

function allCalls(server) {
  if (!fs.existsSync(server.captureFile)) return [];
  return fs.readFileSync(server.captureFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

function captured(server, marker) {
  return allCalls(server).filter((c) => JSON.stringify(c.messages).includes(marker));
}

function readUsage(dbPath, sessionId) {
  const Database = require('better-sqlite3');
  const sqlite = new Database(dbPath, { readonly: true });
  try {
    return sqlite.prepare('SELECT model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_usd FROM usage WHERE session_id = ? ORDER BY id').all(sessionId);
  } finally {
    sqlite.close();
  }
}

/** No call to Sonnet 5.5 may carry a field the API rejects there. */
function assertSonnet55Safe(call, label) {
  assert.equal(call.model, S55, label);
  for (const k of SAMPLING) assert.equal(call[k], undefined, `${label}: ${k}`);
  if (call.thinking) {
    assert.ok(['adaptive', 'between_tools'].includes(call.thinking.type), `${label}: thinking ${call.thinking.type}`);
    if (call.thinking.type === 'between_tools') {
      assert.deepEqual(Object.keys(call.thinking), ['type'], `${label}: nothing else inside between_tools`);
      assert.ok(['low', 'medium', 'high'].includes(call.output_config && call.output_config.effort), `${label}: effort ${JSON.stringify(call.output_config)}`);
    }
  }
}

/** A non-problem call on Sonnet 5.5: between_tools at `effort`, no headroom. */
function assertBetweenTools(call, effort, maxTokens, label) {
  assertSonnet55Safe(call, label);
  assert.deepEqual(call.thinking, { type: 'between_tools' }, label);
  assert.deepEqual(call.output_config, { effort }, label);
  assert.equal(call.max_tokens, maxTokens, label);
  assert.deepEqual(call.paramKeys, KEYS_THINKING, label);
}

/** A homework problem turn, on either model: today's fields (on Sonnet 5.5
 *  with display 'summarized', which is 4.6's default and 5.5's is not). */
function assertProblemCall(call, model, label) {
  assert.equal(call.model, model, label);
  assert.deepEqual(call.thinking, model === S46 ? { type: 'adaptive' } : { type: 'adaptive', display: 'summarized' }, label);
  assert.deepEqual(call.output_config, { effort: 'low' }, label);
  for (const k of SAMPLING) assert.equal(call[k], undefined, `${label}: ${k}`);
  assert.equal(call.max_tokens, model === S46 ? Math.max(CONCISE.maxTokens + 2048, 3000) : S55_CAP.problem, label);
  assert.deepEqual(call.paramKeys, KEYS_THINKING, label);
}

/** A Sonnet 4.6 tutor turn exactly as before TUTOR_MODEL existed. */
function assertTemperatureCall(call, { temperature, maxTokens }, label) {
  assert.equal(call.model, S46, label);
  assert.equal(call.temperature, temperature, label);
  assert.equal(call.max_tokens, maxTokens, label);
  assert.equal(call.thinking, undefined, label);
  assert.equal(call.output_config, undefined, label);
  assert.deepEqual(call.paramKeys, KEYS_TEMPERATURE, label);
}

/** The model's own reply reached the student: not empty, not the refusal
 *  copy an unread (empty) reply turns into, and no thinking in it. */
const noThinkingLeak = (text, label) => {
  assert.ok(typeof text === 'string' && text.trim(), `${label}: a reply`);
  assert.notEqual(text, REFUSAL_COPY, `${label}: the reply text was not found (read by position?)`);
  assert.ok(!text.includes('MOCK_THINKING'), `${label}: thinking reached the reply: ${text.slice(0, 120)}`);
};

const chatBody = (text) => ({ sessionId: sid(), responseMode: 'concise', capabilities: IOS_CAPS, messages: [{ role: 'user', content: text }] });
const lessonBody = (tag, n) => ({
  sessionId: sid(), responseMode: 'concise', capabilities: IOS_CAPS,
  messages: [{ role: 'user', content: `${tag} Teach me what happens inside an LLM (${n}).` }],
});
// A student who sends an equation, then "idk" with a reply that gives the
// answer away: a problem turn, then the answer guard's retry.
const EQUATION_REPLY = 'Here is the answer to your sum: 3x + 5 = 20, so x = 5.\n\nWant me to show the steps?';
const equationBody = (n) => ({
  sessionId: sid(), responseMode: 'concise', capabilities: IOS_CAPS,
  messages: [
    { role: 'user', content: `what is 3x+5 = 20 (${n})` },
    { role: 'assistant', content: 'What happens if you get the 3x by itself first?' },
    { role: 'user', content: `idk MOCK_SAY_B64:${b64(EQUATION_REPLY)}` },
  ],
});
const grade = (server, n) => post(server, '/api/unit-test/grade', {
  sessionId: sid(),
  unitId: 'unit_8',
  unitTitle: 'Unit 8: AI Tools and Agents',
  defensePrompt: 'Pick a real AI tool or agent you have seen. Name one impressive thing and one real risk.',
  answer: `ChatGPT drafts a clear essay outline in seconds (${n}), but it invents citations, so I check every source myself.`,
});

// ---------------------------------------------------------------------------
// TUTOR_MODEL=claude-sonnet-5-5
// ---------------------------------------------------------------------------
for (const flag of ['on', 'off']) {
  describe(`TUTOR_MODEL=claude-sonnet-5-5, flag ${flag}: no forbidden field on any route`, () => {
    const server = () => servers[`s55${flag}`];

    test('a free-chat turn over SSE: between_tools at effort low, the concise budget scaled for the tokenizer, the reply streamed whole', async () => {
      const n = nonce();
      const { deltas, complete } = await chatSse(server(), chatBody(`What is a token, really? (${n})`));
      const [call, ...extra] = captured(server(), n);
      assert.equal(extra.length, 0);
      assertBetweenTools(call, 'low', S55_CAP.concise, 'chat sse');
      noThinkingLeak(complete.reply, 'chat sse');
      assert.equal(deltas.join(''), complete.reply);
    });

    test('a free-chat turn over JSON: the same fields, the text block read by type', async () => {
      const n = nonce();
      const json = await chatJson(server(), { ...chatBody(`How do chatbots pick words? (${n})`), capabilities: undefined });
      const [call] = captured(server(), n);
      assertBetweenTools(call, 'low', S55_CAP.concise, 'chat json');
      noThinkingLeak(json.reply, 'chat json');
    });

    test('a homework problem turn (SSE): adaptive at low effort with the headroom; the answer-guard retry sends the same', async () => {
      const n = nonce();
      const { deltas, complete } = await chatSse(server(), equationBody(n));
      const calls = captured(server(), n);
      assert.equal(calls.length, 2, 'the draft, then the guard retry');
      calls.forEach((c, i) => assertProblemCall(c, S55, `problem call ${i}`));
      assert.match(calls[1].system.map((b) => b.text).join('\n'), /## ANSWER GUARD/);
      noThinkingLeak(complete.reply, 'problem sse');
      assert.ok(!/x = 5\b/.test(complete.reply), complete.reply);
      assert.equal(deltas.length, 1, 'held back and sent whole');
    });

    test('a homework problem turn (JSON): the empty thinking block that starts the reply is skipped', async () => {
      const n = nonce();
      const json = await chatJson(server(), { ...chatBody(`Solve for x: 2x + 6 = 14 (${n})`), capabilities: undefined });
      const [call] = captured(server(), n);
      assertProblemCall(call, S55, 'problem json');
      noThinkingLeak(json.reply, 'problem json');
    });

    test('a Deep-dive lesson turn: between_tools, the lesson budget scaled for the tokenizer', async () => {
      const n = nonce();
      const { complete } = await chatSse(server(), lessonBody(LESSON_TAG, n));
      const [call] = captured(server(), n);
      assertBetweenTools(call, 'low', S55_CAP.lesson, 'lesson');
      noThinkingLeak(complete.reply, 'lesson');
      assert.match(complete.reply, /\[CHECK\]/);
    });

    test('a Basics lesson turn: between_tools, the lesson budget scaled for the tokenizer', async () => {
      const n = nonce();
      const { complete } = await chatSse(server(), lessonBody(BASICS_TAG, n));
      const [call] = captured(server(), n);
      assertBetweenTools(call, 'low', S55_CAP.lesson, 'basics');
      noThinkingLeak(complete.reply, 'basics');
    });

    test('a client naming claude-sonnet-5-5 is allowed (TUTOR_MODEL joins the allowlist)', async () => {
      const n = nonce();
      const json = await chatJson(server(), { ...chatBody(`What is RLHF? (${n})`), capabilities: undefined, model: S55 });
      assertBetweenTools(captured(server(), n)[0], 'low', S55_CAP.concise, 'named model');
      noThinkingLeak(json.reply, 'named model');
    });
  });
}

describe('TUTOR_MODEL=claude-sonnet-5-5: the helpers on the tutor model, the prewarm, health, the ledger', () => {
  const server = () => servers.s55on;

  test('the unit-test grader: between_tools instead of temperature 0.2; the grade still parses', async () => {
    const n = nonce();
    const r = await grade(server(), n);
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.deepEqual(Object.keys(r.json).sort(), ['feedback', 'grade', 'pass']);
    const [call] = captured(server(), n);
    assertBetweenTools(call, 'low', S55_CAP.grader, 'grader');
  });

  test('fact-check and analyze: between_tools; their JSON still parses', async () => {
    const n = nonce();
    const fc = await post(server(), '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${n}` });
    assert.equal(fc.status, 200, JSON.stringify(fc.json));
    assert.equal(typeof fc.json.verdict, 'string');
    assertBetweenTools(captured(server(), n)[0], 'low', S55_CAP.helper, 'factcheck');

    const m = nonce();
    const an = await post(server(), '/api/analyze', { sessionId: sid(), aiOutput: `The Great Wall is visible from space with the naked eye. ${m}` });
    assert.equal(an.status, 200, JSON.stringify(an.json));
    assertBetweenTools(captured(server(), m)[0], 'low', S55_CAP.helper, 'analyze');
  });

  test('the quiz stays on the helper model, unchanged (no sampling or thinking field)', async () => {
    const n = nonce();
    const s = sid();
    let thread = [];
    for (const text of [`How do LLMs pick the next word? ${n}`, 'So it is all probability over tokens?']) {
      thread = [...thread, { role: 'user', content: text }];
      const json = await chatJson(server(), { sessionId: s, messages: thread });
      thread = [...thread, { role: 'assistant', content: json.reply }];
    }
    const quiz = await post(server(), '/api/quiz', { sessionId: s });
    assert.equal(quiz.status, 200, JSON.stringify(quiz.json));
    const helper = captured(server(), n).filter((c) => c.model === 'claude-haiku-4-5');
    assert.equal(helper.length, 1);
    assert.deepEqual(helper[0].paramKeys, KEYS_PLAIN);
  });

  test('the prewarm: between_tools at the tutor effort, so it writes what turns read', async () => {
    const before = allCalls(server()).length;
    const r = await post(server(), '/api/admin/prewarm', {}, { 'x-admin-password': ADMIN_PASSWORD });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const calls = allCalls(server()).slice(before).filter((c) => c.max_tokens === 1);
    assert.ok(calls.length >= 3, `prewarm calls: ${calls.length}`);
    for (const c of calls) assertBetweenTools(c, 'low', 1, 'prewarm');
    assert.ok(r.json.warmed.every((w) => !w.error), JSON.stringify(r.json.warmed));
  });

  test('/api/health names the tutor model', async () => {
    const res = await fetch(`${server().base}/api/health`);
    assert.equal((await res.json()).model, S55);
  });

  test('the usage ledger prices Sonnet 5.5 calls at $2 / $10 / $2.50 / $0.20', async () => {
    const s = sid();
    const n = nonce();
    await chatSse(server(), { ...chatBody(`What is a context window? (${n})`), sessionId: s });
    const rows = await waitFor(() => readUsage(server().dbPath, s), (r) => r.length === 1);
    assert.equal(rows.length, 1);
    const [row] = rows;
    assert.equal(row.model, S55);
    const usage = {
      input_tokens: row.input_tokens,
      output_tokens: row.output_tokens,
      cache_read_input_tokens: row.cache_read_tokens,
      cache_creation_input_tokens: row.cache_write_tokens,
    };
    const expected = (usage.input_tokens * 2 + usage.output_tokens * 10 + usage.cache_creation_input_tokens * 2.5 + usage.cache_read_input_tokens * 0.2) / 1e6;
    assert.ok(Math.abs(row.cost_usd - expected) < 1e-9, `${row.cost_usd} vs ${expected}`);
    assert.ok(row.cost_usd < pricing.costUsd(S46, usage), 'cheaper per token than the 4.6 card');
  });

  test('a client naming claude-sonnet-4-6 on this server gets the 4.6 fields (per chosen model, not per server)', async () => {
    const n = nonce();
    await chatJson(server(), { ...chatBody(`What is a token? (${n})`), capabilities: undefined, model: S46 });
    assertTemperatureCall(captured(server(), n)[0], { temperature: CONCISE.temperature, maxTokens: CONCISE.maxTokens }, 'named 4.6');
    const m = nonce();
    await chatJson(server(), { ...chatBody(`Solve for x: 2x + 6 = 14 (${m})`), capabilities: undefined, model: S46 });
    assertProblemCall(captured(server(), m)[0], S46, 'named 4.6 problem');
  });
});

describe('claude-sonnet-5-5: a think longer than STREAM_IDLE_MS does not trip the idle watchdog', () => {
  const server = () => servers.s55think;

  test('a homework problem turn that thinks for longer than the idle window still completes over SSE', async () => {
    // Under the default display "omitted" the stream would send nothing for
    // THINK_MS (the SDK drops the API's pings) and the watchdog would end the
    // turn with a timeout frame; "summarized" thinking deltas keep it alive,
    // as Sonnet 4.6's default display did. chatSse fails on any error frame.
    const n = nonce();
    const started = Date.now();
    const { complete } = await chatSse(server(), chatBody(`Solve for x: 2x + 6 = 14 (${n})`));
    assert.ok(Date.now() - started >= THINK_MS, 'the mock really thought for THINK_MS');
    const [call] = captured(server(), n);
    assertProblemCall(call, S55, 'problem');
    noThinkingLeak(complete.reply, 'problem');
  });

  test('a turn without extended thinking (between_tools) is not slowed down', async () => {
    const n = nonce();
    const started = Date.now();
    const { complete } = await chatSse(server(), chatBody(`What is a token, really? (${n})`));
    assert.ok(Date.now() - started < THINK_MS, 'no thinking block, so no think time');
    assertBetweenTools(captured(server(), n)[0], 'low', S55_CAP.concise, 'chat');
    noThinkingLeak(complete.reply, 'chat');
  });
});

describe('TUTOR_EFFORT=medium on claude-sonnet-5-5', () => {
  const server = () => servers.s55medium;

  test('tutor turns, lessons and the grader send effort medium; a problem turn stays at low', async () => {
    const n = nonce();
    await chatSse(server(), chatBody(`What is a token, really? (${n})`));
    assertBetweenTools(captured(server(), n)[0], 'medium', S55_CAP.concise, 'chat');

    const l = nonce();
    await chatSse(server(), lessonBody(LESSON_TAG, l));
    assertBetweenTools(captured(server(), l)[0], 'medium', S55_CAP.lesson, 'lesson');

    const g = nonce();
    assert.equal((await grade(server(), g)).status, 200);
    assertBetweenTools(captured(server(), g)[0], 'medium', S55_CAP.grader, 'grader');

    const p = nonce();
    await chatJson(server(), { ...chatBody(`Solve for x: 2x + 6 = 14 (${p})`), capabilities: undefined });
    assertProblemCall(captured(server(), p)[0], S55, 'problem');
  });
});

// ---------------------------------------------------------------------------
// TUTOR_MODEL=claude-sonnet-5: a model whose request rules are not verified
// ---------------------------------------------------------------------------
describe('TUTOR_MODEL=claude-sonnet-5 (unverified): a boot warning, and explicit thinking with headroom on every call', () => {
  const server = () => servers.s5;
  const SUMMARIZED = { type: 'adaptive', display: 'summarized' };

  /** Adaptive thinking (summarized) at `effort`, never a sampling field. */
  function assertExplicitThinking(call, effort, maxTokens, label) {
    assert.equal(call.model, S5, label);
    for (const k of SAMPLING) assert.equal(call[k], undefined, `${label}: ${k}`);
    assert.deepEqual(call.thinking, SUMMARIZED, label);
    assert.deepEqual(call.output_config, { effort }, label);
    assert.equal(call.max_tokens, maxTokens, label);
    assert.deepEqual(call.paramKeys, KEYS_THINKING, label);
  }

  test('the boot log warns that the model is unverified; Sonnet 4.6 and 5.5 servers do not', () => {
    assert.ok(server().stdout().includes(UNVERIFIED_WARNING), server().stdout().slice(0, 2000));
    assert.ok(!servers.s55think.stdout().includes(UNVERIFIED_WARNING), 'claude-sonnet-5-5 is verified');
    assert.ok(!servers.s46warn.stdout().includes(UNVERIFIED_WARNING), 'claude-sonnet-4-6 is verified');
    assert.ok(!server().stdout().includes('has no rate card'), 'claude-sonnet-5 is priced at its own card');
  });

  test('a free-chat turn and a lesson turn think explicitly, with room on top of the reply budget', async () => {
    const n = nonce();
    const { complete } = await chatSse(server(), chatBody(`What is a token, really? (${n})`));
    assertExplicitThinking(captured(server(), n)[0], 'low', Math.max(CONCISE.maxTokens + 2048, 3000), 'chat');
    noThinkingLeak(complete.reply, 'chat');

    const l = nonce();
    const lesson = await chatSse(server(), lessonBody(LESSON_TAG, l));
    assertExplicitThinking(captured(server(), l)[0], 'low', 2048 + 2048, 'lesson');
    noThinkingLeak(lesson.complete.reply, 'lesson');
  });

  test('a homework problem turn: adaptive at low effort, the same headroom', async () => {
    const n = nonce();
    const json = await chatJson(server(), { ...chatBody(`Solve for x: 2x + 6 = 14 (${n})`), capabilities: undefined });
    assertExplicitThinking(captured(server(), n)[0], 'low', 3000, 'problem');
    noThinkingLeak(json.reply, 'problem');
  });

  test('the grader, fact-check and analyze think explicitly with headroom; their JSON still parses', async () => {
    const g = nonce();
    const r = await grade(server(), g);
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.match(r.json.grade, /^[A-D]$/);
    assertExplicitThinking(captured(server(), g)[0], 'low', 3000, 'grader');

    const f = nonce();
    const fc = await post(server(), '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${f}` });
    assert.equal(fc.status, 200, JSON.stringify(fc.json));
    assertExplicitThinking(captured(server(), f)[0], 'low', 3000, 'factcheck');

    const a = nonce();
    const an = await post(server(), '/api/analyze', { sessionId: sid(), aiOutput: `The Great Wall is visible from space. ${a}` });
    assert.equal(an.status, 200, JSON.stringify(an.json));
    assertExplicitThinking(captured(server(), a)[0], 'low', 3000, 'analyze');
  });

  test('the prewarm sends the same thinking, max_tokens 1 (its reply is never read)', async () => {
    const before = allCalls(server()).length;
    const r = await post(server(), '/api/admin/prewarm', {}, { 'x-admin-password': ADMIN_PASSWORD });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const calls = allCalls(server()).slice(before).filter((c) => c.max_tokens === 1);
    assert.ok(calls.length >= 3, `prewarm calls: ${calls.length}`);
    for (const c of calls) assertExplicitThinking(c, 'low', 1, 'prewarm');
  });
});

// ---------------------------------------------------------------------------
// TUTOR_MODEL unset: today's requests, field for field and key for key
// ---------------------------------------------------------------------------
for (const flag of ['on', 'off']) {
  describe(`TUTOR_MODEL unset, flag ${flag}: every request exactly as before`, () => {
    const server = () => servers[`s46${flag}`];
    const concise = { temperature: CONCISE.temperature, maxTokens: CONCISE.maxTokens };

    test('a free-chat turn (SSE and JSON): its temperature, the concise budget, no thinking', async () => {
      const n = nonce();
      const { deltas, complete } = await chatSse(server(), chatBody(`What is a token, really? (${n})`));
      assertTemperatureCall(captured(server(), n)[0], concise, 'chat sse');
      assert.equal(deltas.join(''), complete.reply);
      const m = nonce();
      const json = await chatJson(server(), { ...chatBody(`How do chatbots pick words? (${m})`), capabilities: undefined });
      assertTemperatureCall(captured(server(), m)[0], concise, 'chat json');
      noThinkingLeak(json.reply, 'chat json');
    });

    test('a homework problem turn: adaptive at low effort, max_tokens 3000; the summarized thinking never reaches the reply', async () => {
      const n = nonce();
      const { complete } = await chatSse(server(), equationBody(n));
      const calls = captured(server(), n);
      assert.equal(calls.length, 2, 'the draft, then the guard retry');
      calls.forEach((c, i) => assertProblemCall(c, S46, `problem call ${i}`));
      noThinkingLeak(complete.reply, 'problem sse');
      assert.ok(!complete.reply.includes(MOCK_THINKING_TEXT));

      const m = nonce();
      const json = await chatJson(server(), { ...chatBody(`Solve for x: 2x + 6 = 14 (${m})`), capabilities: undefined });
      assertProblemCall(captured(server(), m)[0], S46, 'problem json');
      noThinkingLeak(json.reply, 'problem json');
    });

    test('a Deep-dive and a Basics lesson turn: temperature, the 2048-token lesson budget', async () => {
      for (const tag of [LESSON_TAG, BASICS_TAG]) {
        const n = nonce();
        await chatSse(server(), lessonBody(tag, n));
        assertTemperatureCall(captured(server(), n)[0], { temperature: CONCISE.temperature, maxTokens: 2048 }, tag);
      }
    });

    test('the unit-test grader: temperature 0.2, max_tokens 400', async () => {
      const n = nonce();
      assert.equal((await grade(server(), n)).status, 200);
      assertTemperatureCall(captured(server(), n)[0], { temperature: 0.2, maxTokens: 400 }, 'grader');
    });

    test('fact-check and analyze: no sampling or thinking field at all', async () => {
      const n = nonce();
      assert.equal((await post(server(), '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${n}` })).status, 200);
      const m = nonce();
      assert.equal((await post(server(), '/api/analyze', { sessionId: sid(), aiOutput: `The Great Wall is visible from space. ${m}` })).status, 200);
      for (const call of [captured(server(), n)[0], captured(server(), m)[0]]) {
        assert.equal(call.model, S46);
        assert.equal(call.max_tokens, 700);
        assert.deepEqual(call.paramKeys, KEYS_PLAIN);
      }
    });

    test('a client naming claude-sonnet-5-5 is refused: the allowlist is unchanged while TUTOR_MODEL is unset', async () => {
      const r = await post(server(), '/api/chat', { ...chatBody('hi'), model: S55 });
      assert.equal(r.status, 400);
      assert.equal(r.json.error, 'invalid_model');
    });
  });
}

describe('TUTOR_MODEL unset: the prewarm and health', () => {
  test('the prewarm sends no sampling or thinking field, max_tokens 1', async () => {
    const server = servers.s46on;
    const before = allCalls(server).length;
    const r = await post(server, '/api/admin/prewarm', {}, { 'x-admin-password': ADMIN_PASSWORD });
    assert.equal(r.status, 200);
    const calls = allCalls(server).slice(before).filter((c) => c.max_tokens === 1);
    assert.ok(calls.length >= 3);
    for (const c of calls) {
      assert.equal(c.model, S46);
      assert.deepEqual(c.paramKeys, KEYS_PLAIN);
    }
  });

  test('/api/health names claude-sonnet-4-6', async () => {
    const res = await fetch(`${servers.s46off.base}/api/health`);
    assert.equal((await res.json()).model, S46);
  });
});

// ---------------------------------------------------------------------------
// MOCK_LEADING_THINKING=1: every reply starts with an empty thinking block
// ---------------------------------------------------------------------------
describe('every reply starts with an empty thinking block: every route reads its text by type', () => {
  const server = () => servers.s55lead;

  test('chat (SSE and JSON) and a lesson turn', async () => {
    const n = nonce();
    const { deltas, complete } = await chatSse(server(), chatBody(`What is a token, really? (${n})`));
    noThinkingLeak(complete.reply, 'chat sse');
    assert.equal(deltas.join(''), complete.reply);
    const json = await chatJson(server(), { ...chatBody(`How do chatbots pick words? (${nonce()})`), capabilities: undefined });
    noThinkingLeak(json.reply, 'chat json');
    const lesson = await chatSse(server(), lessonBody(LESSON_TAG, nonce()));
    noThinkingLeak(lesson.complete.reply, 'lesson');
    assert.match(lesson.complete.reply, /\[CHECK\]/);
  });

  test('a guarded homework turn and its retry', async () => {
    const { complete } = await chatSse(server(), equationBody(nonce()));
    noThinkingLeak(complete.reply, 'problem');
    assert.ok(!/x = 5\b/.test(complete.reply), complete.reply);
  });

  test('the grader, fact-check and analyze parse their JSON', async () => {
    const g = await grade(server(), nonce());
    assert.equal(g.status, 200, JSON.stringify(g.json));
    assert.match(g.json.grade, /^[A-D]$/);
    const fc = await post(server(), '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${nonce()}` });
    assert.equal(fc.status, 200, JSON.stringify(fc.json));
    assert.equal(typeof fc.json.verdict, 'string');
    const an = await post(server(), '/api/analyze', { sessionId: sid(), aiOutput: `The Great Wall is visible from space. ${nonce()}` });
    assert.equal(an.status, 200, JSON.stringify(an.json));
  });

  test('the quiz, report card and concept map (helper model) parse their JSON', async () => {
    const s = sid();
    let thread = [];
    for (const text of [`How do LLMs pick the next word? ${nonce()}`, 'So it is all probability over tokens?']) {
      thread = [...thread, { role: 'user', content: text }];
      const json = await chatJson(server(), { sessionId: s, messages: thread });
      thread = [...thread, { role: 'assistant', content: json.reply }];
    }
    const quiz = await post(server(), '/api/quiz', { sessionId: s });
    assert.equal(quiz.status, 200, JSON.stringify(quiz.json));
    assert.ok(Array.isArray(quiz.json.questions) && quiz.json.questions.length > 0);
    const report = await post(server(), '/api/report-card', { sessionId: s });
    assert.equal(report.status, 200, JSON.stringify(report.json));
    assert.equal(typeof report.json.overallGrade, 'string');
    const map = await post(server(), '/api/concept-map', { sessionId: s });
    assert.equal(map.status, 200, JSON.stringify(map.json));
    assert.ok(Array.isArray(map.json.nodes));
  });
});

// ---------------------------------------------------------------------------
// The Sonnet 5.5 tuning pass (A/B 2026-10-24): model notes, scaled floors,
// the broad problem detector, the calm AI tie-in. Sonnet 4.6 gets none of it.
// ---------------------------------------------------------------------------
const { SAFETY_CORE, SAFETY_CORE_TAGGED } = require('../lib/safetyCore');
const { APP_FACTS, APP_FACTS_TAGGED } = require('../lib/appFacts');
const { SONNET_55_NOTES, SONNET_55_NOTES_TAGGED } = require('../lib/modelNotes');

const NOTES_HEADING = '## MODEL NOTES';
const staticOf = (call) => (Array.isArray(call.system) ? call.system[0].text : String(call.system));
const dynamicOf = (call) => (Array.isArray(call.system) ? call.system.slice(1).map((b) => b.text).join('\n') : '');
const widgetBody = (text) => ({ sessionId: sid(), responseMode: 'concise', capabilities: ['club_v1'], messages: [{ role: 'user', content: text }] });

/** A thread in `mode` (debate / discussion: the legacy prefix differs per mode). */
async function modeChat(server, mode, text) {
  const sessionId = sid();
  // The session exists once it has a turn; then the mode switch applies.
  await chatJson(server, { sessionId, messages: [{ role: 'user', content: `hi (${nonce()})` }] });
  assert.equal((await post(server, '/api/mode', { sessionId, mode })).status, 200);
  const n = nonce();
  await chatJson(server, { sessionId, responseMode: 'concise', messages: [{ role: 'user', content: `${text} (${n})` }] });
  return captured(server, n)[0];
}

for (const flag of ['on', 'off']) {
  describe(`claude-sonnet-5-5, flag ${flag}: its model notes ride the cached free-chat prefix, before the app facts and the safety core`, () => {
    const s55 = () => servers[`s55${flag}`];
    const s46 = () => servers[`s46${flag}`];
    const NOTES = flag === 'on' ? SONNET_55_NOTES_TAGGED : SONNET_55_NOTES;
    const TAIL = flag === 'on'
      ? `\n\n${NOTES}\n\n${APP_FACTS_TAGGED}\n\n${SAFETY_CORE_TAGGED}`
      : `\n\n${NOTES}\n\n${APP_FACTS}\n\n${SAFETY_CORE}`;
    const assertNotesTail = (call, label) => {
      const text = staticOf(call);
      assert.ok(text.endsWith(TAIL), `${label}: notes, then the app facts, then the safety core LAST`);
      assert.equal(text.split(NOTES_HEADING).length, 2, `${label}: the notes once`);
      assert.deepEqual(call.system[0].cache_control, { type: 'ephemeral' }, `${label}: in the cached static block`);
      assert.ok(!dynamicOf(call).includes(NOTES_HEADING), `${label}: never in the dynamic block`);
    };

    test('app and widget turns, SSE and JSON: the notes once, in the same bytes every turn', async () => {
      const [a, b, w] = [nonce(), nonce(), nonce()];
      await chatSse(s55(), chatBody(`What is a token, really? (${a})`));
      await chatJson(s55(), { ...chatBody(`How do chatbots pick words? (${b})`), capabilities: undefined });
      await chatSse(s55(), widgetBody(`When does the club meet? (${w})`));
      const [ca, cb, cw] = [captured(s55(), a)[0], captured(s55(), b)[0], captured(s55(), w)[0]];
      for (const [c, label] of [[ca, 'app sse'], [cb, 'app json'], [cw, 'widget']]) assertNotesTail(c, label);
      assert.equal(staticOf(ca), staticOf(cb), 'byte-stable: one prefix for every app turn');
    });

    test('the same requests on Sonnet 4.6 send the same prefixes without the notes, byte for byte', async () => {
      const pairs = [];
      for (const [label, body] of [['app', (t) => chatBody(t)], ['widget', (t) => widgetBody(t)]]) {
        const [x, y] = [nonce(), nonce()];
        await chatSse(s55(), body(`What is a token, really? (${x})`));
        await chatSse(s46(), body(`What is a token, really? (${y})`));
        pairs.push([label, captured(s55(), x)[0], captured(s46(), y)[0]]);
      }
      for (const mode of ['debate', 'discussion']) {
        pairs.push([mode, await modeChat(s55(), mode, 'AI should be regulated'), await modeChat(s46(), mode, 'AI should be regulated')]);
      }
      for (const [label, c55, c46] of pairs) {
        assertNotesTail(c55, label);
        assert.ok(!staticOf(c46).includes(NOTES_HEADING), `${label}: no notes on 4.6`);
        assert.equal(staticOf(c55).replace(`\n\n${NOTES}`, ''), staticOf(c46), `${label}: the 4.6 prefix plus the notes, nothing else`);
      }
    });

    test('a client naming claude-sonnet-4-6 on this server gets the 4.6 prefix: the notes follow the model each call uses', async () => {
      const n = nonce();
      await chatJson(s55(), { ...chatBody(`What is RLHF? (${n})`), capabilities: undefined, model: S46 });
      assert.ok(!staticOf(captured(s55(), n)[0]).includes(NOTES_HEADING));
    });

    test('lessons (Deep dive and Basics), the grader and the helpers carry no notes', async () => {
      const [l, bs, g, f] = [nonce(), nonce(), nonce(), nonce()];
      await chatSse(s55(), lessonBody(LESSON_TAG, l));
      await chatSse(s55(), lessonBody(BASICS_TAG, bs));
      assert.equal((await grade(s55(), g)).status, 200);
      assert.equal((await post(s55(), '/api/factcheck', { sessionId: sid(), claim: `AI will replace all programmers by 2030 ${f}` })).status, 200);
      for (const [marker, label] of [[l, 'lesson'], [bs, 'basics'], [g, 'grader'], [f, 'factcheck']]) {
        const call = captured(s55(), marker)[0];
        assert.ok(!JSON.stringify(call.system).includes(NOTES_HEADING), label);
      }
    });
  });
}

describe('claude-sonnet-5-5: the prewarm warms the prefixes its turns read', () => {
  test('the free-chat prefixes it writes carry the notes, the lesson prefixes do not; Sonnet 4.6 warms today\'s', async () => {
    for (const [server, notes] of [[servers.s55on, true], [servers.s46on, false]]) {
      const before = allCalls(server).length;
      const r = await post(server, '/api/admin/prewarm', {}, { 'x-admin-password': ADMIN_PASSWORD });
      assert.equal(r.status, 200, JSON.stringify(r.json));
      const calls = allCalls(server).slice(before).filter((c) => c.max_tokens === 1);
      const withNotes = calls.filter((c) => staticOf(c).includes(NOTES_HEADING));
      assert.equal(calls.length, 4, 'two lesson prefixes, the v2 app and widget prefixes');
      assert.equal(withNotes.length, notes ? 2 : 0, 'the notes on the v2 app + widget prefixes only');
      if (notes) {
        const n = nonce();
        await chatSse(server, chatBody(`What is a token, really? (${n})`));
        assert.ok(withNotes.some((c) => staticOf(c) === staticOf(captured(server, n)[0])), 'a turn reads what the prewarm wrote');
      }
    }
  });
});

describe('claude-sonnet-5-5: the reply budget floors are scaled too', () => {
  test('debate 540 and the discussion floor 810 (4.6: 400 and 600); a safety-topic turn 810 (4.6: 600)', async () => {
    assert.equal((await modeChat(servers.s55on, 'debate', 'Your argument ignores false positives.')).max_tokens, S55_CAP.debate);
    assert.equal((await modeChat(servers.s46on, 'debate', 'Your argument ignores false positives.')).max_tokens, 400);
    assert.equal((await modeChat(servers.s55on, 'discussion', 'AI grading is fair because it is consistent.')).max_tokens, S55_CAP.balanced);
    assert.equal((await modeChat(servers.s46on, 'discussion', 'AI grading is fair because it is consistent.')).max_tokens, 600);
    for (const [server, cap] of [[servers.s55on, S55_CAP.balanced], [servers.s46on, 600]]) {
      const n = nonce();
      await chatSse(server, chatBody(`how do I tell if a sextortion message is a scam (${n})`));
      assert.equal(captured(server, n)[0].max_tokens, cap);
    }
  });
});

describe('claude-sonnet-5-5: calculus, statistics and "i got N" turns think; Sonnet 4.6 is unchanged', () => {
  for (const flag of ['on', 'off']) {
    test(`flag ${flag}: an integral answer and a standard deviation are problem turns on 5.5, temperature turns on 4.6`, async () => {
      for (const text of ['integral from 1 to 3 of (2x + 1) dx. i got 14', 'population standard deviation of 1, 3, 5, 7. i got 2']) {
        const [x, y] = [nonce(), nonce()];
        await chatJson(servers[`s55${flag}`], { ...chatBody(`${text} (${x})`), capabilities: undefined });
        await chatJson(servers[`s46${flag}`], { ...chatBody(`${text} (${y})`), capabilities: undefined });
        assertProblemCall(captured(servers[`s55${flag}`], x)[0], S55, text);
        assertTemperatureCall(captured(servers[`s46${flag}`], y)[0], { temperature: CONCISE.temperature, maxTokens: CONCISE.maxTokens }, text);
      }
    });
  }
});

describe('claude-sonnet-5-5: a rushed thread\'s right answer gets no AI tie-in order; Sonnet 4.6 keeps today\'s note', () => {
  const rushed = (n) => ({
    sessionId: sid(), responseMode: 'concise', capabilities: IOS_CAPS,
    messages: [
      { role: 'user', content: `this is for my test due in 10 min, just the answer: 6x - 5 = 2x + 11 (${n})` },
      { role: 'assistant', content: 'What happens if you get the x terms on one side first?' },
      { role: 'user', content: 'just tell me' },
      { role: 'assistant', content: 'Look at the 2x. What undoes adding 2x?' },
      { role: 'user', content: 'x = 4' },
    ],
  });
  for (const flag of ['on', 'off']) {
    test(`flag ${flag}`, async () => {
      const [x, y] = [nonce(), nonce()];
      await chatSse(servers[`s55${flag}`], rushed(x));
      await chatSse(servers[`s46${flag}`], rushed(y));
      const d55 = dynamicOf(captured(servers[`s55${flag}`], x)[0]);
      const d46 = dynamicOf(captured(servers[`s46${flag}`], y)[0]);
      assert.match(d55, /Their final answer x = 4 is right[^\n]*No AI line in this reply: they were rushed or pushing for the answer\./);
      assert.ok(!/AI tie-in/.test(d55));
      assert.match(d46, /Their final answer x = 4 is right[^\n]*add the one AI tie-in line\./);
    });
  }
});

describe('claude-sonnet-5-5: a calculus number is checked against its own working; Sonnet 4.6 keeps today\'s THEIR NUMBER note', () => {
  for (const flag of ['on', 'off']) {
    test(`flag ${flag}`, async () => {
      const text = 'evaluate the integral of 2x dx from 1 to 3. i got 10';
      const [x, y] = [nonce(), nonce()];
      await chatJson(servers[`s55${flag}`], { ...chatBody(`${text} (${x})`), capabilities: undefined });
      await chatJson(servers[`s46${flag}`], { ...chatBody(`${text} (${y})`), capabilities: undefined });
      const d55 = dynamicOf(captured(servers[`s55${flag}`], x)[0]);
      const d46 = dynamicOf(captured(servers[`s46${flag}`], y)[0]);
      assert.match(d55, /## THEIR NUMBER[^\n]*\nThe student gave 10 as their answer to a calculus or statistics problem[^\n]*Never describe a case where their number would be right\./);
      assert.ok(!/run it backwards/.test(d55));
      assert.match(d46, /## THEIR NUMBER[^\n]*\nThe student gave 10 as their answer to a formula or word problem\. Check it with THEIR number only: run it backwards through the formula/);
    });
  }
});

describe('Sonnet 4.6 servers: no request ever carried the notes', () => {
  test('every call captured on the TUTOR_MODEL-unset servers, in both flag states', () => {
    for (const server of [servers.s46on, servers.s46off]) {
      const calls = allCalls(server);
      assert.ok(calls.length > 0, `${server.name}: no calls captured`);
      for (const c of calls) assert.ok(!JSON.stringify(c.system).includes(NOTES_HEADING), `${server.name}: ${c.model}`);
    }
  });
});
