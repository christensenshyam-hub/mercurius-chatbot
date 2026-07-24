'use strict';

/**
 * blockMarkup — the blocks_v1 semantic-markup contract (Presentation P4).
 *
 * Capable clients (request `capabilities` includes "blocks_v1") receive
 * replies whose key content is wrapped in a tiny, line-oriented marker
 * vocabulary that the app renders as NATIVE UI instead of prose:
 *
 *   [KEY]one-sentence takeaway[/KEY]        → key-idea card   (≤1 per reply)
 *   [EX]the concrete example[/EX]           → example card    (≤1 per reply)
 *   [Q]                                     → tappable multiple-choice check
 *   <stem, 1–2 lines>
 *   A) <option>
 *   B) <option>          (2–4 options, lines matching /^[A-D]\) /)
 *   ANS: <letter>        (never rendered by any client)
 *   [/Q]
 *
 * Rules: [Q] replaces [CHECK] for teach-beat RECOGNITION checks only — the
 * exercise and free-recall checks stay open-ended. ≤1 check per reply total
 * ([Q] or [CHECK], never both). No nesting. No attribute syntax — attribute
 * grammars have worse model compliance and break the fixed-literal-token
 * partial-suppression technique every client uses while streaming.
 *
 * This module is the single source of truth shared by server.js, the tests,
 * and scripts/eval-pacing.mjs (via createRequire) so the contract can't
 * drift between prompt, scrubber, and gate.
 */

const BLOCKS_V1 = 'blocks_v1';

/** Whether a request's capabilities opt into blocks_v1. */
function hasBlocks(capabilities) {
  return Array.isArray(capabilities) && capabilities.includes(BLOCKS_V1);
}

/**
 * Appended to CURRICULUM_PROMPT only when the client is capable. Curriculum
 * is exempt from the unified prompt (useUnifiedSystem), so this single
 * concat covers lessons under BOTH USE_UNIFIED_PROMPT states.
 */
const CURRICULUM_BLOCKS_APPENDIX = `

## BLOCK MARKUP (this student's app renders native cards — use these exact markers)
This client renders bracket-tagged blocks as native UI; the tags are stripped from view.
- [KEY]…[/KEY] — the beat's single takeaway, ONE sentence. At most one per reply, placed right after you teach the micro-concept. Not a lesson summary — just this beat.
- [EX]…[/EX] — wrap your one concrete example (real names, dates, systems) in these tags instead of leaving it inline. At most one per reply.
- MULTIPLE-CHOICE CHECKS — for the teach-beat check question (STEP 1), use this exact shape INSTEAD of [CHECK]:
[Q]
<the question, one line>
A) <option>
B) <option>
C) <option>
ANS: <letter of the correct option>
[/Q]
  2–4 options, one clearly correct, distractors drawn from real misconceptions (this lesson's "Common mistake" makes a good distractor). The app shows tappable options and tells the student instantly whether they were right; their pick then arrives as their next message ("I picked B) …") — react to it as you would any answer. Keep using [CHECK]…[/CHECK] (no options) when a check needs the student's own words, and keep the STEP 3 exercise open-ended prose — never a [Q].
- At most ONE check per reply ([Q] or [CHECK], never both). Never nest blocks. Everything else about the beat structure is unchanged — blocks reformat the beat, they don't lengthen it.`;

/**
 * Free-chat variant ([KEY]/[EX] only — no checks outside lessons). Exported
 * for the planned free-chat rollout but NOT WIRED yet: free chat has no eval
 * scenario covering blocks, and we don't ship prompt surface we can't gate.
 */
const UNIFIED_BLOCKS_APPENDIX = `
<block_markup>
This client renders bracket-tagged blocks as native cards (tags stripped from view). When a reply teaches a concept, you MAY mark up:
- [KEY]one-sentence takeaway[/KEY] — at most one per reply.
- [EX]the concrete example[/EX] — at most one per reply.
Use them only when they carry real content — a 2-sentence reply needs no blocks. Never use [Q] or [CHECK] outside curriculum lessons. All global response rules (length, one idea, one closing question) still apply.
</block_markup>`;

const KEY_RE = /\[KEY\]([\s\S]*?)\[\/KEY\]/g;
const EX_RE = /\[EX\]([\s\S]*?)\[\/EX\]/g;
const Q_RE = /\[Q\]\n?([\s\S]*?)\[\/Q\]/g;
const OPTION_LINE_RE = /^[A-D]\)\s+(.+)$/;
const ANS_LINE_RE = /^ANS:\s*([A-D])\s*$/;

/** Parse one [Q] interior into {stem, options, answerIndex} (nulls on malformed). */
function parseQuizInterior(interior) {
  const lines = interior.split('\n').map((l) => l.trim()).filter(Boolean);
  const stemLines = [];
  const options = [];
  let answerIndex = null;
  for (const line of lines) {
    const opt = OPTION_LINE_RE.exec(line);
    if (opt) { options.push(opt[1]); continue; }
    const ans = ANS_LINE_RE.exec(line);
    if (ans) { answerIndex = ans[1].charCodeAt(0) - 65; continue; }
    if (options.length === 0 && answerIndex === null) stemLines.push(line);
  }
  const stem = stemLines.join(' ').trim();
  const wellFormed =
    stem.length > 0 &&
    options.length >= 2 && options.length <= 4 &&
    answerIndex !== null && answerIndex < options.length;
  return { stem, options, answerIndex, wellFormed };
}

/**
 * Structural validation of a reply's block usage. Shared with the eval gate.
 * Returns counts plus `problems` naming each violation (empty = clean).
 */
function validateBlocks(reply) {
  const text = String(reply ?? '');
  const problems = [];

  // Balance: every open marker needs its close, no strays.
  for (const [open, close] of [['[KEY]', '[/KEY]'], ['[EX]', '[/EX]'], ['[Q]', '[/Q]']]) {
    const opens = text.split(open).length - 1;
    const closes = text.split(close).length - 1;
    if (opens !== closes) problems.push(`unbalanced ${open} (${opens} open / ${closes} close)`);
  }

  const keyCount = [...text.matchAll(KEY_RE)].length;
  const exCount = [...text.matchAll(EX_RE)].length;
  const quizzes = [...text.matchAll(Q_RE)].map((m) => parseQuizInterior(m[1]));
  const checkCount = (text.match(/\[CHECK\]/g) || []).length;

  if (keyCount > 1) problems.push(`${keyCount} [KEY] blocks (max 1)`);
  if (exCount > 1) problems.push(`${exCount} [EX] blocks (max 1)`);
  if (quizzes.length + checkCount > 1) problems.push(`${quizzes.length} [Q] + ${checkCount} [CHECK] (max 1 check total)`);
  for (const q of quizzes) {
    if (!q.wellFormed) problems.push(`malformed [Q] (stem="${q.stem.slice(0, 40)}", options=${q.options.length}, ans=${q.answerIndex})`);
  }
  // A bare ANS: line outside a [Q] is an answer leak.
  const outsideQ = text.replace(Q_RE, '');
  if (/^ANS:/m.test(outsideQ)) problems.push('ANS: line outside a [Q] block');

  return { keyCount, exCount, quizzes, checkCount, problems, ok: problems.length === 0 };
}

/**
 * Defense in depth for NON-capable clients: if the model emits block markers
 * anyway (it was never instructed to — this mirrors the TEST_TOKEN_RE
 * philosophy), unwrap [KEY]/[EX] to their inner text and rewrite a [Q] to
 * plain prose — stem + option lines — DROPPING the ANS: line so the answer
 * never leaks to a prose client. Applied to final replies only; deltas
 * already streamed can't be retro-scrubbed (same limitation [CHECK] has).
 */
function scrubBlockMarkers(reply) {
  let out = String(reply ?? '');
  out = out.replace(KEY_RE, (_, inner) => inner.trim());
  out = out.replace(EX_RE, (_, inner) => inner.trim());
  out = out.replace(Q_RE, (_, interior) => {
    const { stem, options } = parseQuizInterior(interior);
    const lines = [stem, ...options.map((o, i) => `${String.fromCharCode(65 + i)}) ${o}`)];
    return lines.filter(Boolean).join('\n');
  });
  return out;
}

module.exports = {
  BLOCKS_V1,
  hasBlocks,
  CURRICULUM_BLOCKS_APPENDIX,
  UNIFIED_BLOCKS_APPENDIX,
  parseQuizInterior,
  validateBlocks,
  scrubBlockMarkers,
};
