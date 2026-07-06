'use strict';

// ---------------------------------------------------------------------------
// Curriculum lesson completion marker
// ---------------------------------------------------------------------------
// In curriculum mode the model is instructed (CURRICULUM_PROMPT) to emit a
// `[LESSON_COMPLETE]` marker on its own final line ONLY when the student has
// demonstrated proficiency. The marker is stripped before any client sees it:
// `processLessonOutcome` strips the marker from the reply (it must never reach
// any client) and reports a `lessonComplete` flag the iOS client uses to mark
// the lesson complete.
//
// The marker is END-ANCHORED on purpose: a `[LESSON_COMPLETE]` that appears
// mid-reply (e.g. the model quoting these very instructions) is NOT a
// completion signal and is left untouched.

// Matches ONE OR MORE trailing markers (a model slip could emit it twice) plus
// surrounding whitespace, anchored to end-of-string — so a doubled marker can't
// leave a literal `[LESSON_COMPLETE]` behind in the reply.
const LESSON_COMPLETE_RE = /(?:\n?\s*\[LESSON_COMPLETE\]\s*)+$/;

// Defense-in-depth: the curriculum prompt only uses [LESSON_COMPLETE], but a
// model slip (or a stale prompt) could emit the legacy test sentinels. Scrub a
// trailing [TEST_PASSED]/[TEST_FAILED] too so no control token ever reaches a
// client — regardless of which client connects. Stripping these does NOT flag
// completion; completion stays gated on [LESSON_COMPLETE] alone.
const TEST_TOKEN_RE = /(?:\n?\s*\[TEST_(?:PASSED|FAILED)\]\s*)+$/;

/**
 * @param {string} reply Raw model reply.
 * @returns {{ reply: string, lessonComplete: boolean }}
 */
function processLessonOutcome(reply) {
  if (typeof reply !== 'string') {
    return { reply, lessonComplete: false };
  }
  const lessonComplete = LESSON_COMPLETE_RE.test(reply);
  const hasTestToken = TEST_TOKEN_RE.test(reply);
  // Fast path: nothing to scrub or flag — return the reply untouched.
  if (!lessonComplete && !hasTestToken) {
    return { reply, lessonComplete: false };
  }
  const stripped = reply
    .replace(LESSON_COMPLETE_RE, '')
    .replace(TEST_TOKEN_RE, '')
    .trimEnd();
  return {
    // Degenerate case: the reply was ONLY marker(s). Never return or persist an
    // empty assistant turn — fall back to a short, mode-appropriate line.
    reply: stripped.length > 0 ? stripped : (lessonComplete ? 'Lesson complete — nice work.' : 'Got it.'),
    lessonComplete,
  };
}

module.exports = { processLessonOutcome };
