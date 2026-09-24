'use strict';

// Tests for the report → Discord alert formatter/poster (lib/reportWebhook).
//
// Pure unit tests — `notify` is injected, so lib/alerts, the network and
// DISCORD_WEBHOOK_URL are never touched. logger.warn is spied with the test
// runner's mock where a failure path is expected to log.
//
//   1. Payload shape — key, header line, quoted student/merc lines, no
//      throttle option.
//   2. Truncation — student 300, merc 600, '…' appended only when cut.
//   3. Missing optional fields — reason/surface/mode/appVersion fall back to
//      'unspecified' / '?', the student line is omitted, null-safe.
//   4. Session id — only the first 8 chars are ever posted.
//   5. Failure paths — notify rejects / throws sync / returns non-boolean →
//      resolves false, never throws, warn carries the key but not the text.
//   6. Hardening — newlines cannot escape the quote, mentions are defused,
//      snake_case rows are accepted.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const logger = require('../lib/logger');
const {
  notifyReport,
  formatReport,
  _alertKey,
  STUDENT_MAX_CHARS,
  MERC_MAX_CHARS,
} = require('../lib/reportWebhook');

const SESSION = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

// An injectable notify that records every call and answers `result`.
function fakeNotify(result = true) {
  const calls = [];
  const fn = async (key, text, opts) => {
    calls.push({ key, text, opts });
    return result;
  };
  fn.calls = calls;
  return fn;
}

function fullReport(overrides = {}) {
  return {
    id: 42,
    ts: 1_700_000_000_000,
    sessionId: SESSION,
    reason: 'harmful',
    content: 'Sure, here is how to get into the school wifi.',
    userMessage: 'how do I get into the school wifi',
    context: { surface: 'chat', mode: 'socratic', lessonId: 'u1_l3', appVersion: '2.3.0' },
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// 1. Payload shape
// ---------------------------------------------------------------------------
describe('notifyReport payload shape', () => {
  test('posts once under report:<id> with the header + quoted student/merc lines and no throttle', async () => {
    const notify = fakeNotify(true);

    const posted = await notifyReport(fullReport(), { notify });

    assert.equal(posted, true);
    assert.equal(notify.calls.length, 1);
    const { key, text, opts } = notify.calls[0];
    assert.equal(key, 'report:42');
    assert.ok(opts === undefined || !opts.throttleMs, 'a report alert must never be throttled');

    const lines = text.split('\n');
    assert.equal(lines.length, 3);
    assert.equal(lines[0], '🚩 Report: harmful · session a1b2c3d4… · chat/socratic · 2.3.0');
    assert.equal(lines[1], '> **student:** how do I get into the school wifi');
    assert.equal(lines[2], '> **merc:** Sure, here is how to get into the school wifi.');
  });

  test('formatReport returns exactly the text notifyReport posts', async () => {
    const notify = fakeNotify(true);
    const report = fullReport();
    await notifyReport(report, { notify });
    assert.equal(notify.calls[0].text, formatReport(report));
  });

  test('lessonId is carried by the queue row, not the alert', () => {
    const text = formatReport(fullReport());
    assert.ok(!text.includes('u1_l3'));
  });

  test('every enum reason renders verbatim in the header', () => {
    for (const reason of ['wrong', 'harmful', 'off_topic', 'other']) {
      assert.ok(formatReport(fullReport({ reason })).startsWith(`🚩 Report: ${reason} · `));
    }
  });

  test('the key falls back to report:<ts> when the row has no id', () => {
    assert.equal(_alertKey({ ts: 1_700_000_000_000 }), 'report:1700000000000');
    assert.equal(_alertKey({ createdAt: 5 }), 'report:5');
    assert.equal(_alertKey({ created_at: 6 }), 'report:6');
    assert.equal(_alertKey({ id: 0 }), 'report:0', 'id 0 is a real id');
    assert.equal(_alertKey({ id: 'abc', ts: 1 }), 'report:abc', 'id wins over ts');
    assert.match(_alertKey({}), /^report:\d+$/, 'no id and no ts → now()');
  });

  test('resolves whatever boolean notify answers (false when Discord did not take it)', async () => {
    assert.equal(await notifyReport(fullReport(), { notify: fakeNotify(false) }), false);
    assert.equal(await notifyReport(fullReport(), { notify: fakeNotify(true) }), true);
  });
});

// ---------------------------------------------------------------------------
// 2. Truncation
// ---------------------------------------------------------------------------
describe('formatReport truncation', () => {
  test('student line is cut at 300 chars with a trailing ellipsis', () => {
    const userMessage = 's'.repeat(STUDENT_MAX_CHARS) + 'ZTAIL';
    const text = formatReport(fullReport({ userMessage }));
    const line = text.split('\n')[1];
    assert.equal(line, `> **student:** ${'s'.repeat(STUDENT_MAX_CHARS)}…`);
    assert.ok(!line.includes('Z'));
  });

  test('merc line is cut at 600 chars with a trailing ellipsis', () => {
    const content = 'm'.repeat(MERC_MAX_CHARS) + 'ZTAIL';
    const text = formatReport(fullReport({ content }));
    const line = text.split('\n')[2];
    assert.equal(line, `> **merc:** ${'m'.repeat(MERC_MAX_CHARS)}…`);
    assert.ok(!line.includes('Z'));
  });

  test('text exactly at the cap is left alone (no ellipsis)', () => {
    const text = formatReport(fullReport({
      userMessage: 's'.repeat(STUDENT_MAX_CHARS),
      content: 'm'.repeat(MERC_MAX_CHARS),
    }));
    const [, student, merc] = text.split('\n');
    assert.equal(student, `> **student:** ${'s'.repeat(STUDENT_MAX_CHARS)}`);
    assert.equal(merc, `> **merc:** ${'m'.repeat(MERC_MAX_CHARS)}`);
  });

  test('a 10 000-char report stays well inside Discord\'s 2000-char limit', () => {
    const text = formatReport(fullReport({ content: 'x'.repeat(10_000), userMessage: 'y'.repeat(4000) }));
    assert.ok(text.length < 1900, `message is ${text.length} chars`);
  });

  test('exports the caps the contract promises', () => {
    assert.equal(STUDENT_MAX_CHARS, 300);
    assert.equal(MERC_MAX_CHARS, 600);
  });
});

// ---------------------------------------------------------------------------
// 3. Missing optional fields
// ---------------------------------------------------------------------------
describe('formatReport with missing optional fields', () => {
  test('the old-client shape { sessionId, content } renders with unspecified/?/? and no student line', () => {
    const text = formatReport({ sessionId: SESSION, content: 'a bad reply' });
    const lines = text.split('\n');
    assert.equal(lines.length, 2);
    assert.equal(lines[0], '🚩 Report: unspecified · session a1b2c3d4… · ?/? · ?');
    assert.equal(lines[1], '> **merc:** a bad reply');
    assert.ok(!text.includes('student'));
  });

  test('a null reason (the DB row default) reads as unspecified', () => {
    assert.ok(formatReport(fullReport({ reason: null })).startsWith('🚩 Report: unspecified · '));
    assert.ok(formatReport(fullReport({ reason: '' })).startsWith('🚩 Report: unspecified · '));
  });

  test('a partial context fills only the keys it has', () => {
    const text = formatReport(fullReport({ context: { surface: 'lesson' } }));
    assert.equal(text.split('\n')[0], '🚩 Report: harmful · session a1b2c3d4… · lesson/? · ?');
  });

  test('an empty or whitespace-only userMessage omits the student line', () => {
    for (const userMessage of ['', '   ', null, undefined]) {
      const text = formatReport(fullReport({ userMessage }));
      assert.equal(text.split('\n').length, 2, `userMessage=${JSON.stringify(userMessage)}`);
      assert.ok(!text.includes('**student:**'));
    }
  });

  test('a missing content still yields a merc line (never a crash)', () => {
    const text = formatReport({ sessionId: SESSION });
    assert.equal(text.split('\n')[1], '> **merc:** ');
  });

  test('garbage input (null / undefined / a string) still returns a string', () => {
    for (const junk of [null, undefined, 'nope', 42, []]) {
      const text = formatReport(junk);
      assert.equal(typeof text, 'string');
      assert.ok(text.startsWith('🚩 Report: unspecified · session ? · ?/? · ?'));
    }
  });
});

// ---------------------------------------------------------------------------
// 4. Session id never leaks
// ---------------------------------------------------------------------------
describe('session id handling', () => {
  test('only the first 8 chars are posted, followed by an ellipsis', async () => {
    const notify = fakeNotify(true);
    await notifyReport(fullReport(), { notify });
    const { text, key } = notify.calls[0];
    assert.ok(text.includes('session a1b2c3d4…'));
    assert.ok(!text.includes(SESSION), 'the full session id must never be posted');
    assert.ok(!text.includes(SESSION.slice(0, 9)), 'not even 9 chars of it');
    assert.ok(!key.includes(SESSION), 'nor go into the alert key');
  });

  test('a missing session id renders as ? rather than throwing', () => {
    assert.ok(formatReport({ content: 'x' }).includes('session ? ·'));
    assert.ok(formatReport({ sessionId: null, content: 'x' }).includes('session ? ·'));
  });
});

// ---------------------------------------------------------------------------
// 5. Failure paths never throw
// ---------------------------------------------------------------------------
describe('notifyReport swallows failures', () => {
  test('notify rejects → resolves false, logs at warn with the key, never throws', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    const notify = async () => { throw new Error('ECONNRESET'); };

    let result;
    await assert.doesNotReject(async () => { result = await notifyReport(fullReport(), { notify }); });
    assert.equal(result, false);
    assert.equal(warn.mock.callCount(), 1);
    const [fields, msg] = warn.mock.calls[0].arguments;
    assert.equal(fields.key, 'report:42');
    assert.equal(fields.err.message, 'ECONNRESET');
    assert.match(msg, /reportWebhook/);
  });

  test('notify throws synchronously → resolves false', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    const notify = () => { throw new TypeError('not today'); };
    assert.equal(await notifyReport(fullReport(), { notify }), false);
  });

  test('the report text is never passed to the logger on failure', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    const notify = async () => { throw new Error('boom'); };
    await notifyReport(fullReport({ content: 'SECRET-MERC-TEXT', userMessage: 'SECRET-STUDENT-TEXT' }), { notify });
    const serialized = JSON.stringify(warn.mock.calls.map((c) => c.arguments));
    assert.ok(!serialized.includes('SECRET-MERC-TEXT'));
    assert.ok(!serialized.includes('SECRET-STUDENT-TEXT'));
    assert.ok(!serialized.includes(SESSION));
  });

  test('a non-boolean answer from notify is coerced: only literal true counts as posted', async () => {
    assert.equal(await notifyReport(fullReport(), { notify: async () => undefined }), false);
    assert.equal(await notifyReport(fullReport(), { notify: async () => 'yes' }), false);
    assert.equal(await notifyReport(fullReport(), { notify: async () => true }), true);
  });

  test('a null report still resolves a boolean (formatter is null-safe)', async () => {
    const notify = fakeNotify(true);
    assert.equal(await notifyReport(null, { notify }), true);
    assert.match(notify.calls[0].key, /^report:\d+$/);
  });

  test('without an injected notify it falls back to lib/alerts, which no-ops to false when DISCORD_WEBHOOK_URL is unset', async (t) => {
    t.mock.method(logger, 'warn', () => {}); // alerts warns once about the unset URL
    const alerts = require('../lib/alerts');
    alerts.__resetForTest();
    const saved = process.env.DISCORD_WEBHOOK_URL;
    delete process.env.DISCORD_WEBHOOK_URL;
    try {
      assert.equal(await notifyReport(fullReport()), false);
    } finally {
      if (saved === undefined) delete process.env.DISCORD_WEBHOOK_URL;
      else process.env.DISCORD_WEBHOOK_URL = saved;
      alerts.__resetForTest();
    }
  });
});

// ---------------------------------------------------------------------------
// 6. Hardening
// ---------------------------------------------------------------------------
describe('formatReport hardening', () => {
  test('newlines in the quoted text are collapsed so the reply cannot leave the > block', () => {
    const text = formatReport(fullReport({
      content: 'line one\nline two\r\nline three',
      userMessage: 'q1\nq2',
    }));
    const lines = text.split('\n');
    assert.equal(lines.length, 3);
    assert.equal(lines[1], '> **student:** q1 q2');
    assert.equal(lines[2], '> **merc:** line one line two line three');
  });

  test('@everyone / @here / <@id> in student text cannot ping the channel', () => {
    const text = formatReport(fullReport({
      userMessage: 'hey @everyone and @here look <@123>',
      content: 'ok @EVERYONE',
    }));
    assert.ok(!text.includes('@everyone'));
    assert.ok(!text.includes('@here'));
    assert.ok(!text.includes('@EVERYONE'));
    assert.ok(!text.includes('<@123>'));
    assert.ok(text.includes('@​everyone'), 'defused with a zero-width space, not deleted');
  });

  test('a reports-table row (snake_case) formats the same as the request body', () => {
    const row = {
      id: 7,
      session_id: SESSION,
      reason: 'wrong',
      content: 'two plus two is five',
      user_message: 'what is 2+2',
      created_at: 1_700_000_000_000,
      surface: 'lesson',
      mode: 'debate',
      lesson_id: 'u2_l1',
      app_version: '2.3.0',
    };
    const text = formatReport(row);
    assert.equal(text.split('\n')[0], '🚩 Report: wrong · session a1b2c3d4… · lesson/debate · 2.3.0');
    assert.equal(text.split('\n')[1], '> **student:** what is 2+2');
    assert.equal(_alertKey(row), 'report:7');
  });

  test('context keys win over flat fallbacks when both are present', () => {
    const text = formatReport(fullReport({ surface: 'lesson', context: { surface: 'chat' } }));
    assert.ok(text.includes(' · chat/? · '));
  });
});
