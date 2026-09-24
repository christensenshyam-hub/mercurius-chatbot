'use strict';

/**
 * curriculumTag — helpers around the hidden lesson opener the iOS client
 * re-sends as a wire prefix.
 *
 * Every curriculum lesson starter in ios/.../Curriculum.swift begins with a
 * tag of the form
 *
 *   [CURRICULUM: Unit 1, Lesson 3] Teach me about …
 *   [CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive …
 *   [CURRICULUM: Unit 5, Lesson 4 - Final Review] Have me build …
 *
 * and the server (server.js) routes a request into curriculum mode when ANY
 * user message on the wire starts with `[CURRICULUM:`. The client keeps the
 * opener as a hidden wire prefix (ChatViewModel.lessonWirePrefix) — it is
 * inserted at index 0 of every lesson request but never shown in the thread.
 *
 * The wrinkle this module exists for: as a legacy-server bridge the client
 * ALSO re-tags the LAST user turn on the wire — `tag + " " + content`, where
 * `tag` is the opener's text from `[` through the first `]`. That re-tag is
 * wire-only, so the very same message arrives UNTAGGED on the next turn (it
 * is now a middle turn, and the new last turn carries the tag instead). A
 * replayed lesson thread is therefore not byte-stable from one request to the
 * next unless it is normalized, and byte-stability is what prompt caching
 * needs. `normalizeReplayedHistory` is that normalization: it strips the tag
 * from every user message EXCEPT index 0, so the opener (which the model needs
 * for lesson context) keeps its tag and every later turn is the student's
 * literal text — identical bytes whichever turn it is replayed on.
 *
 * Two levels of "carries a tag", on purpose:
 *   - LOOSE  — the text starts with the literal `[CURRICULUM:`. This is the
 *              server's current routing rule and what `isCurriculumThread`
 *              and `stripCurriculumTag` use, so a lesson whose tag is oddly
 *              formed still routes (and still normalizes) as a lesson.
 *   - STRICT — the tag also names `Unit N` and `Lesson k` and closes with `]`.
 *              This is what `parseCurriculumTag` / `lessonIdFromMessages`
 *              need, since they have to yield numbers. A thread can be a
 *              curriculum thread (loose) with no lesson id (strict fails) —
 *              callers should treat that as "lesson, unknown id".
 * Both are case-sensitive (`[CURRICULUM:`, `Unit`, `Lesson`), matching
 * server.js's startsWith check and the only producer (Curriculum.swift). The
 * tag must be at index 0 of the text — no leading whitespace, no mid-text
 * matches — again mirroring the server rule. Punctuation and spacing INSIDE
 * the tag are tolerant: `Unit 1, Lesson 3`, `Unit 01 · Lesson 3`,
 * `Unit1-Lesson3`, and anything after the lesson number up to `]` (the
 * ` - Review` suffix) is ignored.
 *
 * Contract:
 *   - CURRICULUM_TAG_PREFIX     → the literal '[CURRICULUM:'.
 *   - hasCurriculumPrefix(text) → LOOSE check: string starting with the
 *                                 literal prefix. false for non-strings.
 *   - parseCurriculumTag(text)  → STRICT parse of a tag at the very start of
 *                                 `text`: { unit, lesson, raw } — `unit` and
 *                                 `lesson` are positive integers (zero padding
 *                                 dropped), `raw` is the tag exactly as it
 *                                 appeared, `[` through `]` inclusive. null
 *                                 when there is no well-formed tag at index 0
 *                                 (including non-string input).
 *   - lessonId(unit, lesson)    → 'u{unit}_l{lesson}', the Curriculum.swift
 *                                 lesson id convention (u1_l1 … u8_l5).
 *   - lessonIdFromMessages(messages)
 *                               → lessonId of the FIRST user message whose
 *                                 string content parses (strict), else null.
 *   - isCurriculumThread(messages)
 *                               → true when ANY user message has string
 *                                 content carrying the LOOSE prefix — the
 *                                 current server routing rule, verbatim.
 *   - stripCurriculumTag(text)  → `text` with one leading LOOSE tag (the
 *                                 prefix through the first `]`) removed and
 *                                 the remainder trimStart()ed. Returned as-is
 *                                 when there is no tag, no closing `]`, or the
 *                                 input is not a string. Strips ONE tag only —
 *                                 the client never double-tags.
 *   - normalizeReplayedHistory(messages)
 *                               → a NEW array in which every user message at
 *                                 index > 0 carrying the SAME leading tag as
 *                                 the index-0 opener has that tag stripped (a
 *                                 new object, other fields preserved). Only
 *                                 the iOS bridge's re-tag is ever removed: a
 *                                 DIFFERENT tag on a later turn is a genuine
 *                                 opener (the club widget starting Lesson 2
 *                                 in a thread that already held Lesson 1)
 *                                 and survives, because CURRICULUM_PROMPT
 *                                 follows the most recent tag. When index 0
 *                                 carries no tag nothing is stripped. Index
 *                                 0, assistant messages, and non-string
 *                                 (multimodal array) content pass through
 *                                 unchanged — same references, input never
 *                                 mutated. A non-array input yields [].
 *
 * Note for callers: stripping the re-tag off an image-only turn (the client
 * sends `tag + " "` + "") yields "" — that IS the student's original content;
 * the existing empty-content handling in the chat route still applies.
 */

const CURRICULUM_TAG_PREFIX = '[CURRICULUM:';

// Strict shape. Anchored at index 0; the keyword tokens are case-sensitive;
// whitespace and the separator between the unit and lesson clauses are loose;
// anything after the lesson number up to the closing bracket is ignored.
const TAG_RE = /^\[CURRICULUM:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]/;

function hasCurriculumPrefix(text) {
  return typeof text === 'string' && text.startsWith(CURRICULUM_TAG_PREFIX);
}

function parseCurriculumTag(text) {
  if (!hasCurriculumPrefix(text)) return null;
  const m = TAG_RE.exec(text);
  if (!m) return null;
  const unit = Number(m[1]);
  const lesson = Number(m[2]);
  if (!Number.isInteger(unit) || !Number.isInteger(lesson) || unit < 1 || lesson < 1) return null;
  return { unit, lesson, raw: m[0] };
}

function lessonId(unit, lesson) {
  return `u${unit}_l${lesson}`;
}

function isUserMessage(m) {
  return !!m && m.role === 'user';
}

function lessonIdFromMessages(messages) {
  if (!Array.isArray(messages)) return null;
  for (const m of messages) {
    if (!isUserMessage(m)) continue;
    const tag = parseCurriculumTag(m.content);
    if (tag) return lessonId(tag.unit, tag.lesson);
  }
  return null;
}

function isCurriculumThread(messages) {
  if (!Array.isArray(messages)) return false;
  return messages.some((m) => isUserMessage(m) && hasCurriculumPrefix(m.content));
}

function stripCurriculumTag(text) {
  if (!hasCurriculumPrefix(text)) return text;
  const close = text.indexOf(']');
  if (close === -1) return text;
  return text.slice(close + 1).trimStart();
}

// The tag text from `[` through the first `]`, or null when there is none.
function leadingTag(text) {
  if (!hasCurriculumPrefix(text)) return null;
  const close = text.indexOf(']');
  return close === -1 ? null : text.slice(0, close + 1);
}

function normalizeReplayedHistory(messages) {
  if (!Array.isArray(messages)) return [];
  const first = messages[0];
  const openerTag = first && isUserMessage(first) && typeof first.content === 'string'
    ? leadingTag(first.content)
    : null;
  if (!openerTag) return messages.slice();
  return messages.map((m, i) => {
    if (i === 0 || !isUserMessage(m) || typeof m.content !== 'string') return m;
    if (leadingTag(m.content) !== openerTag) return m;
    const stripped = stripCurriculumTag(m.content);
    if (stripped === m.content) return m;
    return { ...m, content: stripped };
  });
}

module.exports = {
  CURRICULUM_TAG_PREFIX,
  hasCurriculumPrefix,
  parseCurriculumTag,
  lessonId,
  lessonIdFromMessages,
  isCurriculumThread,
  stripCurriculumTag,
  normalizeReplayedHistory,
};
