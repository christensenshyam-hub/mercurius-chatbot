'use strict';

// End-to-end for the trust + ops rails wired into server.js:
//   POST /api/report (reason / userMessage / context) → admin review queue;
//     a report for a session the server has never seen is acknowledged and
//     dropped; a dedicated per-IP bucket (REPORT_IP_PER_MIN, set low here)
//   GET  /api/admin/reports, POST /api/admin/reports/:id/resolve (idempotent;
//     ids are plain decimal digits)
//   lesson_events from real chat turns (mocked Anthropic): one row per
//     answered turn, the opener is the start, complete once per attempt
//   GET  /api/admin/stats — the founder's weekly numbers + live rails state
//
// Boots the real server once with ANTHROPIC_MOCK=1 and its own SQLite file,
// which this process opens through db.js as well to read lesson_events
// directly. The admin limiter is 10 req/min per IP, so the default client
// makes < 10 admin calls; the id-format cases ride a second forwarded
// address (server.js trusts one proxy hop). The report flood test is last
// because it trips the report bucket for the rest of the minute.

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
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');
let proc;

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const admin = { 'x-admin-password': ADMIN_PASSWORD };

async function call(method, p, body, headers = {}) {
  const res = await fetch(`${BASE}${p}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

// /api/mode is the cheapest route that creates the session row.
async function createSession(s) {
  const res = await call('POST', '/api/mode', { sessionId: s, mode: 'socratic' });
  assert.equal(res.status, 200, JSON.stringify(res.json));
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
        // Low enough for the flood test to trip it quickly; the default (60)
        // would not, which is what proves the env knob is honored.
        REPORT_IP_PER_MIN: '12',
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
    await createSession(s);
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

  test('a report for a session the server has never seen is acknowledged and dropped', async () => {
    const marker = 'never-seen-' + crypto.randomBytes(4).toString('hex');
    const posted = await call('POST', '/api/report', { sessionId: sid(), content: marker, reason: 'other' });
    assert.equal(posted.status, 200);
    assert.deepEqual(posted.json, { ok: true }, 'no id: nothing was stored');

    const all = await call('GET', '/api/admin/reports?limit=50', undefined, admin);
    assert.equal(all.status, 200);
    assert.ok(!all.json.reports.some((r) => r.content === marker), 'not in the queue');
    assert.ok(!(await db.listReports({ limit: 50 })).some((r) => r.content === marker), 'not in the table either');
  });

  test('report ids are plain decimal digits: exponents, hex, negatives, overflow and decimals are 400s', async () => {
    // A second admin bucket: server.js trusts one proxy hop, so a forwarded
    // address keeps these calls out of the 10/min the rest of the file uses.
    const other = { ...admin, 'x-forwarded-for': '203.0.113.7' };
    for (const bad of ['abc', '1e21', '0x10', '-1', '1234567890', '1.0', '%201']) {
      const res = await call('POST', `/api/admin/reports/${bad}/resolve`, undefined, other);
      assert.equal(res.status, 400, `${bad} → ${res.status}`);
      assert.equal(res.json.error, 'invalid_request');
    }
    const unknown = await call('POST', '/api/admin/reports/999999999/resolve', undefined, other);
    assert.equal(unknown.status, 200, 'nine digits is the widest accepted id');
    assert.equal(unknown.json.resolved, false);
  });
});

describe('lesson events + admin stats', () => {
  test('one lesson_events row per answered turn: the opener is the start, the pass adds turn + complete, complete once per attempt', async () => {
    const s = sid();
    const opener = '[CURRICULUM: Unit 1, Lesson 1] Teach me what a token is.';
    // The funnel rows are written after the reply, fire-and-forget: give them a beat.
    const events = async () => {
      await sleep(200);
      return (await db.lessonEventsSince(0)).filter((r) => r.session_id === s);
    };

    // Turn 1: exactly one user message on the wire → exactly one row, the start.
    const t1 = await call('POST', '/api/chat', { sessionId: s, messages: [{ role: 'user', content: opener }] });
    assert.equal(t1.status, 200, JSON.stringify(t1.json));
    assert.equal(typeof t1.json.reply, 'string');
    let rows = await events();
    assert.deepEqual(rows.map((r) => [r.event, r.turn_index, r.lesson_id]), [['start', 1, 'u1_l1']]);

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
    rows = await events();
    assert.deepEqual(rows.map((r) => [r.event, r.turn_index]), [['start', 1], ['turn', 5], ['complete', 5]]);

    // The iOS client keeps a passed lesson's thread open: the same request
    // again is one more turn, not a second completion.
    const again = await call('POST', '/api/chat', { sessionId: s, messages: thread });
    assert.equal(again.status, 200, JSON.stringify(again.json));
    assert.equal(again.json.lessonComplete, true, 'the client is still told it passed');
    rows = await events();
    assert.deepEqual(rows.map((r) => r.event), ['start', 'turn', 'complete', 'turn']);

    const stats = await call('GET', '/api/admin/stats?days=7', undefined, admin);
    assert.equal(stats.status, 200);
    const j = stats.json;
    assert.equal(j.ok, true);
    assert.equal(j.windowDays, 7);
    assert.ok(Array.isArray(j.perDay) && j.perDay.length === 7, 'one row per day in the window');
    assert.equal(j.lessonsStarted, 1, 'one start for one opener');
    assert.equal(j.lessonsCompleted, 1, 'completions count passes, not turns after the pass');
    assert.equal(j.lessonsAbandoned, 0);
    assert.ok(j.newSessions >= 1);
    assert.equal(typeof j.wau, 'number');
    assert.ok(j.retention && 'd1' in j.retention && 'd7' in j.retention);
    // Live rails state rides along so the Friday check is one call.
    assert.ok(j.budget && typeof j.budget === 'object', 'spend cap state');
    assert.ok(j.killSwitch && typeof j.killSwitch === 'object', 'kill switch state');
    assert.equal(j.draining, false);
    assert.equal(j.scheduler, null, 'scheduler is off under NODE_ENV=test');
  });

  test('a lesson thread with no assistant turn yet is a start, even with two user messages on the wire', async () => {
    // The opener got no reply (stop / timeout / refusal) and the student typed
    // on instead of tapping Retry: [opener, turn] is still the first answered
    // turn, so it must be the start — otherwise the lesson could complete
    // without starting and could never count as abandoned.
    const s = sid();
    const res = await call('POST', '/api/chat', {
      sessionId: s,
      messages: [
        { role: 'user', content: '[CURRICULUM: Unit 1, Lesson 2] Teach me about context windows.' },
        { role: 'user', content: 'Answer 2: I think it is how much text the model can see at once.' },
      ],
    });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    await sleep(200);
    const rows = (await db.lessonEventsSince(0)).filter((r) => r.session_id === s);
    assert.deepEqual(rows.map((r) => [r.event, r.turn_index, r.lesson_id]), [['start', 2, 'u1_l2']]);
  });

  test('days is clamped and non-numeric input falls back to 7', async () => {
    const res = await call('GET', '/api/admin/stats?days=banana', undefined, admin);
    assert.equal(res.status, 200);
    assert.equal(res.json.windowDays, 7);
  });
});

describe('POST /api/report flood', () => {
  test('the dedicated per-IP bucket (REPORT_IP_PER_MIN) trips long before the global limiter would', async () => {
    const s = sid();
    await createSession(s);
    const statuses = [];
    // Two reports were already posted above; 16 more clears the 12/min set
    // for this server, while the 400/min global bucket is nowhere near.
    for (let i = 0; i < 16; i++) {
      const r = await call('POST', '/api/report', { sessionId: s, content: `flood ${i}`, reason: 'other' });
      statuses.push(r.status);
      if (r.status === 429) assert.equal(r.json.error, 'rate_limited');
    }
    assert.equal(statuses[0], 200);
    assert.ok(statuses.includes(429), `expected a 429 in ${JSON.stringify(statuses)}`);
    assert.equal(statuses.at(-1), 429, 'stays tripped');
  });
});
