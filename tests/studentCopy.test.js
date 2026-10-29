'use strict';

/**
 * Words the server sends that a student can read, checked against what the
 * server actually does (overnight round 4).
 *
 * Who reads which text, so a change here is a change on their screen:
 *   - iOS 2.0.0 and 2.3.0, and the Mac app: the text of an SSE error frame on
 *     /api/chat, as written, with a Retry button (for daily_limit frames
 *     2.3.0 swaps the "tomorrow" sentence for a local clock time). On JSON
 *     routes they show the server's `message` only for a daily_limit 429 or
 *     a 503, and their own copy for everything else.
 *   - The web widget: `error` of a frame and `message` of a JSON body,
 *     everywhere.
 *
 *   1. A student never signs up (the app's own privacy screen says "There's
 *      no sign-up."), so the network's new-device allowance doesn't say
 *      "sign-ups".
 *   2. Lesson turns and chat turns are separate allowances: when one is used
 *      up the other still works, so neither says Mercurius is closed until
 *      tomorrow.
 *   (The spend cap's copy, Mercurius's own limit, is pinned in
 *   spendCap.test.js.)
 */

const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';

const quotas = require('../lib/quotas');

const IP = '10.9.9.9';

describe('daily-limit copy says what is really used up', () => {
  beforeEach(() => quotas.__resetForTest());

  test('the new-device allowance never talks about sign-ups', () => {
    quotas.configure({ IP_DAILY_NEW_SESSIONS: 0 });
    const r = quotas.noteNewSession(IP);
    assert.equal(r.ok, false);
    assert.equal(r.error, 'daily_limit');
    assert.equal(r.scope, 'ip');
    assert.doesNotMatch(r.message, /sign[- ]?ups?/i, 'students never sign up');
    assert.equal(r.message, "This network has reached today's limit for new devices. Switch to cellular data, or try again tomorrow.");
  });

  test('used-up lesson turns: free chat still works, so the copy does not close Mercurius', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 0 });
    const lesson = quotas.check({ sessionId: 's1', ip: IP, kind: 'lesson' });
    assert.equal(lesson.ok, false);
    assert.equal(lesson.reason, 'lesson_turns');
    assert.equal(quotas.check({ sessionId: 's1', ip: IP, kind: 'chat' }).ok, true, 'chat is a separate allowance');
    assert.doesNotMatch(lesson.message, /Mercurius will be ready/);
    assert.equal(lesson.message, "You've used today's lesson turns. Lessons come back tomorrow.");
  });

  test('used-up chat turns: lessons still work, so the copy does not close Mercurius', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 0 });
    const chat = quotas.check({ sessionId: 's2', ip: IP, kind: 'chat' });
    assert.equal(chat.ok, false);
    assert.equal(chat.reason, 'chat_turns');
    assert.equal(quotas.check({ sessionId: 's2', ip: IP, kind: 'lesson' }).ok, true, 'lessons are a separate allowance');
    assert.doesNotMatch(chat.message, /Mercurius will be ready/);
    assert.equal(chat.message, "You've used today's chat turns. Chat comes back tomorrow.");
  });

  test("the student's dollar allowance covers everything, so it still says Mercurius is back tomorrow", () => {
    quotas.configure({ SESSION_DAILY_USD: 0 });
    for (const kind of ['lesson', 'chat', 'image']) {
      const r = quotas.check({ sessionId: 's3', ip: IP, kind });
      assert.equal(r.reason, 'session_usd', kind);
      assert.equal(r.message, "You've reached today's usage limit. Mercurius will be ready again tomorrow.");
    }
  });
});
