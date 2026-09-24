'use strict';

// Tests for the report → Discord alert formatter/poster (lib/reportWebhook).
//
// Pure unit tests — `notify` is injected, so lib/alerts, the network and
// DISCORD_WEBHOOK_URL are never touched (one test wires the real lib/alerts
// with a fake fetch to prove the throttle). logger.warn is spied with the
// test runner's mock where a failure path is expected to log.
//
//   1. Payload shape — fixed key + 60 s throttle, header, counts line,
//      review pointer.
//   2. No content — the student's turn and the model's reply never appear,
//      whatever their length; only their character counts do.
//   3. Missing optional fields — id/reason/surface/mode/lessonId/appVersion
//      fall back to '?' / 'unspecified', counts read 0, null-safe.
//   4. Session id — only the first 8 chars are ever posted.
//   5. Failure paths — notify rejects / throws sync / returns non-boolean →
//      resolves false, never throws, warn carries the key but not the text.
//   6. Hardening — newlines cannot break the line, mentions are defused,
//      snake_case rows are accepted; a burst collapses under lib/alerts.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const logger = require('../lib/logger');
const {
  notifyReport,
  formatReport,
  ALERT_KEY,
  REPORT_THROTTLE_MS,
  REVIEW_HINT,
} = require('../lib/reportWebhook');

const SESSION = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
const STUDENT_TEXT = 'how do I get into the school wifi';
const MERC_TEXT = 'Sure, here is how to get into the school wifi.';

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
    content: MERC_TEXT,
    userMessage: STUDENT_TEXT,
    context: { surface: 'chat', mode: 'socratic', lessonId: 'u1_l3', appVersion: '2.3.0' },
    ...overrides,
  };
}

const HEADER = '🚩 Report #42: harmful · chat/socratic · lesson u1_l3 · 2.3.0 · session a1b2c3d4…';

// ---------------------------------------------------------------------------
// 1. Payload shape
// ---------------------------------------------------------------------------
describe('notifyReport payload shape', () => {
  test('posts once under the fixed key with a 60 s throttle: header, counts line, review pointer', async () => {
    const notify = fakeNotify(true);

    const posted = await notifyReport(fullReport(), { notify });

    assert.equal(posted, true);
    assert.equal(notify.calls.length, 1);
    const { key, text, opts } = notify.calls[0];
    assert.equal(key, 'report');
    assert.equal(key, ALERT_KEY);
    assert.deepEqual(opts, { throttleMs: 60_000 });
    assert.equal(REPORT_THROTTLE_MS, 60_000);

    const lines = text.split('\n');
    assert.equal(lines.length, 3);
    assert.equal(lines[0], HEADER);
    assert.equal(lines[1], `student ${STUDENT_TEXT.length} chars · merc ${MERC_TEXT.length} chars`);
    assert.equal(lines[2], 'Review: GET /api/admin/reports?unresolved=1');
    assert.equal(lines[2], REVIEW_HINT);
  });

  test('formatReport returns exactly the text notifyReport posts', async () => {
    const notify = fakeNotify(true);
    const report = fullReport();
    await notifyReport(report, { notify });
    assert.equal(notify.calls[0].text, formatReport(report));
  });

  test('every enum reason renders verbatim in the header', () => {
    for (const reason of ['wrong', 'harmful', 'off_topic', 'other']) {
      assert.ok(formatReport(fullReport({ reason })).startsWith(`🚩 Report #42: ${reason} · `));
    }
  });

  test('the key never varies per report, so a burst shares one throttle clock', async () => {
    const notify = fakeNotify(true);
    await notifyReport(fullReport({ id: 1 }), { notify });
    await notifyReport(fullReport({ id: 2, ts: 5 }), { notify });
    await notifyReport({}, { notify });
    assert.deepEqual(notify.calls.map((c) => c.key), ['report', 'report', 'report']);
  });

  test('resolves whatever boolean notify answers (false when Discord did not take it)', async () => {
    assert.equal(await notifyReport(fullReport(), { notify: fakeNotify(false) }), false);
    assert.equal(await notifyReport(fullReport(), { notify: fakeNotify(true) }), true);
  });
});

// ---------------------------------------------------------------------------
// 2. No content leaves the server
// ---------------------------------------------------------------------------
describe('formatReport carries no student or model text', () => {
  test('the student turn and the model reply are absent; only their lengths are posted', () => {
    const text = formatReport(fullReport({ userMessage: 'SECRET-STUDENT-TEXT', content: 'SECRET-MERC-TEXT-LONGER' }));
    assert.ok(!text.includes('SECRET'));
    assert.ok(!text.includes('wifi'));
    assert.match(text, /^student 19 chars · merc 23 chars$/m);
  });

  test('no fragment of a long reply appears, and the message stays tiny', () => {
    const content = Array.from({ length: 400 }, (_, i) => `token${i}`).join(' ');
    const userMessage = Array.from({ length: 200 }, (_, i) => `word${i}`).join(' ');
    const text = formatReport(fullReport({ content, userMessage }));
    assert.ok(!text.includes('token'));
    assert.ok(!text.includes('word'));
    assert.match(text, new RegExp(`student ${userMessage.length} chars · merc ${content.length} chars`));
    assert.ok(text.length < 300, `message is ${text.length} chars`);
  });

  test('a 10 000-char report stays well inside Discord\'s 2000-char limit', () => {
    const text = formatReport(fullReport({ content: 'x'.repeat(10_000), userMessage: 'y'.repeat(4000) }));
    assert.ok(text.length < 300, `message is ${text.length} chars`);
    assert.match(text, /student 4000 chars · merc 10000 chars/);
  });

  test('non-string content counts as 0 chars rather than being stringified', () => {
    const text = formatReport(fullReport({ content: { nested: 'SECRET' }, userMessage: 12345 }));
    assert.ok(!text.includes('SECRET'));
    assert.match(text, /student 0 chars · merc 0 chars/);
  });
});

// ---------------------------------------------------------------------------
// 3. Missing optional fields
// ---------------------------------------------------------------------------
describe('formatReport with missing optional fields', () => {
  test('the old-client shape { sessionId, content } renders with ?/unspecified and a 0-char student', () => {
    const text = formatReport({ sessionId: SESSION, content: 'a bad reply' });
    const lines = text.split('\n');
    assert.equal(lines.length, 3);
    assert.equal(lines[0], '🚩 Report #?: unspecified · ?/? · lesson ? · ? · session a1b2c3d4…');
    assert.equal(lines[1], 'student 0 chars · merc 11 chars');
    assert.equal(lines[2], REVIEW_HINT);
  });

  test('a null reason (the DB row default) reads as unspecified', () => {
    assert.ok(formatReport(fullReport({ reason: null })).startsWith('🚩 Report #42: unspecified · '));
    assert.ok(formatReport(fullReport({ reason: '' })).startsWith('🚩 Report #42: unspecified · '));
  });

  test('a partial context fills only the keys it has', () => {
    const text = formatReport(fullReport({ context: { surface: 'lesson' } }));
    assert.equal(text.split('\n')[0], '🚩 Report #42: harmful · lesson/? · lesson ? · ? · session a1b2c3d4…');
  });

  test('id 0 is a real id; a missing id is ?', () => {
    assert.ok(formatReport(fullReport({ id: 0 })).startsWith('🚩 Report #0: '));
    assert.ok(formatReport(fullReport({ id: undefined })).startsWith('🚩 Report #?: '));
    assert.ok(formatReport(fullReport({ id: null })).startsWith('🚩 Report #?: '));
  });

  test('garbage input (null / undefined / a string) still returns the three lines', () => {
    for (const junk of [null, undefined, 'nope', 42, []]) {
      const text = formatReport(junk);
      assert.equal(typeof text, 'string');
      assert.equal(text.split('\n')[0], '🚩 Report #?: unspecified · ?/? · lesson ? · ? · session ?');
      assert.equal(text.split('\n')[1], 'student 0 chars · merc 0 chars');
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
    assert.ok(formatReport({ content: 'x' }).includes('session ?'));
    assert.ok(formatReport({ sessionId: null, content: 'x' }).includes('session ?'));
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
    assert.equal(fields.key, 'report');
    assert.equal(fields.err.message, 'ECONNRESET');
    assert.match(msg, /reportWebhook/);
  });

  test('notify throws synchronously → resolves false', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    const notify = () => { throw new TypeError('not today'); };
    assert.equal(await notifyReport(fullReport(), { notify }), false);
  });

  test('the report is never passed to the logger on failure', async (t) => {
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
    assert.equal(notify.calls[0].key, 'report');
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
  test('newlines in the posted metadata are collapsed so a field cannot add lines', () => {
    const text = formatReport(fullReport({
      reason: 'wrong\nline',
      context: { surface: 'chat\r\nx', mode: 'so\ncratic', lessonId: 'u1\n_l3', appVersion: '2.3\n.0' },
    }));
    const lines = text.split('\n');
    assert.equal(lines.length, 3);
    assert.equal(lines[0], '🚩 Report #42: wrong line · chat x/so cratic · lesson u1 _l3 · 2.3 .0 · session a1b2c3d4…');
  });

  test('@everyone / @here / <@id> in posted fields cannot ping the channel', () => {
    const text = formatReport(fullReport({
      reason: 'hey @everyone',
      context: { surface: '@here', mode: '<@123>', lessonId: '@EVERYONE', appVersion: '@Here' },
    }));
    assert.ok(!text.includes('@everyone'));
    assert.ok(!text.includes('@here'));
    assert.ok(!text.includes('@EVERYONE'));
    assert.ok(!text.includes('@Here'));
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
    assert.equal(text.split('\n')[0], '🚩 Report #7: wrong · lesson/debate · lesson u2_l1 · 2.3.0 · session a1b2c3d4…');
    assert.equal(text.split('\n')[1], 'student 11 chars · merc 20 chars');
    assert.ok(!text.includes('2+2'));
    assert.ok(!text.includes('five'));
  });

  test('context keys win over flat fallbacks when both are present', () => {
    const text = formatReport(fullReport({ surface: 'lesson', context: { surface: 'chat' } }));
    assert.ok(text.includes(' · chat/? · '));
  });

  test('through the real lib/alerts, a burst inside 60 s becomes one Discord post', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    const alerts = require('../lib/alerts');
    alerts.__resetForTest();
    let clock = 1_700_000_000_000;
    const posts = [];
    alerts.configure({
      webhookUrl: 'https://discord.example/webhook',
      now: () => clock,
      fetch: async (_url, init) => { posts.push(JSON.parse(init.body).content); return { ok: true, status: 204 }; },
    });
    try {
      assert.equal(await notifyReport(fullReport({ id: 1 })), true);
      assert.equal(await notifyReport(fullReport({ id: 2 })), false, 'collapsed');
      clock += 59_000;
      assert.equal(await notifyReport(fullReport({ id: 3 })), false, 'still inside the window');
      clock += 1_000;
      assert.equal(await notifyReport(fullReport({ id: 4 })), true, 'the next window posts again');
      assert.equal(posts.length, 2);
      assert.ok(posts[0].startsWith('🚩 Report #1:'));
      assert.ok(posts[1].startsWith('🚩 Report #4:'));
      assert.ok(posts.every((p) => !p.includes('wifi')), 'no content in any post');
    } finally {
      alerts.__resetForTest();
    }
  });
});
