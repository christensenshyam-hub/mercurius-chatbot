'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const { processLessonOutcome } = require('../lib/lessonOutcome');

describe('processLessonOutcome', () => {
  test('a reply with no marker is returned unchanged, not complete', () => {
    const out = processLessonOutcome('Nice work so far. Try one more example.');
    assert.equal(out.reply, 'Nice work so far. Try one more example.');
    assert.equal(out.lessonComplete, false);
  });

  test('an end-anchored marker on its own line is stripped and flags complete', () => {
    const out = processLessonOutcome('Excellent — you nailed it.\n[LESSON_COMPLETE]');
    assert.equal(out.reply, 'Excellent — you nailed it.');
    assert.equal(out.lessonComplete, true);
  });

  test('trailing whitespace/newlines after the marker are tolerated', () => {
    const out = processLessonOutcome('Great job.\n\n[LESSON_COMPLETE]   \n');
    assert.equal(out.reply, 'Great job.');
    assert.equal(out.lessonComplete, true);
  });

  test('a marker NOT at the end (e.g. quoted mid-reply) is left untouched', () => {
    const reply = 'You should never write [LESSON_COMPLETE] yourself. Keep going.';
    const out = processLessonOutcome(reply);
    assert.equal(out.reply, reply);
    assert.equal(out.lessonComplete, false);
  });

  test('the marker never leaks into the cleaned reply', () => {
    const out = processLessonOutcome('All set.\n[LESSON_COMPLETE]');
    assert.ok(!out.reply.includes('[LESSON_COMPLETE]'));
  });

  test('non-string input is handled safely', () => {
    const out = processLessonOutcome(undefined);
    assert.equal(out.reply, undefined);
    assert.equal(out.lessonComplete, false);
  });

  test('a doubled trailing marker is fully stripped — no literal token leaks', () => {
    const out = processLessonOutcome('Great work.\n[LESSON_COMPLETE]\n[LESSON_COMPLETE]');
    assert.equal(out.reply, 'Great work.');
    assert.equal(out.lessonComplete, true);
    assert.ok(!out.reply.includes('[LESSON_COMPLETE]'));
  });

  test('a marker-only reply falls back to a non-empty confirmation', () => {
    const out = processLessonOutcome('[LESSON_COMPLETE]');
    assert.equal(out.lessonComplete, true);
    assert.ok(out.reply.length > 0);
    assert.ok(!out.reply.includes('[LESSON_COMPLETE]'));
  });

  test('a marker glued directly to the text (no separator) is still stripped', () => {
    const out = processLessonOutcome('All done.[LESSON_COMPLETE]');
    assert.equal(out.reply, 'All done.');
    assert.equal(out.lessonComplete, true);
  });

  test('CRLF line endings around the marker are handled', () => {
    const out = processLessonOutcome('Done.\r\n[LESSON_COMPLETE]\r\n');
    assert.equal(out.reply, 'Done.');
    assert.equal(out.lessonComplete, true);
  });

  // Defense-in-depth: legacy [TEST_PASSED]/[TEST_FAILED] sentinels are scrubbed
  // even though the curriculum prompt never instructs them — a model slip must
  // not leak a control token to any client. Stripping does NOT flag completion.
  test('a trailing [TEST_PASSED] is stripped but does NOT flag completion', () => {
    const out = processLessonOutcome('Strong defense of your reasoning.\n[TEST_PASSED]');
    assert.equal(out.reply, 'Strong defense of your reasoning.');
    assert.equal(out.lessonComplete, false);
    assert.ok(!out.reply.includes('[TEST_PASSED]'));
  });

  test('a trailing [TEST_FAILED] is stripped and not flagged complete', () => {
    const out = processLessonOutcome('Not quite — reconsider the assumption.\n[TEST_FAILED]');
    assert.equal(out.reply, 'Not quite — reconsider the assumption.');
    assert.equal(out.lessonComplete, false);
    assert.ok(!out.reply.includes('[TEST_FAILED]'));
  });

  test('a [LESSON_COMPLETE] plus a stray test token are both scrubbed', () => {
    const out = processLessonOutcome('Mastered it.\n[TEST_PASSED]\n[LESSON_COMPLETE]');
    assert.equal(out.lessonComplete, true);
    assert.ok(!out.reply.includes('[TEST_PASSED]'));
    assert.ok(!out.reply.includes('[LESSON_COMPLETE]'));
    assert.equal(out.reply, 'Mastered it.');
  });

  test('a mid-reply [TEST_PASSED] (quoted) is left untouched', () => {
    const reply = 'The system emits [TEST_PASSED] for you — never type it yourself.';
    const out = processLessonOutcome(reply);
    assert.equal(out.reply, reply);
    assert.equal(out.lessonComplete, false);
  });
});
