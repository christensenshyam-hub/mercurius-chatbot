'use strict';

// Tests for the global daily spend cap (audit finding P0-A), now denominated
// in US dollars.
//
//   1. Unit — the in-memory USD accumulator (lib/spendCap): pricing by model,
//      the cache weighting (read 0.1×, write 1.25×), the estimate fallback for
//      calls that never yield a usage object, both recordUsage shapes, hydrate
//      only ever raising, the UTC-midnight rollover, and DAILY_BUDGET_USD=0 as
//      the "closed" lever.
//   2. Integration — with the budget forced to zero (DAILY_BUDGET_USD=0),
//      POST /api/chat returns 503 and makes ZERO Anthropic calls. "Zero calls"
//      is proven by the response body: the only code path that emits
//      error==='spend_cap' is the pre-call gate, so a real attempt (which
//      would surface a different 5xx under the placeholder key) never
//      produces it.

const { describe, test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');

const spendCap = require('../lib/spendCap');
const { PRICES } = require('../lib/pricing');

const SONNET = PRICES['claude-sonnet-4-6'];
const HAIKU = PRICES['claude-haiku-4-5'];
const M = 1_000_000;

function close(actual, expected, msg) {
  assert.ok(Math.abs(actual - expected) < 1e-9, msg || `expected ${expected}, got ${actual}`);
}

// ---------------------------------------------------------------------------
// Unit — the in-memory daily USD accumulator
// ---------------------------------------------------------------------------
describe('spendCap USD accumulator', () => {
  const savedBudget = process.env.DAILY_BUDGET_USD;
  beforeEach(() => spendCap.__resetForTest());
  after(() => {
    if (savedBudget === undefined) delete process.env.DAILY_BUDGET_USD;
    else process.env.DAILY_BUDGET_USD = savedBudget;
    spendCap.__resetForTest();
  });

  // --- budget env -----------------------------------------------------------

  test('unset budget uses the $15 default (open)', () => {
    delete process.env.DAILY_BUDGET_USD;
    assert.equal(spendCap.budgetUsd(), 15);
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M, output_tokens: 100_000 } }); // $4.50
    assert.equal(spendCap.isCeilingExceeded(), false);
  });

  test('invalid budget values fall back to the default', () => {
    for (const bad of ['abc', '-3', 'Infinity', '']) {
      process.env.DAILY_BUDGET_USD = bad;
      assert.equal(spendCap.budgetUsd(), 15, `DAILY_BUDGET_USD=${JSON.stringify(bad)}`);
    }
  });

  test('DAILY_BUDGET_USD=0 refuses immediately with nothing recorded', () => {
    process.env.DAILY_BUDGET_USD = '0';
    assert.equal(spendCap.budgetUsd(), 0);
    assert.equal(spendCap.currentUsd(), 0);
    assert.equal(spendCap.isCeilingExceeded(), true);
    assert.equal(spendCap.fraction(), 1, 'budget 0 → fraction 1');
  });

  // --- pricing --------------------------------------------------------------

  test('under the budget → not exceeded; dollars match the Sonnet card', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M, output_tokens: 100_000 } });
    close(spendCap.currentUsd(), 3 + 1.5);
    close(spendCap.fraction(), 0.45);
    assert.equal(spendCap.isCeilingExceeded(), false);
  });

  test('recording past the budget flips isCeilingExceeded()', () => {
    process.env.DAILY_BUDGET_USD = '4';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M, output_tokens: 100_000 } }); // $4.50 >= $4
    assert.equal(spendCap.isCeilingExceeded(), true);
    assert.ok(spendCap.fraction() > 1, 'fraction is not clamped');
  });

  test('Haiku calls are priced at Haiku rates', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-haiku-4-5-20251001', usage: { input_tokens: M, output_tokens: M } });
    close(spendCap.currentUsd(), HAIKU.in + HAIKU.out); // $6, not Sonnet's $18
  });

  test('cache reads are weighted at 0.1× the input rate', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { cache_read_input_tokens: M } });
    close(spendCap.currentUsd(), SONNET.in * 0.1); // $0.30
    assert.deepEqual(spendCap.state().tokens, { input: 0, output: 0, cacheRead: M, cacheWrite: 0 });
  });

  test('cache writes are weighted at 1.25× the input rate', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { cache_creation_input_tokens: M } });
    close(spendCap.currentUsd(), SONNET.in * 1.25); // $3.75
    assert.deepEqual(spendCap.state().tokens, { input: 0, output: 0, cacheRead: 0, cacheWrite: M });
  });

  test('a cached prefix costs a tenth of the same prefix uncached', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: 50_000 } });
    const uncached = spendCap.currentUsd();
    spendCap.__resetForTest();
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { cache_read_input_tokens: 50_000 } });
    close(spendCap.currentUsd(), uncached / 10);
  });

  test('accumulates across calls and mixed models', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: 1000, output_tokens: 500 } });
    spendCap.recordUsage({ model: 'claude-haiku-4-5', usage: { input_tokens: 1000, output_tokens: 500 } });
    const expected = (1000 * 3 + 500 * 15 + 1000 * 1 + 500 * 5) / 1e6;
    close(spendCap.currentUsd(), expected);
    assert.equal(spendCap.currentTokens(), 3000);
  });

  // --- estimate fallback ----------------------------------------------------

  test('new shape: missing usage falls back to the OUTPUT-token estimate at the model rate', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-haiku-4-5', usage: undefined, estimatedOutputTokens: 200_000 });
    close(spendCap.currentUsd(), 200_000 * HAIKU.out / 1e6); // $1.00
    assert.deepEqual(spendCap.state().tokens, { input: 0, output: 200_000, cacheRead: 0, cacheWrite: 0 });
  });

  test('new shape: an empty usage object also triggers the estimate', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: {}, estimatedOutputTokens: 100 });
    close(spendCap.currentUsd(), 100 * SONNET.out / 1e6);
  });

  test('new shape: a real usage object wins over the estimate', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({
      model: 'claude-sonnet-4-6',
      usage: { input_tokens: 100, output_tokens: 10 },
      estimatedOutputTokens: 999_999,
    });
    close(spendCap.currentUsd(), (100 * 3 + 10 * 15) / 1e6);
    assert.equal(spendCap.currentTokens(), 110);
  });

  test('estimate fallback can close the gate on its own', () => {
    process.env.DAILY_BUDGET_USD = '1';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', estimatedOutputTokens: 100_000 }); // $1.50
    assert.equal(spendCap.isCeilingExceeded(), true);
  });

  // --- legacy shape (what server.js calls today) ----------------------------

  test('legacy shape: recordUsage(usage) prices at Sonnet rates', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ input_tokens: M, output_tokens: M });
    close(spendCap.currentUsd(), SONNET.in + SONNET.out); // $18
    assert.equal(spendCap.currentTokens(), 2 * M);
  });

  test('legacy shape: cache classes on the SDK usage object are weighted too', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ input_tokens: 0, output_tokens: 0, cache_read_input_tokens: M, cache_creation_input_tokens: M });
    close(spendCap.currentUsd(), SONNET.cacheRead + SONNET.cacheWrite);
  });

  test('legacy shape: missing usage falls back to fallbackTokens as INPUT tokens at Sonnet rates', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage(undefined, M);
    close(spendCap.currentUsd(), SONNET.in); // $3
    assert.deepEqual(spendCap.state().tokens, { input: M, output: 0, cacheRead: 0, cacheWrite: 0 });
    assert.equal(spendCap.currentTokens(), M);
  });

  test('legacy shape: a real usage object wins over fallbackTokens', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage({ input_tokens: 10, output_tokens: 10 }, M);
    close(spendCap.currentUsd(), (10 * 3 + 10 * 15) / 1e6);
    assert.equal(spendCap.currentTokens(), 20);
  });

  test('legacy shape: nothing at all records nothing', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.recordUsage(undefined);
    spendCap.recordUsage(null, 0);
    spendCap.recordUsage({});
    assert.equal(spendCap.currentUsd(), 0);
    assert.equal(spendCap.currentTokens(), 0);
  });

  // --- hydrate --------------------------------------------------------------

  test('hydrate() only ever raises the in-memory total', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.hydrate(5);
    assert.equal(spendCap.currentUsd(), 5);
    spendCap.hydrate(2); // lower → ignored
    assert.equal(spendCap.currentUsd(), 5);
    spendCap.hydrate(7);
    assert.equal(spendCap.currentUsd(), 7);
    spendCap.hydrate(NaN);
    spendCap.hydrate('junk');
    spendCap.hydrate(undefined);
    assert.equal(spendCap.currentUsd(), 7);
  });

  test('hydrate() does not fabricate a token breakdown', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.hydrate(3);
    assert.equal(spendCap.currentTokens(), 0);
    assert.deepEqual(spendCap.state().tokens, { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  });

  test('hydrate() past the budget closes the gate at boot', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.hydrate(10);
    assert.equal(spendCap.isCeilingExceeded(), true);
  });

  test('recordUsage() adds on top of a hydrated total', () => {
    process.env.DAILY_BUDGET_USD = '10';
    spendCap.hydrate(1);
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M } });
    close(spendCap.currentUsd(), 4);
  });

  // --- state() --------------------------------------------------------------

  test('state() reports day, usd, budget, fraction and the token breakdown', () => {
    process.env.DAILY_BUDGET_USD = '20';
    spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M, output_tokens: 100_000 } });
    const s = spendCap.state();
    assert.match(s.day, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(s.day, new Date().toISOString().slice(0, 10));
    close(s.usd, 4.5);
    assert.equal(s.budgetUsd, 20);
    close(s.fraction, 0.225);
    assert.deepEqual(s.tokens, { input: M, output: 100_000, cacheRead: 0, cacheWrite: 0 });
  });

  test('state().tokens is a copy — mutating it does not touch the accumulator', () => {
    process.env.DAILY_BUDGET_USD = '20';
    spendCap.state().tokens.input = 999;
    assert.equal(spendCap.currentTokens(), 0);
  });

  // --- UTC day rollover -----------------------------------------------------

  test('the accumulator zeroes itself on the first touch of a new UTC day', () => {
    process.env.DAILY_BUDGET_USD = '1';
    mock.timers.enable({ apis: ['Date'], now: new Date('2026-09-23T23:59:00Z') });
    try {
      spendCap.__resetForTest();
      spendCap.recordUsage({ model: 'claude-sonnet-4-6', usage: { input_tokens: M } }); // $3 >= $1
      spendCap.hydrate(2.5); // lower than $3 → no-op, but proves hydrate is day-scoped too
      assert.equal(spendCap.state().day, '2026-09-23');
      assert.equal(spendCap.isCeilingExceeded(), true);

      mock.timers.setTime(new Date('2026-09-24T00:01:00Z').getTime());

      assert.equal(spendCap.isCeilingExceeded(), false, 'new day → gate reopens');
      assert.equal(spendCap.currentUsd(), 0);
      assert.equal(spendCap.currentTokens(), 0);
      const s = spendCap.state();
      assert.equal(s.day, '2026-09-24');
      assert.equal(s.fraction, 0);
      assert.deepEqual(s.tokens, { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
    } finally {
      mock.timers.reset();
    }
  });
});

// ---------------------------------------------------------------------------
// Integration — the chat handler 503s and makes zero Anthropic calls
// ---------------------------------------------------------------------------
describe('spend cap closes the chat handler', () => {
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
          DAILY_BUDGET_USD: '0', // budget closed → the first call is refused
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
    assert.equal(res.status, 503, 'handler must 503 when the budget is closed');
    assert.ok(
      json && json.error === 'spend_cap',
      `expected {error:'spend_cap'} (proves the pre-call gate fired, no Anthropic call), got ${JSON.stringify(json)}`
    );
  });
});
