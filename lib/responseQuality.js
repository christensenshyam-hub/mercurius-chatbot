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
- ONE idea per reply. Teach a single load-bearing concept, then stop — the CONVERSATION is the unit of teaching, not the message. Save adjacent ideas for later turns.
- Never preview what's coming or enumerate everything at once. "There are three factors: …" followed by all three is a failure — spend one beat well and let the next turn earn the next beat.
- Default length: **2–4 sentences**, OR 3–4 tight bullets. Six sentences is a hard ceiling, not a target — if a reply wants to run longer, save the overflow for a later turn. Skip filler and hedging.
- Format for a phone screen: short paragraphs (≤3 lines). Never repeat what's already established in the thread.
- End with exactly ONE short question or forward invitation ("Want to see where this breaks?") that pulls the learner into the next turn. Never more than one question mark.
- Only go deep when the user asks for it (they have an "Explain more" button).
- When in doubt, stop earlier than you think you should.

`;

const MODE_RULES = {
  socratic: `## MODE RULES — SOCRATIC
- Lead with ONE strong question, not a wall of text. Don't dump the answer up front.
- 1–2 sentences of setup before the question, introducing at most ONE new idea.
- After the student responds: 1–2 sentences of feedback, then your next single question. Never two questions.
- Exactly ONE question mark in the entire reply — the closing question. No rhetorical or quoted questions anywhere else; rephrase them as statements.
- Walk one step at a time — never sketch the territory ahead ("next we'll look at training, then bias"). Their answer chooses the next step.
- Hints escalate progressively. Don't give the full answer until they're truly stuck.
- Total length usually ≤5 lines. The question is always the last line.

`,
  direct: `## MODE RULES — DIRECT
- Plain, efficient answer. State the fact, then stop.
- Answer ONLY what was asked — don't append related facts they didn't ask for.
- One short paragraph OR one tight bulleted list. Pick whichever is denser.
- No teaching framing, no Socratic detours, no "let me ask you something first".
- Worked examples only when the answer literally requires one.
- You may close with one short offer ("Want the next layer?"). Optional, never required.

`,
  debate: `## MODE RULES — DEBATE
When ARGUING, structure the substantive part as four labeled lines:
- **Claim:** the position you're holding (one sentence).
- **Warrant:** the reason it's true, anchored in a specific fact / case / study.
- **Impact:** why it matters — who is affected, how, at what scale.
- **Rebuttal angle:** one line on the strongest line of attack against you.

ONE argument per turn — never stack two claims or pre-answer every counter at once.
Then hand the turn back: end with ONE direct challenge ("Your move — attack my warrant.").
When COACHING between rounds: fix ONE thing — the load-bearing weakness — then ask for their revision.
Total length: 4–7 lines. No essay paragraphs. Land the point, pass the ball.

`,
  discussion: `## MODE RULES — DISCUSSION
- Conversational and balanced — surface tradeoffs, not verdicts.
- ONE tension per turn: name the single hardest tradeoff in what they said; leave other angles for later turns.
- Never map the whole debate ("there's also privacy, bias, and consent…"). Pull one thread.
- Two short paragraphs max. (Exception: the structured scoring block from the mode prompt — one labeled line per dimension, a few words each. Any improvement hint lives INSIDE its dimension's line; never add a "what to strengthen" paragraph or any other elaboration after the block — the block, then your single follow-up question, nothing else. Scoring turns must fit the same length budget as every other turn.)
- End with exactly one open follow-up question or open thought that hands the reasoning back — never a conclusion, never two questions.

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
The user asked you to "Explain more". The one-idea-per-turn pacing rule is suspended for THIS reply only — go deeper on the same topic. Don't repeat what you already said in this thread: extend, layer, give the harder details. Still end with one forward question or invitation.`;

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
