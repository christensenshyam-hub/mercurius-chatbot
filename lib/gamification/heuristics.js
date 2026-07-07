'use strict';

/**
 * Heuristics-first detection of reasoning moves in a student's turn.
 *
 * ⚠️ SCAFFOLD ONLY — NOT WIRED INTO THE LIVE PATH. These pure functions exist
 * so the XP system can eventually classify chat turns cheaply, but Phase 1
 * does NOT call them from /api/chat — the tutor flow stays byte-identical. XP
 * in Phase 1 is awarded only via explicit POST /api/progression/event. A later
 * (separately gated) phase may wire these in, with optional Claude
 * classification layered behind its own sub-flag — async, rate-limited, never
 * blocking a response, never run on every message.
 *
 * These detect PROCESS (questioning, revising, doubting), never correctness.
 */

const { REASON } = require('./reasons');

const CLARIFYING = /\b(what do you mean|can you clarify|why is that|how does that|what if|is it because|could it be|what's the difference|how come)\b/i;
const REVISION = /\b(i was wrong|i changed my mind|on second thought|actually,? i think|i'd revise|let me reconsider|i take that back|i now think)\b/i;
const SELF_CORRECTION = /\b(i made a mistake|i misspoke|correction|that's not right, i|i mixed up|i confused)\b/i;
const UNCERTAINTY = /\b(i'm not sure|i'm unsure|i don't know|i'm uncertain|not entirely sure|hard to say|i could be wrong)\b/i;

/**
 * Return the single best-matching reasoning-move reason for a user turn, or
 * null. Priority favors the higher-effort move when several match. `prior`
 * (the previous assistant turn) is accepted for future context-aware
 * heuristics; unused in this minimal version.
 */
function detectReasoningMove(userText /*, prior */) {
  const t = String(userText || '');
  if (!t.trim()) return null;
  if (SELF_CORRECTION.test(t)) return REASON.SELF_CORRECTION;
  if (REVISION.test(t)) return REASON.POSITION_REVISION;
  if (CLARIFYING.test(t) && t.includes('?')) return REASON.CLARIFYING_QUESTION;
  if (UNCERTAINTY.test(t)) return REASON.UNCERTAINTY_EXPRESSED;
  return null;
}

module.exports = { detectReasoningMove };
