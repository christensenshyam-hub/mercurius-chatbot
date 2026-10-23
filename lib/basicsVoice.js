'use strict';

/**
 * basicsVoice — a small, deterministic clean-up of Basics lesson replies
 * (2026-10), run on the stream before lib/airyReflow.
 *
 * The Basics guide bans filler words and tells Merc never to copy its own
 * labels, and the model still slips: across the smoke runs about 1 reply in
 * 4 said "just", and the UX review's live lessons showed "One line on that:"
 * and a bold "Safety point:" (the guide's own wording) reaching the learner.
 * Like the paragraph limit (lib/airyReflow), a formatting invariant gets a
 * transform, not more prompt text. The prompt rules stay as well.
 *
 * What it changes, and nothing else:
 *   - "just" and "simply" as a whole word followed by a space, outside double
 *     quotes ("…" or “…”, on the current line): dropped with the space after
 *     them. At a sentence start the next word gets a capital ("Just type" →
 *     "Type"). After a negation the word becomes "only" ("not just you" →
 *     "not only you", "isn't just for" → "isn't only for"), and before "because" or "put" it stays ("just because",
 *     "simply put" read wrong without it). A word followed by a line break,
 *     punctuation or the end of the reply stays.
 *   - At the start of a line, one of the guide's labels with its colon
 *     ("One line on that:", "Safety point:", "Idea 2:", "Recap:", "Trap:",
 *     "Follow-up:"), bold or not, is removed and the sentence after it keeps
 *     going with a capital. "**Safety point:** Cover …" → "Cover …";
 *     "**Safety point: Cover …**" → "**Cover …**".
 *   - At the start of a sentence, a filler lead-in the guide bans
 *     ("Think of it this way:", "Here's the thing:", "Here's another way to
 *     think about it:", "One line on that:") is removed and the sentence
 *     goes on with a capital. These lead-ins are where the live replies'
 *     longest sentences came from (26 to 30 words).
 *   Quoted text is never touched, so practice lines (`Try asking me: "…"`)
 *   and anything the learner is quoted as saying stay word for word. The
 *   contract markers ([KEY], [Q], [LESSON_COMPLETE] …) pass through.
 *
 * Only Basics lessons use it (server.js), so every other reply is
 * byte-identical to before.
 *
 * Like airyReflow it is CHUNK-BOUNDARY INDEPENDENT: the same text in any
 * chunking gives byte-identical output (tests/basicsVoice.test.js fuzzes
 * it). It holds back at most the start of a line (up to 32 characters,
 * until a label is ruled in or out) and a dropped word's next word.
 *
 * Contract:
 *   createBasicsVoice() → { push(chunk) → string, flush() → string }
 *   basicsVoiceText(text) → the whole text at once (push + flush).
 */

const DROP_WORDS = new Set(['just', 'simply']);
// "just because …" and "simply put, …" need the word.
const KEEP_BEFORE = new Set(['because', 'put']);
// "not just you", "isn't just for", "never just": the word becomes "only",
// or dropping it would flip the meaning.
const NEGATION_RE = /^(?:not|never)$|n['\u2019]t$/;
const LABEL_RE = /^([ \t]{0,3})(\*\*|__)?(?:One line on that|Safety point|Idea [12]|Recap|Trap|Follow-up)[ \t]{0,2}:[ \t]{0,2}(\*\*|__)?[ \t]{0,2}/i;
// LABEL_RE never matches more than this many characters, so a line start
// this long (or a whole line) decides it.
const LABEL_WINDOW = 32;
// The first letters a label can start with (after optional spaces and bold).
const LABEL_INITIALS = 'osirtf';
// Sentence-start lead-ins, word by word (lower case, straight apostrophes).
const LEAD_INS = Object.freeze([
  ['think', 'of', 'it', 'this', 'way:'],
  ["here's", 'the', 'thing:'],
  ["here's", 'another', 'way', 'to', 'think', 'about', 'it:'],
  ["here's", 'another', 'way', 'to', 'look', 'at', 'it:'],
  ['one', 'line', 'on', 'that:'],
]);
const WAIT = -1;
const normWord = (w) => w.toLowerCase().replace(/\u2019/g, "'");

/** How many characters of `text` (from its start) are a lead-in and the
 *  spaces after it; 0 for none; WAIT when more text could decide it. */
function leadInLength(text, final) {
  let undecided = false;
  for (const words of LEAD_INS) {
    let at = 0;
    let ok = true;
    for (let i = 0; i < words.length && ok; i++) {
      const m = /^[^ \t\r\n]+/.exec(text.slice(at));
      if (!m) {
        // Nothing yet where this word goes: more text may bring it.
        if (at >= text.length && !final) undecided = true;
        ok = false;
        break;
      }
      const word = normWord(m[0]);
      const complete = at + m[0].length < text.length || final;
      if (!complete) {
        if (words[i].startsWith(word)) undecided = true;
        ok = false;
        break;
      }
      if (word !== words[i]) { ok = false; break; }
      at += m[0].length;
      if (i < words.length - 1) {
        const gap = /^[ \t]+/.exec(text.slice(at));
        if (!gap) {
          if (at >= text.length && !final) undecided = true;
          ok = false;
          break;
        }
        at += gap[0].length;
      }
    }
    if (!ok) continue;
    const gap = /^[ \t]*/.exec(text.slice(at))[0];
    if (at + gap.length >= text.length && !final) return WAIT; // the spaces may go on
    return at + gap.length;
  }
  return undecided ? WAIT : 0;
}

function capitalizeFirstLetter(token) {
  const m = /^([*_"“'‘(\[]*)([a-z])/.exec(token);
  return m ? m[1] + m[2].toUpperCase() + token.slice(m[0].length) : token;
}

function createBasicsVoice() {
  let pending = '';
  // Per line: whether the label check is done, quote state, the previous
  // kept word (lowercase, letters only) and whether the next word starts a
  // sentence.
  let labelChecked = false;
  let inQuote = false;
  let prevWord = null;
  let sentenceStart = true;
  let capNext = false;

  function newLine() {
    labelChecked = false;
    inQuote = false;
    prevWord = null;
    sentenceStart = true;
    capNext = false;
  }

  function trackQuotes(s) {
    for (const c of s) {
      if (c === '"') inQuote = !inQuote;
      else if (c === '“') inQuote = true;
      else if (c === '”') inQuote = false;
    }
  }

  function keepToken(tok) {
    const t = capNext ? capitalizeFirstLetter(tok) : tok;
    capNext = false;
    trackQuotes(tok);
    const core = tok.toLowerCase().replace(/^[^a-z]+|[^a-z]+$/g, '');
    prevWord = core || prevWord;
    sentenceStart = /[.!?…]["”'’)\]*_]*$/.test(tok);
    return t;
  }

  function run(final) {
    let out = '';
    for (;;) {
      if (pending === '') break;

      if (!labelChecked) {
        const nl = pending.indexOf('\n');
        const line = nl < 0 ? pending : pending.slice(0, nl);
        const complete = nl >= 0 || final;
        const initial = /^[ \t]{0,3}(?:\*\*|__)?([^ \t*_])/.exec(line);
        const ruledOut = initial && !LABEL_INITIALS.includes(initial[1].toLowerCase());
        if (!ruledOut && !complete && line.length < LABEL_WINDOW) break;
        const m = ruledOut ? null : LABEL_RE.exec(line);
        labelChecked = true;
        if (m) {
          // Keep the indent, and an opening bold the label didn't close.
          out += m[1] + (m[2] && !m[3] ? m[2] : '');
          pending = pending.slice(m[0].length);
          sentenceStart = true;
          capNext = true;
        }
        continue;
      }

      const ws = /^[ \t\r\n]+/.exec(pending);
      if (ws) {
        out += ws[0];
        pending = pending.slice(ws[0].length);
        if (ws[0].includes('\n')) newLine();
        continue;
      }

      if (!inQuote && sentenceStart) {
        const lead = leadInLength(pending, final);
        if (lead === WAIT) break;
        if (lead > 0) {
          pending = pending.slice(lead);
          capNext = true;
          continue;
        }
      }

      const tok = /^[^ \t\r\n]+/.exec(pending)[0];
      if (tok.length === pending.length && !final) break; // the word may go on

      if (!inQuote && DROP_WORDS.has(tok.toLowerCase())) {
        const after = pending.slice(tok.length);
        const gap = /^[ \t]+/.exec(after);
        if (gap) {
          const rest = after.slice(gap[0].length);
          const next = /^[^ \t\r\n]+/.exec(rest);
          if (!next) {
            if (rest === '' && !final) break; // what follows decides
          } else {
            if (next[0].length === rest.length && !final) break; // the next word may go on
            const nextCore = next[0].toLowerCase().replace(/^[^a-z]+|[^a-z]+$/g, '');
            if (!KEEP_BEFORE.has(nextCore)) {
              if (!sentenceStart && NEGATION_RE.test(prevWord || '')) {
                out += keepToken(/^[A-Z]/.test(tok) ? 'Only' : 'only');
                pending = after;
                continue;
              }
              // Drop the word and the space after it.
              if (sentenceStart) capNext = true;
              pending = rest;
              continue;
            }
          }
        }
      }

      out += keepToken(tok);
      pending = pending.slice(tok.length);
    }
    return out;
  }

  return {
    push(chunk) {
      pending += String(chunk ?? '');
      return run(false);
    },
    flush() {
      const out = run(true);
      pending = '';
      return out;
    },
  };
}

function basicsVoiceText(text) {
  const v = createBasicsVoice();
  return v.push(String(text ?? '')) + v.flush();
}

module.exports = Object.freeze({ createBasicsVoice, basicsVoiceText, LABEL_WINDOW });
