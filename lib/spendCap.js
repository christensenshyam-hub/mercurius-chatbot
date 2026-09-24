'use strict';

/**
 * Global daily Anthropic spend cap, denominated in US DOLLARS (audit finding
 * P0-A).
 *
 * The deployment is a SINGLE Railway replica with NO Redis (REDIS_URL unset),
 * so a module-level in-memory accumulator IS the whole mechanism — there is
 * no cross-process state to reconcile. If this ever scales to >1 replica the
 * cap becomes per-replica and must move to a shared store; until then,
 * in-memory is correct and adds zero infrastructure. Across a RESTART the
 * day's total is recovered by hydrate() from the usage table at boot.
 *
 * Why dollars, not tokens: the four token classes the API reports are billed
 * at very different rates (lib/pricing) — on Sonnet an output token costs 5×
 * an input token, a cache WRITE 1.25×, and a cache READ only 0.1×. A flat
 * token count therefore over-charges cache hits (the thing prompt caching is
 * meant to make cheap) and under-charges long generations, so it can neither
 * be set from the budget the operators actually have nor be compared with the
 * bill. Each recorded call is priced at its model's rate card and the day's
 * total is kept as USD; the per-class token tally is kept alongside for
 * observability only.
 *
 * The accumulator is keyed by UTC date and resets automatically at UTC
 * midnight (the first read or write on a new day zeroes it).
 *
 * Contract:
 *   - isCeilingExceeded()  → true once today's USD has reached
 *                            DAILY_BUDGET_USD. Callers MUST check this BEFORE
 *                            every Anthropic call and refuse (503 for
 *                            user-facing routes, skip for background calls).
 *   - recordUsage(arg, fallback)
 *                          → add a completed call's cost to the day. Two
 *                            shapes are accepted:
 *                              NEW:    recordUsage({ model, usage,
 *                                                    estimatedOutputTokens })
 *                                      priced at `model`'s rates; when
 *                                      `usage` is missing/empty (aborted
 *                                      stream, thrown call) the estimate is
 *                                      counted as OUTPUT tokens — the dearest
 *                                      class, so the fallback over-counts.
 *                              LEGACY: recordUsage(usage, fallbackTokens)
 *                                      (what server.js calls today) — priced
 *                                      at SONNET rates; `fallbackTokens` is
 *                                      counted as input tokens at Sonnet
 *                                      rates when `usage` is missing/empty.
 *   - currentUsd()         → today's accumulated dollars.
 *   - budgetUsd()          → the effective DAILY_BUDGET_USD.
 *   - fraction()           → currentUsd / budgetUsd (budget 0 → 1). Not
 *                            clamped, so >1 means "over".
 *   - hydrate(usd)         → at boot, seed today's total from persisted
 *                            usage. Only ever RAISES the in-memory value, so
 *                            a stale or partial read can never lower what
 *                            this process has already counted.
 *   - state()              → { day, usd, budgetUsd, fraction, tokens } for the
 *                            admin/status endpoint.
 *   - currentTokens()      → summed token count across all four classes
 *                            (kept for callers of the old token counter).
 *
 * Env: DAILY_BUDGET_USD = max dollars per UTC day before calls are refused.
 * Unset/invalid/negative → DEFAULT_BUDGET_USD. 0 → refuse everything (a hard
 * daily stop; also the lever the test uses to force the gate closed).
 * REPLACES the former DAILY_TOKEN_CEILING, which is no longer read.
 */

const pricing = require('./pricing');

// A backstop, not a per-user quota: high enough for a ~20-user app's normal
// day, low enough that a runaway loop or abuse spike can't reach a bill the
// operators can't pay. Tune via the env var.
const DEFAULT_BUDGET_USD = 15;

function budgetUsd() {
  const raw = process.env.DAILY_BUDGET_USD;
  if (raw === undefined || raw === '') return DEFAULT_BUDGET_USD;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_BUDGET_USD;
}

function utcDay(date = new Date()) {
  return date.toISOString().slice(0, 10); // YYYY-MM-DD in UTC
}

function freshDay() {
  return {
    day: utcDay(),
    usd: 0,
    tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  };
}

let current = freshDay();

function roll() {
  if (current.day !== utcDay()) current = freshDay();
}

function isCeilingExceeded() {
  roll();
  return current.usd >= budgetUsd();
}

function addTokens(t) {
  current.tokens.input += t.input;
  current.tokens.output += t.output;
  current.tokens.cacheRead += t.cacheRead;
  current.tokens.cacheWrite += t.cacheWrite;
}

function isNewShape(arg) {
  return Boolean(arg) && typeof arg === 'object' &&
    ('model' in arg || 'usage' in arg || 'estimatedOutputTokens' in arg);
}

function recordUsage(arg, fallback = 0) {
  roll();

  let model;
  let usage;
  let estimate;
  let estimateClass;
  if (isNewShape(arg)) {
    model = arg.model;
    usage = arg.usage;
    estimate = Number(arg.estimatedOutputTokens) || 0;
    estimateClass = 'output';
  } else {
    model = pricing.FALLBACK_MODEL;
    usage = arg;
    estimate = Number(fallback) || 0;
    estimateClass = 'input';
  }

  const t = pricing.normalizeUsage(usage);
  const real = t.input + t.output + t.cacheRead + t.cacheWrite;
  if (real > 0) {
    current.usd += pricing.costUsd(model, usage);
    addTokens(t);
    return;
  }
  if (estimate > 0) {
    const est = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    est[estimateClass] = estimate;
    const p = pricing.priceFor(model);
    current.usd += (estimate * (estimateClass === 'output' ? p.out : p.in)) / 1_000_000;
    addTokens(est);
  }
}

function currentUsd() {
  roll();
  return current.usd;
}

function fraction() {
  roll();
  const b = budgetUsd();
  return b === 0 ? 1 : current.usd / b;
}

function hydrate(usd) {
  roll();
  const n = Number(usd);
  if (Number.isFinite(n) && n > current.usd) current.usd = n;
}

function currentTokens() {
  roll();
  const t = current.tokens;
  return t.input + t.output + t.cacheRead + t.cacheWrite;
}

function state() {
  roll();
  return {
    day: current.day,
    usd: current.usd,
    budgetUsd: budgetUsd(),
    fraction: fraction(),
    tokens: { ...current.tokens },
  };
}

// Test-only: reset the in-memory accumulator to a clean day.
function __resetForTest() {
  current = freshDay();
}

module.exports = {
  isCeilingExceeded,
  recordUsage,
  currentUsd,
  fraction,
  budgetUsd,
  hydrate,
  state,
  currentTokens,
  __resetForTest,
};
