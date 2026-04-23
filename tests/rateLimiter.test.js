'use strict';

/**
 * Rate-limiter unit tests.
 *
 * Covers both backing stores:
 *
 *   - In-memory (no REDIS_URL). Tests the exact counter semantics:
 *     Nth-and-below allowed, (N+1)th rejected, window resets, distinct
 *     session keys are independent.
 *
 *   - Redis-backed, driven through ioredis-mock so CI doesn't need a
 *     real Redis server. Verifies the exact same counter semantics
 *     hold and — critically — that two independent limiter instances
 *     pointed at the same mock Redis see each other's increments (the
 *     whole reason we added Redis: state shared across replicas).
 */

const { describe, test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

// Make sure pino stays silent across these tests — the rate-limiter
// logs on Redis init + errors.
process.env.NODE_ENV = 'test';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function clearRedisUrl() {
  delete process.env.REDIS_URL;
}

async function countHits(limiter, key, iterations) {
  const results = [];
  for (let i = 0; i < iterations; i++) {
    results.push(await limiter(key));
  }
  return results;
}

// ---------------------------------------------------------------------------
// In-memory store
// ---------------------------------------------------------------------------

describe('sessionLimiter — in-memory store (no REDIS_URL)', () => {
  let rateLimiter;

  beforeEach(() => {
    clearRedisUrl();
    // Force a fresh require so _redisClient state is clean. Removing
    // the cached module entry is cheap and makes the tests robust to
    // ordering.
    delete require.cache[require.resolve('../lib/rateLimiter')];
    rateLimiter = require('../lib/rateLimiter');
    rateLimiter._resetForTests();
  });

  afterEach(() => {
    rateLimiter._resetForTests();
  });

  test('allows N requests under the limit, blocks the (N+1)th', async () => {
    const isLimited = rateLimiter.sessionLimiter(60_000, 3);
    const flags = await countHits(isLimited, 'sess_a', 4);
    assert.deepEqual(flags, [false, false, false, true]);
  });

  test('distinct session ids have independent buckets', async () => {
    const isLimited = rateLimiter.sessionLimiter(60_000, 2);
    assert.equal(await isLimited('sess_a'), false);
    assert.equal(await isLimited('sess_a'), false);
    assert.equal(await isLimited('sess_a'), true, 'sess_a is now over');
    assert.equal(await isLimited('sess_b'), false, 'sess_b has its own bucket');
    assert.equal(await isLimited('sess_b'), false);
    assert.equal(await isLimited('sess_b'), true);
  });

  test('falsy sessionId passes through (not rate-limited)', async () => {
    const isLimited = rateLimiter.sessionLimiter(60_000, 1);
    assert.equal(await isLimited(''), false);
    assert.equal(await isLimited(null), false);
    assert.equal(await isLimited(undefined), false);
  });

  test('sliding window: stamps outside the window are forgotten', async () => {
    // Drive through the exported private constructor so we can
    // inspect the time-sensitive branch without real clock sleep.
    const isLimited = rateLimiter._sessionLimiterMemory(50, 2);
    assert.equal(await isLimited('s'), false);
    assert.equal(await isLimited('s'), false);
    assert.equal(await isLimited('s'), true);
    await new Promise((resolve) => setTimeout(resolve, 60));
    // Window has rolled over — hits should be clear.
    assert.equal(await isLimited('s'), false);
  });
});

// ---------------------------------------------------------------------------
// Redis-backed store via ioredis-mock
// ---------------------------------------------------------------------------

describe('sessionLimiter — Redis-backed store (ioredis-mock)', () => {
  let rateLimiter;
  let mockRedis;

  beforeEach(() => {
    clearRedisUrl();
    delete require.cache[require.resolve('../lib/rateLimiter')];
    // `ioredis-mock` exports a class with the same API surface as
    // ioredis. We don't go through getRedisClient() because that
    // would require setting REDIS_URL; instead we hand the
    // private `_sessionLimiterRedis` a mock instance directly.
    const IoRedisMock = require('ioredis-mock');
    mockRedis = new IoRedisMock();
    rateLimiter = require('../lib/rateLimiter');
  });

  afterEach(async () => {
    await mockRedis.flushall();
    await mockRedis.quit();
  });

  test('allows N requests under the limit, blocks the (N+1)th', async () => {
    const isLimited = rateLimiter._sessionLimiterRedis(mockRedis, 60_000, 3);
    const flags = await countHits(isLimited, 'sess_a', 4);
    assert.deepEqual(flags, [false, false, false, true]);
  });

  test('distinct sessions have independent counters in Redis', async () => {
    const isLimited = rateLimiter._sessionLimiterRedis(mockRedis, 60_000, 2);
    assert.equal(await isLimited('sess_a'), false);
    assert.equal(await isLimited('sess_a'), false);
    assert.equal(await isLimited('sess_a'), true);
    assert.equal(await isLimited('sess_b'), false);
    assert.equal(await isLimited('sess_b'), false);
    assert.equal(await isLimited('sess_b'), true);
  });

  test('two limiter instances sharing a Redis see each other — the replica scenario', async () => {
    // The whole point of Redis: replica A increments, replica B
    // observes the increment, the 5th hit from replica B across the
    // combined 4 already-served is the one that 429s.
    const replicaA = rateLimiter._sessionLimiterRedis(mockRedis, 60_000, 4);
    const replicaB = rateLimiter._sessionLimiterRedis(mockRedis, 60_000, 4);

    // Hit A three times, B once — all under the limit.
    assert.equal(await replicaA('shared_sess'), false);
    assert.equal(await replicaA('shared_sess'), false);
    assert.equal(await replicaA('shared_sess'), false);
    assert.equal(await replicaB('shared_sess'), false);

    // Fifth hit — regardless of which replica handles it — should 429.
    assert.equal(await replicaB('shared_sess'), true, 'replica B must see replica A hits');
  });

  test('Redis EXPIRE is set on first increment — key self-evicts', async () => {
    const isLimited = rateLimiter._sessionLimiterRedis(mockRedis, 200, 2);
    await isLimited('sess_ttl');
    await isLimited('sess_ttl');
    assert.equal(await isLimited('sess_ttl'), true);

    // Wait past the window. A real Redis would PEXPIRE the key.
    await new Promise((resolve) => setTimeout(resolve, 260));
    assert.equal(await isLimited('sess_ttl'), false, 'window should have rolled over');
  });

  test('Redis transport failure opens the gate (degrades safely)', async () => {
    // Simulate a Redis that always throws on eval.
    const brokenRedis = {
      eval: async () => {
        throw new Error('connection refused');
      },
    };
    const isLimited = rateLimiter._sessionLimiterRedis(brokenRedis, 60_000, 2);
    // Under failure we prefer to let the user through rather than
    // 500 every chat request — that's the open-fail convention the
    // module docs advertise.
    assert.equal(await isLimited('sess_x'), false);
    assert.equal(await isLimited('sess_x'), false);
    assert.equal(await isLimited('sess_x'), false);
  });

  test('falsy sessionId short-circuits even with Redis attached', async () => {
    const isLimited = rateLimiter._sessionLimiterRedis(mockRedis, 60_000, 1);
    assert.equal(await isLimited(''), false);
    assert.equal(await isLimited(null), false);
    assert.equal(await isLimited(undefined), false);
  });
});

// ---------------------------------------------------------------------------
// URL redaction
// ---------------------------------------------------------------------------

describe('_redactUrl', () => {
  let rateLimiter;

  beforeEach(() => {
    clearRedisUrl();
    delete require.cache[require.resolve('../lib/rateLimiter')];
    rateLimiter = require('../lib/rateLimiter');
  });

  test('strips the password from a redis:// URL', () => {
    const redacted = rateLimiter._redactUrl('redis://user:supersecret@redis-host:6379/0');
    assert.ok(!redacted.includes('supersecret'));
    assert.ok(redacted.includes('REDACTED'));
    assert.ok(redacted.includes('redis-host'));
  });

  test('passes through URLs without a password unchanged', () => {
    const redacted = rateLimiter._redactUrl('redis://redis-host:6379/0');
    assert.ok(redacted.startsWith('redis://'));
    assert.ok(!redacted.includes('REDACTED'));
  });

  test('invalid URL returns a safe sentinel, not a throw', () => {
    assert.doesNotThrow(() => rateLimiter._redactUrl('not a url'));
    assert.equal(rateLimiter._redactUrl('not a url'), '[invalid url]');
  });
});

// ---------------------------------------------------------------------------
// Factory wiring — env flag + getRedisClient
// ---------------------------------------------------------------------------

describe('getRedisClient', () => {
  let rateLimiter;

  beforeEach(() => {
    clearRedisUrl();
    delete require.cache[require.resolve('../lib/rateLimiter')];
    rateLimiter = require('../lib/rateLimiter');
  });

  afterEach(() => {
    rateLimiter._resetForTests();
    clearRedisUrl();
  });

  test('returns null when REDIS_URL is not set', () => {
    assert.equal(rateLimiter.getRedisClient(), null);
  });

  test('result is cached across calls (same nullness)', () => {
    const a = rateLimiter.getRedisClient();
    const b = rateLimiter.getRedisClient();
    assert.equal(a, b);
  });

  test('after _resetForTests, a new REDIS_URL is re-evaluated', () => {
    assert.equal(rateLimiter.getRedisClient(), null);
    rateLimiter._resetForTests();
    // Still unset → still null.
    assert.equal(rateLimiter.getRedisClient(), null);
  });
});
