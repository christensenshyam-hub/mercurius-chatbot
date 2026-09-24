'use strict';

/**
 * Global daily Anthropic token ceiling (audit finding P0-A).
 *
 * The deployment is a SINGLE Railway replica with NO Redis (REDIS_URL unset),
 * so a module-level in-memory counter IS the whole mechanism — there is no
 * cross-process state to reconcile. If this ever scales to >1 replica the cap
 * becomes per-replica and must move to a shared store; until then, in-memory
 * is correct and adds zero infrastructure.
 *
 * The counter is keyed by UTC date and resets automatically at UTC midnight
 * (the first read or write on a new day zeroes it).
 *
 * Contract:
 *   - isCeilingExceeded()  → true once the day's summed tokens have reached
 *                            DAILY_TOKEN_CEILING. Callers MUST check this
 *                            BEFORE every Anthropic call and refuse (503 for
 *                            user-facing routes, skip for background calls).
 *   - recordUsage(usage, fallbackTokens)
 *                          → add a completed call's tokens to the day's total.
 *                            Pass the SDK `message.usage`
 *                            ({ input_tokens, output_tokens }); when usage is
 *                            unavailable at a call site, pass a fallback
 *                            estimate instead.
 *
 * Env: DAILY_TOKEN_CEILING = max input+output tokens per UTC day before calls
 * are refused. Unset/invalid → DEFAULT_CEILING. 0 → refuse everything (a hard
 * daily stop; also the lever the test uses to force the gate closed).
 */

// A backstop, not a per-user quota: high enough for a ~20-user app's normal
// day, low enough that a runaway loop or abuse spike can't reach a bill the
// operators can't pay. Tune via the env var.
const DEFAULT_CEILING = 2_000_000;

function ceiling() {
  const raw = process.env.DAILY_TOKEN_CEILING;
  if (raw === undefined || raw === '') return DEFAULT_CEILING;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_CEILING;
}

function utcDay(date = new Date()) {
  return date.toISOString().slice(0, 10); // YYYY-MM-DD in UTC
}

let state = { day: utcDay(), tokens: 0 };

function roll() {
  const today = utcDay();
  if (state.day !== today) state = { day: today, tokens: 0 };
}

function isCeilingExceeded() {
  roll();
  return state.tokens >= ceiling();
}

function recordUsage(usage, fallbackTokens = 0) {
  roll();
  const real = usage
    ? (Number(usage.input_tokens) || 0) + (Number(usage.output_tokens) || 0)
    : 0;
  state.tokens += real || (Number(fallbackTokens) || 0);
}

function currentTokens() {
  roll();
  return state.tokens;
}

// Test-only: reset the in-memory counter to a clean day.
function __resetForTest() {
  state = { day: utcDay(), tokens: 0 };
}

module.exports = { isCeilingExceeded, recordUsage, currentTokens, __resetForTest };
