'use strict';

/**
 * quizShuffle — put the options of every [Q]…[/Q] check in a stable order
 * of the server's choosing, and rewrite its ANS line to match (AUD-18).
 *
 * The model puts the right answer at B about 79% of the time (audit
 * 2026-10, 53 lesson checks: B 42, C 7, A 4), so a student who taps B
 * without reading gets "Exactly right!". Prompting for balance is the kind of
 * formatting invariant that plateaus below 100%, so the server fixes the
 * order on the way out, for blocks_v1 clients (the only ones that see [Q]).
 *
 * The order: options sorted by sha256(version, stem, option text). So
 *   - it is deterministic: the same stem with the same options always comes
 *     out in the same order, whatever order the model wrote them in;
 *   - it is idempotent: the client stores and replays the reordered block,
 *     and a model that repeats the check word for word (the prompt asks it
 *     to after an off-topic reply) gets the same arrangement again, so the
 *     student's "I picked B) …", the cards and the model's history agree;
 *   - over many checks the right answer lands on each letter about equally
 *     often. The text of every line is unchanged; only which option sits on
 *     which letter, and the ANS letter, move.
 *
 * Anything this module is not sure about passes through byte for byte: a
 * block that isn't exactly stem, then options "A) " "B) " … in letter order
 * (2–4, distinct), then one "ANS: X" line; a block with another marker
 * inside; an option or stem that points at a position ("Both A and B",
 * "All of the above"), which a reorder would make wrong; an unclosed [Q];
 * a [Q] whose [/Q] is not within MAX_SPAN_CHARS.
 *
 * The streaming transformer holds text from "[Q]" until its "[/Q]" (a block
 * is ~250 chars, at most ~480 in the audit corpus) and is
 * CHUNK-BOUNDARY INDEPENDENT: every decision depends on the text alone, so
 * any chunking of a reply produces the same bytes as the one-shot
 * `shuffleQuizzes` (which the JSON path and the tests use).
 */

const crypto = require('node:crypto');

const OPEN = '[Q]';
const CLOSE = '[/Q]';
/// Longest [Q] span the stream will hold, from "[Q]" through "[/Q]".
const MAX_SPAN_CHARS = 2000;
/// Salt for the order. Changing it reorders every check, deliberately.
const ORDER_VERSION = 'quiz-order-v1';
const LETTERS = ['A', 'B', 'C', 'D'];

// Both parsers that read these lines (lib/blockMarkup.js parseQuizInterior,
// iOS BlockParser.parseQuiz) accept "A) text" with a space after ")" and
// "ANS: X"; the strict forms here are the intersection.
const OPTION_LINE_RE = /^([ \t]*)([A-D])\)( +)(.*\S)([ \t]*)$/;
const ANS_LINE_RE = /^([ \t]*ANS:[ \t]*)([A-D])([ \t]*)$/;
const OTHER_MARKER_RE = /\[\/?(?:Q|KEY|EX|CHECK)\]/;

// Text that refers to the other options or to their letters, which a reorder
// would make wrong. Only real cross-references, NOT generous: the Deep-dive
// guide (lib/blockMarkup.js) has the model write the right option first, as
// A), so a false alarm sends that check out with the answer at A. Ordinary
// lesson wording must not trip these ("the letters B, A, N, K", "both of
// those sentences", "its next answer"; tests/quizShuffle.test.js keeps the
// recorded eval checks that used to).
const POSITIONAL_RES = [
  // "All of the above", "None of these options", "both of the answers below"
  /\b(?:all|none|both|neither|either|any)\s+of\s+(?:the\s+|these\s+|those\s+)?(?:above|below|options|answers|choices)\b/i,
  // A whole option that is "None of these" or "Both of them." (in a longer
  // line, "both of those sentences" points at the lesson, not the options)
  /^(?:all|none|both|neither|either|any)\s+of\s+(?:these|those|them)\s*[.!?]?$/i,
  /\b(?:the|options?|answers?|choices?|listed|mentioned)\s+(?:above|below)\b/i,
  // "the previous option" ("next answer", "first answer" are a model's answers)
  /\b(?:previous|preceding)\s+(?:option|choice)s?\b/i,
  // "option B", "Answer C"
  /\b(?:[Oo]ptions?|[Aa]nswers?|[Cc]hoices?)\s+[A-D]\b/,
  // "A and B", "A, B, and C", "neither A nor D", "A & B" (not a bare comma or
  // slash: "B, A, N, K" spells a word, "A/B testing" is a term)
  /\b[A-D](?:,?\s+(?:and|or|nor)\s+|\s*&\s*)[A-D]\b/,
  /\b[A-D]\)|\([A-D]\)/,
];

const norm = (s) => String(s).replace(/\s+/g, ' ').trim();

function positional(text) {
  return POSITIONAL_RES.some((re) => re.test(text));
}

/**
 * Strictly parse a [Q] interior. Returns null unless it is exactly: stem
 * line(s), then 2–4 option lines lettered A, B, C, D in order with distinct
 * texts, then one ANS line naming one of them (blank lines allowed between).
 */
function analyzeInterior(interior) {
  if (OTHER_MARKER_RE.test(interior)) return null;
  const lines = interior.split('\n');
  const stem = [];
  const options = [];
  let ans = null;
  for (let idx = 0; idx < lines.length; idx += 1) {
    const line = lines[idx];
    if (!line.trim()) continue;
    const opt = OPTION_LINE_RE.exec(line);
    if (opt) {
      if (ans || stem.length === 0) return null;
      options.push({ idx, lead: opt[1], letter: opt[2], sep: opt[3], text: opt[4], trail: opt[5] });
      continue;
    }
    const a = ANS_LINE_RE.exec(line);
    if (a) {
      if (ans || options.length === 0) return null;
      ans = { idx, head: a[1], letter: a[2], tail: a[3] };
      continue;
    }
    if (options.length > 0 || ans) return null; // prose after the options began
    stem.push(line.trim());
  }
  if (!ans || options.length < 2 || options.length > 4) return null;
  if (options.some((o, k) => o.letter !== LETTERS[k])) return null;
  const answerIndex = LETTERS.indexOf(ans.letter);
  if (answerIndex >= options.length) return null;
  const keys = options.map((o) => norm(o.text));
  if (new Set(keys).size !== keys.length) return null;
  return { lines, stem: norm(stem.join(' ')), options, ans, answerIndex };
}

function orderKey(stem, optionText) {
  return crypto.createHash('sha256')
    .update(`${ORDER_VERSION}\u0000${stem}\u0000${norm(optionText)}`)
    .digest('hex');
}

/**
 * The server's order for a parsed block: `order[k]` is the index (in the
 * model's order) of the option that goes on letter k.
 */
function optionOrder(stem, optionTexts) {
  const keyed = optionTexts.map((t, i) => ({ i, key: orderKey(stem, t) }));
  keyed.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : a.i - b.i));
  return keyed.map((k) => k.i);
}

/**
 * Reorder one complete "[Q]…[/Q]" span. Returns the span unchanged when it
 * isn't a block this module is sure about (see the header).
 */
function shuffleQuizSpan(span) {
  if (!span.startsWith(OPEN) || !span.endsWith(CLOSE)) return span;
  const interior = span.slice(OPEN.length, span.length - CLOSE.length);
  const q = analyzeInterior(interior);
  if (!q) return span;
  if (positional(q.stem) || q.options.some((o) => positional(o.text))) return span;

  const order = optionOrder(q.stem, q.options.map((o) => o.text));
  const out = q.lines.slice();
  q.options.forEach((slot, k) => {
    const src = q.options[order[k]];
    out[slot.idx] = `${slot.lead}${slot.letter})${slot.sep}${src.text}${slot.trail}`;
  });
  const newAnswer = order.indexOf(q.answerIndex);
  out[q.ans.idx] = `${q.ans.head}${LETTERS[newAnswer]}${q.ans.tail}`;
  const rebuilt = out.join('\n');

  // Belt and braces: the new block must parse, with the same options and
  // the same right answer, or the model's block goes out as written.
  const check = analyzeInterior(rebuilt);
  if (!check ||
      check.options[check.answerIndex].text !== q.options[q.answerIndex].text ||
      check.options.map((o) => norm(o.text)).sort().join('\u0000') !==
        q.options.map((o) => norm(o.text)).sort().join('\u0000')) {
    return span;
  }
  return OPEN + rebuilt + CLOSE;
}

/** Length of the longest proper prefix of `token` that `text` ends with. */
function partialTailLength(text, token) {
  for (let k = Math.min(token.length - 1, text.length); k > 0; k -= 1) {
    if (text.endsWith(token.slice(0, k))) return k;
  }
  return 0;
}

/** Streaming transformer: `push(chunk) -> string`, `flush() -> string`. */
function createQuizShuffler() {
  let buf = '';

  function push(chunk) {
    buf += String(chunk ?? '');
    let out = '';
    for (;;) {
      const open = buf.indexOf(OPEN);
      if (open === -1) {
        // Hold only a tail that could still become "[Q]".
        const keep = partialTailLength(buf, OPEN);
        out += buf.slice(0, buf.length - keep);
        buf = buf.slice(buf.length - keep);
        return out;
      }
      out += buf.slice(0, open);
      buf = buf.slice(open);
      // buf starts with "[Q]". A block is closed only if its "[/Q]" ends
      // within MAX_SPAN_CHARS — a rule about the text, not the chunking.
      const close = buf.indexOf(CLOSE, OPEN.length);
      if (close !== -1 && close + CLOSE.length <= MAX_SPAN_CHARS) {
        const span = buf.slice(0, close + CLOSE.length);
        out += shuffleQuizSpan(span);
        buf = buf.slice(span.length);
        continue;
      }
      if (buf.length >= MAX_SPAN_CHARS) {
        // Never closes in time: release the opener as written and keep
        // scanning after it.
        out += OPEN;
        buf = buf.slice(OPEN.length);
        continue;
      }
      return out; // wait for the rest of the block
    }
  }

  function flush() {
    // An unclosed [Q] (or a partial "[Q" tail) goes out as written.
    const rest = buf;
    buf = '';
    return rest;
  }

  return { push, flush };
}

/** One-shot form of the streaming transformer (same bytes, by construction). */
function shuffleQuizzes(text) {
  const s = createQuizShuffler();
  return s.push(String(text ?? '')) + s.flush();
}

module.exports = {
  createQuizShuffler,
  shuffleQuizzes,
  shuffleQuizSpan,
  analyzeInterior,
  optionOrder,
  MAX_SPAN_CHARS,
  ORDER_VERSION,
};
