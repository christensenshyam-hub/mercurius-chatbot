'use strict';

/**
 * lib/claudeCall — the single seam in front of the Anthropic SDK.
 *
 * Runs against lib/anthropicMock (ANTHROPIC_MOCK=1), so no key is needed.
 * The load-bearing property is settle-once accounting: every call — ok,
 * errored, or aborted mid-stream — produces exactly one usage row, feeds the
 * dollar budget and the quotas, and releases its in-flight slot.
 */

const { describe, test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.ANTHROPIC_MOCK = '1';
process.env.MOCK_STREAM_DELAY_MS = '2';

const claudeCall = require('../lib/claudeCall');
const quotas = require('../lib/quotas');
const spendCap = require('../lib/spendCap');
const alerts = require('../lib/alerts');
const pricing = require('../lib/pricing');

function fakeDb() {
  const rows = [];
  return {
    rows,
    async recordUsage(row) { rows.push(row); },
  };
}

function chatParams(text = 'What is a token?') {
  return {
    model: 'claude-sonnet-4-6',
    max_tokens: 200,
    system: 'You are a Socratic tutor.',
    messages: [{ role: 'user', content: text }],
  };
}

function waitFor(stream, event) {
  return new Promise((resolve) => stream.on(event, resolve));
}

describe('claudeCall', () => {
  let db;

  beforeEach(() => {
    delete process.env.MOCK_SCENARIO;
    claudeCall.__resetForTest();
    quotas.__resetForTest();
    spendCap.__resetForTest();
    alerts.__resetForTest();
    alerts.configure({ webhookUrl: '', fetch: async () => ({ ok: true }) });
    db = fakeDb();
    claudeCall.init({ apiKey: 'unused', db, ipHashSalt: 'test-salt' });
  });

  afterEach(() => {
    delete process.env.MOCK_SCENARIO;
  });

  test('createMessage: returns the message and settles one ok row with cost', async () => {
    const message = await claudeCall.createMessage({
      route: '/api/chat', kind: 'chat', sessionId: 'sess-1', ip: '10.0.0.1', traceId: 't-1',
      params: chatParams(),
    });
    assert.ok(message.content[0].text.length > 0, 'mock reply text present');
    await new Promise((r) => setImmediate(r));

    assert.equal(db.rows.length, 1, 'exactly one ledger row');
    const row = db.rows[0];
    assert.equal(row.status, 'ok');
    assert.equal(row.route, '/api/chat');
    assert.equal(row.kind, 'chat');
    assert.equal(row.session_id, 'sess-1');
    assert.equal(row.trace_id, 't-1');
    assert.ok(row.input_tokens > 0 && row.output_tokens > 0, 'token counts recorded');
    assert.ok(row.cost_usd > 0, 'cost priced');
    assert.equal(row.ip_hash, claudeCall.hashIp('10.0.0.1'));
    assert.notEqual(row.ip_hash, '10.0.0.1', 'ip is hashed, never stored raw');
    assert.ok(spendCap.currentUsd() > 0, 'budget fed');
    assert.equal(quotas.inflight().global, 0, 'in-flight slot released');
  });

  test('createMessage: feeds the per-session quota', async () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1 });
    assert.equal(quotas.check({ sessionId: 's', ip: '1.1.1.1', kind: 'chat' }).ok, true);
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 's', ip: '1.1.1.1', params: chatParams() });
    const verdict = quotas.check({ sessionId: 's', ip: '1.1.1.1', kind: 'chat' });
    assert.equal(verdict.ok, false);
    assert.equal(verdict.error, 'daily_limit');
    assert.equal(verdict.scope, 'session');
  });

  test('streamMessage: settles once on end with real output tokens', async () => {
    const stream = claudeCall.streamMessage({
      route: '/api/chat', kind: 'lesson', sessionId: 'sess-2', ip: '10.0.0.2',
      params: chatParams('[CURRICULUM: Unit 1, Lesson 1] start'),
    });
    let text = '';
    stream.on('text', (t) => { text += t; });
    await waitFor(stream, 'end');
    await new Promise((r) => setImmediate(r));

    assert.ok(text.length > 0, 'deltas received');
    assert.equal(db.rows.length, 1, 'settled exactly once');
    assert.equal(db.rows[0].status, 'ok');
    assert.equal(db.rows[0].kind, 'lesson');
    assert.ok(db.rows[0].output_tokens > 0);
    assert.equal(quotas.inflight().global, 0);
    assert.ok(stream.accounting(), 'accounting result exposed after end');
  });

  test('streamMessage: an aborted stream is billed for the text actually received', async () => {
    const stream = claudeCall.streamMessage({
      route: '/api/chat', kind: 'chat', sessionId: 'sess-3', ip: '10.0.0.3', params: chatParams(),
    });
    // Let several chunks arrive before aborting so the estimate is well above
    // the API's message_start placeholder of 1 output token.
    let received = '';
    let chunks = 0;
    stream.on('text', (t) => {
      received += t;
      chunks += 1;
      if (chunks === 4) stream.abort();
    });
    await waitFor(stream, 'end');
    await new Promise((r) => setImmediate(r));

    assert.equal(db.rows.length, 1, 'settled exactly once despite abort + end');
    assert.equal(db.rows[0].status, 'aborted');
    const estimate = pricing.estimateTokens(received);
    assert.ok(estimate > 1, `test needs >1 token received (got ${received.length} chars)`);
    assert.ok(db.rows[0].output_tokens >= estimate, `billed ${db.rows[0].output_tokens} output tokens for an estimate of ${estimate}`);
    assert.equal(quotas.inflight().global, 0, 'slot released on abort');
    assert.equal(db.rows[0].error_kind, 'client_abort', 'a Stop / disconnect is the client going away');
  });

  test("streamMessage: an abort through the route's own signal (its watchdog) is a timeout", async () => {
    const watchdog = new AbortController();
    const stream = claudeCall.streamMessage({
      route: '/api/chat', kind: 'chat', sessionId: 'sess-4', ip: '10.0.0.4', params: chatParams(), signal: watchdog.signal,
    });
    let chunks = 0;
    stream.on('text', () => { chunks += 1; if (chunks === 2) watchdog.abort(); });
    await waitFor(stream, 'end');
    await new Promise((r) => setImmediate(r));
    assert.equal(db.rows.length, 1);
    assert.equal(db.rows[0].status, 'aborted');
    assert.equal(db.rows[0].error_kind, 'timeout');
  });

  test('beginCall re-checks quotas atomically and refuses with QuotaError', async () => {
    quotas.configure({ MAX_INFLIGHT: 0 });
    await assert.rejects(
      () => claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 's', ip: '4.4.4.4', params: chatParams() }),
      (err) => err instanceof claudeCall.QuotaError && err.code === 'busy' && err.status === 503,
    );
    assert.equal(db.rows.length, 0, 'a refused call is never billed');
    assert.equal(quotas.inflight().global, 0, 'nothing acquired on refusal');
    quotas.configure({ MAX_INFLIGHT: null });

    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 0 });
    await assert.rejects(
      () => claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 's2', ip: '4.4.4.4', params: chatParams() }),
      (err) => err instanceof claudeCall.QuotaError && err.code === 'daily_limit' && err.status === 429 && err.verdict.scope === 'session',
    );
  });

  test('createMessage: an upstream error settles an error row and rethrows', async () => {
    process.env.MOCK_SCENARIO = 'overloaded';
    claudeCall.__resetForTest();
    claudeCall.init({ apiKey: 'unused', db });

    await assert.rejects(
      () => claudeCall.createMessage({ route: '/api/quiz', kind: 'helper', sessionId: 's', ip: '2.2.2.2', params: chatParams() }),
      (err) => Number(err.status) === 529 || /overloaded/i.test(String(err.message)),
    );
    await new Promise((r) => setImmediate(r));
    assert.equal(db.rows.length, 1);
    assert.equal(db.rows[0].status, 'error');
    assert.equal(db.rows[0].error_kind, 'overloaded');
    assert.equal(quotas.inflight().global, 0);
  });

  test('streamMessage: a stream error settles once even though the SDK also emits end', async () => {
    process.env.MOCK_SCENARIO = 'error';
    claudeCall.__resetForTest();
    claudeCall.init({ apiKey: 'unused', db });

    const stream = claudeCall.streamMessage({ route: '/api/chat', kind: 'chat', sessionId: 's', ip: '3.3.3.3', params: chatParams() });
    stream.on('error', () => {});
    await waitFor(stream, 'end');
    await new Promise((r) => setImmediate(r));

    assert.equal(db.rows.length, 1, 'one row for error + end');
    assert.equal(db.rows[0].status, 'error');
    assert.equal(quotas.inflight().global, 0);
  });

  test('classifyError maps the vocabulary we alert and chart on', () => {
    assert.equal(claudeCall.classifyError({ status: 529, message: 'Overloaded' }), 'overloaded');
    assert.equal(claudeCall.classifyError({ status: 429, message: 'rate' }), 'rate_limited');
    assert.equal(claudeCall.classifyError({ status: 400, message: 'Your credit balance is too low' }), 'credit');
    assert.equal(claudeCall.classifyError({ status: 401, message: 'bad key' }), 'auth');
    assert.equal(claudeCall.classifyError({ status: 500, message: 'boom' }), 'http_500');
    assert.equal(claudeCall.classifyError({ name: 'AbortError', message: 'aborted' }), 'abort');
    assert.equal(claudeCall.classifyError({ name: 'APIConnectionTimeoutError', message: 'Request timed out' }), 'timeout');
    assert.equal(claudeCall.classifyError(null), 'unknown');
  });

  test('hashIp is deterministic, salted, and short', () => {
    const a = claudeCall.hashIp('203.0.113.9');
    assert.equal(a, claudeCall.hashIp('203.0.113.9'));
    assert.equal(a.length, 16);
    assert.equal(claudeCall.hashIp(''), null);
    claudeCall.init({ apiKey: 'unused', db, ipHashSalt: 'other-salt' });
    assert.notEqual(a, claudeCall.hashIp('203.0.113.9'), 'salt changes the hash');
  });

  test('a credit-balance error pages on its first occurrence (not after a 5-error burst)', async () => {
    const posts = [];
    alerts.configure({ webhookUrl: 'https://discord.invalid/hook', fetch: async (_url, init) => { posts.push(JSON.parse(init.body).content); return { ok: true }; } });
    process.env.MOCK_SCENARIO = 'credit';
    claudeCall.__resetForTest();
    claudeCall.init({ apiKey: 'unused', db });
    await assert.rejects(claudeCall.createMessage({ route: '/api/quiz', kind: 'helper', sessionId: 'c1', ip: '10.0.0.3', params: chatParams() }));
    await new Promise((r) => setImmediate(r));
    assert.equal(db.rows[0].error_kind, 'credit');
    assert.equal(posts.length, 1, JSON.stringify(posts));
    assert.match(posts[0], /credit balance is too low.*\/api\/quiz/);
  });

  test('the budget-spent page fires again on the next budget day, even < 24 h later', async (t) => {
    const saved = process.env.DAILY_BUDGET_USD;
    const savedTz = process.env.STREAK_TZ;
    process.env.DAILY_BUDGET_USD = '0.000001';
    process.env.STREAK_TZ = 'America/Chicago';
    t.after(() => {
      if (saved === undefined) delete process.env.DAILY_BUDGET_USD; else process.env.DAILY_BUDGET_USD = saved;
      if (savedTz === undefined) delete process.env.STREAK_TZ; else process.env.STREAK_TZ = savedTz;
    });
    t.mock.timers.enable({ apis: ['Date'], now: Date.UTC(2026, 8, 28, 23, 0, 0) }); // 6 PM CDT, Sep 28
    const posts = [];
    alerts.configure({ webhookUrl: 'https://discord.invalid/hook', fetch: async (_url, init) => { posts.push(JSON.parse(init.body).content); return { ok: true }; } });
    spendCap.__resetForTest();

    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'b1', ip: '10.0.0.9', params: chatParams() });
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'b1', ip: '10.0.0.9', params: chatParams() }).catch(() => {});
    t.mock.timers.setTime(Date.UTC(2026, 8, 29, 1, 0, 0)); // 8 PM CDT: past UTC midnight, same budget day
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'b1', ip: '10.0.0.9', params: chatParams() }).catch(() => {});
    t.mock.timers.setTime(Date.UTC(2026, 8, 29, 20, 0, 0)); // 21 h later, a new budget day
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'b2', ip: '10.0.0.9', params: chatParams() });
    await new Promise((r) => setImmediate(r));

    const spent = posts.filter((p) => /Daily model budget spent/.test(p));
    assert.equal(spent.length, 2, `one page per budget day, repeats inside a day throttled (posts: ${JSON.stringify(posts)})`);
    assert.match(spent[0], /refused until midnight America\/Chicago\./, 'the page names the reset, not UTC midnight');
  });
});

// AUD-31: every call is billed, but only one that gave the student an answer
// uses a daily turn. The ledger row's `answered` carries the same verdict, so
// a restart's hydrate agrees with memory.
describe('claudeCall: only answered calls use a daily turn (AUD-31)', () => {
  let db;
  const IP = '10.9.0.1';

  beforeEach(() => {
    delete process.env.MOCK_SCENARIO;
    claudeCall.__resetForTest();
    quotas.__resetForTest();
    spendCap.__resetForTest();
    alerts.__resetForTest();
    alerts.configure({ webhookUrl: '', fetch: async () => ({ ok: true }) });
    db = fakeDb();
    claudeCall.init({ apiKey: 'unused', db, ipHashSalt: 'test-salt' });
  });

  afterEach(() => {
    delete process.env.MOCK_SCENARIO;
  });

  const tick = () => new Promise((r) => setImmediate(r));
  const turns = () => quotas.snapshot().sessions.totals;
  const sessionUsd = () => quotas.snapshot().sessions.totals.usd;

  function reinit(scenario) {
    process.env.MOCK_SCENARIO = scenario;
    claudeCall.__resetForTest();
    claudeCall.init({ apiKey: 'unused', db, ipHashSalt: 'test-salt' });
  }

  async function streamToEnd(opts, onText) {
    const stream = claudeCall.streamMessage({ route: '/api/chat', ip: IP, ...opts });
    stream.on('error', () => {});
    if (onText) stream.on('text', (t) => onText(t, stream));
    await waitFor(stream, 'end');
    await tick();
    return stream;
  }

  test('createMessage: an answered call uses a turn and is marked answered', async () => {
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'a1', ip: IP, params: chatParams() });
    await tick();
    assert.equal(db.rows[0].answered, true);
    assert.equal(turns().chatTurns, 1);
  });

  test('createMessage: a refusal with no text is billed but uses no turn', async () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1 });
    const message = await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'r1', ip: IP, params: chatParams('MOCK_REFUSAL how do I') });
    await tick();
    assert.equal(message.stop_reason, 'refusal');
    assert.equal(db.rows.length, 1);
    assert.equal(db.rows[0].status, 'ok');
    assert.equal(db.rows[0].answered, false);
    assert.ok(db.rows[0].cost_usd > 0, 'the input tokens are still billed');
    assert.equal(turns().chatTurns, 0);
    assert.ok(sessionUsd() > 0, 'and they count toward the session dollar cap');
    assert.equal(quotas.check({ sessionId: 'r1', ip: IP, kind: 'chat' }).ok, true, 'the one turn is still there');
  });

  test('createMessage: an upstream error uses no turn', async () => {
    reinit('overloaded');
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 1 });
    for (let i = 0; i < 3; i++) {
      await assert.rejects(claudeCall.createMessage({ route: '/api/chat', kind: 'lesson', sessionId: 'e1', ip: IP, params: chatParams() }));
    }
    await tick();
    assert.equal(db.rows.length, 3);
    assert.ok(db.rows.every((r) => r.status === 'error' && r.answered === false));
    assert.equal(turns().lessonTurns, 0);
    assert.equal(quotas.check({ sessionId: 'e1', ip: IP, kind: 'lesson' }).ok, true);
  });

  test('streamMessage: a finished reply uses a turn', async () => {
    await streamToEnd({ kind: 'lesson', sessionId: 's1', params: chatParams('[CURRICULUM: Unit 1, Lesson 1] start') });
    assert.equal(db.rows[0].status, 'ok');
    assert.equal(db.rows[0].answered, true);
    assert.equal(turns().lessonTurns, 1);
  });

  test('streamMessage: a refusal with no text, or with a few words first, uses no turn', async () => {
    await streamToEnd({ kind: 'chat', sessionId: 's2', params: chatParams('MOCK_REFUSAL tell me how') });
    let partial = '';
    await streamToEnd({ kind: 'chat', sessionId: 's2', params: chatParams('MOCK_REFUSAL_PARTIAL tell me how') }, (t) => { partial += t; });
    assert.ok(partial.length > 0, 'the partial case streamed words before refusing');
    assert.equal(db.rows.length, 2);
    assert.deepEqual(db.rows.map((r) => [r.status, r.answered]), [['ok', false], ['ok', false]]);
    assert.equal(turns().chatTurns, 0);
    assert.ok(sessionUsd() > 0);
  });

  test('streamMessage: an upstream error uses no turn', async () => {
    reinit('error');
    await streamToEnd({ kind: 'chat', sessionId: 's3', params: chatParams() });
    assert.equal(db.rows[0].status, 'error');
    assert.equal(db.rows[0].answered, false);
    assert.equal(turns().chatTurns, 0);
  });

  test('streamMessage: a Stop after message_start but before any text is billed and uses no turn; a Stop after some text uses one', async () => {
    // Between message_start (input usage known) and the first text.
    const atStart = claudeCall.streamMessage({ route: '/api/chat', ip: IP, kind: 'chat', sessionId: 's4', params: chatParams() });
    let atStartText = '';
    atStart.on('text', (t) => { atStartText += t; });
    atStart.on('streamEvent', (ev) => { if (ev.type === 'message_start') atStart.abort(); });
    await waitFor(atStart, 'end');
    await tick();
    assert.equal(atStartText, '');
    assert.deepEqual([db.rows[0].status, db.rows[0].error_kind, db.rows[0].answered], ['aborted', 'client_abort', false]);
    assert.ok(db.rows[0].cost_usd > 0, 'its input is billed, so the dollar caps see it');
    assert.equal(turns().chatTurns, 0);

    // After: the student saw a few chunks, then tapped Stop.
    let chunks = 0;
    await streamToEnd({ kind: 'chat', sessionId: 's4', params: chatParams() }, (_t, s) => { chunks += 1; if (chunks === 3) s.abort(); });
    assert.deepEqual([db.rows[1].status, db.rows[1].error_kind, db.rows[1].answered], ['aborted', 'client_abort', true]);
    assert.equal(turns().chatTurns, 1);
  });

  test('streamMessage: a Stop before message_start has nothing to bill, so it uses a turn (review of AUD-31)', async () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 2 });
    for (let i = 0; i < 2; i++) {
      // Abort as soon as the stream exists: the mock waits a delay before
      // message_start, so neither usage nor text has arrived.
      const early = claudeCall.streamMessage({ route: '/api/chat', ip: IP, kind: 'chat', sessionId: 's6', params: chatParams() });
      early.abort();
      await waitFor(early, 'end');
    }
    await tick();
    assert.deepEqual(db.rows.map((r) => [r.status, r.error_kind, r.answered, r.cost_usd]), [
      ['aborted', 'client_abort', true, 0],
      ['aborted', 'client_abort', true, 0],
    ]);
    assert.equal(turns().chatTurns, 2);
    assert.equal(quotas.check({ sessionId: 's6', ip: IP, kind: 'chat' }).ok, false, 'the allowance bounds a script that cancels every request');
  });

  test("streamMessage: the route's watchdog cutting a reply short uses no turn, even after text", async () => {
    const watchdog = new AbortController();
    let chunks = 0;
    await streamToEnd(
      { kind: 'lesson', sessionId: 's5', params: chatParams('[CURRICULUM: Unit 1, Lesson 1] start'), signal: watchdog.signal },
      () => { chunks += 1; if (chunks === 2) watchdog.abort(); },
    );
    assert.deepEqual([db.rows[0].status, db.rows[0].error_kind, db.rows[0].answered], ['aborted', 'timeout', false]);
    assert.equal(turns().lessonTurns, 0);
  });

  test('the dollar budget counts every call, answered or not', async () => {
    await claudeCall.createMessage({ route: '/api/chat', kind: 'chat', sessionId: 'd1', ip: IP, params: chatParams('MOCK_REFUSAL x') });
    await tick();
    const refusedCost = db.rows[0].cost_usd;
    assert.ok(refusedCost > 0);
    assert.ok(Math.abs(spendCap.currentUsd() - refusedCost) < 1e-12, 'the refused call is on the global budget');
    assert.ok(Math.abs(quotas.snapshot().ips.usd - refusedCost) < 1e-9, 'and on the network dollar cap');
  });
});
