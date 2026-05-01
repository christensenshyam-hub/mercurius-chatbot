'use strict';

/**
 * Response-quality system: universal preamble + per-mode rules +
 * response-mode budget mapping. Extracted from `server.js` so the
 * pieces are unit-testable in isolation (the chat handler calls
 * Anthropic and is harder to drive cleanly in tests).
 *
 * Design notes:
 *   - The preamble is intentionally short — long preambles get
 *     ignored. Six bullets ≤ ~50 tokens land reliably.
 *   - Per-mode rules sit AFTER the preamble so the order of attention
 *     is "be concise → here's how concise looks for *your* mode".
 *   - `RESPONSE_MODE_BUDGETS` is the single source of truth for
 *     length/temperature; the chat handler reads from this table only.
 *   - `resolveResponseMode` is defensive: Zod already 400s on known-bad
 *     values, but if anything ever bypasses the schema, the handler
 *     still falls back to `concise` instead of crashing.
 */

const RESPONSE_QUALITY_PREAMBLE = `## RESPONSE QUALITY (read first; applies to every reply)
- Lead with the direct answer. No "Great question", "Sure!", or other warm-up.
- Default length: **2–4 sentences**, OR 3–4 tight bullets. Skip filler and hedging.
- Format for a phone screen: short paragraphs (≤3 lines), tight bullets.
- Never repeat content already established earlier in the thread.
- Only go deep when the user asks for it (they have an "Explain more" button).
- A short, useful answer beats a thorough lecture every time.
- When in doubt, stop earlier than you think you should.

`;

const MODE_RULES = {
  socratic: `## MODE RULES — SOCRATIC
- Lead with ONE strong question, not a wall of text.
- Use 2–4 sentences before the question. Don't dump the answer up front.
- After the student responds: 1–2 sentences of feedback, then your next question.
- Hints escalate progressively. Don't give the full answer until they're truly stuck.
- Question first, explanation second. Total length usually ≤6 lines.

`,
  direct: `## MODE RULES — DIRECT
- Plain, efficient answer. State the fact, then stop.
- One short paragraph OR one tight bulleted list. Pick whichever is denser.
- No teaching framing, no Socratic detours, no "let me ask you something first".
- Worked examples only when the answer literally requires one.

`,
  debate: `## MODE RULES — DEBATE
Structure every substantive reply as four labeled lines:
- **Claim:** the position you're holding (one sentence).
- **Warrant:** the reason it's true, anchored in a specific fact / case / study.
- **Impact:** why it matters — who is affected, how, at what scale.
- **Rebuttal angle:** one line on the strongest line of attack against you.

Total length: 4–7 lines. Punchy enough for speech prep or live cross-x.
No essay paragraphs. No throat-clearing. Land the points.

`,
  discussion: `## MODE RULES — DISCUSSION
- Conversational and balanced — surface tradeoffs, not verdicts.
- Two short paragraphs max, OR a tight set of bullets.
- Acknowledge the strong version of the other side; name the tension.
- End with one open thought or follow-up question, not a conclusion.

`,
};

// Tightened May 2026 after pre-TestFlight QA: replies at concise=400
// felt "long-winded" on the phone — too much room for the model to
// ramble even with the preamble. 250 tokens ≈ 180 words ≈ 3-4
// sentences, which lines up with the new "Default length: 2-4
// sentences" preamble rule. Spec range: 200-300.
const RESPONSE_MODE_BUDGETS = {
  one_line: { maxTokens: 120, temperature: 0.3 },
  concise:  { maxTokens: 250, temperature: 0.4 },
  balanced: { maxTokens: 600, temperature: 0.6 },
  deep:     { maxTokens: 1400, temperature: 0.7 },
};

const VALID_RESPONSE_MODES = new Set(Object.keys(RESPONSE_MODE_BUDGETS));

/**
 * Append-only instruction the chat handler tacks onto the system
 * prompt when `responseMode === 'deep'`. The iOS client doesn't echo
 * the prior assistant turn into the request, so the model needs an
 * explicit "don't repeat yourself" nudge — without it the deep
 * response often re-states what was already said.
 */
const EXPAND_MODE_NOTE = `

## EXPAND-MODE NOTE
The user asked you to "Explain more". Go deeper on the same topic. Don't repeat what you already said in this thread — extend, layer, give the harder details.`;

function resolveResponseMode(input) {
  if (typeof input === 'string' && VALID_RESPONSE_MODES.has(input)) {
    return input;
  }
  return 'concise';
}

function modeRulesFor(mode) {
  return MODE_RULES[mode] || MODE_RULES.socratic;
}

/**
 * Compose a final system-prompt prefix for a chat turn. Returns the
 * preamble + mode rules — the caller concatenates this with the
 * mode-specific deep prompt. Kept as a helper so the handler stays
 * readable (`prompt = qualityPrefix(mode) + DIRECT_PROMPT + ...`)
 * and so unit tests can assert prefix shape without spawning a server.
 */
function qualityPrefix(mode) {
  return RESPONSE_QUALITY_PREAMBLE + modeRulesFor(mode);
}

module.exports = {
  RESPONSE_QUALITY_PREAMBLE,
  MODE_RULES,
  RESPONSE_MODE_BUDGETS,
  EXPAND_MODE_NOTE,
  VALID_RESPONSE_MODES,
  resolveResponseMode,
  modeRulesFor,
  qualityPrefix,
};
