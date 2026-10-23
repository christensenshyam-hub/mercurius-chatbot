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
 *
 * ── The Basics track (2026-10) ──────────────────────────────────────────────
 * A second, separate course for adult beginners ("Basics", next to the
 * 8-unit "Deep dive" above). Its openers carry their own tag, so a Basics
 * lesson can never fall into the Deep-dive guide (CURRICULUM_PROMPT) and a
 * Deep-dive lesson can never fall into the Basics guide (lib/basicsGuide):
 *
 *   [BASICS: Unit 1, Lesson 1] Teach me what an AI chatbot is, …   (canonical)
 *   [CURRICULUM: Basics Unit 1, Lesson 1] Teach me …               (alias)
 *
 * The alias is the form the Basics curriculum draft (basics.json) wrote. It
 * starts with `[CURRICULUM:`, so the LOOSE Deep-dive check above matches it,
 * but the STRICT Deep-dive TAG_RE does not (it wants `Unit` straight after
 * the colon), so it never yields a `u` id; this module classifies it as
 * Basics. New clients should send the canonical `[BASICS:` form: a server
 * that predates Basics routes it to free chat, never to the Deep dive.
 * Same tolerance rules as the Deep-dive tag: index 0, case-sensitive
 * keywords, loose separators, anything after the lesson number ignored.
 * Basics lesson ids are `b{unit}_l{lesson}` (b1_l1 … b5_l4).
 *
 * Contract (additive; every export above is unchanged):
 *   - BASICS_TAG_PREFIX         → the literal '[BASICS:'.
 *   - hasBasicsPrefix(text)     → LOOSE: starts with '[BASICS:' or with the
 *                                 alias '[CURRICULUM: Basics'. false for
 *                                 non-strings.
 *   - tagTrack(text)            → 'basics' | 'deep' | null for ONE text, by
 *                                 the LOOSE checks (Basics first, so the
 *                                 alias is Basics).
 *   - parseBasicsTag(text)      → STRICT parse of either Basics form at index
 *                                 0: { unit, lesson, raw }, else null.
 *   - basicsLessonId(unit, lesson) → 'b{unit}_l{lesson}'.
 *   - lessonTrack(messages)     → the track of the MOST RECENT user message
 *                                 (string content) that carries a LOOSE tag of
 *                                 either track, else null. iOS re-tags the
 *                                 last turn with its own opener's tag, so the
 *                                 latest tag is the lesson in progress; a
 *                                 widget thread that opens a new lesson after
 *                                 an old one follows the new one. Truthy
 *                                 exactly when some user message carries a
 *                                 loose tag, so for a thread with no Basics
 *                                 tag it is 'deep' exactly when
 *                                 isCurriculumThread is true.
 *   - lessonMetaFromMessages(messages, track)
 *                               → { track, unit, lesson, lessonId } from the
 *                                 FIRST user message whose STRICT parse
 *                                 matches `track` ('deep' → parseCurriculumTag
 *                                 + lessonId, exactly what lessonIdFromMessages
 *                                 reads; 'basics' → parseBasicsTag +
 *                                 basicsLessonId). unit/lesson/lessonId are
 *                                 null when no message parses strictly (a
 *                                 lesson with an unknown id). null for an
 *                                 unknown track.
 *   - stripLessonTag(text)      → stripCurriculumTag for either track's LOOSE
 *                                 prefix.
 *   normalizeReplayedHistory treats a Basics opener exactly like a Deep-dive
 *   one: the iOS bridge's re-tag (the SAME tag as index 0) is stripped from
 *   every later user turn. For threads with no Basics tag it is unchanged.
 */

const CURRICULUM_TAG_PREFIX = '[CURRICULUM:';
const BASICS_TAG_PREFIX = '[BASICS:';
const BASICS_ALIAS_RE = /^\[CURRICULUM:\s*Basics\b/;

// Strict shape. Anchored at index 0; the keyword tokens are case-sensitive;
// whitespace and the separator between the unit and lesson clauses are loose;
// anything after the lesson number up to the closing bracket is ignored.
const TAG_RE = /^\[CURRICULUM:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]/;
// The two Basics forms, same tolerance as TAG_RE.
const BASICS_TAG_RE = /^\[BASICS:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]/;
const BASICS_ALIAS_TAG_RE = /^\[CURRICULUM:\s*Basics\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]/;

function hasCurriculumPrefix(text) {
  return typeof text === 'string' && text.startsWith(CURRICULUM_TAG_PREFIX);
}

function hasBasicsPrefix(text) {
  return typeof text === 'string' && (text.startsWith(BASICS_TAG_PREFIX) || BASICS_ALIAS_RE.test(text));
}

function tagTrack(text) {
  if (hasBasicsPrefix(text)) return 'basics';
  if (hasCurriculumPrefix(text)) return 'deep';
  return null;
}

function unitLesson(m) {
  if (!m) return null;
  const unit = Number(m[1]);
  const lesson = Number(m[2]);
  if (!Number.isInteger(unit) || !Number.isInteger(lesson) || unit < 1 || lesson < 1) return null;
  return { unit, lesson, raw: m[0] };
}

function parseCurriculumTag(text) {
  if (!hasCurriculumPrefix(text)) return null;
  return unitLesson(TAG_RE.exec(text));
}

function parseBasicsTag(text) {
  if (!hasBasicsPrefix(text)) return null;
  return unitLesson(BASICS_TAG_RE.exec(text) || BASICS_ALIAS_TAG_RE.exec(text));
}

function lessonId(unit, lesson) {
  return `u${unit}_l${lesson}`;
}

function basicsLessonId(unit, lesson) {
  return `b${unit}_l${lesson}`;
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

function lessonTrack(messages) {
  if (!Array.isArray(messages)) return null;
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (!isUserMessage(m)) continue;
    const track = tagTrack(m.content);
    if (track) return track;
  }
  return null;
}

const TRACK_PARSERS = {
  deep: { parse: parseCurriculumTag, id: lessonId },
  basics: { parse: parseBasicsTag, id: basicsLessonId },
};

function lessonMetaFromMessages(messages, track) {
  const p = TRACK_PARSERS[track];
  if (!p) return null;
  const list = Array.isArray(messages) ? messages : [];
  for (const m of list) {
    if (!isUserMessage(m)) continue;
    // A Basics alias never parses as Deep dive (TAG_RE), and a Deep-dive
    // tag never parses as Basics, so each track only ever sees its own ids.
    const tag = p.parse(m.content);
    if (tag) return { track, unit: tag.unit, lesson: tag.lesson, lessonId: p.id(tag.unit, tag.lesson) };
  }
  return { track, unit: null, lesson: null, lessonId: null };
}

function stripCurriculumTag(text) {
  if (!hasCurriculumPrefix(text)) return text;
  const close = text.indexOf(']');
  if (close === -1) return text;
  return text.slice(close + 1).trimStart();
}

// The alias starts with '[CURRICULUM:', so stripCurriculumTag covers it; the
// canonical Basics prefix needs the same treatment.
function stripLessonTag(text) {
  if (!tagTrack(text)) return text;
  const close = text.indexOf(']');
  if (close === -1) return text;
  return text.slice(close + 1).trimStart();
}

// The tag text from `[` through the first `]` (either track), or null.
function leadingTag(text) {
  if (!tagTrack(text)) return null;
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
    const stripped = stripLessonTag(m.content);
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
  // Basics track
  BASICS_TAG_PREFIX,
  hasBasicsPrefix,
  tagTrack,
  parseBasicsTag,
  basicsLessonId,
  lessonTrack,
  lessonMetaFromMessages,
  stripLessonTag,
};
