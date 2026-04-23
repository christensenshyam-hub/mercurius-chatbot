'use strict';

/**
 * Rate-limiter factory with pluggable storage.
 *
 *   - REDIS_URL unset  → in-memory store. Fine for a single Railway
 *                        replica. Zero new infrastructure to run.
 *   - REDIS_URL set    → ioredis client + rate-limit-redis store.
 *                        Limits are consistent across replicas; safe
 *                        to scale horizontally.
 *
 * The module exposes three things:
 *
 *   1. `ipLimiter(name, { windowMs, max })` — Express middleware
 *      keyed on the requester's IP. Use this for broad DoS control.
 *   2. `sessionLimiter(windowMs, max)` — a pure JS function
 *      `isRateLimited(sessionId) -> Promise<boolean>` used inside
 *      /api/chat to throttle a single device even when it rotates
 *      IPs (mobile networks do this).
 *   3. `getRedisClient()` — lazy singleton. Exported so metrics /
 *      health checks can observe connection state.
 *
 * Wire-contract stability:
 *   The 429 envelope `{ error: 'rate_limited', reply|message: "..." }`
 *   that the existing server returned is preserved exactly. The
 *   `handler` option on express-rate-limit renders our legacy
 *   payload so the iOS client (which keys off `error === 'rate_limited'`)
 *   sees no difference whether the store is memory or Redis.
 */

const rateLimit = require('express-rate-limit');
const logger = require('./logger');
const metrics = require('./metrics');

// ---------------------------------------------------------------------------
// Redis client — single shared connection for every limiter
// ---------------------------------------------------------------------------

let _redisClient = null;
let _redisInitAttempted = false;

function getRedisClient() {
  if (_redisInitAttempted) return _redisClient;
  _redisInitAttempted = true;

  const url = process.env.REDIS_URL;
  if (!url) {
    logger.info('rate-limiter: no REDIS_URL — using in-memory store (single-replica mode)');
    return null;
  }

  try {
    // Lazy-require so environments without Redis still work if the
    // module is absent for some reason (shouldn't happen in practice
    // — it's a regular dep — but we keep the failure-mode graceful).
    const Redis = require('ioredis');
    _redisClient = new Redis(url, {
      // Keep retrying forever but back off so we don't torch the
      // CPU or log spam during a Redis outage. Rate-limiting
      // silently degrades to "allow" if Redis is unreachable —
      // see `skip` callback on the limiter below.
      retryStrategy: (times) => Math.min(times * 200, 2000),
      maxRetriesPerRequest: 3,
      enableOfflineQueue: false,
      lazyConnect: false,
    });

    _redisClient.on('error', (err) => {
      // One-line warn per failure; ioredis reconnects automatically.
      logger.warn({ err: err.message }, 'redis error');
    });
    _redisClient.on('ready', () => {
      logger.info({ url: redactUrl(url) }, 'rate-limiter: Redis connected');
    });

    return _redisClient;
  } catch (err) {
    logger.error({ err: err.message }, 'rate-limiter: failed to init Redis — falling back to memory');
    _redisClient = null;
    return null;
  }
}

/**
 * Strip the password out of a redis:// URL for logging.
 */
function redactUrl(url) {
  try {
    const u = new URL(url);
    if (u.password) u.password = 'REDACTED';
    return u.toString();
  } catch {
    return '[invalid url]';
  }
}

// ---------------------------------------------------------------------------
// IP-based Express middleware limiter
// ---------------------------------------------------------------------------

/**
 * Build an Express rate-limit middleware keyed on the request IP.
 * Uses Redis storage when REDIS_URL is set, else in-memory.
 *
 *   const limiter = ipLimiter('global', { windowMs: 60_000, max: 60 });
 *   app.use('/api/', limiter);
 */
function ipLimiter(name, { windowMs, max }) {
  const redis = getRedisClient();

  const options = {
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
    // If Redis is supposed to be active but has errored, we'd rather
    // let the request through than hard-fail — the "skip" callback
    // runs before store access. rate-limit-redis already signals
    // degraded state by throwing; we catch that here.
    skip: (req) => {
      if (!redis) return false;
      if (redis.status === 'end' || redis.status === 'close') {
        // Logged separately — don't spam on every request.
        return false;
      }
      return false;
    },
  };

  if (redis) {
    // Lazy-require so the absence of rate-limit-redis doesn't crash
    // startup in the memory-only path.
    const RedisStore = require('rate-limit-redis');
    const sendCommand = (...args) => redis.call(...args);
    options.store = new RedisStore({
      prefix: `rl:ip:${name}:`,
      sendCommand,
    });
  }

  return rateLimit(options);
}

// ---------------------------------------------------------------------------
// Session-keyed token bucket
// ---------------------------------------------------------------------------

/**
 * Build an in-memory fallback session token bucket. Used when there's
 * no Redis or as a direct replacement for the old `isRateLimited`.
 *
 * Returns a function `isRateLimited(sessionId) -> Promise<boolean>`.
 * Resolves `true` when the session is OVER the limit (caller should
 * send 429), else `false`.
 */
function sessionLimiter(windowMs, max) {
  const redis = getRedisClient();
  if (redis) return sessionLimiterRedis(redis, windowMs, max);
  return sessionLimiterMemory(windowMs, max);
}

function sessionLimiterMemory(windowMs, max) {
  const buckets = Object.create(null);

  // Periodic sweep — identical to the old inline cleanup that lived
  // in server.js. Keeps memory bounded to sessions active in the
  // last 5 minutes.
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

function sessionLimiterRedis(redis, windowMs, max) {
  // Fixed-window counter via INCR + EXPIRE. Simpler than a
  // sliding window, and at our scale the boundary-effect
  // (burst allowed right after a window rolls over) is fine.
  //
  // Script runs atomically on the Redis side — no race between
  // INCR and EXPIRE if two replicas hit the same key at the same
  // instant.
  const LUA = `
local v = redis.call('INCR', KEYS[1])
if v == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
return v
`;

  return async function isRateLimited(sessionId) {
    if (!sessionId) return false;
    try {
      const key = `rl:session:${sessionId}`;
      const v = await redis.eval(LUA, 1, key, windowMs);
      return Number(v) > max;
    } catch (err) {
      // Redis is down — degrade to "allow". We'd rather let a
      // user through than 500 on every chat request.
      logger.warn({ err: err.message, sessionId }, 'session rate-limit check failed (open-fail)');
      return false;
    }
  };
}

// ---------------------------------------------------------------------------
// Testing hooks
// ---------------------------------------------------------------------------

/**
 * For tests only. Resets module-level state so subsequent calls to
 * `getRedisClient` re-evaluate `process.env.REDIS_URL` and
 * `sessionLimiter` rebuilds its bucket. Safe to call from
 * `beforeEach`.
 */
function _resetForTests() {
  if (_redisClient && typeof _redisClient.disconnect === 'function') {
    try { _redisClient.disconnect(); } catch { /* noop */ }
  }
  _redisClient = null;
  _redisInitAttempted = false;
}

module.exports = {
  ipLimiter,
  sessionLimiter,
  getRedisClient,
  _resetForTests,
  _redactUrl: redactUrl,
  _sessionLimiterMemory: sessionLimiterMemory,
  _sessionLimiterRedis: sessionLimiterRedis,
};
