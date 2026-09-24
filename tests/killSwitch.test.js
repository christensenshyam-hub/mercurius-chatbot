'use strict';

// Tests for the runtime Claude kill switch (audit finding P0-B).
//
//   1. Unit — lib/killSwitch: env boot default, runtime override precedence.
//   2. Unit — persistence: init(db) seeds the override from the settings row
//      (row beats env, no row → env), set() writes through, a failed write
//      keeps the in-memory flip and never throws, state().persisted reports
//      durability. Uses a fake db object against the getSetting/setSetting
//      contract — db.js is never imported here.
//   3. Integration — a server booted with CLAUDE_DISABLED=1 refuses /api/chat
//      with 503 service_disabled (zero Anthropic calls — only the pre-call
//      gate emits that code); the admin endpoint flips it off and back on at
//      runtime with no restart, and rejects unauthenticated callers.

const { describe, test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const killSwitch = require('../lib/killSwitch');

// ---------------------------------------------------------------------------
// Unit — env default + runtime override
// ---------------------------------------------------------------------------
describe('killSwitch flag', () => {
  const saved = process.env.CLAUDE_DISABLED;
  beforeEach(() => killSwitch.__resetForTest());
  after(() => {
    if (saved === undefined) delete process.env.CLAUDE_DISABLED;
    else process.env.CLAUDE_DISABLED = saved;
    killSwitch.__resetForTest();
  });

  test('unset env → not killed', () => {
    delete process.env.CLAUDE_DISABLED;
    assert.equal(killSwitch.isKilled(), false);
    assert.deepEqual(killSwitch.state(), { disabled: false, source: 'env', persisted: false });
  });

  test('CLAUDE_DISABLED=1 → killed at boot', () => {
    process.env.CLAUDE_DISABLED = '1';
    assert.equal(killSwitch.isKilled(), true);
  });

  test('runtime set() overrides the env in both directions', () => {
    process.env.CLAUDE_DISABLED = '1';
    killSwitch.set(false);               // re-enable despite env
    assert.equal(killSwitch.isKilled(), false);
    assert.equal(killSwitch.state().source, 'runtime');
    killSwitch.set(true);                // and kill again
    assert.equal(killSwitch.isKilled(), true);
  });
});

// ---------------------------------------------------------------------------
// Unit — persistence via the settings-row contract
// ---------------------------------------------------------------------------
describe('killSwitch persistence', () => {
  const KEY = 'claude_disabled';
  const saved = process.env.CLAUDE_DISABLED;
  beforeEach(() => killSwitch.__resetForTest());
  after(() => {
    if (saved === undefined) delete process.env.CLAUDE_DISABLED;
    else process.env.CLAUDE_DISABLED = saved;
    killSwitch.__resetForTest();
  });

  // Fake against the db contract the integrator wires up:
  //   getSetting(key) → Promise<string|null>, setSetting(key, value) → Promise<void>
  function fakeDb({ row = null, failWrite = false, failRead = false } = {}) {
    const writes = [];
    return {
      writes,
      async getSetting(key) {
        assert.equal(key, KEY);
        if (failRead) throw new Error('sqlite: table missing');
        return row;
      },
      async setSetting(key, value) {
        assert.equal(key, KEY);
        if (failWrite) throw new Error('sqlite: disk I/O error');
        writes.push(value);
      },
    };
  }

  test('init with row "1" overrides the env default (and "0" re-enables despite env)', async () => {
    delete process.env.CLAUDE_DISABLED;
    await killSwitch.init(fakeDb({ row: '1' }));
    assert.equal(killSwitch.isKilled(), true);
    assert.deepEqual(killSwitch.state(), { disabled: true, source: 'runtime', persisted: true });

    killSwitch.__resetForTest();
    process.env.CLAUDE_DISABLED = '1';
    await killSwitch.init(fakeDb({ row: '0' }));
    assert.equal(killSwitch.isKilled(), false);
    assert.equal(killSwitch.state().source, 'runtime');
  });

  test('init without a row falls through to the env default', async () => {
    process.env.CLAUDE_DISABLED = '1';
    await killSwitch.init(fakeDb());
    assert.equal(killSwitch.isKilled(), true);
    assert.deepEqual(killSwitch.state(), { disabled: true, source: 'env', persisted: false });

    killSwitch.__resetForTest();
    delete process.env.CLAUDE_DISABLED;
    await killSwitch.init(fakeDb());
    assert.equal(killSwitch.isKilled(), false);
    assert.equal(killSwitch.state().source, 'env');
  });

  test('init read failure is swallowed and falls through to env', async () => {
    process.env.CLAUDE_DISABLED = '1';
    await assert.doesNotReject(killSwitch.init(fakeDb({ failRead: true })));
    assert.equal(killSwitch.isKilled(), true);
    assert.deepEqual(killSwitch.state(), { disabled: true, source: 'env', persisted: false });
  });

  test('set() writes through as "1"/"0" when a db is attached', async () => {
    delete process.env.CLAUDE_DISABLED;
    const db = fakeDb();
    await killSwitch.init(db);

    await killSwitch.set(true);
    assert.equal(killSwitch.isKilled(), true);
    assert.deepEqual(db.writes, ['1']);
    assert.equal(killSwitch.state().persisted, true);

    await killSwitch.set(false);
    assert.equal(killSwitch.isKilled(), false);
    assert.deepEqual(db.writes, ['1', '0']);
    assert.equal(killSwitch.state().persisted, true);
  });

  test('set() applies to memory synchronously, before the db write settles', async () => {
    delete process.env.CLAUDE_DISABLED;
    await killSwitch.init(fakeDb());
    const p = killSwitch.set(true);   // deliberately not awaited yet
    assert.equal(killSwitch.isKilled(), true, 'flip must be visible before any await');
    assert.ok(p && typeof p.then === 'function', 'set() returns a Promise');
    await p;
    assert.equal(killSwitch.state().persisted, true);
  });

  test('write failure keeps the in-memory change and never throws', async () => {
    delete process.env.CLAUDE_DISABLED;
    await killSwitch.init(fakeDb({ failWrite: true }));

    await assert.doesNotReject(killSwitch.set(true));
    assert.equal(killSwitch.isKilled(), true, 'Claude must stay killed even if the db write failed');
    assert.deepEqual(killSwitch.state(), { disabled: true, source: 'runtime', persisted: false });

    await assert.doesNotReject(killSwitch.set(false));
    assert.equal(killSwitch.isKilled(), false);
    assert.equal(killSwitch.state().persisted, false);
  });

  test('state().persisted is false with no db attached, true after a successful write', async () => {
    delete process.env.CLAUDE_DISABLED;
    // No init → memory-only mode (how the old sync callers behave).
    await killSwitch.set(true);
    assert.equal(killSwitch.isKilled(), true);
    assert.deepEqual(killSwitch.state(), { disabled: true, source: 'runtime', persisted: false });

    killSwitch.__resetForTest();
    await killSwitch.init(fakeDb());
    await killSwitch.set(true);
    assert.equal(killSwitch.state().persisted, true);
    assert.equal(typeof killSwitch.state().persisted, 'boolean');
  });

  test('__resetForTest() detaches the db', async () => {
    delete process.env.CLAUDE_DISABLED;
    const db = fakeDb();
    await killSwitch.init(db);
    killSwitch.__resetForTest();
    await killSwitch.set(true);
    assert.deepEqual(db.writes, [], 'no write after reset — db reference must be cleared');
    assert.equal(killSwitch.state().persisted, false);
  });
});

// ---------------------------------------------------------------------------
// Integration — 503 when killed; admin endpoint toggles at runtime
// ---------------------------------------------------------------------------
describe('kill switch closes the chat handler and toggles via admin', () => {
  const PORT = 9200 + Math.floor(Math.random() * 700);
  const BASE = `http://localhost:${PORT}`;
  const ADMIN_PW = 'test-admin-' + crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-killswitch-${crypto.randomBytes(4).toString('hex')}.db`);
  let proc;

  const chatBody = () => JSON.stringify({
    sessionId: 'test_' + crypto.randomBytes(6).toString('hex'),
    messages: [{ role: 'user', content: 'hello' }],
  });

  before(async () => {
    await new Promise((resolve, reject) => {
      proc = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: {
          ...process.env,
          PORT: String(PORT),
          CLAUDE_DISABLED: '1',            // boot dark
          ADMIN_PASSWORD: ADMIN_PW,
          ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
          ALLOWED_ORIGIN: `http://localhost:${PORT}`,
          SQLITE_PATH: dbPath,
          NODE_ENV: 'test',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
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
  });

  after(() => {
    if (proc) proc.kill('SIGKILL');
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('booted with CLAUDE_DISABLED=1 → /api/chat 503 service_disabled, no Anthropic call', async () => {
    const res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: chatBody(),
    });
    const json = await res.json().catch(() => null);
    assert.equal(res.status, 503);
    assert.equal(json && json.error, 'service_disabled');
  });

  test('admin toggle requires the password', async () => {
    const res = await fetch(`${BASE}/api/admin/kill-switch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ disabled: false }),
    });
    assert.equal(res.status, 401);
  });

  test('admin can re-enable and re-kill at runtime, no restart', async () => {
    // Re-enable
    let res = await fetch(`${BASE}/api/admin/kill-switch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-admin-password': ADMIN_PW },
      body: JSON.stringify({ disabled: false }),
    });
    let json = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual({ disabled: json.disabled, source: json.source }, { disabled: false, source: 'runtime' });

    // Status endpoint agrees
    res = await fetch(`${BASE}/api/admin/kill-switch`, {
      headers: { 'x-admin-password': ADMIN_PW },
    });
    json = await res.json();
    assert.equal(json.disabled, false);

    // Kill again — chat must 503 immediately
    res = await fetch(`${BASE}/api/admin/kill-switch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-admin-password': ADMIN_PW },
      body: JSON.stringify({ disabled: true }),
    });
    assert.equal(res.status, 200);

    res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: chatBody(),
    });
    json = await res.json().catch(() => null);
    assert.equal(res.status, 503);
    assert.equal(json && json.error, 'service_disabled');
  });

  test('non-boolean payload is rejected', async () => {
    const res = await fetch(`${BASE}/api/admin/kill-switch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-admin-password': ADMIN_PW },
      body: JSON.stringify({ disabled: 'yes' }),
    });
    assert.equal(res.status, 400);
  });
});
