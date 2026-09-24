'use strict';

/**
 * Per-minute rate limiters, in-memory.
 *
 * The deployment is ONE Railway replica, so process memory is the whole
 * store — the same reasoning as lib/spendCap and lib/quotas. A Redis-backed
 * variant used to live here for a horizontal-scaling future that never
 * arrived; it was removed because its failure mode was wrong (a Redis outage
 * would have 500'd every /api request — `passOnStoreError` defaults to
 * false and the `skip` hook never engaged). If replicas ever become real,
 * reintroduce a shared store with `passOnStoreError: true` and fail OPEN.
 *
 * The module exposes two things:
 *
 *   1. `ipLimiter(name, { windowMs, max })` — Express middleware keyed on the
 *      requester's IP. Broad DoS control. Sized for a classroom behind one
 *      school NAT (see server.js), so the sharp limit is the session one.
 *   2. `sessionLimiter(windowMs, max)` — a pure function
 *      `isRateLimited(sessionId) -> Promise<boolean>` used inside the model
 *      routes to throttle a single device even when it rotates IPs.
 *
 * Wire-contract stability:
 *   The 429 envelope `{ error: 'rate_limited', message: "..." }` is preserved
 *   exactly — the iOS client keys off `error === 'rate_limited'`.
 */

const rateLimit = require('express-rate-limit');
const metrics = require('./metrics');

// ---------------------------------------------------------------------------
// IP-based Express middleware limiter
// ---------------------------------------------------------------------------

/**
 * Build an Express rate-limit middleware keyed on the request IP.
 *
 *   const limiter = ipLimiter('global', { windowMs: 60_000, max: 400 });
 *   app.use('/api/', limiter);
 */
function ipLimiter(name, { windowMs, max }) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    // On trip: preserve the legacy envelope the iOS client expects.
    handler: (req, res /*, next, optionsUsed */) => {
      metrics.rateLimitRejectionsTotal.inc({
        scope: `ip:${name}`,
        endpoint: req.route?.path || req.originalUrl || 'unknown',
      });
      res.status(429).json({
        error: 'rate_limited',
        message:
          name === 'chat'
            ? 'Slow down — try again in a moment.'
            : 'Too many requests. Try again in a moment.',
      });
    },
  });
}

// ---------------------------------------------------------------------------
// Session-keyed sliding window
// ---------------------------------------------------------------------------

/**
 * Returns a function `isRateLimited(sessionId) -> Promise<boolean>`.
 * Resolves `true` when the session is OVER the limit (caller should send
 * 429), else `false`. Async so the call sites don't change if a shared
 * store ever comes back.
 */
function sessionLimiter(windowMs, max) {
  const buckets = Object.create(null);

  // Periodic sweep keeps memory bounded to sessions active in the last
  // five windows.
  const sweep = setInterval(() => {
    const cutoff = Date.now() - windowMs * 5;
    for (const key in buckets) {
      buckets[key] = buckets[key].filter((t) => t > cutoff);
      if (buckets[key].length === 0) delete buckets[key];
    }
  }, windowMs * 5);
  // Don't block process exit on the sweep interval — important for tests.
  sweep.unref?.();

  return async function isRateLimited(sessionId) {
    if (!sessionId) return false;
    const now = Date.now();
    const hits = buckets[sessionId] || (buckets[sessionId] = []);
    // Drop expired stamps in-place.
    while (hits.length && now - hits[0] >= windowMs) hits.shift();
    if (hits.length >= max) return true;
    hits.push(now);
    return false;
  };
}

// Kept for callers that reset limiter state between tests; there is no
// module-level state left to clear.
function _resetForTests() {}

module.exports = {
  ipLimiter,
  sessionLimiter,
  _resetForTests,
  _sessionLimiterMemory: sessionLimiter,
};
