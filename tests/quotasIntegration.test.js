'use strict';

/**
 * End-to-end: the real server booted with ANTHROPIC_MOCK=1 (no key), tight
 * quota env, and a throwaway SQLite file.
 *
 *   1. A streamed chat turn reaches [DONE] with keepalive comments, and the
 *      call lands in the `usage` ledger priced and marked ok.
 *   2. Daily per-session turns are enforced (429 daily_limit, scope session).
 *   3. New session ids per IP are capped (429 daily_limit, scope ip) — the
 *      id-rotation bypass is closed.
 *   4. /metrics is admin-only and carries the cost counters.
 *   5. SIGTERM drains: an in-flight stream finishes, new model work is
 *      refused with 503 restarting, and the process exits 0.
 */

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const ROOT = path.join(__dirname, '..');

function spawnServer(extraEnv = {}) {
  const PORT = 9300 + Math.floor(Math.random() * 600);
  const dbPath = path.join(os.tmpdir(), `merc-quotas-${crypto.randomBytes(4).toString('hex')}.db`);
  const ADMIN_PW = 'test-admin-' + crypto.randomBytes(4).toString('hex');
  const proc = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env: {
      ...process.env,
      PORT: String(PORT),
      ADMIN_PASSWORD: ADMIN_PW,
      ANTHROPIC_MOCK: '1',
      MOCK_STREAM_DELAY_MS: '1',
      ANTHROPIC_API_KEY: 'sk-ant-test-placeholder',
      ALLOWED_ORIGIN: `http://localhost:${PORT}`,
      SQLITE_PATH: dbPath,
      NODE_ENV: 'test',
      DISCORD_WEBHOOK_URL: '',
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const ready = new Promise((resolve, reject) => {
    let started = false;
    proc.stdout.on('data', (c) => {
      if (!started && c.toString().includes('Mercurius')) {
        started = true;
        setTimeout(resolve, 300);
      }
    });
    proc.stderr.on('data', (c) => {
      const t = c.toString();
      if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
    });
    proc.on('error', reject);
    proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
    setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
  });
  const cleanup = () => {
    if (proc.exitCode === null) proc.kill('SIGKILL');
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
    }
  };
  return { proc, ready, cleanup, base: `http://localhost:${PORT}`, adminPw: ADMIN_PW, dbPath };
}

const newSession = () => 'sess_' + crypto.randomBytes(6).toString('hex');

async function chatJson(base, sessionId, content = 'What is a token?') {
  const res = await fetch(`${base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages: [{ role: 'user', content }] }),
  });
  return { status: res.status, json: await res.json().catch(() => null), headers: res.headers };
}

/** Streams a chat turn; resolves with the raw body and parsed data frames. */
async function chatSse(base, sessionId, { onFirstDelta } = {}) {
  const res = await fetch(`${base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sessionId, messages: [{ role: 'user', content: 'Explain a token.' }] }),
  });
  if (res.status !== 200) return { status: res.status, json: await res.json().catch(() => null) };
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let raw = '';
  let firedFirst = false;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    raw += decoder.decode(value, { stream: true });
    if (!firedFirst && raw.includes('"type":"delta"') && onFirstDelta) {
      firedFirst = true;
      await onFirstDelta();
    }
  }
  const frames = raw.split('\n').filter((l) => l.startsWith('data: ')).map((l) => l.slice(6));
  const events = frames.filter((f) => f !== '[DONE]').map((f) => JSON.parse(f));
  return { status: 200, raw, events, done: frames.includes('[DONE]') };
}

function readUsage(dbPath) {
  const Database = require('better-sqlite3');
  const sqlite = new Database(dbPath, { readonly: true });
  try {
    return sqlite.prepare('SELECT status, route, kind, cost_usd, output_tokens FROM usage ORDER BY ts').all();
  } finally {
    sqlite.close();
  }
}

// ---------------------------------------------------------------------------
describe('quotas end-to-end (mock upstream)', () => {
  const srv = spawnServer({
    SESSION_DAILY_CHAT_TURNS: '2',
    SESSION_DAILY_LESSON_TURNS: '2',
    IP_DAILY_NEW_SESSIONS: '3',
  });
  const sessionA = newSession();

  before(() => srv.ready);
  after(() => srv.cleanup());

  test('a streamed turn reaches [DONE] with keepalive comments and lands in the ledger', async () => {
    const out = await chatSse(srv.base, sessionA);
    assert.equal(out.status, 200);
    assert.ok(out.raw.startsWith(': connected'), 'keepalive comment frame precedes data');
    assert.ok(out.events.some((e) => e.type === 'delta'), 'deltas streamed');
    const complete = out.events.find((e) => e.type === 'complete');
    assert.ok(complete, 'complete frame present');
    assert.equal(complete.sessionId, sessionA);
    assert.ok(!('difficulty' in complete), 'dead personalization field is gone');
    assert.ok(out.done, '[DONE] terminator');

    await new Promise((r) => setTimeout(r, 200));
    const rows = readUsage(srv.dbPath);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].status, 'ok');
    assert.equal(rows[0].route, '/api/chat');
    assert.equal(rows[0].kind, 'chat');
    assert.ok(rows[0].cost_usd > 0, 'priced');
    assert.ok(rows[0].output_tokens > 0);
  });

  test('a JSON turn works too and the session hits its daily chat-turn quota on the third', async () => {
    const second = await chatJson(srv.base, sessionA);
    assert.equal(second.status, 200, JSON.stringify(second.json));
    assert.ok(second.json.reply.length > 0);
    assert.ok(!('difficulty' in second.json));

    const third = await chatJson(srv.base, sessionA);
    assert.equal(third.status, 429);
    assert.equal(third.json.error, 'daily_limit');
    assert.equal(third.json.scope, 'session');
    assert.ok(third.json.retryAfterSec > 0);
    assert.ok(third.headers.get('retry-after'), 'Retry-After header set');
    assert.match(third.json.message, /tomorrow/i);
  });

  test('rotating session ids trips the per-IP new-session cap', async () => {
    // sessionA was the first new session; two more are allowed, the fourth is not.
    const b = await chatJson(srv.base, newSession());
    assert.equal(b.status, 200);
    const c = await chatJson(srv.base, newSession());
    assert.equal(c.status, 200);
    const d = await chatJson(srv.base, newSession());
    assert.equal(d.status, 429);
    assert.equal(d.json.error, 'daily_limit');
    assert.equal(d.json.scope, 'ip');
  });

  test('/metrics is admin-only and carries cost + in-flight series', async () => {
    const anon = await fetch(`${srv.base}/metrics`);
    assert.equal(anon.status, 401);
    const res = await fetch(`${srv.base}/metrics`, { headers: { 'x-admin-password': srv.adminPw } });
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.match(text, /anthropic_cost_usd_total\{[^}]*route="\/api\/chat"[^}]*\}\s+[0-9.e-]+/);
    assert.match(text, /anthropic_tokens_total\{[^}]*kind="output"[^}]*\}\s+\d+/);
    assert.match(text, /inflight_model_calls(\{[^}]*\})?\s+0\b/);
    assert.match(text, /quota_rejections_total\{[^}]*scope="session:daily_limit"[^}]*\}\s+\d+/);
  });

  test('GET /api/session returns only the summary the client reads', async () => {
    const res = await fetch(`${srv.base}/api/session/${sessionA}`);
    const json = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(json), ['stats']);
    assert.deepEqual(Object.keys(json.stats.session).sort(), ['last_session_date', 'message_count', 'mode', 'streak']);
    assert.ok(!('recentMessages' in json));
  });
});

// ---------------------------------------------------------------------------
describe('SIGTERM drains in-flight streams', () => {
  const srv = spawnServer({ MOCK_STREAM_DELAY_MS: '40' });
  before(() => srv.ready);
  after(() => srv.cleanup());

  test('an open stream finishes, new work is refused, and the process exits 0', async () => {
    const exited = new Promise((resolve) => srv.proc.on('exit', (code) => resolve(code)));
    let duringDrain = null;
    const out = await chatSse(srv.base, newSession(), {
      onFirstDelta: async () => {
        srv.proc.kill('SIGTERM');
        await new Promise((r) => setTimeout(r, 50));
        duringDrain = await chatJson(srv.base, newSession()).catch(() => ({ status: 'conn-refused' }));
      },
    });
    assert.ok(out.done, 'the in-flight stream reached [DONE] after SIGTERM');
    assert.ok(out.events.some((e) => e.type === 'complete'));
    // Either the gate answered 503 restarting, or the listener had already
    // closed (connection refused) — both mean no new model work started.
    assert.ok(
      (duringDrain && duringDrain.status === 503 && duringDrain.json && duringDrain.json.error === 'restarting')
        || (duringDrain && duringDrain.status === 'conn-refused'),
      `unexpected during-drain response: ${JSON.stringify(duringDrain)}`,
    );
    const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r('timeout'), 8000))]);
    assert.equal(code, 0, 'process exited cleanly after drain');
  });
});
