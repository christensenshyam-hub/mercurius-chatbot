'use strict';

/**
 * Zod-schema unit tests.
 *
 * These run independently of the HTTP server — they exercise the
 * schemas in lib/schemas.js directly. Paired with the integration
 * tests in server.test.js which verify the end-to-end 400 responses.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const {
  SessionId,
  ChatMessage,
  ChatMode,
  ChatRequest,
  ModeRequest,
  QuizRequest,
  _legacyErrorCode,
} = require('../lib/schemas');

describe('SessionId', () => {
  test('accepts well-formed ids', () => {
    assert.ok(SessionId.safeParse('abc123').success);
    assert.ok(SessionId.safeParse('a-b_c-D9').success);
    assert.ok(SessionId.safeParse('a').success);
    assert.ok(SessionId.safeParse('A'.repeat(64)).success);
  });

  test('rejects empty, over-length, and junk chars', () => {
    assert.ok(!SessionId.safeParse('').success);
    assert.ok(!SessionId.safeParse('x'.repeat(65)).success);
    assert.ok(!SessionId.safeParse('has spaces').success);
    assert.ok(!SessionId.safeParse("'; DROP TABLE").success);
    assert.ok(!SessionId.safeParse('has/slash').success);
    assert.ok(!SessionId.safeParse(123).success, 'non-string must fail');
    assert.ok(!SessionId.safeParse(null).success);
    assert.ok(!SessionId.safeParse(undefined).success);
  });
});

describe('ChatMessage', () => {
  test('round-trips a valid user message', () => {
    const parsed = ChatMessage.parse({ role: 'user', content: 'hi' });
    assert.equal(parsed.role, 'user');
    assert.equal(parsed.content, 'hi');
  });

  test('accepts assistant + system roles', () => {
    assert.ok(ChatMessage.safeParse({ role: 'assistant', content: 'ok' }).success);
    assert.ok(ChatMessage.safeParse({ role: 'system', content: 'ok' }).success);
  });

  test('rejects unknown roles', () => {
    assert.ok(!ChatMessage.safeParse({ role: 'tool', content: 'x' }).success);
    assert.ok(!ChatMessage.safeParse({ role: '', content: 'x' }).success);
  });

  test('rejects non-string content', () => {
    assert.ok(!ChatMessage.safeParse({ role: 'user', content: 42 }).success);
    assert.ok(!ChatMessage.safeParse({ role: 'user', content: null }).success);
  });

  test('rejects content over 10_000 chars', () => {
    assert.ok(!ChatMessage.safeParse({ role: 'user', content: 'x'.repeat(10_001) }).success);
  });
});

describe('ChatMode', () => {
  test('accepts every shipping mode', () => {
    for (const m of ['socratic', 'direct', 'debate', 'discussion']) {
      assert.ok(ChatMode.safeParse(m).success, `should accept ${m}`);
    }
  });
  test('rejects unknown modes', () => {
    assert.ok(!ChatMode.safeParse('turbo').success);
    assert.ok(!ChatMode.safeParse('SOCRATIC').success);
  });
});

describe('ChatRequest', () => {
  const sid = 'abc_DEF-123';

  test('parses a minimal valid body', () => {
    const parsed = ChatRequest.parse({
      sessionId: sid,
      messages: [{ role: 'user', content: 'hello' }],
    });
    assert.equal(parsed.sessionId, sid);
    assert.equal(parsed.messages.length, 1);
  });

  test('rejects empty messages array', () => {
    assert.ok(!ChatRequest.safeParse({ sessionId: sid, messages: [] }).success);
  });

  test('rejects over-long messages array', () => {
    const messages = Array.from({ length: 201 }, () => ({ role: 'user', content: 'x' }));
    assert.ok(!ChatRequest.safeParse({ sessionId: sid, messages }).success);
  });

  test('rejects missing sessionId', () => {
    const out = ChatRequest.safeParse({ messages: [{ role: 'user', content: 'hi' }] });
    assert.ok(!out.success);
    // Verify our error-code mapper routes this correctly.
    assert.equal(_legacyErrorCode(out.error.issues), 'invalid_session');
  });
});

describe('ModeRequest', () => {
  test('parses a minimal valid body', () => {
    const out = ModeRequest.parse({ sessionId: 'abc', mode: 'debate' });
    assert.equal(out.mode, 'debate');
  });

  test('rejects an unknown mode', () => {
    const out = ModeRequest.safeParse({ sessionId: 'abc', mode: 'yolo' });
    assert.ok(!out.success);
    assert.equal(_legacyErrorCode(out.error.issues), 'invalid_request');
  });

  test('accepts optional clientUnlocked without enforcing it', () => {
    const out = ModeRequest.parse({ sessionId: 'abc', mode: 'direct', clientUnlocked: true });
    assert.equal(out.mode, 'direct');
    // Schema validation doesn't enforce policy — the server still
    // refuses `direct` for a locked session, just not at this layer.
  });
});

describe('QuizRequest', () => {
  test('accepts a body with just sessionId', () => {
    const out = QuizRequest.parse({ sessionId: 'abc' });
    assert.equal(out.sessionId, 'abc');
  });

  test('accepts a body with empty messages array', () => {
    const out = QuizRequest.parse({ sessionId: 'abc', messages: [] });
    assert.equal(out.sessionId, 'abc');
  });

  test('rejects missing sessionId', () => {
    assert.ok(!QuizRequest.safeParse({ messages: [] }).success);
  });
});

describe('legacyErrorCode mapping', () => {
  test('session path → invalid_session', () => {
    const bad = ChatRequest.safeParse({ sessionId: '', messages: [{ role: 'user', content: 'x' }] });
    assert.equal(_legacyErrorCode(bad.error.issues), 'invalid_session');
  });

  test('messages path → invalid_messages', () => {
    const bad = ChatRequest.safeParse({ sessionId: 'abc', messages: [] });
    assert.equal(_legacyErrorCode(bad.error.issues), 'invalid_messages');
  });

  test('mode path → invalid_request', () => {
    const bad = ModeRequest.safeParse({ sessionId: 'abc', mode: 'nope' });
    assert.equal(_legacyErrorCode(bad.error.issues), 'invalid_request');
  });

  test('unrecognized path falls back to invalid_request', () => {
    assert.equal(_legacyErrorCode([{ path: ['other'], code: 'invalid_type' }]), 'invalid_request');
  });
});
