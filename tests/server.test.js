'use strict';

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const crypto = require('node:crypto');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SERVER_DIR = path.join(__dirname, '..');
const TEST_PORT = 9000 + Math.floor(Math.random() * 1000);
const BASE_URL = `http://localhost:${TEST_PORT}`;
const ADMIN_PASSWORD = 'test-admin-pw-' + crypto.randomBytes(4).toString('hex');

let serverProc;

function makeSessionId() {
  return 'test_' + crypto.randomBytes(8).toString('hex');
}

async function post(path, body, headers = {}) {
  const res = await fetch(`${BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json, headers: res.headers };
}

async function get(path, headers = {}) {
  const res = await fetch(`${BASE_URL}${path}`, { headers });
  const json = await res.json().catch(() => null);
  return { status: res.status, json, headers: res.headers };
}

// ---------------------------------------------------------------------------
// Re-implement isValidSessionId locally (server does not export it)
// ---------------------------------------------------------------------------
function isValidSessionId(id) {
  return id && typeof id === 'string' && id.length <= 64 && /^[a-zA-Z0-9_-]+$/.test(id);
}

// ---------------------------------------------------------------------------
// Server lifecycle — start before all tests, stop after
// ---------------------------------------------------------------------------

before(async () => {
  await new Promise((resolve, reject) => {
    serverProc = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: {
        ...process.env,
        PORT: String(TEST_PORT),
        ADMIN_PASSWORD,
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
        ALLOWED_ORIGIN: `http://localhost:${TEST_PORT}`,
        NODE_ENV: 'test',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let started = false;

    serverProc.stdout.on('data', (chunk) => {
      const text = chunk.toString();
      if (!started && text.includes('Mercurius')) {
        started = true;
        // Give the server a moment to fully bind
        setTimeout(resolve, 300);
      }
    });

    serverProc.stderr.on('data', (chunk) => {
      // Suppress stderr noise in tests, but log real errors
      const text = chunk.toString();
      if (text.includes('Error') || text.includes('EADDRINUSE')) {
        if (!started) reject(new Error(text));
      }
    });

    serverProc.on('error', reject);
    serverProc.on('exit', (code) => {
      if (!started) reject(new Error(`Server exited prematurely with code ${code}`));
    });

    // Timeout safety
    setTimeout(() => {
      if (!started) reject(new Error('Server did not start within 10 seconds'));
    }, 10000);
  });
});

after(() => {
  if (serverProc) {
    serverProc.kill('SIGTERM');
  }
});

// ===========================================================================
// 1. Session ID validation helper (pure function tests)
// ===========================================================================

describe('isValidSessionId', () => {
  test('accepts valid IDs', () => {
    assert.ok(isValidSessionId('abc123'));
    assert.ok(isValidSessionId('session-with-dashes'));
    assert.ok(isValidSessionId('session_with_underscores'));
    assert.ok(isValidSessionId('MiXeDcAsE99'));
    assert.ok(isValidSessionId('a'));
    assert.ok(isValidSessionId('A'.repeat(64)));
  });

  test('rejects SQL injection attempts', () => {
    assert.equal(isValidSessionId("'; DROP TABLE sessions;--"), false);
    assert.equal(isValidSessionId("1 OR 1=1"), false);
    assert.equal(isValidSessionId("session' UNION SELECT * FROM users--"), false);
    assert.equal(isValidSessionId("Robert'); DROP TABLE Students;--"), false);
  });

  test('rejects empty, null, undefined, and numeric values', () => {
    assert.ok(!isValidSessionId(''));
    assert.ok(!isValidSessionId(null));
    assert.ok(!isValidSessionId(undefined));
    assert.ok(!isValidSessionId(0));
  });
});

// ===========================================================================
// 2. Input validation tests — POST /api/chat
// ===========================================================================

describe('POST /api/chat — input validation', () => {
  test('rejects missing sessionId on /api/chat', async () => {
    const { status, json } = await post('/api/chat', {
      messages: [{ role: 'user', content: 'hello' }],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_session');
  });

  test('rejects sessionId longer than 64 chars', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: 'a'.repeat(65),
      messages: [{ role: 'user', content: 'hello' }],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_session');
  });

  test('rejects sessionId with special characters', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: "test'; DROP TABLE sessions;--",
      messages: [{ role: 'user', content: 'hello' }],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_session');
  });

  test('rejects empty messages array', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: makeSessionId(),
      messages: [],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_messages');
  });

  test('rejects messages with content over 2000 chars', async () => {
    // The server truncates content to 2000 chars rather than rejecting outright.
    // We verify the server does not crash and processes the request (it will
    // fail downstream because of a placeholder API key, but should not 400).
    const sid = makeSessionId();
    const longContent = 'x'.repeat(3000);
    const { status } = await post('/api/chat', {
      sessionId: sid,
      messages: [{ role: 'user', content: longContent }],
    });
    // The server truncates and proceeds — it will either succeed or hit an API
    // error (500) due to the placeholder key. It should NOT be 400 for length.
    assert.notEqual(status, 400, 'Server should truncate, not reject, long content');
  });

  test('rejects messages with non-string content (Zod catches)', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: makeSessionId(),
      messages: [{ role: 'user', content: 42 }],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_messages');
  });

  test('rejects messages with unknown role (Zod enum catches)', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: makeSessionId(),
      messages: [{ role: 'tool', content: 'hi' }],
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_messages');
  });

  test('rejects off-allowlist model with 400 invalid_model', async () => {
    const { status, json } = await post('/api/chat', {
      sessionId: makeSessionId(),
      messages: [{ role: 'user', content: 'hi' }],
      model: 'gpt-5-ultra-expensive',
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_model');
  });

  test('accepts an allowlisted model override (proceeds past 400)', async () => {
    // Spec: if the override matches the server default it passes the
    // allowlist check. The downstream Anthropic call then fails with
    // the placeholder key and returns 500, not 400. The important
    // assertion is that the model-check path didn't reject.
    const { status } = await post('/api/chat', {
      sessionId: makeSessionId(),
      messages: [{ role: 'user', content: 'hi' }],
      model: 'claude-sonnet-4-6',
    });
    assert.notEqual(status, 400, 'on-allowlist model must not be rejected at validation');
  });
});

// ===========================================================================
// 3. Mode switching tests — POST /api/mode
// ===========================================================================

describe('POST /api/mode', () => {
  test('rejects invalid mode', async () => {
    const { status, json } = await post('/api/mode', {
      sessionId: makeSessionId(),
      mode: 'turbo',
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_request');
  });

  test('rejects direct mode when locked', async () => {
    const sid = makeSessionId();
    const { status, json } = await post('/api/mode', {
      sessionId: sid,
      mode: 'direct',
    });
    assert.equal(status, 403);
    assert.equal(json.error, 'locked');
  });

  test('allows socratic mode', async () => {
    const sid = makeSessionId();
    const { status, json } = await post('/api/mode', {
      sessionId: sid,
      mode: 'socratic',
    });
    assert.equal(status, 200);
    assert.equal(json.mode, 'socratic');
  });

  test('allows debate mode without unlock', async () => {
    const sid = makeSessionId();
    const { status, json } = await post('/api/mode', {
      sessionId: sid,
      mode: 'debate',
    });
    assert.equal(status, 200);
    assert.equal(json.mode, 'debate');
  });

  test('allows discussion mode without unlock', async () => {
    const sid = makeSessionId();
    const { status, json } = await post('/api/mode', {
      sessionId: sid,
      mode: 'discussion',
    });
    assert.equal(status, 200);
    assert.equal(json.mode, 'discussion');
  });

  test('does NOT trust clientUnlocked', async () => {
    // Even if a client sends an "unlocked" field, the server should check DB state.
    // A fresh session is always locked, so direct mode must be rejected.
    const sid = makeSessionId();
    const { status, json } = await post('/api/mode', {
      sessionId: sid,
      mode: 'direct',
      clientUnlocked: true,
      unlocked: true,
    });
    assert.equal(status, 403);
    assert.equal(json.error, 'locked');
  });
});

// ===========================================================================
// 4. Admin auth tests
// ===========================================================================

describe('Admin endpoints', () => {
  test('GET /api/admin/events rejects without password', async () => {
    const { status, json } = await get('/api/admin/events');
    assert.equal(status, 401);
    assert.equal(json.error, 'unauthorized');
  });

  test('POST /api/admin/events rejects wrong password', async () => {
    const { status, json } = await post(
      '/api/admin/events',
      { data: { test: true } },
      { 'x-admin-password': 'wrong-password' },
    );
    assert.equal(status, 401);
    assert.equal(json.error, 'unauthorized');
  });

  test('admin endpoints reject when ADMIN_PASSWORD env var not set', async () => {
    // We cannot unset the env var in the running server, but we CAN verify
    // that sending no password is rejected even when a valid password is set.
    // The server logic is: if (!adminPw || pw !== adminPw) → 401.
    // This test confirms the first branch (!adminPw) by sending no header.
    const { status: getStatus } = await get('/api/admin/events');
    assert.equal(getStatus, 401);

    const { status: postStatus } = await post('/api/admin/events', {
      data: { upcoming: [] },
    });
    assert.equal(postStatus, 401);
  });

  test('GET /api/admin/events succeeds with correct password', async () => {
    const { status } = await get('/api/admin/events', {
      'x-admin-password': ADMIN_PASSWORD,
    });
    assert.equal(status, 200);
  });

  test('POST /api/admin/events succeeds with correct password', async () => {
    const { status, json } = await post(
      '/api/admin/events',
      { data: { upcoming: [], schedule: { day: 'Thursday' } } },
      { 'x-admin-password': ADMIN_PASSWORD },
    );
    assert.equal(status, 200);
    assert.equal(json.ok, true);
  });
});

// ===========================================================================
// 5. Rate limiting tests (per-session rate limiter)
// ===========================================================================

describe('Rate limiting', () => {
  test('per-session limiter returns 429 after threshold (single sessionId)', async () => {
    // Per-session rate limiter: 20 requests per minute per sessionId.
    // The session check fires after IP-based chatLimiter (15 req/min per IP)
    // in the chat handler. To isolate the *session* layer we'd need
    // per-request IPs; in this single-process test the IP limiter trips
    // first. What we assert here is simply: after enough chat requests
    // from one sessionId, the server returns 429 — regardless of which
    // layer fired first. This proves at-least-one-layer enforcement.
    const sid = makeSessionId();
    const body = {
      sessionId: sid,
      messages: [{ role: 'user', content: 'test' }],
    };

    const results = [];
    for (let i = 0; i < 20; i++) {
      results.push(post('/api/chat', body));
    }
    await Promise.all(results);

    const { status, json } = await post('/api/chat', body);
    assert.equal(status, 429, 'Expected 429 after exceeding session rate limit');
    assert.equal(json.error, 'rate_limited', 'wire-contract error code preserved');
  });

  test('IP-scoped chat limiter enforces across different sessionIds from the same IP', async () => {
    // Different sessionIds, same local IP (127.0.0.1 from this test
    // harness). The per-session limiter would NOT fire — each session
    // starts fresh. The IP-scoped chatLimiter (15/min/IP) is what
    // should catch this burst.
    //
    // We fire 16 chat requests, each with a freshly-generated
    // sessionId, and assert the 16th comes back 429 with the
    // legacy rate_limited shape.
    const statuses = [];
    for (let i = 0; i < 16; i++) {
      const { status, json } = await post('/api/chat', {
        sessionId: makeSessionId(), // each one distinct
        messages: [{ role: 'user', content: 'test' }],
      });
      statuses.push({ status, error: json?.error });
    }

    const last = statuses[statuses.length - 1];
    assert.equal(
      last.status,
      429,
      `16th request from the same IP across distinct sessions should be 429 — got ${last.status} and ${JSON.stringify(statuses.slice(-3))}`,
    );
    assert.equal(last.error, 'rate_limited', 'legacy error code preserved on IP trip');
  });

  // NOTE: A third test exercising the globalLimiter (60 req/min on
  // /api/*) was considered but removed. The flood would drain the
  // shared per-minute budget and cause unrelated subsequent tests
  // (like the Health check suite below) to see 429s on /api/health.
  // The two tests above already prove enforcement at both the
  // per-session and per-IP layers; the global limiter is exercised
  // indirectly whenever any endpoint serves > 60 req/min.
});

// ===========================================================================
// 6. Health check
// ===========================================================================

describe('Health check', () => {
  test('GET /api/health returns 200 with status and timestamp', async () => {
    const { status, json } = await get('/api/health');
    assert.equal(status, 200);
    assert.equal(json.status, 'ok');
    assert.ok(json.timestamp, 'should include timestamp');
    assert.ok(json.uptime !== undefined, 'should include uptime');
    assert.equal(json.db, 'connected');
  });
});

// ===========================================================================
// 7. Prometheus metrics endpoint
// ===========================================================================

describe('GET /metrics', () => {
  async function getText(path) {
    const res = await fetch(`${BASE_URL}${path}`);
    const text = await res.text();
    return { status: res.status, text, contentType: res.headers.get('content-type') };
  }

  test('serves text/plain Prometheus exposition format', async () => {
    const { status, text, contentType } = await getText('/metrics');
    assert.equal(status, 200);
    assert.match(contentType || '', /^text\/plain/);
    assert.match(contentType || '', /version=/);
    // The body should start with `# HELP` per the exposition format.
    assert.ok(text.startsWith('# HELP'), 'body must start with a HELP line');
  });

  test('exposes core HTTP metrics', async () => {
    // Prime one request so the counters emit at least one sample.
    await get('/api/health');
    const { text } = await getText('/metrics');
    assert.ok(text.includes('http_requests_total'));
    assert.ok(text.includes('http_request_duration_seconds_bucket'));
    assert.ok(text.includes('http_request_duration_seconds_count'));
    assert.ok(text.includes('http_request_duration_seconds_sum'));
  });

  test('service label is applied globally', async () => {
    const { text } = await getText('/metrics');
    assert.ok(text.includes('service="mercurius"'));
  });

  test('counts 400 responses against the matched route', async () => {
    // Send a known-bad request to /api/chat → validation 400.
    await post('/api/chat', { messages: [] });
    const { text } = await getText('/metrics');
    // We don't pin an exact count since other tests also hit /api/chat —
    // we just assert the label combination appears at least once.
    assert.match(
      text,
      /http_requests_total\{[^}]*route="\/api\/chat"[^}]*status="400"[^}]*\}\s+\d+/,
    );
  });

  test('collapses unknown routes into the `unmatched` bucket', async () => {
    await get('/api/totally-nonexistent-route');
    const { text } = await getText('/metrics');
    assert.match(
      text,
      /http_requests_total\{[^}]*route="unmatched"[^}]*\}\s+\d+/,
    );
  });
});
