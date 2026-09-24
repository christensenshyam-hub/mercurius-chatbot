'use strict';

// Tests for the in-process Anthropic SDK stand-in (lib/anthropicMock).
//
//   1. create() — reply shaping: chat (Socratic), curriculum ([CHECK] +
//      [LESSON_COMPLETE] after 5 user turns), and every JSON route's shape as
//      server.js's parsers consume it.
//   2. Usage — chars/3.8 estimates and prompt-cache creation-vs-read
//      accounting across the module-level Set.
//   3. stream() — SDK event ordering + usage placement (message_start carries
//      input/cache tokens, message_delta carries output_tokens), abort
//      mid-stream (direct and via options.signal), async iteration.
//   4. Scenarios — error / overloaded / credit / hang / slow, on both create()
//      and stream(), with real SDK APIError instances.
//   5. Request validation the real API enforces (first role, `timeout`).

const { describe, test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');

const mock = require('../lib/anthropicMock');
const { createMockClient, isMockEnabled, SCENARIOS, __resetForTest } = mock;
const { processLessonOutcome } = require('../lib/lessonOutcome');
const { parseUnitTestGrade, UNIT_TEST_GRADER_PROMPT, buildGraderUserMessage } = require('../lib/unitTestGrader');
const Anthropic = require('@anthropic-ai/sdk');

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
const CHAT_SYSTEM = 'You are Mercurius, a Socratic AI-literacy tutor. Ask before you tell.';
const CURRICULUM_SYSTEM =
  'You are Mercurius running a structured lesson.\nWhen a message starts with [CURRICULUM: Unit X, Lesson Y], you are in lesson mode.';
const QUIZ_SYSTEM =
  'Generate exactly 4 questions as VALID JSON in this EXACT format: {"title":"[Short topic] Quiz","questions":[{"q":"?","options":[],"answer":"A","explanation":""}]}';
const REPORT_SYSTEM = 'Return ONLY a JSON object in this EXACT format: {"overallGrade":"B+","summary":"...","strengths":[]}';
const MAP_SYSTEM = 'Return ONLY a JSON object: {"central":"Main Topic","nodes":[{"id":"n1"}],"edges":[]}';
const FACTCHECK_SYSTEM = 'A student has submitted a claim about AI for fact-checking. Return ONLY a valid JSON object: {"verdict":"accurate"}';
const ANALYZE_SYSTEM = 'Return ONLY a valid JSON object: {"overallAssessment":"decent","issues":[]}';
const BRIEFING_SYSTEM = 'Generate a pre-meeting briefing and return ONLY a valid JSON object: {"meetingTitle":"..."}';
const UNKNOWN_JSON_SYSTEM = 'Return ONLY JSON.';

function chat(text, { system = CHAT_SYSTEM, model = 'claude-sonnet-4-6', max_tokens = 600 } = {}) {
  return { model, max_tokens, system, messages: [{ role: 'user', content: text }] };
}

// n user turns interleaved with assistant turns, first + last are user.
function conversation(n, { opener = 'Tell me about training data', system = CHAT_SYSTEM } = {}) {
  const messages = [];
  for (let i = 0; i < n; i++) {
    messages.push({ role: 'user', content: i === 0 ? opener : `Student turn ${i + 1}: I think it predicts words.` });
    if (i < n - 1) messages.push({ role: 'assistant', content: `Tutor turn ${i + 1}` });
  }
  return { model: 'claude-sonnet-4-6', max_tokens: 2048, system, messages };
}

// Register every SDK-surface listener and record the order things happened.
function record(stream) {
  const log = [];
  const out = { log, texts: [], snapshots: [], message: null, finalMessage: null, error: null, abortErr: null };
  stream.on('streamEvent', (e, snapshot) => { log.push(e.type); out.snapshots.push({ type: e.type, content: snapshot.content.length }); });
  stream.on('text', (delta, full) => { log.push('text'); out.texts.push({ delta, full }); });
  stream.on('contentBlock', () => log.push('contentBlock'));
  stream.on('message', (m) => { log.push('message'); out.message = m; });
  stream.on('finalMessage', (m) => { log.push('finalMessage'); out.finalMessage = m; });
  stream.on('error', (e) => { log.push('error'); out.error = e; });
  stream.on('abort', (e) => { log.push('abort'); out.abortErr = e; });
  out.ended = new Promise((resolve) => stream.on('end', () => { log.push('end'); resolve(); }));
  return out;
}

const sentences = (text) => text.split(/(?<=[.?!])\s+/).filter(Boolean);

// ---------------------------------------------------------------------------
// isMockEnabled + scenario resolution
// ---------------------------------------------------------------------------
describe('isMockEnabled / scenario selection', () => {
  const savedMock = process.env.ANTHROPIC_MOCK;
  const savedScenario = process.env.MOCK_SCENARIO;
  after(() => {
    if (savedMock === undefined) delete process.env.ANTHROPIC_MOCK; else process.env.ANTHROPIC_MOCK = savedMock;
    if (savedScenario === undefined) delete process.env.MOCK_SCENARIO; else process.env.MOCK_SCENARIO = savedScenario;
  });

  test('ANTHROPIC_MOCK must be exactly "1"', () => {
    delete process.env.ANTHROPIC_MOCK;
    assert.equal(isMockEnabled(), false);
    process.env.ANTHROPIC_MOCK = 'true';
    assert.equal(isMockEnabled(), false);
    process.env.ANTHROPIC_MOCK = '1';
    assert.equal(isMockEnabled(), true);
  });

  test('MOCK_SCENARIO env is the default scenario; unknown values fall back to ok', () => {
    process.env.MOCK_SCENARIO = 'overloaded';
    assert.equal(createMockClient().scenario, 'overloaded');
    delete process.env.MOCK_SCENARIO;
    assert.equal(createMockClient().scenario, 'ok');
    assert.equal(createMockClient({ scenario: 'nonsense' }).scenario, 'ok');
    assert.deepEqual([...SCENARIOS], ['ok', 'error', 'overloaded', 'slow', 'hang', 'credit']);
  });
});

// ---------------------------------------------------------------------------
// create() — reply shapes
// ---------------------------------------------------------------------------
describe('create(): chat reply', () => {
  const client = createMockClient({ delayMs: 1 });

  test('returns an SDK-shaped Message with a 2–3 sentence Socratic reply ending in one question', async () => {
    const msg = await client.messages.create(chat('Is AI conscious?'));
    assert.equal(msg.type, 'message');
    assert.equal(msg.role, 'assistant');
    assert.equal(msg.model, 'claude-sonnet-4-6');
    assert.match(msg.id, /^msg_mock_[0-9a-f]{24}$/);
    assert.equal(msg.stop_reason, 'end_turn');
    assert.equal(msg.stop_sequence, null);
    assert.equal(msg.content[0].type, 'text');
    const text = msg.content[0].text;
    const parts = sentences(text);
    assert.ok(parts.length >= 2 && parts.length <= 3, `expected 2-3 sentences, got ${parts.length}: ${text}`);
    assert.ok(text.trim().endsWith('?'));
    assert.equal((text.match(/\?/g) || []).length, 1, 'exactly one question');
    assert.ok(text.includes('"Is AI conscious"'), 'reply echoes the student turn (minus its terminal punctuation)');
    assert.doesNotMatch(text, /\[(CHECK|LESSON_COMPLETE|KEY|EX|Q)\]/, 'no markers in chat mode');
  });

  test('is deterministic for identical params', async () => {
    const a = await client.messages.create(chat('What is a token?'));
    const b = await client.messages.create(chat('What is a token?'));
    assert.equal(a.content[0].text, b.content[0].text);
    assert.equal(a.id, b.id);
    assert.deepEqual(a.usage, b.usage);
  });

  test('reads multimodal user content (text blocks) — the vision path', async () => {
    const params = {
      model: 'm', max_tokens: 100, system: CHAT_SYSTEM,
      messages: [{ role: 'user', content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } },
        { type: 'text', text: 'What is in this screenshot?' },
      ] }],
    };
    const msg = await client.messages.create(params);
    assert.ok(msg.content[0].text.includes('"What is in this screenshot"'));
  });
});

describe('create(): curriculum reply', () => {
  const client = createMockClient({ delayMs: 1 });

  test('[CURRICULUM in the system prompt → two paragraphs + a [CHECK] line, no completion yet', async () => {
    const msg = await client.messages.create(conversation(1, { system: CURRICULUM_SYSTEM }));
    const text = msg.content[0].text;
    const paragraphs = text.split(/\n\n+/);
    assert.equal(paragraphs.length, 3, `2 prose paragraphs + the check line: ${text}`);
    assert.match(paragraphs[2], /^\[CHECK\][^[\]]+\?\[\/CHECK\]$/);
    for (const p of paragraphs.slice(0, 2)) assert.ok(sentences(p).length <= 2, `short paragraph: ${p}`);
    assert.doesNotMatch(text, /\[LESSON_COMPLETE\]/);
    assert.equal(processLessonOutcome(text).lessonComplete, false);
  });

  test('last user turn starting with [CURRICULUM: triggers lesson mode even with a chat system prompt', async () => {
    const msg = await client.messages.create(chat('[CURRICULUM: Unit 2, Lesson 3] Teach me about bias.'));
    const text = msg.content[0].text;
    assert.match(text, /\[CHECK\].*\[\/CHECK\]/);
    assert.ok(text.includes('Unit 2, Lesson 3'), 'lesson tag is echoed');
  });

  test('[LESSON_COMPLETE] is appended once the conversation has ≥5 user turns', async () => {
    const four = await client.messages.create(conversation(4, { system: CURRICULUM_SYSTEM, opener: '[CURRICULUM: Unit 1, Lesson 1] Go.' }));
    assert.doesNotMatch(four.content[0].text, /\[LESSON_COMPLETE\]/);

    const five = await client.messages.create(conversation(5, { system: CURRICULUM_SYSTEM, opener: '[CURRICULUM: Unit 1, Lesson 1] Go.' }));
    const text = five.content[0].text;
    assert.ok(text.endsWith('[LESSON_COMPLETE]'), 'marker on its own final line');
    const outcome = processLessonOutcome(text);
    assert.equal(outcome.lessonComplete, true);
    assert.doesNotMatch(outcome.reply, /\[LESSON_COMPLETE\]/, 'server strips it cleanly');
    assert.match(outcome.reply, /\[CHECK\]/, 'check line survives');

    const seven = await client.messages.create(conversation(7, { system: CURRICULUM_SYSTEM, opener: '[CURRICULUM: Unit 1, Lesson 1] Go.' }));
    assert.ok(seven.content[0].text.endsWith('[LESSON_COMPLETE]'));
  });
});

describe('create(): JSON routes', () => {
  const client = createMockClient({ delayMs: 1 });
  const history = (system) => conversation(4, { system, opener: 'Tell me about training data' });
  const parseLikeServer = (raw) => {
    try { return JSON.parse(raw); } catch { return JSON.parse(raw.match(/\{[\s\S]*\}/)[0]); }
  };

  test('quiz: title + questions[{q, options×4, answer∈ABCD, explanation}], parses with JSON.parse directly', async () => {
    const msg = await client.messages.create(history(QUIZ_SYSTEM));
    const quiz = JSON.parse(msg.content[0].text);
    assert.equal(typeof quiz.title, 'string');
    assert.ok(quiz.title.includes('training data'), 'title is built from the conversation topic');
    assert.equal(quiz.questions.length, 4);
    for (const q of quiz.questions) {
      assert.equal(typeof q.q, 'string');
      assert.equal(q.options.length, 4);
      assert.match(q.answer, /^[ABCD]$/);
      assert.ok(q.options.some((o) => o.startsWith(q.answer + ')')), 'answer letter matches an option');
      assert.equal(typeof q.explanation, 'string');
    }
  });

  test('report card shape', async () => {
    const msg = await client.messages.create(history(REPORT_SYSTEM));
    const r = parseLikeServer(msg.content[0].text);
    assert.match(r.overallGrade, /^[ABC][+-]?$/);
    assert.equal(typeof r.summary, 'string');
    for (const k of ['strengths', 'areasToRevisit', 'conceptsCovered', 'misconceptionsAddressed']) assert.ok(Array.isArray(r[k]), k);
    assert.ok(r.criticalThinkingScore >= 0 && r.criticalThinkingScore <= 100);
    assert.ok(r.curiosityScore >= 0 && r.curiosityScore <= 100);
    assert.equal(typeof r.nextSessionSuggestion, 'string');
  });

  test('concept map shape: central + nodes + edges referencing known ids', async () => {
    const msg = await client.messages.create(history(MAP_SYSTEM));
    const m = parseLikeServer(msg.content[0].text);
    assert.equal(typeof m.central, 'string');
    assert.ok(m.nodes.length >= 4 && m.nodes.length <= 8);
    const ids = new Set(['central', ...m.nodes.map((n) => n.id)]);
    for (const n of m.nodes) assert.ok(['core', 'related', 'example'].includes(n.group));
    for (const e of m.edges) {
      assert.ok(ids.has(e.from) && ids.has(e.to), `edge ${e.from}→${e.to} references known nodes`);
      assert.equal(typeof e.label, 'string');
    }
  });

  test('unit-test grade parses with parseUnitTestGrade; brief answers fail, substantive ones pass', async () => {
    const graded = (answer) => client.messages.create({
      model: 'm', max_tokens: 400, temperature: 0.2, system: UNIT_TEST_GRADER_PROMPT,
      messages: [{ role: 'user', content: buildGraderUserMessage({ unitTitle: 'Unit 1', defensePrompt: 'Why is fluency not accuracy?', answer }) }],
    });
    const weak = parseUnitTestGrade((await graded('idk')).content[0].text);
    assert.ok(weak, 'parses');
    assert.equal(weak.pass, false);
    assert.equal(weak.grade, 'D');

    const strong = parseUnitTestGrade((await graded(
      'A model produces fluent text by predicting likely tokens, which says nothing about whether the facts are right; confident prose can still be fabricated.',
    )).content[0].text);
    assert.ok(strong);
    assert.equal(strong.pass, true);
    assert.equal(strong.grade, 'B');
  });

  test('factcheck shape (server extracts {...} with a regex)', async () => {
    const msg = await client.messages.create(chat('Fact-check this claim: AI never makes mistakes', { system: FACTCHECK_SYSTEM }));
    const raw = msg.content[0].text;
    const f = JSON.parse(raw.match(/\{[\s\S]*\}/)[0]);
    assert.ok(['accurate', 'misleading', 'false', 'nuanced', 'unverifiable'].includes(f.verdict));
    assert.equal(f.verdictLabel, f.verdict[0].toUpperCase() + f.verdict.slice(1));
    assert.ok(f.breakdown.length >= 1 && f.breakdown.length <= 3);
    for (const b of f.breakdown) assert.ok(['true', 'false', 'partial'].includes(b.status));
    assert.ok(f.breakdown[0].claim.includes('AI never makes mistakes'));
    assert.equal(typeof f.nuances, 'string');
    assert.equal(typeof f.literacyLesson, 'string');
  });

  test('analyze shape', async () => {
    const msg = await client.messages.create(chat('Analyze this AI-generated response:\n\nAI is always right.', { system: ANALYZE_SYSTEM }));
    const a = JSON.parse(msg.content[0].text.match(/\{[\s\S]*\}/)[0]);
    assert.ok(['strong', 'decent', 'problematic'].includes(a.overallAssessment));
    assert.ok(a.issues.length >= 2 && a.issues.length <= 4);
    assert.ok(a.issues.some((i) => i.type === 'good'), 'includes something done well');
    for (const k of ['summary', 'confidenceFlags', 'missingPerspectives', 'literacyLesson']) assert.equal(typeof a[k], 'string', k);
  });

  test('pre-briefing shape: exactly 3 bullets', async () => {
    const msg = await client.messages.create(chat('Generate a pre-meeting briefing for the next upcoming club meeting.', { system: BRIEFING_SYSTEM }));
    const b = JSON.parse(msg.content[0].text.match(/\{[\s\S]*\}/)[0]);
    assert.equal(typeof b.meetingTitle, 'string');
    assert.equal(typeof b.date, 'string');
    assert.equal(b.bullets.length, 3);
    for (const x of b.bullets) { assert.equal(typeof x.heading, 'string'); assert.equal(typeof x.body, 'string'); }
    assert.equal(typeof b.keyQuestion, 'string');
    assert.equal(typeof b.suggestedTopicToDiscuss, 'string');
  });

  test('memory extraction (no system prompt, JSON asked for in the user turn) → an array of {type, content}', async () => {
    const memoryPrompt = 'Analyze this student-AI exchange and extract key memories.\n\nStudent message: "I love AI in healthcare"\nAI response: "Great"\nMode: socratic\n\nReturn a JSON array of memory objects. Each object has "type" and "content".\nReturn ONLY valid JSON array, nothing else';
    const msg = await client.messages.create({ model: 'm', max_tokens: 200, messages: [{ role: 'user', content: memoryPrompt }] });
    const memories = JSON.parse(msg.content[0].text.trim());
    assert.ok(Array.isArray(memories));
    assert.ok(memories.length <= 3);
    for (const m of memories) { assert.equal(typeof m.type, 'string'); assert.equal(typeof m.content, 'string'); }
    assert.equal(memories[0].content, 'I love AI in healthcare');
  });

  test('an unrecognised JSON prompt defaults to the quiz shape', async () => {
    const msg = await client.messages.create(history(UNKNOWN_JSON_SYSTEM));
    const q = JSON.parse(msg.content[0].text);
    assert.ok(Array.isArray(q.questions) && q.questions.length === 4);
  });

  test('a system prompt without "JSON" never yields JSON', async () => {
    const msg = await client.messages.create(chat('Give me json please'));
    assert.throws(() => JSON.parse(msg.content[0].text));
  });
});

// ---------------------------------------------------------------------------
// Usage — estimates + cache accounting
// ---------------------------------------------------------------------------
describe('usage accounting', () => {
  const client = createMockClient({ delayMs: 1 });
  beforeEach(() => __resetForTest());

  test('input/output tokens are chars/3.8 estimates; cache fields are 0 without cache_control', async () => {
    const params = chat('Is AI conscious?');
    const msg = await client.messages.create(params);
    const inputChars = CHAT_SYSTEM.length + 'Is AI conscious?'.length;
    assert.equal(msg.usage.input_tokens, Math.round(inputChars / 3.8));
    assert.equal(msg.usage.output_tokens, Math.round(msg.content[0].text.length / 3.8));
    assert.equal(msg.usage.cache_creation_input_tokens, 0);
    assert.equal(msg.usage.cache_read_input_tokens, 0);
  });

  test('array system prompt: first call with a cache_control block is a creation, later calls are reads', async () => {
    const STATIC = 'STATIC PREFIX '.repeat(200);       // 2800 chars
    const ctx = 'Runtime context: mode=socratic';
    const params = () => ({
      model: 'm', max_tokens: 100,
      system: [
        { type: 'text', text: STATIC, cache_control: { type: 'ephemeral' } },
        { type: 'text', text: ctx },
      ],
      messages: [{ role: 'user', content: 'hello there' }],
    });
    const staticTokens = Math.round(STATIC.length / 3.8);
    const uncached = Math.round((ctx.length + 'hello there'.length) / 3.8);

    const first = await client.messages.create(params());
    assert.equal(first.usage.cache_creation_input_tokens, staticTokens);
    assert.equal(first.usage.cache_read_input_tokens, 0);
    assert.equal(first.usage.input_tokens, uncached, 'input_tokens excludes the cached block, like the real API');

    const second = await client.messages.create(params());
    assert.equal(second.usage.cache_creation_input_tokens, 0);
    assert.equal(second.usage.cache_read_input_tokens, staticTokens);
    assert.equal(second.usage.input_tokens, uncached);

    // A stream shares the same module-level Set → still a read.
    const s = client.messages.stream(params());
    const final = await s.finalMessage();
    assert.equal(final.usage.cache_read_input_tokens, staticTokens);
    assert.equal(final.usage.cache_creation_input_tokens, 0);

    // A different cached text is a fresh creation.
    const other = params();
    other.system[0].text = 'A DIFFERENT PREFIX '.repeat(100);
    const third = await client.messages.create(other);
    assert.equal(third.usage.cache_creation_input_tokens, Math.round(other.system[0].text.length / 3.8));
    assert.equal(third.usage.cache_read_input_tokens, 0);

    __resetForTest();
    const again = await client.messages.create(params());
    assert.equal(again.usage.cache_creation_input_tokens, staticTokens, 'reset forgets the block');
  });

  test('image blocks count a fixed 1200 tokens, not their base64 length', async () => {
    const params = {
      model: 'm', max_tokens: 100,
      messages: [{ role: 'user', content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'A'.repeat(500000) } },
        { type: 'text', text: 'What is this?' },
      ] }],
    };
    const msg = await client.messages.create(params);
    assert.equal(msg.usage.input_tokens, Math.round((1200 * 3.8 + 'What is this?'.length) / 3.8));
  });
});

// ---------------------------------------------------------------------------
// stream() — ordering, usage placement, abort, iteration
// ---------------------------------------------------------------------------
describe('stream(): happy path', () => {
  const client = createMockClient({ delayMs: 1 });

  test('emits the SDK event sequence with usage in message_start and message_delta', async () => {
    const params = chat('Is AI conscious?');
    const expected = await client.messages.create(params);
    const stream = client.messages.stream(params);
    const rec = record(stream);
    const final = await stream.finalMessage();
    await rec.ended;

    const log = rec.log;
    assert.deepEqual(log.slice(0, 2), ['message_start', 'content_block_start']);
    const textDeltas = log.filter((e) => e === 'content_block_delta').length;
    assert.ok(textDeltas >= 2);
    for (let i = 2; i < 2 + textDeltas * 2; i += 2) assert.deepEqual(log.slice(i, i + 2), ['content_block_delta', 'text']);
    assert.deepEqual(log.slice(2 + textDeltas * 2), [
      'content_block_stop', 'contentBlock', 'message_delta', 'message_stop', 'message', 'finalMessage', 'end',
    ]);

    // Text deltas are ~12 chars and reassemble to the create() reply.
    assert.ok(rec.texts.every((t) => t.delta.length <= 12 && t.delta.length > 0));
    assert.equal(rec.texts.map((t) => t.delta).join(''), expected.content[0].text);
    assert.equal(rec.texts[rec.texts.length - 1].full, expected.content[0].text, "'text' second arg is the accumulated text");

    // Snapshot passed alongside streamEvent grows like the SDK's.
    assert.equal(rec.snapshots[0].content, 0);
    assert.equal(rec.snapshots[1].content, 1);

    // Final message === the 'message' event payload, with full usage.
    assert.equal(final, rec.message);
    assert.equal(final, rec.finalMessage);
    assert.equal(final.content[0].text, expected.content[0].text);
    assert.deepEqual(final.usage, expected.usage);
    assert.equal(final.stop_reason, 'end_turn');
    assert.equal(stream.ended, true);
    assert.equal(stream.errored, false);
    assert.equal(stream.aborted, false);
    assert.equal(stream.currentMessage, final);
    assert.equal(stream.receivedMessages.length, 1);
    assert.equal(stream.messages.length, params.messages.length + 1);
    assert.equal(await stream.finalText(), expected.content[0].text);
  });

  test('message_start carries input + cache tokens with output_tokens:1; message_delta carries the real output_tokens', async () => {
    const params = chat('What is a token?');
    const stream = client.messages.stream(params);
    let startUsage = null;
    let startContentLength = -1;
    let delta = null;
    stream.on('streamEvent', (e) => {
      // event.message IS the live snapshot (SDK parity) — capture at event time.
      if (e.type === 'message_start') { startUsage = { ...e.message.usage }; startContentLength = e.message.content.length; }
      if (e.type === 'message_delta') delta = e;
    });
    const final = await stream.finalMessage();
    assert.deepEqual(Object.keys(startUsage).sort(), ['cache_creation_input_tokens', 'cache_read_input_tokens', 'input_tokens', 'output_tokens']);
    assert.equal(startUsage.output_tokens, 1);
    assert.equal(startUsage.input_tokens, final.usage.input_tokens);
    assert.equal(startContentLength, 0, 'message_start has an empty content array');
    assert.deepEqual(delta.delta, { stop_reason: 'end_turn', stop_sequence: null });
    assert.equal(delta.usage.output_tokens, final.usage.output_tokens);
    assert.equal(delta.usage.output_tokens, Math.round(final.content[0].text.length / 3.8));
    assert.equal(final.usage.output_tokens, delta.usage.output_tokens, 'snapshot picks up output_tokens from message_delta');
  });

  test('done() resolves after end; emitted() awaits a named event; async iteration yields streamEvents', async () => {
    const stream = client.messages.stream(chat('hi'));
    const messagePromise = stream.emitted('message');
    const types = [];
    for await (const ev of stream) types.push(ev.type);
    await stream.done();
    assert.equal(types[0], 'message_start');
    assert.equal(types[types.length - 1], 'message_stop');
    assert.equal((await messagePromise).role, 'assistant');
    assert.equal(stream.ended, true);
  });

  test('curriculum stream carries the [LESSON_COMPLETE] marker at the very end', async () => {
    const stream = client.messages.stream(conversation(5, { system: CURRICULUM_SYSTEM, opener: '[CURRICULUM: Unit 1, Lesson 1] Go.' }));
    let full = '';
    stream.on('text', (t) => { full += t; });
    await stream.done();
    assert.ok(full.endsWith('[LESSON_COMPLETE]'));
    assert.equal(processLessonOutcome(full).lessonComplete, true);
  });
});

describe('stream(): abort', () => {
  const client = createMockClient({ delayMs: 5 });

  test('abort() mid-stream → aborted (and errored, as the SDK flags it), "abort" then "end", no message', async () => {
    const stream = client.messages.stream(chat('Tell me everything about tokenization in great detail.'));
    const rec = record(stream);
    stream.on('text', () => { if (rec.texts.length === 2) stream.abort(); });
    await rec.ended;
    assert.equal(stream.aborted, true);
    assert.equal(stream.errored, true, 'SDK 0.39 sets errored on abort too — server.js checks both');
    assert.equal(stream.ended, true);
    assert.equal(rec.texts.length, 2, 'no deltas after abort');
    assert.equal(rec.message, null);
    assert.equal(rec.finalMessage, null);
    assert.equal(rec.log.indexOf('error'), -1, "aborts emit 'abort', never 'error'");
    assert.deepEqual(rec.log.slice(-2), ['abort', 'end']);
    assert.ok(rec.abortErr instanceof Error);
    assert.match(rec.abortErr.message, /aborted/i);
    await assert.rejects(stream.done());
    await assert.rejects(stream.finalMessage());
  });

  test('abort surfaces asynchronously, so code after abort() runs first (SDK parity)', async () => {
    const stream = client.messages.stream(chat('hello'));
    const rec = record(stream);
    stream.abort();
    assert.equal(stream.aborted, false, 'not yet — the fetch rejects on a later tick');
    await rec.ended;
    assert.equal(stream.aborted, true);
    assert.deepEqual(rec.log, ['abort', 'end'], 'nothing streamed before the abort landed');
  });

  test('options.signal (the server\'s watchdog AbortController) aborts the stream', async () => {
    const ac = new AbortController();
    const stream = client.messages.stream(chat('Tell me everything about tokenization in great detail.'), { signal: ac.signal });
    const rec = record(stream);
    stream.on('text', () => { if (rec.texts.length === 1) ac.abort(); });
    await rec.ended;
    assert.equal(stream.aborted, true);
    assert.equal(rec.texts.length, 1);
    assert.deepEqual(rec.log.slice(-2), ['abort', 'end']);
  });

  test('an already-aborted signal aborts before any event', async () => {
    const ac = new AbortController();
    ac.abort();
    const stream = client.messages.stream(chat('hello'), { signal: ac.signal });
    const rec = record(stream);
    await rec.ended;
    assert.deepEqual(rec.log, ['abort', 'end']);
  });

  test('abort() after end is a no-op', async () => {
    const stream = client.messages.stream(chat('hello'));
    const rec = record(stream);
    await rec.ended;
    stream.abort();
    await new Promise((r) => setTimeout(r, 10));
    assert.equal(stream.aborted, false);
    assert.equal(rec.log.filter((e) => e === 'end').length, 1);
  });
});

// ---------------------------------------------------------------------------
// Scenarios — error / overloaded / credit / hang / slow
// ---------------------------------------------------------------------------
describe('error scenarios', () => {
  const cases = [
    { scenario: 'error', status: 500, type: 'api_error', cls: Anthropic.InternalServerError },
    { scenario: 'overloaded', status: 529, type: 'overloaded_error', cls: Anthropic.InternalServerError },
    { scenario: 'credit', status: 400, type: 'invalid_request_error', cls: Anthropic.BadRequestError },
  ];

  for (const { scenario, status, type, cls } of cases) {
    test(`${scenario}: create() rejects with a real SDK APIError (status ${status}, ${type})`, async () => {
      const client = createMockClient({ scenario, delayMs: 1 });
      await assert.rejects(client.messages.create(chat('hi')), (err) => {
        assert.ok(err instanceof Anthropic.APIError);
        assert.ok(err instanceof cls);
        assert.equal(err.status, status);
        assert.deepEqual(err.error.type, 'error');
        assert.equal(err.error.error.type, type);
        assert.match(err.message, new RegExp('^' + status + ' '));
        assert.match(err.request_id, /^req_mock_/);
        if (scenario === 'credit') assert.match(err.error.error.message, /credit balance is too low/);
        return true;
      });
    });

    test(`${scenario}: stream() emits 'error' then 'end', errored=true, no message`, async () => {
      const client = createMockClient({ scenario, delayMs: 1 });
      const stream = client.messages.stream(chat('hi'));
      const rec = record(stream);
      await rec.ended;
      assert.deepEqual(rec.log, ['error', 'end']);
      assert.equal(stream.errored, true);
      assert.equal(stream.aborted, false);
      assert.equal(stream.ended, true);
      assert.equal(rec.error.status, status);
      assert.equal(rec.error.error.error.type, type);
      assert.equal(rec.message, null);
      await assert.rejects(stream.finalMessage(), (e) => e.status === status);
    });
  }

  test('hang: stream sends message_start + one delta then stalls until abort()', async () => {
    const client = createMockClient({ scenario: 'hang', delayMs: 1 });
    const stream = client.messages.stream(chat('Tell me everything about tokenization.'));
    const rec = record(stream);
    await new Promise((r) => setTimeout(r, 60));
    assert.deepEqual(rec.log, ['message_start', 'content_block_start', 'content_block_delta', 'text']);
    assert.equal(stream.ended, false);
    stream.abort();                                   // what the server watchdog does
    await rec.ended;
    assert.equal(stream.aborted, true);
    assert.deepEqual(rec.log.slice(-2), ['abort', 'end']);
  });

  test('hang: create() fails like the SDK client timeout after timeoutMs', async () => {
    const client = createMockClient({ scenario: 'hang', delayMs: 1, timeoutMs: 30 });
    const started = Date.now();
    await assert.rejects(client.messages.create(chat('hi')), (err) => {
      assert.ok(err instanceof Anthropic.APIConnectionTimeoutError);
      assert.match(err.message, /timed out/i);
      return true;
    });
    assert.ok(Date.now() - started >= 25, 'waited for the timeout');
  });

  test('slow: chunks arrive 20× slower than ok', async () => {
    const params = chat('Tell me everything about tokenization in great detail please.');
    const time = async (client) => {
      const t0 = Date.now();
      await client.messages.stream(params).finalMessage();
      return Date.now() - t0;
    };
    const okMs = await time(createMockClient({ scenario: 'ok', delayMs: 1 }));
    const slowMs = await time(createMockClient({ scenario: 'slow', delayMs: 1 }));
    const chunks = Math.ceil((await createMockClient({ delayMs: 1 }).messages.create(params)).content[0].text.length / 12);
    assert.ok(slowMs >= chunks * 20 * 0.5, `slow took ${slowMs}ms for ${chunks} chunks`);
    assert.ok(slowMs > okMs, `slow ${slowMs}ms should exceed ok ${okMs}ms`);
  });
});

// ---------------------------------------------------------------------------
// Request validation the real API enforces
// ---------------------------------------------------------------------------
describe('request validation (real-API 400s)', () => {
  const client = createMockClient({ delayMs: 1 });

  test('first message must be a user turn', async () => {
    await assert.rejects(
      client.messages.create({ model: 'm', max_tokens: 10, messages: [{ role: 'assistant', content: 'x' }, { role: 'user', content: 'y' }] }),
      (err) => err.status === 400 && /user/.test(err.error.error.message),
    );
  });

  test('`timeout` in the body is rejected (the bug the client-level timeout fixed)', async () => {
    await assert.rejects(
      client.messages.create({ ...chat('hi'), timeout: 30000 }),
      (err) => err.status === 400 && /timeout: Extra inputs/.test(err.error.error.message),
    );
  });

  test('empty messages → 400 on stream() too, as an error event', async () => {
    const stream = client.messages.stream({ model: 'm', max_tokens: 10, messages: [] });
    const rec = record(stream);
    await rec.ended;
    assert.deepEqual(rec.log, ['error', 'end']);
    assert.equal(rec.error.status, 400);
  });
});
