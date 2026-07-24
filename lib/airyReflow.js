'use strict';

/**
 * airyReflow — deterministic paragraph-density enforcement for tutor replies.
 *
 * The presentation contract says a paragraph is 1–2 sentences (3 for
 * curriculum beats and deep explainers). Prompting alone hovers around ~90%
 * compliance at temperature, which reads as intermittent walls of text on a
 * phone — so the server enforces the invariant mechanically: whenever a
 * prose paragraph reaches its sentence limit, the next sentence starts a new
 * paragraph (the inter-sentence whitespace becomes "\n\n").
 *
 * Exempt regions (never reflowed):
 *   - fenced code blocks (``` … ```)
 *   - bullet/numbered list lines (-, *, +, 1., 1))
 *   - [CHECK]…[/CHECK] spans (clients render the span as one callout card)
 *
 * The transformer is CHUNK-BOUNDARY INDEPENDENT: feeding the same text in
 * any chunking (1-char deltas vs one string) yields byte-identical output,
 * so the streamed concatenation always equals the one-shot reflow of the
 * final reply — clients never see the text change shape at finalize.
 *
 * Design: a consume-once state machine. Characters are consumed exactly
 * once, in order; all state (fence/check/list/sentence counters) mutates
 * only at consumption. When the buffered tail is too short to classify the
 * next token (a partial marker, or a sentence terminal whose following
 * whitespace run hasn't ended), consumption stops BEFORE it with no state
 * change and resumes on the next push. Lookahead is bounded (longest marker
 * + one whitespace run), so streaming hold-back is imperceptible.
 */

const ABBREVIATIONS = new Set([
  'dr', 'mr', 'mrs', 'ms', 'st', 'vs', 'etc', 'e.g', 'i.e', 'u.s', 'u.k',
  'a.i', 'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept',
  'oct', 'nov', 'dec', 'no', 'inc', 'ltd', 'co',
]);

const CHECK_OPEN = '[CHECK]';
const CHECK_CLOSE = '[/CHECK]';
const DECORATION_RE = /["'”’»)*\]`_]/;
const LIST_PREFIX_FULL_RE = /^\s{0,3}(?:[-*+]|\d{1,3}[.)])\s$/;
const LIST_PREFIX_PARTIAL_RE = /^\s{0,3}(?:[-*+]|\d{0,3}[.)]?)?$/;

function endsWithAbbreviation(recent) {
  const m = /([A-Za-z][A-Za-z.]{0,6})\.$/.exec(recent);
  if (!m) return false;
  const word = m[1].toLowerCase().replace(/\.$/, '');
  if (word.length === 1) return true; // initials: "J."
  return ABBREVIATIONS.has(word);
}

/** One-shot reflow of a complete text. */
function reflowText(text, limit) {
  const r = createReflow({ limit });
  return r.push(String(text ?? '')) + r.flush();
}

/** Streaming reflow transformer: `push(chunk) -> string`, `flush() -> string`. */
function createReflow({ limit }) {
  let buf = '';
  let inFence = false;
  let inCheck = false;
  let sentencesInPara = 0;
  // Line classification for the CURRENT line: 'unknown' until the prefix
  // decides, then 'list' or 'prose'. Reset at every newline.
  let lineType = 'unknown';
  let linePrefix = '';
  // Tail of consumed text, for abbreviation lookback.
  let recent = '';

  function classify(ch) {
    if (lineType !== 'unknown') return;
    linePrefix += ch;
    if (LIST_PREFIX_FULL_RE.test(linePrefix)) lineType = 'list';
    else if (!LIST_PREFIX_PARTIAL_RE.test(linePrefix)) lineType = 'prose';
  }

  function newLine() {
    lineType = 'unknown';
    linePrefix = '';
  }

  function newParagraph() {
    sentencesInPara = 0;
    newLine();
  }

  function push(chunk) {
    buf += String(chunk ?? '');
    let out = '';
    let i = 0;
    const emit = (s) => { out += s; recent = (recent + s).slice(-48); };

    scan: while (i < buf.length) {
      const rest = buf.length - i;

      // --- control tokens (fence + check tags) --------------------------
      if (buf[i] === '`') {
        if (rest < 3 && '```'.startsWith(buf.slice(i))) break; // partial fence tail
        if (buf.startsWith('```', i)) {
          inFence = !inFence;
          emit('```'); i += 3;
          continue;
        }
        emit(buf[i]); classify(buf[i]); i += 1;
        continue;
      }
      if (!inFence && buf[i] === '[') {
        const tail = buf.slice(i, i + CHECK_CLOSE.length);
        const openIsPrefix = CHECK_OPEN.startsWith(tail) || tail.startsWith(CHECK_OPEN);
        const closeIsPrefix = CHECK_CLOSE.startsWith(tail) || tail.startsWith(CHECK_CLOSE);
        if (!inCheck && tail.startsWith(CHECK_OPEN)) {
          inCheck = true;
          emit(CHECK_OPEN); i += CHECK_OPEN.length;
          continue;
        }
        if (inCheck && tail.startsWith(CHECK_CLOSE)) {
          inCheck = false;
          emit(CHECK_CLOSE); i += CHECK_CLOSE.length;
          continue;
        }
        // Possible partial tag at the very tail — wait for more data.
        if (rest < CHECK_CLOSE.length && (openIsPrefix || closeIsPrefix)) break;
        emit('['); classify('['); i += 1;
        continue;
      }

      // --- exempt regions pass through ----------------------------------
      if (inFence || inCheck) {
        emit(buf[i]); i += 1;
        continue;
      }

      const ch = buf[i];

      // --- newlines ------------------------------------------------------
      if (ch === '\n') {
        if (rest < 2) break; // need to know single vs double
        if (buf[i + 1] === '\n') {
          let j = i;
          while (j < buf.length && buf[j] === '\n') j += 1;
          if (j >= buf.length && buf[j - 1] === '\n') {
            // newline run may continue in the next chunk — but two are
            // already certain; consume all but keep determinism: a longer
            // run just re-enters here with rest<2 handling. Consume run.
          }
          emit(buf.slice(i, j)); i = j;
          newParagraph();
          continue;
        }
        emit('\n'); i += 1;
        newLine();
        continue;
      }

      // --- sentence terminals -------------------------------------------
      if ((ch === '.' || ch === '!' || ch === '?' || ch === '…') && lineType !== 'list') {
        // decoration run after the terminal
        let j = i + 1;
        while (j < buf.length && DECORATION_RE.test(buf[j])) j += 1;
        if (j >= buf.length) break; // can't classify yet
        const wsStart = j;
        if (buf[wsStart] !== ' ' && buf[wsStart] !== '\t' && buf[wsStart] !== '\n') {
          // Not a sentence end (e.g. "3.5", "U.S.A"): consume terminal char only.
          emit(ch); classify(ch); i += 1;
          continue;
        }
        // Abbreviation guard for '.' ("Dr. Smith", "e.g. this"). Decimals
        // ("1.8") never reach here — no whitespace follows their dot.
        if (ch === '.' && endsWithAbbreviation(recent + buf.slice(Math.max(0, i - 12), i + 1))) {
          emit(ch); classify(ch); i += 1;
          continue;
        }
        // whitespace run; stop if it may continue past the tail
        let k = wsStart;
        let brokeParagraph = false;
        while (k < buf.length && (buf[k] === ' ' || buf[k] === '\t' || buf[k] === '\n')) {
          if (buf[k] === '\n' && buf[k + 1] === '\n') { brokeParagraph = true; break; }
          k += 1;
        }
        if (!brokeParagraph && k >= buf.length) break; // run unresolved — wait

        // A real sentence boundary: consume terminal + decoration.
        emit(buf.slice(i, wsStart));
        i = wsStart;
        sentencesInPara += 1;

        if (brokeParagraph) continue; // the \n\n branch will handle reset

        if (sentencesInPara >= limit) {
          // Force a paragraph break in place of the whitespace run.
          emit('\n\n');
          i = k;
          newParagraph();
          continue;
        }
        // Keep the original whitespace; single newlines reset line state.
        const ws = buf.slice(i, k);
        emit(ws);
        if (ws.includes('\n')) newLine();
        i = k;
        continue;
      }

      // --- ordinary characters ------------------------------------------
      emit(ch); classify(ch); i += 1;
    }

    buf = buf.slice(i);
    return out;
  }

  function flush() {
    const rest = buf;
    buf = '';
    return rest;
  }

  return { push, flush };
}

/** Paragraph-sentence limit for a request: 3 for curriculum lessons and
 *  deep ("Explain more") replies, 2 for everything else. Debate is EXEMPT
 *  (Infinity): its contract is a line-structured labeled block
 *  (Claim/Warrant/Impact/Rebuttal, 4–7 lines) — reflowing it inflates the
 *  line count past its own contract. */
function reflowLimit({ isCurriculum, responseMode, mode }) {
  if (mode === 'debate') return Infinity;
  return isCurriculum || responseMode === 'deep' ? 3 : 2;
}

module.exports = { createReflow, reflowText, reflowLimit };
