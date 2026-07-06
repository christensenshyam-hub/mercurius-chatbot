'use strict';

/**
 * Standby gamification (quiet progress) — Phase 1 test suite.
 *
 * Three layers:
 *   1. Pure modules (level curve, reasons registry) — no I/O.
 *   2. The XP service against a fake db — deterministic idempotency/caps/
 *      diminishing-returns/level-up logic, and the LEVEL ≠ RANK invariant.
 *   3. Integration: spawn the real server.js against a throwaway SQLite, with
 *      the flag ON and OFF, asserting the wire contract + that the flag-off
 *      path creates no tables and the flag-on path never mutates `rank`.
 */

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const SERVER_DIR = path.join(__dirname, '..');

const reasons = require('../lib/gamification/reasons');
const level = require('../lib/gamification/level');
const xp = require('../lib/gamification/xp');

// ─────────────────────────── helpers ───────────────────────────

function makeSessionId() {
  return 'test_' + crypto.randomBytes(8).toString('hex');
}

function tmpDbPath() {
  return path.join(os.tmpdir(), `merc-gam-${crypto.randomBytes(6).toString('hex')}.db`);
}

function cleanupDb(p) {
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.unlinkSync(p + suffix); } catch (_) { /* ignore */ }
  }
}

function startServer({ port, gamification, sqlitePath }) {
  return new Promise((resolve, reject) => {
    const proc = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: {
        ...process.env,
        PORT: String(port),
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
        ALLOWED_ORIGIN: `http://localhost:${port}`,
        NODE_ENV: 'test',
        DATABASE_URL: '', // force the SQLite driver regardless of the parent env
        SQLITE_PATH: sqlitePath,
        ...(gamification ? { GAMIFICATION_ENABLED: '1' } : {}),
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let started = false;
    proc.stdout.on('data', (chunk) => {
      if (!started && chunk.toString().includes('Mercurius')) {
        started = true;
        resolve(proc);
      }
    });
    proc.stderr.on('data', () => { /* swallow */ });
    proc.on('error', reject);
    setTimeout(() => { if (!started) reject(new Error('server start timeout')); }, 15000);
  });
}

function stopServer(proc) {
  return new Promise((resolve) => {
    if (!proc) return resolve();
    proc.on('exit', () => resolve());
    proc.kill('SIGTERM');
    setTimeout(() => { try { proc.kill('SIGKILL'); } catch (_) {} resolve(); }, 3000);
  });
}

function makeClient(port) {
  const base = `http://localhost:${port}`;
  return {
    async get(p) {
      const r = await fetch(base + p);
      return { status: r.status, json: await r.json().catch(() => null) };
    },
    async post(p, body) {
      const r = await fetch(base + p, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      return { status: r.status, json: await r.json().catch(() => null) };
    },
  };
}

// ─────────────────────── 1. pure modules ───────────────────────

describe('gamification — level curve', () => {
  test('level 1 = 0 xp; 0 xp = level 1', () => {
    assert.equal(level.xpForLevel(1), 0);
    assert.equal(level.levelForXp(0), 1);
  });
  test('round-trips and is strictly monotonic', () => {
    for (let L = 1; L <= 50; L++) assert.equal(level.levelForXp(level.xpForLevel(L)), L);
    for (let L = 1; L < 50; L++) assert.ok(level.xpForLevel(L + 1) > level.xpForLevel(L));
  });
  test('caps at MAX_LEVEL with xpToNext 0 and progress 1', () => {
    assert.equal(level.levelForXp(1e12), 50);
    assert.equal(level.xpToNext(level.xpForLevel(50)), 0);
    assert.equal(level.progressPercent(level.xpForLevel(50)), 1);
  });
});

describe('gamification — reasons', () => {
  test('exactly the seven engagement reasons are valid', () => {
    assert.equal(reasons.ALL_REASONS.length, 7);
    assert.ok(reasons.isValidReason('MODULE_COMPLETED'));
    assert.ok(reasons.isValidReason('CLARIFYING_QUESTION'));
  });
  test('correctness / volume / time are NOT reasons', () => {
    assert.ok(!reasons.isValidReason('CORRECT_ANSWER'));
    assert.ok(!reasons.isValidReason('MESSAGE_SENT'));
    assert.ok(!reasons.isValidReason('TIME_SPENT'));
  });
  test('diminishing multiplier clamps to [last]', () => {
    assert.equal(reasons.diminishingMultiplier(0), 1);
    assert.equal(reasons.diminishingMultiplier(99), 0.15);
  });
});

// ───────────────── 2. XP service against a fake db ─────────────────

function fakeDb() {
  const ledger = [];
  const prog = new Map();
  let rankWrites = 0;
  return {
    ledger,
    rankWrites: () => rankWrites,
    async ensureProgression(sid) {
      if (!prog.has(sid)) prog.set(sid, { session_id: sid, xp: 0, current_streak: 0, longest_streak: 0, rank: 'copper' });
    },
    async getProgression(sid) { return prog.get(sid) || null; },
    async updateProgression(sid, fields) {
      if ('rank' in fields) rankWrites++; // must NEVER happen
      const p = prog.get(sid); p.xp = fields.xp;
    },
    async recordXpEvent(e) {
      if (e.sourceId != null && ledger.some((r) => r.sessionId === e.sessionId && r.sourceType === e.sourceType && r.sourceId === e.sourceId)) {
        return { inserted: false };
      }
      ledger.push(e);
      return { inserted: true };
    },
    async countXpEvents(sid, reason, { sinceTs = null, sessionRef = null } = {}) {
      return ledger.filter((r) => r.sessionId === sid && r.reason === reason
        && (sinceTs == null || r.createdAt >= sinceTs)
        && (sessionRef == null || r.sessionRef === sessionRef)).length;
    },
    async sumXp(sid) { return ledger.filter((r) => r.sessionId === sid).reduce((a, r) => a + r.amount, 0); },
  };
}

describe('gamification — XP service (fake db)', () => {
  const now = Date.parse('2026-06-14T12:00:00Z');

  test('module completion awards once; replay is idempotent', async () => {
    const db = fakeDb();
    const a = await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm1', now });
    const b = await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm1', now });
    assert.equal(a.status, 'awarded');
    assert.equal(a.awarded, 60);
    assert.equal(b.status, 'idempotent');
    assert.equal(b.awarded, 0);
    assert.equal(db.ledger.length, 1);
  });

  test('idempotent reason requires a source id', async () => {
    const r = await xp.awardXp(fakeDb(), { sessionId: 's', reason: 'MODULE_COMPLETED', now });
    assert.equal(r.status, 'missing_source_id');
  });

  test('per-day cap blocks the second daily return', async () => {
    const db = fakeDb();
    const a = await xp.awardXp(db, { sessionId: 's', reason: 'DAILY_RETURN', sourceId: 'd1', now });
    const b = await xp.awardXp(db, { sessionId: 's', reason: 'DAILY_RETURN', sourceId: 'd2', now });
    assert.equal(a.status, 'awarded');
    assert.equal(b.status, 'capped_day');
  });

  test('diminishing returns shrink repeated low-effort moves', async () => {
    const db = fakeDb();
    const amts = [];
    for (let i = 0; i < 3; i++) {
      amts.push((await xp.awardXp(db, { sessionId: 's', reason: 'CLARIFYING_QUESTION', now: now + i })).awarded);
    }
    assert.equal(amts[0], 6);
    assert.ok(amts[1] < amts[0] && amts[2] < amts[1], `expected shrinking, got ${JSON.stringify(amts)}`);
  });

  test('crossing the threshold levels up', async () => {
    const db = fakeDb();
    await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm1', now });
    const r = await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm2', now });
    assert.equal(r.xp, 120);
    assert.equal(r.level, 2);
    assert.equal(r.leveledUp, true);
  });

  test('the XP service NEVER writes rank (Level ≠ Rank)', async () => {
    const db = fakeDb();
    await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm1', now });
    await xp.awardXp(db, { sessionId: 's', reason: 'MODULE_COMPLETED', sourceId: 'm2', now });
    assert.equal(db.rankWrites(), 0);
  });

  test('an invalid reason is rejected', async () => {
    const r = await xp.awardXp(fakeDb(), { sessionId: 's', reason: 'CORRECT_ANSWER', sourceId: 'x', now });
    assert.equal(r.ok, false);
    assert.equal(r.status, 'invalid_reason');
  });
});

// ──────────────── 3a. integration — routes, flag ON ────────────────

describe('gamification — routes, flag ON', () => {
  const PORT = 9300 + Math.floor(Math.random() * 300);
  const dbPath = tmpDbPath();
  let proc, client;

  before(async () => {
    proc = await startServer({ port: PORT, gamification: true, sqlitePath: dbPath });
    client = makeClient(PORT);
  });
  after(async () => { await stopServer(proc); cleanupDb(dbPath); });

  test('GET /me on a fresh session → enabled, level 1, 0 xp', async () => {
    const r = await client.get(`/api/progression/me?sessionId=${makeSessionId()}`);
    assert.equal(r.status, 200);
    assert.equal(r.json.enabled, true);
    assert.equal(r.json.xp, 0);
    assert.equal(r.json.level, 1);
  });

  test('POST /event module completion awards 50; replay is idempotent', async () => {
    const sid = makeSessionId();
    const a = await client.post('/api/progression/event', { sessionId: sid, reason: 'MODULE_COMPLETED', sourceType: 'module', sourceId: 'u01' });
    assert.equal(a.status, 200);
    assert.equal(a.json.enabled, true);
    assert.equal(a.json.status, 'awarded');
    assert.equal(a.json.awarded, 60);
    const b = await client.post('/api/progression/event', { sessionId: sid, reason: 'MODULE_COMPLETED', sourceType: 'module', sourceId: 'u01' });
    assert.equal(b.json.status, 'idempotent');
    assert.equal(b.json.awarded, 0);
  });

  test('POST /event with an invalid reason → 400', async () => {
    const r = await client.post('/api/progression/event', { sessionId: makeSessionId(), reason: 'CORRECT_ANSWER' });
    assert.equal(r.status, 400);
  });

  test('per-day cap blocks a second daily return', async () => {
    const sid = makeSessionId();
    const a = await client.post('/api/progression/event', { sessionId: sid, reason: 'DAILY_RETURN', sourceType: 'daily', sourceId: 'day-a' });
    const b = await client.post('/api/progression/event', { sessionId: sid, reason: 'DAILY_RETURN', sourceType: 'daily', sourceId: 'day-b' });
    assert.equal(a.json.status, 'awarded');
    assert.equal(b.json.status, 'capped_day');
  });

  test('Level ≠ Rank: rank stays "copper" in the DB after XP + a level-up', async () => {
    const sid = makeSessionId();
    await client.post('/api/progression/event', { sessionId: sid, reason: 'MODULE_COMPLETED', sourceType: 'module', sourceId: 'r1' });
    await client.post('/api/progression/event', { sessionId: sid, reason: 'MODULE_COMPLETED', sourceType: 'module', sourceId: 'r2' });
    const me = await client.get(`/api/progression/me?sessionId=${sid}`);
    assert.equal(me.json.level, 2); // engagement advanced…

    // …but inspect the real DB the server wrote: rank must be untouched.
    const Database = require('better-sqlite3');
    const ro = new Database(dbPath, { readonly: true });
    const row = ro.prepare('SELECT xp, level, rank FROM progression WHERE session_id = ?').get(sid);
    ro.close();
    assert.equal(row.rank, 'copper');
    assert.equal(row.xp, 120);
  });
});

// ──────────────── 3b. integration — routes, flag OFF ───────────────

describe('gamification — routes, flag OFF (default)', () => {
  const PORT = 9650 + Math.floor(Math.random() * 300);
  const dbPath = tmpDbPath();
  let proc, client;

  before(async () => {
    proc = await startServer({ port: PORT, gamification: false, sqlitePath: dbPath });
    client = makeClient(PORT);
  });
  after(async () => { await stopServer(proc); cleanupDb(dbPath); });

  test('GET /me → { enabled: false }', async () => {
    const r = await client.get(`/api/progression/me?sessionId=${makeSessionId()}`);
    assert.equal(r.status, 200);
    assert.deepEqual(r.json, { enabled: false });
  });

  test('POST /event → { enabled: false }, no award', async () => {
    const r = await client.post('/api/progression/event', { sessionId: makeSessionId(), reason: 'MODULE_COMPLETED', sourceId: 'x' });
    assert.equal(r.status, 200);
    assert.equal(r.json.enabled, false);
  });

  test('flag OFF created NO gamification tables', async () => {
    const Database = require('better-sqlite3');
    const ro = new Database(dbPath, { readonly: true });
    const tables = ro.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => r.name);
    ro.close();
    assert.ok(!tables.includes('progression'), 'progression table must not exist when flag is off');
    assert.ok(!tables.includes('xp_ledger'), 'xp_ledger table must not exist when flag is off');
  });
});
