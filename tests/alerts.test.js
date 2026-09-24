'use strict';

// Tests for the Discord webhook alerter (lib/alerts).
//
// Pure unit tests — fetch and the clock are injected via configure(), so no
// network and no timers. logger.warn is spied with the test runner's mock
// (pino defines level methods on the instance, so the spy intercepts the
// module's calls and auto-restores when each test ends).
//
//   1. Happy path — payload shape, URL, method/headers, truncation, env fallback.
//   2. Throttle — skipped inside the window, fires once it has elapsed,
//      independent per key, stamped on the attempt (a failed post still
//      throttles), cleared by __resetForTest().
//   3. Unset URL — false, ONE warning per process, fetch never touched.
//   4. Failure paths — fetch rejects / throws sync / non-2xx → false, never
//      throws, logged at warn.
//   5. Timeout wiring — an AbortSignal from AbortSignal.timeout(5000) is passed.

const { describe, test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');

const logger = require('../lib/logger');
const alerts = require('../lib/alerts');

const URL = 'https://discord.com/api/webhooks/123/test-token';

// An injectable fetch that records every call and answers with `response`.
function fakeFetch(response = { ok: true, status: 204 }) {
  const calls = [];
  const fn = async (url, opts) => {
    calls.push({ url, opts });
    return response;
  };
  fn.calls = calls;
  return fn;
}

// A controllable clock.
function fakeClock(start = 1_000_000) {
  let t = start;
  const now = () => t;
  now.advance = (ms) => { t += ms; };
  return now;
}

const savedEnv = process.env.DISCORD_WEBHOOK_URL;
after(() => {
  if (savedEnv === undefined) delete process.env.DISCORD_WEBHOOK_URL;
  else process.env.DISCORD_WEBHOOK_URL = savedEnv;
  alerts.__resetForTest();
});

beforeEach(() => {
  alerts.__resetForTest();
  delete process.env.DISCORD_WEBHOOK_URL;
});

// ---------------------------------------------------------------------------
// 1. Happy path
// ---------------------------------------------------------------------------
describe('alerts.notify posts to the webhook', () => {
  test('POSTs { content } as JSON to the configured URL and resolves true', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL });

    const posted = await alerts.notify('boot', 'server up');

    assert.equal(posted, true);
    assert.equal(fetch.calls.length, 1);
    const { url, opts } = fetch.calls[0];
    assert.equal(url, URL);
    assert.equal(opts.method, 'POST');
    assert.equal(opts.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(opts.body), { content: 'server up' });
  });

  test('content is truncated to 1900 chars (Discord limit is 2000)', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL });

    await alerts.notify('digest', 'x'.repeat(5000));

    const body = JSON.parse(fetch.calls[0].opts.body);
    assert.equal(body.content.length, 1900);
    assert.deepEqual(Object.keys(body), ['content']);
  });

  test('falls back to process.env.DISCORD_WEBHOOK_URL when not configured', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch }); // no webhookUrl override
    process.env.DISCORD_WEBHOOK_URL = URL;

    assert.equal(await alerts.notify('boot', 'env url'), true);
    assert.equal(fetch.calls[0].url, URL);
  });

  test('any 2xx counts as posted (Discord answers 204 No Content)', async () => {
    alerts.configure({ fetch: fakeFetch({ ok: true, status: 200 }), webhookUrl: URL });
    assert.equal(await alerts.notify('report', 'ok'), true);
  });
});

// ---------------------------------------------------------------------------
// 2. Throttle
// ---------------------------------------------------------------------------
describe('alerts.notify per-key throttle', () => {
  test('a repeat inside throttleMs is skipped; it fires again once the window elapses', async () => {
    const fetch = fakeFetch();
    const now = fakeClock();
    alerts.configure({ fetch, webhookUrl: URL, now });

    assert.equal(await alerts.notify('budget_80', 'first', { throttleMs: 60_000 }), true);
    now.advance(10_000);
    assert.equal(await alerts.notify('budget_80', 'too soon', { throttleMs: 60_000 }), false);
    now.advance(49_999); // 59_999 ms since the first — still inside
    assert.equal(await alerts.notify('budget_80', 'still too soon', { throttleMs: 60_000 }), false);
    now.advance(1); // exactly 60_000 ms — window has elapsed
    assert.equal(await alerts.notify('budget_80', 'again', { throttleMs: 60_000 }), true);

    assert.equal(fetch.calls.length, 2);
    assert.deepEqual(
      fetch.calls.map((c) => JSON.parse(c.opts.body).content),
      ['first', 'again']
    );
  });

  test('keys throttle independently', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL, now: fakeClock() });

    assert.equal(await alerts.notify('ip_cap:aaaa', 'a', { throttleMs: 60_000 }), true);
    assert.equal(await alerts.notify('ip_cap:bbbb', 'b', { throttleMs: 60_000 }), true);
    assert.equal(await alerts.notify('ip_cap:aaaa', 'a again', { throttleMs: 60_000 }), false);
    assert.equal(fetch.calls.length, 2);
  });

  test('throttleMs defaults to 0 → never throttled', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL, now: fakeClock() });

    assert.equal(await alerts.notify('kill_switch', 'on'), true);
    assert.equal(await alerts.notify('kill_switch', 'off'), true);
    assert.equal(fetch.calls.length, 2);
  });

  test('the throttle is stamped on the attempt: a failed post still throttles the key', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    const now = fakeClock();
    let calls = 0;
    const fetch = async () => {
      calls += 1;
      if (calls === 1) throw new Error('ECONNRESET');
      return { ok: true, status: 204 };
    };
    alerts.configure({ fetch, webhookUrl: URL, now });

    assert.equal(await alerts.notify('anthropic_errors', 'burst', { throttleMs: 60_000 }), false);
    now.advance(1_000);
    assert.equal(await alerts.notify('anthropic_errors', 'burst', { throttleMs: 60_000 }), false);
    assert.equal(calls, 1, 'second call must be throttled, not retried at request rate');
    now.advance(60_000);
    assert.equal(await alerts.notify('anthropic_errors', 'burst', { throttleMs: 60_000 }), true);
    assert.equal(calls, 2);
  });

  test('__resetForTest() clears throttle stamps', async () => {
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL, now: fakeClock() });

    assert.equal(await alerts.notify('budget_100', 'x', { throttleMs: 60_000 }), true);
    assert.equal(await alerts.notify('budget_100', 'x', { throttleMs: 60_000 }), false);
    alerts.__resetForTest();
    alerts.configure({ fetch, webhookUrl: URL, now: fakeClock() });
    assert.equal(await alerts.notify('budget_100', 'x', { throttleMs: 60_000 }), true);
  });
});

// ---------------------------------------------------------------------------
// 3. Unset URL
// ---------------------------------------------------------------------------
describe('alerts.notify with no webhook URL', () => {
  test('resolves false, warns exactly once, never calls fetch', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    const fetch = fakeFetch();
    alerts.configure({ fetch }); // env deleted in beforeEach → unset

    assert.equal(await alerts.notify('boot', 'a'), false);
    assert.equal(await alerts.notify('boot', 'b'), false);
    assert.equal(await alerts.notify('digest', 'c'), false);

    assert.equal(warn.mock.callCount(), 1, 'the unset-URL warning is emitted once per process');
    assert.match(warn.mock.calls[0].arguments[1], /DISCORD_WEBHOOK_URL/);
    assert.equal(fetch.calls.length, 0);
  });

  test('an empty-string URL counts as unset', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: '' });

    assert.equal(await alerts.notify('boot', 'a'), false);
    assert.equal(fetch.calls.length, 0);
    assert.equal(warn.mock.callCount(), 1);
  });

  test('the warned-once flag resets with __resetForTest()', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    alerts.configure({ fetch: fakeFetch() });

    await alerts.notify('boot', 'a');
    alerts.__resetForTest();
    alerts.configure({ fetch: fakeFetch() });
    await alerts.notify('boot', 'b');

    assert.equal(warn.mock.callCount(), 2);
  });
});

// ---------------------------------------------------------------------------
// 4. Failure paths never throw
// ---------------------------------------------------------------------------
describe('alerts.notify swallows failures', () => {
  test('fetch rejects → resolves false, logs at warn, does not throw', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    alerts.configure({
      fetch: async () => { throw new Error('ECONNRESET'); },
      webhookUrl: URL,
    });

    let result;
    await assert.doesNotReject(async () => { result = await alerts.notify('unhandled_rejection', 'x'); });
    assert.equal(result, false);
    assert.equal(warn.mock.callCount(), 1);
    const [fields] = warn.mock.calls[0].arguments;
    assert.equal(fields.key, 'unhandled_rejection');
    assert.equal(fields.err.message, 'ECONNRESET');
  });

  test('fetch throws synchronously → resolves false', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    alerts.configure({
      fetch: () => { throw new TypeError('fetch is broken'); },
      webhookUrl: URL,
    });
    assert.equal(await alerts.notify('boot', 'x'), false);
  });

  test('an AbortError (timeout) → resolves false', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    alerts.configure({
      fetch: async () => {
        const err = new Error('The operation was aborted due to timeout');
        err.name = 'TimeoutError';
        throw err;
      },
      webhookUrl: URL,
    });
    assert.equal(await alerts.notify('boot', 'x'), false);
  });

  test('non-2xx response → resolves false and logs the status', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    alerts.configure({ fetch: fakeFetch({ ok: false, status: 429 }), webhookUrl: URL });

    assert.equal(await alerts.notify('report', 'x'), false);
    assert.equal(warn.mock.callCount(), 1);
    assert.equal(warn.mock.calls[0].arguments[0].status, 429);
  });

  test('the webhook URL and the alert text are never passed to the logger', async (t) => {
    const warn = t.mock.method(logger, 'warn', () => {});
    alerts.configure({ fetch: fakeFetch({ ok: false, status: 500 }), webhookUrl: URL });

    await alerts.notify('report', 'SECRET-ALERT-TEXT');

    const serialized = JSON.stringify(warn.mock.calls.map((c) => c.arguments));
    assert.ok(!serialized.includes(URL), 'webhook URL (a secret) must not be logged');
    assert.ok(!serialized.includes('SECRET-ALERT-TEXT'), 'alert text must not be logged');
  });

  test('garbage inputs (undefined key/text, non-function fetch) still resolve a boolean', async (t) => {
    t.mock.method(logger, 'warn', () => {});
    alerts.configure({ fetch: 'not a function', webhookUrl: URL });
    const result = await alerts.notify(undefined, undefined);
    assert.equal(typeof result, 'boolean');
    assert.equal(result, false);
  });
});

// ---------------------------------------------------------------------------
// 5. Timeout wiring
// ---------------------------------------------------------------------------
describe('alerts.notify timeout', () => {
  test('passes an AbortSignal built by AbortSignal.timeout(5000)', async (t) => {
    const timeoutSpy = t.mock.method(AbortSignal, 'timeout'); // call-through spy
    const fetch = fakeFetch();
    alerts.configure({ fetch, webhookUrl: URL });

    await alerts.notify('boot', 'x');

    const { opts } = fetch.calls[0];
    assert.ok(opts.signal instanceof AbortSignal, 'fetch must receive an AbortSignal');
    assert.equal(opts.signal.aborted, false);
    assert.equal(timeoutSpy.mock.callCount(), 1);
    assert.equal(timeoutSpy.mock.calls[0].arguments[0], 5000);
    assert.equal(opts.signal, timeoutSpy.mock.calls[0].result);
  });
});
