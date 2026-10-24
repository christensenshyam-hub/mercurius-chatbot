'use strict';

/**
 * lib/modelParams.js — the request fields that depend on WHICH model a call
 * goes to. Pure: no env reads at call time, no I/O.
 *
 * Why: the tutor model is configurable (TUTOR_MODEL, step 1 of the
 * eval-gated move to Claude Sonnet 5.5), and the two models take different
 * sampling and thinking fields:
 *
 *   claude-sonnet-4-6 (today, the default) — `temperature` on every turn;
 *     a homework problem turn sends thinking {type:'adaptive'} +
 *     output_config {effort:'low'} and no temperature (PR #44).
 *   claude-sonnet-5-5 — any non-default temperature / top_p / top_k is a
 *     400, so none is ever sent. Omitting `thinking` runs ADAPTIVE thinking
 *     at effort `high`, and thinking {type:'disabled'} is a 400; the lowest
 *     setting is thinking {type:'between_tools'} (no extended thinking; no
 *     other field inside `thinking`; effort `high` or below only; rejected by
 *     every other model). So a problem turn keeps adaptive + effort low, and
 *     every other call that runs on the tutor model (tutor turns, the
 *     unit-test grader, fact-check, analyze, the cache prewarm) sends
 *     between_tools + output_config {effort: TUTOR_EFFORT}.
 *
 *   Adaptive thinking on a 4.7+/5.x model asks for display 'summarized'
 *   (the default there is 'omitted'; on 4.6 it is 'summarized', so a 4.6
 *   request is unchanged). Under 'omitted' a think streams no event at all
 *   until its signature (the SDK drops the API's pings), and the server's
 *   stream idle watchdog (STREAM_IDLE_MS) would end a long problem turn with
 *   a timeout; summarized thinking deltas keep it fed, as on 4.6. They never
 *   reach a student: the relay forwards 'text' events only, and every
 *   reader takes text blocks by type.
 *
 *   Only those two models are verified (isVerifiedTutorModel; the server
 *   logs a boot warning for any other TUTOR_MODEL). Another 4.7+/5.x id,
 *   reachable only through TUTOR_MODEL or MODEL_ALLOWLIST, takes no
 *   sampling, rejects between_tools, and on several of them (Sonnet 5, Opus
 *   5 and 5.5, Haiku 5.5) an omitted `thinking` means adaptive thinking, so
 *   leaving it out would think inside the small reply budgets and run out.
 *   Every call to such a model says so instead: thinking adaptive (display
 *   'summarized') at TUTOR_EFFORT, with the same max_tokens headroom a
 *   problem turn gets.
 *
 * No route hand-builds these fields: each asks `requestFields(model, intent)`
 * and `maxTokensFor(model, intent, base)` and spreads the result between
 * `max_tokens` and `system`, the order the requests have always had, so a
 * claude-sonnet-4-6 request is byte-identical to the one sent before this
 * module existed.
 *
 * Contract:
 *   - resolveTutorModel(raw)   → the trimmed TUTOR_MODEL, or
 *                                'claude-sonnet-4-6' when unset/blank.
 *   - resolveTutorEffort(raw)  → { effort, valid }: low | medium | high
 *                                (between_tools rejects xhigh and max), or
 *                                'low' with valid:false for anything else
 *                                (blank/unset is valid and means 'low').
 *   - acceptsSampling(model)   → false for Claude 4.7-or-later and 5.x ids
 *                                (temperature/top_p/top_k are 400s there);
 *                                true for every other id, including legacy
 *                                'claude-3-5-haiku-latest'-style ids.
 *   - usesBetweenTools(model)  → true only for claude-sonnet-5-5 (and its
 *                                dated ids): the one model that accepts it.
 *   - isVerifiedTutorModel(model)
 *                              → true for claude-sonnet-4-6 and
 *                                claude-sonnet-5-5 (and its dated ids), the
 *                                two models whose request fields are checked
 *                                against the API's rules.
 *   - thinksOnProblems(model)  → whether a homework problem turn gets
 *                                adaptive thinking on this model: exactly
 *                                claude-sonnet-4-6 / claude-opus-4-6 (today's
 *                                THINKING_MODEL_RE) or any 4.7+/5.x id.
 *   - thinks(model, intent)    → whether this call carries adaptive thinking:
 *                                a problem turn on a model above, or any call
 *                                to a 4.7+/5.x model other than Sonnet 5.5.
 *   - requestFields(model, intent, { temperature, effort })
 *                              → the fields to spread into the params:
 *                                { temperature } | {} | { thinking,
 *                                output_config }.
 *   - maxTokensFor(model, intent, base)
 *                              → base, or base + 2048 (at least 3000) for a
 *                                call that thinks: thinking tokens count
 *                                against max_tokens. between_tools calls get
 *                                no headroom (no thinking), nor does the
 *                                prewarm (its reply is never read). On
 *                                claude-sonnet-5-5 each of those counts (the
 *                                base, the 2048 and the 3000) is first scaled
 *                                by TOKENIZER_SCALE (rounded up), prewarm
 *                                aside: its tokenizer counts more tokens for
 *                                the same words, so a cap written for 4.6 cut
 *                                its replies off. Every other model: as
 *                                written.
 *
 * Intents: 'turn' (a tutor turn: free chat, a Deep-dive lesson, a Basics
 * lesson), 'problem' (a free-chat turn on homework to work), 'grader' (the
 * unit-test grader), 'helper' (fact-check, analyze), 'prewarm' (the cache
 * prewarm). Only 'problem' (and 'prewarm' for max_tokens) differs from the
 * rest; the names keep each call site honest about what it is, and an
 * unknown intent throws.
 */

const DEFAULT_TUTOR_MODEL = 'claude-sonnet-4-6';
const DEFAULT_TUTOR_EFFORT = 'low';
// between_tools is accepted only at effort `high` or below.
const TUTOR_EFFORTS = Object.freeze(['low', 'medium', 'high']);
// Homework problem turns (PR #44): adaptive thinking at low effort.
const PROBLEM_EFFORT = 'low';
const THINKING_HEADROOM = 2048;
const THINKING_MIN_TOKENS = 3000;
// Sonnet 5.5's tokenizer counts more tokens than 4.6's for the same text:
// 1.28x over every non-thinking reply of the Oct 24 A/B (eval-pacing --runs 3,
// docs/sonnet-5-5/ab-2026-10-24), 1.34x on Debate, whose [SOURCE: …] tags
// tokenize heavily and whose third reply was cut off at its 400 cap in 2 of
// 3 runs. So its caps hold the words a 4.6 cap holds, on the heaviest route
// too. The cap never shaped a reply's length (the model does not see it);
// it only cut replies off. Applied in whole percent, so 700 → 945 exactly
// (700 * 1.35 is 945.0000000000001 in floating point). A thinking problem
// turn's headroom and floor are scaled as well (2048 → 2765, 3000 → 4050):
// its thinking is text in the same tokenizer, and the wider problem detector
// (lib/homeworkGuard `broad`) sends proofs and integrals there. The longest
// of the A/B's 240 Sonnet 5.5 homework eval replies used 862 output tokens,
// thinking included, so this is margin, not a fix.
const TOKENIZER_SCALE_PERCENT = 135;
const TOKENIZER_SCALE = TOKENIZER_SCALE_PERCENT / 100;
const INTENTS = Object.freeze(['turn', 'problem', 'grader', 'helper', 'prewarm']);

// Today's exact set (server.js THINKING_MODEL_RE before this module): no
// dated suffix, so a pinned snapshot id keeps the temperature path.
const ADAPTIVE_4_6_RE = /^claude-(?:sonnet|opus)-4-6$/;
// claude-<family>-<major>[-<minor>] at a '-' boundary. A dated suffix
// ('-20251001') is never read as the minor: the minor is 1–2 digits.
const GENERATION_RE = /^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?=-|$)/;
const BETWEEN_TOOLS_RE = /^claude-sonnet-5-5(?:-|$)/;

function normalize(model) {
  return String(model || '').trim().toLowerCase();
}

function resolveTutorModel(raw) {
  const id = String(raw || '').trim();
  return id || DEFAULT_TUTOR_MODEL;
}

function resolveTutorEffort(raw) {
  const value = String(raw || '').trim().toLowerCase();
  if (!value) return { effort: DEFAULT_TUTOR_EFFORT, valid: true };
  if (TUTOR_EFFORTS.includes(value)) return { effort: value, valid: true };
  return { effort: DEFAULT_TUTOR_EFFORT, valid: false };
}

/** { family, major, minor } for a current-style id, else null. */
function generation(model) {
  const m = GENERATION_RE.exec(normalize(model));
  if (!m) return null;
  return { family: m[1], major: Number(m[2]), minor: m[3] === undefined ? 0 : Number(m[3]) };
}

/** Claude 4.7 or later, any 5.x and up: no sampling fields, effort-driven. */
function isModern(model) {
  const g = generation(model);
  if (!g) return false;
  return g.major > 4 || (g.major === 4 && g.minor >= 7);
}

function acceptsSampling(model) {
  return !isModern(model);
}

function usesBetweenTools(model) {
  return BETWEEN_TOOLS_RE.test(normalize(model));
}

function isVerifiedTutorModel(model) {
  return String(model || '').trim() === DEFAULT_TUTOR_MODEL || usesBetweenTools(model);
}

function thinksOnProblems(model) {
  return ADAPTIVE_4_6_RE.test(String(model || '')) || isModern(model);
}

function checkIntent(intent) {
  if (!INTENTS.includes(intent)) throw new TypeError(`modelParams: unknown intent '${intent}'`);
}

function thinks(model, intent) {
  checkIntent(intent);
  if (intent === 'problem' && thinksOnProblems(model)) return true;
  return isModern(model) && !usesBetweenTools(model);
}

// Adaptive thinking, summarized on a model whose default display is
// "omitted" (4.7+/5.x) so a long think still streams; exactly today's
// {type:'adaptive'} on 4.6.
function adaptiveThinking(model) {
  return isModern(model) ? { type: 'adaptive', display: 'summarized' } : { type: 'adaptive' };
}

function requestFields(model, intent, { temperature, effort = DEFAULT_TUTOR_EFFORT } = {}) {
  checkIntent(intent);
  const level = TUTOR_EFFORTS.includes(effort) ? effort : DEFAULT_TUTOR_EFFORT;
  if (thinks(model, intent)) {
    // A problem turn thinks at low effort on every model (PR #44). Any other
    // call that thinks is on an unverified 4.7+/5.x model (see the header):
    // adaptive is the one thinking setting all of them accept.
    return { thinking: adaptiveThinking(model), output_config: { effort: intent === 'problem' ? PROBLEM_EFFORT : level } };
  }
  if (acceptsSampling(model)) {
    return temperature === undefined ? {} : { temperature };
  }
  // claude-sonnet-5-5: no extended thinking, at TUTOR_EFFORT.
  return { thinking: { type: 'between_tools' }, output_config: { effort: level } };
}

function maxTokensFor(model, intent, base) {
  checkIntent(intent);
  // The prewarm only writes the cache: its 1-token reply is never read.
  if (intent === 'prewarm') return base;
  // Every count here is in 4.6 tokens, the thinking room included: thinking
  // text tokenizes heavier on Sonnet 5.5 too.
  const scale = (n) => (usesBetweenTools(model) ? Math.ceil((n * TOKENIZER_SCALE_PERCENT) / 100) : n);
  if (thinks(model, intent)) return Math.max(scale(base) + scale(THINKING_HEADROOM), scale(THINKING_MIN_TOKENS));
  return scale(base);
}

module.exports = {
  DEFAULT_TUTOR_MODEL,
  DEFAULT_TUTOR_EFFORT,
  TUTOR_EFFORTS,
  INTENTS,
  THINKING_HEADROOM,
  THINKING_MIN_TOKENS,
  TOKENIZER_SCALE,
  resolveTutorModel,
  resolveTutorEffort,
  acceptsSampling,
  usesBetweenTools,
  isVerifiedTutorModel,
  thinksOnProblems,
  thinks,
  requestFields,
  maxTokensFor,
};
