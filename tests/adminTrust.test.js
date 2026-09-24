'use strict';

// End-to-end for the trust + ops rails wired into server.js:
//   POST /api/report (reason / userMessage / context) → admin review queue
//   GET  /api/admin/reports, POST /api/admin/reports/:id/resolve (idempotent)
//   lesson_events start/turn/complete from real chat turns (mocked Anthropic)
//   GET  /api/admin/stats — the founder's weekly numbers + live rails state
//
// Boots the real server once with ANTHROPIC_MOCK=1 and its own SQLite file.
// The admin limiter is 10 req/min per IP, so this file makes < 10 admin calls.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const PORT = 9700 + Math.floor(Math.random() * 200);
const BASE = `http://localhost:${PORT}`;
const ADMIN_PASSWORD = 'test-admin-pw-' + crypto.randomBytes(4).toString('hex');
const dbPath = path.join(os.tmpdir(), `merc-admin-trust-${crypto.randomBytes(4).toString('hex')}.db`);
let proc;

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }
const admin = { 'x-admin-password': ADMIN_PASSWORD };

async function call(method, p, body, headers = {}) {
  const res = await fetch(`${BASE}${p}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

before(async () => {
  await new Promise((resolve, reject) => {
    proc = spawn(process.execPath, ['server.js'], {
      cwd: path.join(__dirname, '..'),
      env: {
        ...process.env,
        PORT: String(PORT),
        DATABASE_URL: '',
        SQLITE_PATH: dbPath,
        ANTHROPIC_MOCK: '1',
        ANTHROPIC_API_KEY: '',
        ADMIN_PASSWORD,
        ALLOWED_ORIGIN: `http://localhost:${PORT}`,
        NODE_ENV: 'test',
        DISCORD_WEBHOOK_URL: '',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let started = false;
    proc.stdout.on('data', (c) => {
      if (!started && c.toString().includes('Mercurius')) { started = true; setTimeout(resolve, 300); }
    });
    proc.stderr.on('data', (c) => {
      const t = c.toString();
      if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
    });
    proc.on('error', reject);
    proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
    setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
  });
});

after(() => {
  if (proc) proc.kill('SIGKILL');
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

describe('content reports → admin review queue', () => {
  test('admin report + stats routes answer 401 without the password', async () => {
    assert.equal((await call('GET', '/api/admin/reports')).status, 401);
    assert.equal((await call('GET', '/api/admin/stats')).status, 401);
  });

  test('a report round-trips with reason, user turn and context, then resolves exactly once', async () => {
    const s = sid();
    const posted = await call('POST', '/api/report', {
      sessionId: s,
      content: 'The model said the moon is made of cheese.',
      reason: 'wrong',
      userMessage: 'What is the moon made of?',
      context: { surface: 'lesson', mode: 'socratic', lessonId: 'u1_l1', appVersion: '2.3.0' },
    });
    assert.equal(posted.status, 200);
    assert.equal(posted.json.ok, true);
    assert.ok(Number.isInteger(posted.json.id), 'report id returned to the client');
    const id = posted.json.id;

    const open = await call('GET', '/api/admin/reports?unresolved=1&limit=10', undefined, admin);
    assert.equal(open.status, 200);
    const row = open.json.reports.find((r) => r.id === id);
    assert.ok(row, 'report is in the open queue');
    assert.equal(row.session_id, s);
    assert.equal(row.reason, 'wrong');
    assert.equal(row.user_message, 'What is the moon made of?');
    assert.deepEqual(row.context, { surface: 'lesson', mode: 'socratic', lessonId: 'u1_l1', appVersion: '2.3.0' });
    assert.equal(row.resolved_at, null);

    const first = await call('POST', `/api/admin/reports/${id}/resolve`, undefined, admin);
    assert.equal(first.status, 200);
    assert.equal(first.json.resolved, true);

    const again = await call('POST', `/api/admin/reports/${id}/resolve`, undefined, admin);
    assert.equal(again.status, 200, 'resolving twice is idempotent, not an error');
    assert.equal(again.json.resolved, false);

    const stillOpen = await call('GET', '/api/admin/reports?unresolved=1&limit=10', undefined, admin);
    assert.ok(!stillOpen.json.reports.some((r) => r.id === id), 'resolved report left the open queue');
  });

  test('a non-integer report id is a 400, not a crash', async () => {
    const res = await call('POST', '/api/admin/reports/abc/resolve', undefined, admin);
    assert.equal(res.status, 400);
    assert.equal(res.json.error, 'invalid_request');
  });
});

describe('lesson events + admin stats', () => {
  test('a lesson start and a completing turn show up in the weekly numbers', async () => {
    const s = sid();
    const opener = '[CURRICULUM: Unit 1, Lesson 1] Teach me what a token is.';

    // Turn 1: exactly one user message on the wire → start + turn.
    const t1 = await call('POST', '/api/chat', { sessionId: s, messages: [{ role: 'user', content: opener }] });
    assert.equal(t1.status, 200, JSON.stringify(t1.json));
    assert.equal(typeof t1.json.reply, 'string');

    // Turn 5: the mock appends [LESSON_COMPLETE] from the 5th user turn on.
    const thread = [{ role: 'user', content: opener }];
    for (let i = 2; i <= 5; i++) {
      thread.push({ role: 'assistant', content: 'Here is the next idea.' });
      thread.push({ role: 'user', content: `Answer ${i}: a token is a chunk of text.` });
    }
    const t5 = await call('POST', '/api/chat', { sessionId: s, messages: thread });
    assert.equal(t5.status, 200, JSON.stringify(t5.json));
    assert.equal(t5.json.lessonComplete, true, 'server judged the lesson complete');
    assert.ok(!String(t5.json.reply).includes('[LESSON_COMPLETE]'), 'marker stripped from the reply');

    await new Promise((r) => setTimeout(r, 300));
    const stats = await call('GET', '/api/admin/stats?days=7', undefined, admin);
    assert.equal(stats.status, 200);
    const j = stats.json;
    assert.equal(j.ok, true);
    assert.equal(j.windowDays, 7);
    assert.ok(Array.isArray(j.perDay) && j.perDay.length === 7, 'one row per day in the window');
    assert.ok(j.lessonsStarted >= 1, `lessonsStarted=${j.lessonsStarted}`);
    assert.ok(j.lessonsCompleted >= 1, `lessonsCompleted=${j.lessonsCompleted}`);
    assert.ok(j.newSessions >= 1);
    assert.equal(typeof j.wau, 'number');
    assert.ok(j.retention && 'd1' in j.retention && 'd7' in j.retention);
    // Live rails state rides along so the Friday check is one call.
    assert.ok(j.budget && typeof j.budget === 'object', 'spend cap state');
    assert.ok(j.killSwitch && typeof j.killSwitch === 'object', 'kill switch state');
    assert.equal(j.draining, false);
    assert.equal(j.scheduler, null, 'scheduler is off under NODE_ENV=test');
  });

  test('days is clamped and non-numeric input falls back to 7', async () => {
    const res = await call('GET', '/api/admin/stats?days=banana', undefined, admin);
    assert.equal(res.status, 200);
    assert.equal(res.json.windowDays, 7);
  });
});
