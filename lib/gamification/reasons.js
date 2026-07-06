'use strict';

/**
 * Centralized XP-reason registry for the standby gamification system.
 *
 * ──────────────────────────────────────────────────────────────────────────
 * ARCHITECTURE RULE (non-negotiable): LEVEL ≠ RANK.
 *   • XP (and therefore Level) rewards ENGAGEMENT and REASONING MOVES — the
 *     encouragement layer the UI surfaces quietly. It must NOT imply mastery.
 *   • XP MUST NEVER feed Rank. Rank is the credentialed AI-literacy competency
 *     ladder (copper→…→mercurial) advanced ONLY by demonstrated competencies,
 *     computed by a separate Phase-2 engine. Nothing in this file — or anything
 *     that consumes it — may compute or influence rank.
 * ──────────────────────────────────────────────────────────────────────────
 *
 * What earns XP: clarifying/probing questions, revising a position after a
 * flaw is surfaced, self-correction, expressing calibrated uncertainty,
 * completing a reflection, completing a module, and returning daily.
 *
 * What NEVER earns XP (enforced by omission — there is simply no reason code
 * for them): correct answers, raw message volume, session length, passive
 * time, login frequency, or filler/spam. Correctness is deliberately absent.
 */

// Reason codes — the only XP-awardable events. Frozen so a typo throws instead
// of silently minting a new reason at a call site.
const REASON = Object.freeze({
  DAILY_RETURN: 'DAILY_RETURN',
  CLARIFYING_QUESTION: 'CLARIFYING_QUESTION',
  POSITION_REVISION: 'POSITION_REVISION',
  SELF_CORRECTION: 'SELF_CORRECTION',
  UNCERTAINTY_EXPRESSED: 'UNCERTAINTY_EXPRESSED',
  REFLECTION_COMPLETED: 'REFLECTION_COMPLETED',
  MODULE_COMPLETED: 'MODULE_COMPLETED',
});

/**
 * Per-reason award config. All XP amounts and caps live here — no magic
 * numbers in the service.
 *   • baseXp        — nominal award before diminishing returns.
 *   • idempotent    — structural one-shot event; requires a stable sourceId so
 *                     the (session_id, source_type, source_id) unique index
 *                     dedupes replays to zero. (A module completes only once.)
 *   • perSessionCap — max awards of this reason within one activity session
 *                     (counted by session_ref; skipped if the client omits it).
 *   • perDayCap     — max awards of this reason per UTC day. Always enforced.
 *   • diminishing   — if true, repeated awards in a short window pay less
 *                     (anti-grind). See DIMINISHING below.
 */
// Weighting (tuned): depth and metacognition pay most. Structural completions
// (module 60, reflection 25) dwarf the micro-moves, so real work beats chatter;
// among micro-moves self-correction (16) > position revision (14) >
// uncertainty (8) > clarifying question (6) — hardest/most-valuable first.
// Daily return (10) is a small nudge, never a rival to thinking. The easiest
// move (clarifying) caps soonest (4/session, 15/day).
const REASON_CONFIG = Object.freeze({
  [REASON.DAILY_RETURN]:          { baseXp: 10, idempotent: true,  perSessionCap: null, perDayCap: 1,    diminishing: false },
  [REASON.CLARIFYING_QUESTION]:   { baseXp: 6,  idempotent: false, perSessionCap: 4,    perDayCap: 15,   diminishing: true  },
  [REASON.POSITION_REVISION]:     { baseXp: 14, idempotent: false, perSessionCap: 4,    perDayCap: 12,   diminishing: true  },
  [REASON.SELF_CORRECTION]:       { baseXp: 16, idempotent: false, perSessionCap: 4,    perDayCap: 12,   diminishing: true  },
  [REASON.UNCERTAINTY_EXPRESSED]: { baseXp: 8,  idempotent: false, perSessionCap: 4,    perDayCap: 12,   diminishing: true  },
  [REASON.REFLECTION_COMPLETED]:  { baseXp: 25, idempotent: true,  perSessionCap: null, perDayCap: 5,    diminishing: false },
  [REASON.MODULE_COMPLETED]:      { baseXp: 60, idempotent: true,  perSessionCap: null, perDayCap: null, diminishing: false },
});

/**
 * Diminishing-returns schedule. When a `diminishing` reason has already been
 * awarded N times for this session+reason within DIMINISHING.windowMs, the
 * next award is multiplied by multipliers[min(N, last)]. Repeated low-effort
 * grinding trends toward zero; genuine varied engagement is unaffected.
 */
const DIMINISHING = Object.freeze({
  windowMs: 60 * 60 * 1000, // 1-hour rolling window
  multipliers: Object.freeze([1, 0.7, 0.5, 0.3, 0.15]), // index by prior-count; clamps to last
});

const ALL_REASONS = Object.freeze(Object.values(REASON));

function isValidReason(reason) {
  return Object.prototype.hasOwnProperty.call(REASON_CONFIG, reason);
}

function configFor(reason) {
  return REASON_CONFIG[reason] || null;
}

function diminishingMultiplier(priorCount) {
  const m = DIMINISHING.multipliers;
  return m[Math.min(Math.max(0, priorCount), m.length - 1)];
}

module.exports = {
  REASON,
  REASON_CONFIG,
  DIMINISHING,
  ALL_REASONS,
  isValidReason,
  configFor,
  diminishingMultiplier,
};
