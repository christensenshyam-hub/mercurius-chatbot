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
});
