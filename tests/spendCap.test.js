'use strict';

// Tests for the global daily spend ceiling (audit finding P0-A).
//
//   1. Unit — the in-memory counter (lib/spendCap): accumulation, the ceiling
//      flip, the missing-usage fallback, the 0 = closed lever.
//   2. Integration — with the counter forced above the limit
//      (DAILY_TOKEN_CEILING=0), POST /api/chat returns 503 and makes ZERO
//      Anthropic calls. "Zero calls" is proven by the response body: the only
//      code path that emits error==='spend_cap' is the pre-call gate, so a
//      real attempt (which would surface a different 5xx under the placeholder
//      key) never produces it.

const { describe, test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const spendCap = require('../lib/spendCap');

// ---------------------------------------------------------------------------
// Unit — the in-memory daily counter
// ---------------------------------------------------------------------------
describe('spendCap counter', () => {
  const savedCeiling = process.env.DAILY_TOKEN_CEILING;
  beforeEach(() => spendCap.__resetForTest());
  after(() => {
    if (savedCeiling === undefined) delete process.env.DAILY_TOKEN_CEILING;
    else process.env.DAILY_TOKEN_CEILING = savedCeiling;
    spendCap.__resetForTest();
  });

  test('under the ceiling → not exceeded', () => {
    process.env.DAILY_TOKEN_CEILING = '1000';
    spendCap.recordUsage({ input_tokens: 100, output_tokens: 100 });
    assert.equal(spendCap.currentTokens(), 200);
    assert.equal(spendCap.isCeilingExceeded(), false);
  });

  test('recording usage above the ceiling flips isCeilingExceeded()', () => {
    process.env.DAILY_TOKEN_CEILING = '150';
    spendCap.recordUsage({ input_tokens: 100, output_tokens: 100 }); // 200 >= 150
    assert.equal(spendCap.isCeilingExceeded(), true);
  });

  test('missing usage falls back to the estimate (call sites without usage)', () => {
    process.env.DAILY_TOKEN_CEILING = '50';
    spendCap.recordUsage(undefined, 80); // no usage object → estimate counted
    assert.equal(spendCap.currentTokens(), 80);
    assert.equal(spendCap.isCeilingExceeded(), true);
  });

  test('ceiling of 0 refuses immediately with nothing recorded', () => {
    process.env.DAILY_TOKEN_CEILING = '0';
    assert.equal(spendCap.currentTokens(), 0);
    assert.equal(spendCap.isCeilingExceeded(), true);
  });

  test('unset ceiling uses the high default (open)', () => {
    delete process.env.DAILY_TOKEN_CEILING;
    spendCap.recordUsage({ input_tokens: 1000, output_tokens: 1000 });
    assert.equal(spendCap.isCeilingExceeded(), false);
  });
});

// ---------------------------------------------------------------------------
// Integration — the chat handler 503s and makes zero Anthropic calls
// ---------------------------------------------------------------------------
describe('spend ceiling closes the chat handler', () => {
  const PORT = 9200 + Math.floor(Math.random() * 700);
  const BASE = `http://localhost:${PORT}`;
  const dbPath = path.join(os.tmpdir(), `merc-spendcap-${crypto.randomBytes(4).toString('hex')}.db`);
  let proc;

  before(async () => {
    await new Promise((resolve, reject) => {
      proc = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: {
          ...process.env,
          PORT: String(PORT),
          DAILY_TOKEN_CEILING: '0', // ceiling closed → the first call is refused
          ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
          ALLOWED_ORIGIN: `http://localhost:${PORT}`,
          SQLITE_PATH: dbPath, // throwaway db — never touch the real mercurius.db
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

  test('POST /api/chat → 503 spend_cap, never invoking Anthropic', async () => {
    const res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sessionId: 'test_' + crypto.randomBytes(6).toString('hex'),
        messages: [{ role: 'user', content: 'hello' }],
      }),
    });
    const json = await res.json().catch(() => null);
    assert.equal(res.status, 503, 'handler must 503 when the ceiling is closed');
    assert.ok(
      json && json.error === 'spend_cap',
      `expected {error:'spend_cap'} (proves the pre-call gate fired, no Anthropic call), got ${JSON.stringify(json)}`
    );
  });
});
