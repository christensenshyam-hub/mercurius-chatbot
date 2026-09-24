'use strict';

// Tests for the daily per-session / per-IP quotas and in-flight caps
// (lib/quotas, ops/safety-rails).
//
//   Pure unit tests — the module is in-memory and synchronous, so nothing
//   here spawns a server. Day rollover and retryAfterSec are exercised by
//   mocking Date via node:test's mock.timers (the module reads Date.now()).

const { describe, test, beforeEach, afterEach, after, mock } = require('node:test');
const assert = require('node:assert/strict');

const quotas = require('../lib/quotas');

const ENV_KEYS = Object.keys(quotas.DEFAULTS);
const savedEnv = {};
for (const key of ENV_KEYS) savedEnv[key] = process.env[key];

function clearEnv() {
  for (const key of ENV_KEYS) delete process.env[key];
}

function restoreEnv() {
  for (const key of ENV_KEYS) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
}

// Every block starts from a clean module + clean env; the env is put back
// once the file is done so other test files see what they expect.
beforeEach(() => {
  clearEnv();
  quotas.__resetForTest();
});
after(() => {
  restoreEnv();
  quotas.__resetForTest();
});

const SID = 'sess_a';
const IP = '10.0.0.1';

function recordN(n, fields) {
  for (let i = 0; i < n; i += 1) quotas.record(fields);
}

// ---------------------------------------------------------------------------
// Env parsing + configure()
// ---------------------------------------------------------------------------
describe('limits: env parsing', () => {
  test('unset env → documented defaults', () => {
    assert.deepEqual(quotas.limits(), {
      SESSION_DAILY_LESSON_TURNS: 40,
      SESSION_DAILY_CHAT_TURNS: 60,
      SESSION_DAILY_USD: 0.75,
      SESSION_DAILY_IMAGES: 20,
      IP_DAILY_USD: 10,
      IP_DAILY_NEW_SESSIONS: 60,
      IP_DAILY_IMAGES: 200,
      IP_DAILY_IMAGE_BYTES: 500 * 1024 * 1024,
      IP_MAX_INFLIGHT: 40,
      MAX_INFLIGHT: 80,
    });
  });

  test('valid env values are parsed as numbers', () => {
    process.env.SESSION_DAILY_LESSON_TURNS = '5';
    process.env.SESSION_DAILY_USD = '1.5';
    process.env.MAX_INFLIGHT = '3';
    const L = quotas.limits();
    assert.equal(L.SESSION_DAILY_LESSON_TURNS, 5);
    assert.equal(L.SESSION_DAILY_USD, 1.5);
    assert.equal(L.MAX_INFLIGHT, 3);
  });

  test('invalid env values fall back to the default', () => {
    process.env.SESSION_DAILY_LESSON_TURNS = 'abc';
    process.env.SESSION_DAILY_CHAT_TURNS = '-5';
    process.env.SESSION_DAILY_USD = '';
    process.env.IP_DAILY_USD = 'Infinity';
    process.env.IP_MAX_INFLIGHT = ' ';
    const L = quotas.limits();
    assert.equal(L.SESSION_DAILY_LESSON_TURNS, 40);
    assert.equal(L.SESSION_DAILY_CHAT_TURNS, 60);
    assert.equal(L.SESSION_DAILY_USD, 0.75);
    assert.equal(L.IP_DAILY_USD, 10);
    assert.equal(L.IP_MAX_INFLIGHT, 40);
  });

  test('0 is a valid limit and refuses immediately (hard stop lever)', () => {
    process.env.SESSION_DAILY_LESSON_TURNS = '0';
    assert.equal(quotas.limits().SESSION_DAILY_LESSON_TURNS, 0);
    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' });
    assert.equal(r.ok, false);
    assert.equal(r.reason, 'lesson_turns');
  });
});

describe('configure() overrides', () => {
  test('override wins over env and default; returns effective limits', () => {
    process.env.SESSION_DAILY_CHAT_TURNS = '5';
    const L = quotas.configure({ SESSION_DAILY_CHAT_TURNS: 2, MAX_INFLIGHT: 1 });
    assert.equal(L.SESSION_DAILY_CHAT_TURNS, 2);
    assert.equal(L.MAX_INFLIGHT, 1);
    assert.equal(quotas.limits().SESSION_DAILY_CHAT_TURNS, 2);
    // Other keys untouched.
    assert.equal(L.SESSION_DAILY_LESSON_TURNS, 40);
  });

  test('unknown keys and invalid values are ignored', () => {
    quotas.configure({ NOT_A_LIMIT: 1, SESSION_DAILY_USD: 'nope', IP_DAILY_USD: -1 });
    const L = quotas.limits();
    assert.equal('NOT_A_LIMIT' in L, false);
    assert.equal(L.SESSION_DAILY_USD, 0.75);
    assert.equal(L.IP_DAILY_USD, 10);
  });

  test('undefined clears an override back to env/default', () => {
    process.env.SESSION_DAILY_IMAGES = '3';
    quotas.configure({ SESSION_DAILY_IMAGES: 1 });
    assert.equal(quotas.limits().SESSION_DAILY_IMAGES, 1);
    quotas.configure({ SESSION_DAILY_IMAGES: undefined });
    assert.equal(quotas.limits().SESSION_DAILY_IMAGES, 3);
  });

  test('configure with no argument is a no-op that returns limits', () => {
    quotas.configure({ MAX_INFLIGHT: 7 });
    assert.equal(quotas.configure().MAX_INFLIGHT, 7);
    assert.equal(quotas.configure(null).MAX_INFLIGHT, 7);
  });

  test('__resetForTest clears overrides', () => {
    quotas.configure({ MAX_INFLIGHT: 7 });
    quotas.__resetForTest();
    assert.equal(quotas.limits().MAX_INFLIGHT, 80);
  });
});

// ---------------------------------------------------------------------------
// Turn caps per kind
// ---------------------------------------------------------------------------
describe('session daily turn caps', () => {
  test('lesson turns: allowed up to the cap, refused after, with the lesson message', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 2 });
    assert.deepEqual(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }), { ok: true });
    recordN(2, { sessionId: SID, ip: IP, kind: 'lesson', usd: 0.01 });

    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' });
    assert.equal(r.ok, false);
    assert.equal(r.status, 429);
    assert.equal(r.error, 'daily_limit');
    assert.equal(r.scope, 'session');
    assert.equal(r.reason, 'lesson_turns');
    assert.equal(r.message, "You've used today's lesson turns. Mercurius will be ready again tomorrow.");
    assert.ok(Number.isInteger(r.retryAfterSec) && r.retryAfterSec >= 1 && r.retryAfterSec <= 86400);
  });

  test('lesson cap does not block chat turns, and vice versa', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 1, SESSION_DAILY_CHAT_TURNS: 1 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson' });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).ok, false);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);

    quotas.record({ sessionId: SID, ip: IP, kind: 'chat' });
    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'chat' });
    assert.equal(r.ok, false);
    assert.equal(r.reason, 'chat_turns');
    assert.equal(r.message, "You've used today's chat turns. Mercurius will be ready again tomorrow.");
  });

  test('helper turns count toward the chat cap', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 2 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'helper' });
    quotas.record({ sessionId: SID, ip: IP, kind: 'chat' });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'helper' }).reason, 'chat_turns');
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).reason, 'chat_turns');
    assert.equal(quotas.snapshot().sessions.totals.chatTurns, 2);
  });

  test('an unrecognised kind is treated as chat (conservative)', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'quiz' });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'quiz' }).reason, 'chat_turns');
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).reason, 'chat_turns');
  });

  test('image uploads do not consume chat or lesson turns', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1, SESSION_DAILY_LESSON_TURNS: 1 });
    recordN(5, { sessionId: SID, ip: IP, kind: 'image' });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).ok, true);
  });

  test('turns are per session — another session on the same ip is unaffected', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 1 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson' });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).ok, false);
    assert.equal(quotas.check({ sessionId: 'sess_b', ip: IP, kind: 'lesson' }).ok, true);
  });

  test('a record without a kind counts usd only, never a turn', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1 });
    quotas.record({ sessionId: SID, ip: IP, usd: 0.05 });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
    assert.equal(quotas.snapshot().sessions.totals.chatTurns, 0);
    assert.equal(quotas.snapshot().sessions.totals.usd, 0.05);
  });
});

// ---------------------------------------------------------------------------
// USD caps
// ---------------------------------------------------------------------------
describe('daily USD caps', () => {
  test('session usd: refused once the session has spent the cap (any kind)', () => {
    quotas.configure({ SESSION_DAILY_USD: 0.5 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson', usd: 0.3 });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
    quotas.record({ sessionId: SID, ip: IP, kind: 'helper', usd: 0.25 });

    for (const kind of ['lesson', 'chat', 'helper', 'image']) {
      const r = quotas.check({ sessionId: SID, ip: IP, kind });
      assert.equal(r.ok, false, kind);
      assert.equal(r.scope, 'session');
      assert.equal(r.reason, 'session_usd');
      assert.equal(r.message, "You've reached today's usage limit. Mercurius will be ready again tomorrow.");
    }
  });

  test('ip usd: sums across sessions on the network and blocks a fresh session', () => {
    quotas.configure({ SESSION_DAILY_USD: 10, IP_DAILY_USD: 0.5 });
    quotas.record({ sessionId: 'sess_a', ip: IP, kind: 'chat', usd: 0.3 });
    quotas.record({ sessionId: 'sess_b', ip: IP, kind: 'chat', usd: 0.3 });

    const r = quotas.check({ sessionId: 'sess_c', ip: IP, kind: 'chat' });
    assert.equal(r.ok, false);
    assert.equal(r.status, 429);
    assert.equal(r.error, 'daily_limit');
    assert.equal(r.scope, 'ip');
    assert.equal(r.reason, 'ip_usd');
    assert.equal(r.message, "This network has reached today's usage limit. Mercurius will be ready again tomorrow.");

    // A different network is untouched.
    assert.equal(quotas.check({ sessionId: 'sess_c', ip: '10.0.0.2', kind: 'chat' }).ok, true);
  });

  test('negative or non-numeric usd is recorded as 0', () => {
    quotas.record({ sessionId: SID, ip: IP, kind: 'chat', usd: -5 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'chat', usd: 'lots' });
    const snap = quotas.snapshot();
    assert.equal(snap.sessions.totals.usd, 0);
    assert.equal(snap.ips.usd, 0);
    assert.equal(snap.sessions.totals.chatTurns, 2);
  });
});

// ---------------------------------------------------------------------------
// Image cap
// ---------------------------------------------------------------------------
describe('session daily image cap', () => {
  test('refused after the cap with the image message; chat still allowed', () => {
    quotas.configure({ SESSION_DAILY_IMAGES: 1 });
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'image' }).ok, true);
    quotas.record({ sessionId: SID, ip: IP, kind: 'image' });

    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'image' });
    assert.equal(r.ok, false);
    assert.equal(r.scope, 'session');
    assert.equal(r.reason, 'images');
    assert.equal(r.message, "You've used today's image uploads. Mercurius will be ready again tomorrow.");

    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).ok, true);
  });
});

// ---------------------------------------------------------------------------
// New-session cap
// ---------------------------------------------------------------------------
describe('noteNewSession() per-ip cap', () => {
  test('counts up to the cap, then refuses without counting', () => {
    quotas.configure({ IP_DAILY_NEW_SESSIONS: 2 });
    assert.deepEqual(quotas.noteNewSession(IP), { ok: true });
    assert.deepEqual(quotas.noteNewSession(IP), { ok: true });

    const r = quotas.noteNewSession(IP);
    assert.equal(r.ok, false);
    assert.equal(r.status, 429);
    assert.equal(r.error, 'daily_limit');
    assert.equal(r.scope, 'ip');
    assert.equal(r.reason, 'new_sessions');
    assert.equal(r.message, 'Too many new sessions from this network today.');
    assert.ok(r.retryAfterSec >= 1);

    // The refused attempt did not bump the counter.
    assert.equal(quotas.snapshot().ips.newSessions, 2);
    assert.equal(quotas.noteNewSession(IP).ok, false);

    // Another network is independent.
    assert.deepEqual(quotas.noteNewSession('10.0.0.2'), { ok: true });
  });

  test('missing ip is allowed (nothing to key on)', () => {
    quotas.configure({ IP_DAILY_NEW_SESSIONS: 0 });
    assert.deepEqual(quotas.noteNewSession(undefined), { ok: true });
    assert.deepEqual(quotas.noteNewSession(''), { ok: true });
  });
});

// ---------------------------------------------------------------------------
// Evaluation order + retryAfterSec
// ---------------------------------------------------------------------------
describe('check() evaluation order', () => {
  test('session turns beat session usd, which beats ip usd, which beats in-flight', () => {
    quotas.configure({
      SESSION_DAILY_LESSON_TURNS: 1,
      SESSION_DAILY_USD: 0.1,
      IP_DAILY_USD: 0.1,
      IP_MAX_INFLIGHT: 1,
      MAX_INFLIGHT: 1,
    });
    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson', usd: 1 });
    quotas.acquire(IP);

    // Everything is exhausted; the earliest gate reports.
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).reason, 'lesson_turns');
    // A kind whose turn cap is fine falls through to session usd.
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).reason, 'session_usd');
    // A fresh session on the same network falls through to ip usd.
    assert.equal(quotas.check({ sessionId: 'sess_b', ip: IP, kind: 'chat' }).reason, 'ip_usd');
    // A fresh session on a fresh network hits the global in-flight cap.
    assert.equal(quotas.check({ sessionId: 'sess_b', ip: '10.0.0.2', kind: 'chat' }).reason, 'inflight_global');
  });

  test('ip in-flight is reported before global in-flight', () => {
    quotas.configure({ IP_MAX_INFLIGHT: 1, MAX_INFLIGHT: 1 });
    quotas.acquire(IP);
    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'chat' });
    assert.equal(r.scope, 'ip');
    assert.equal(r.reason, 'inflight_ip');
  });

  test('missing sessionId skips session gates; missing ip skips ip gates', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 0, IP_DAILY_USD: 0, IP_MAX_INFLIGHT: 0 });
    assert.equal(quotas.check({ ip: IP, kind: 'chat' }).reason, 'ip_usd');
    assert.equal(quotas.check({ sessionId: SID, kind: 'chat' }).reason, 'chat_turns');
    assert.deepEqual(quotas.check({ kind: 'chat' }), { ok: true });
    assert.deepEqual(quotas.check(), { ok: true });
    assert.deepEqual(quotas.check(null), { ok: true });
  });

  test('check() is read-only — it never creates counters', () => {
    quotas.check({ sessionId: SID, ip: IP, kind: 'chat' });
    const snap = quotas.snapshot();
    assert.equal(snap.sessions.tracked, 0);
    assert.equal(snap.ips.tracked, 0);
  });
});

describe('retryAfterSec', () => {
  afterEach(() => mock.timers.reset());

  test('daily refusals report the seconds until UTC midnight', () => {
    mock.timers.enable({ apis: ['Date'], now: Date.UTC(2026, 8, 23, 23, 59, 30) });
    quotas.__resetForTest();
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 0, IP_DAILY_NEW_SESSIONS: 0 });

    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).retryAfterSec, 30);
    assert.equal(quotas.noteNewSession(IP).retryAfterSec, 30);

    // Sub-second remainders round UP, and never report 0.
    mock.timers.setTime(Date.UTC(2026, 8, 23, 23, 59, 59, 800));
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).retryAfterSec, 1);

    mock.timers.setTime(Date.UTC(2026, 8, 23, 0, 0, 0));
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).retryAfterSec, 86400);
  });

  test('busy refusals report a flat 60 seconds', () => {
    quotas.configure({ MAX_INFLIGHT: 0 });
    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'chat' });
    assert.equal(r.status, 503);
    assert.equal(r.error, 'busy');
    assert.equal(r.retryAfterSec, 60);
    assert.equal(r.message, 'Mercurius is helping a lot of students right now. Try again in a minute.');
  });
});

// ---------------------------------------------------------------------------
// Day rollover
// ---------------------------------------------------------------------------
describe('UTC day rollover', () => {
  afterEach(() => mock.timers.reset());

  test('daily counters reset at UTC midnight; in-flight does not', () => {
    mock.timers.enable({ apis: ['Date'], now: Date.UTC(2026, 8, 23, 22, 0, 0) });
    quotas.__resetForTest();
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 1, IP_DAILY_NEW_SESSIONS: 1, MAX_INFLIGHT: 1 });

    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson', usd: 0.2 });
    quotas.noteNewSession(IP);
    quotas.acquire(IP);
    assert.equal(quotas.snapshot().day, '2026-09-23');
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).reason, 'lesson_turns');
    assert.equal(quotas.noteNewSession(IP).ok, false);

    // 23:59:59 → still yesterday's counters.
    mock.timers.setTime(Date.UTC(2026, 8, 23, 23, 59, 59));
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).ok, false);

    // Midnight: daily state is fresh.
    mock.timers.setTime(Date.UTC(2026, 8, 24, 0, 0, 0));
    const snap = quotas.snapshot();
    assert.equal(snap.day, '2026-09-24');
    assert.equal(snap.sessions.tracked, 0);
    assert.equal(snap.ips.tracked, 0);
    assert.equal(quotas.noteNewSession(IP).ok, true);

    // In-flight is live state, not daily state: the global cap still bites.
    assert.equal(snap.inflight.global, 1);
    assert.equal(quotas.inflightFor(IP), 1);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).reason, 'inflight_global');
    quotas.release(IP);
    assert.deepEqual(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }), { ok: true });
  });

  test('a session can be hydrated again on the new day', () => {
    mock.timers.enable({ apis: ['Date'], now: Date.UTC(2026, 8, 23, 12, 0, 0) });
    quotas.__resetForTest();
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 3, usd: 0.1 }]), true);
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 9, usd: 0.9 }]), false);

    mock.timers.setTime(Date.UTC(2026, 8, 24, 12, 0, 0));
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 1, usd: 0.05 }]), true);
    assert.equal(quotas.snapshot().sessions.totals.chatTurns, 1);
  });
});

// ---------------------------------------------------------------------------
// hydrateSession()
// ---------------------------------------------------------------------------
describe('hydrateSession()', () => {
  test('seeds counters from usage rows; helper rows count as chat', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 5, SESSION_DAILY_CHAT_TURNS: 5 });
    const applied = quotas.hydrateSession(SID, [
      { kind: 'lesson', count: 5, usd: 0.2 },
      { kind: 'chat', count: 2, usd: 0.1 },
      { kind: 'helper', count: 3, usd: 0.05 },
      { kind: 'image', count: 4, usd: 0 },
    ]);
    assert.equal(applied, true);

    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'lesson' }).reason, 'lesson_turns');
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).reason, 'chat_turns');
    const s = quotas.snapshot().sessions;
    assert.equal(s.hydrated, 1);
    assert.deepEqual(s.totals, { lessonTurns: 5, chatTurns: 5, images: 4, usd: 0.35 });
  });

  test('applies only once per session per day', () => {
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 2, usd: 0.1 }]), true);
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 50, usd: 5 }]), false);
    assert.deepEqual(quotas.snapshot().sessions.totals, { lessonTurns: 0, chatTurns: 2, images: 0, usd: 0.1 });
  });

  test('only raises counters — never lowers what memory already recorded', () => {
    recordN(3, { sessionId: SID, ip: IP, kind: 'chat', usd: 0.1 });
    quotas.record({ sessionId: SID, ip: IP, kind: 'lesson', usd: 0 });
    // db says fewer chat turns (stale) but more lesson turns (pre-restart).
    quotas.hydrateSession(SID, [
      { kind: 'chat', count: 1, usd: 0.05 },
      { kind: 'lesson', count: 4, usd: 0 },
    ]);
    const t = quotas.snapshot().sessions.totals;
    assert.equal(t.chatTurns, 3);
    assert.equal(t.lessonTurns, 4);
    assert.equal(t.usd, 0.3);
  });

  test('tolerates string numerics (pg) and junk rows', () => {
    const applied = quotas.hydrateSession(SID, [
      { kind: 'chat', count: '4', usd: '0.25' },
      { kind: 'image', count: 'NaN', usd: null },
      null,
      'garbage',
      { kind: 'lesson' },
    ]);
    assert.equal(applied, true);
    assert.deepEqual(quotas.snapshot().sessions.totals, { lessonTurns: 0, chatTurns: 4, images: 0, usd: 0.25 });
  });

  test('a non-array (failed query) is skipped and does not burn the once-per-day slot', () => {
    assert.equal(quotas.hydrateSession(SID, undefined), false);
    assert.equal(quotas.hydrateSession(SID, null), false);
    assert.equal(quotas.hydrateSession(SID, { rows: [] }), false);
    assert.equal(quotas.hydrateSession(undefined, []), false);
    assert.equal(quotas.snapshot().sessions.hydrated, 0);
    assert.equal(quotas.hydrateSession(SID, [{ kind: 'chat', count: 1, usd: 0 }]), true);
  });

  test('hydration does not touch ip counters', () => {
    quotas.hydrateSession(SID, [{ kind: 'chat', count: 1, usd: 5 }]);
    assert.equal(quotas.snapshot().ips.tracked, 0);
  });
});

// ---------------------------------------------------------------------------
// In-flight caps
// ---------------------------------------------------------------------------
describe('in-flight acquire/release', () => {
  test('acquire and release keep per-ip and global counts', () => {
    assert.deepEqual(quotas.inflight(), { global: 0, byIp: {} });
    quotas.acquire(IP);
    quotas.acquire(IP);
    quotas.acquire('10.0.0.2');
    assert.deepEqual(quotas.inflight(), { global: 3, byIp: { [IP]: 2, '10.0.0.2': 1 } });
    assert.equal(quotas.inflightFor(IP), 2);
    assert.equal(quotas.inflightFor('10.0.0.9'), 0);

    quotas.release(IP);
    assert.equal(quotas.inflightFor(IP), 1);
    quotas.release(IP);
    quotas.release('10.0.0.2');
    assert.deepEqual(quotas.inflight(), { global: 0, byIp: {} });
  });

  test('release never goes below 0 and a stray release does not disturb others', () => {
    quotas.release(IP);
    quotas.release();
    assert.deepEqual(quotas.inflight(), { global: 0, byIp: {} });

    quotas.acquire(IP);
    quotas.release('10.0.0.2'); // never acquired — must not steal IP's slot
    assert.deepEqual(quotas.inflight(), { global: 1, byIp: { [IP]: 1 } });
    quotas.release(IP);
    quotas.release(IP); // double release
    assert.deepEqual(quotas.inflight(), { global: 0, byIp: {} });
    assert.equal(quotas.inflightFor(IP), 0);
  });

  test('acquire/release without an ip track the global count only', () => {
    quotas.acquire();
    quotas.acquire('');
    assert.deepEqual(quotas.inflight(), { global: 2, byIp: {} });
    quotas.release();
    quotas.release(null);
    assert.deepEqual(quotas.inflight(), { global: 0, byIp: {} });
  });

  test('per-ip cap → 503 busy scope ip; other networks still admitted', () => {
    quotas.configure({ IP_MAX_INFLIGHT: 2, MAX_INFLIGHT: 10 });
    quotas.acquire(IP);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
    quotas.acquire(IP);

    const r = quotas.check({ sessionId: SID, ip: IP, kind: 'chat' });
    assert.deepEqual(r, {
      ok: false,
      status: 503,
      error: 'busy',
      scope: 'ip',
      reason: 'inflight_ip',
      message: 'Mercurius is helping a lot of students right now. Try again in a minute.',
      retryAfterSec: 60,
    });
    assert.equal(quotas.check({ sessionId: SID, ip: '10.0.0.2', kind: 'chat' }).ok, true);

    quotas.release(IP);
    assert.equal(quotas.check({ sessionId: SID, ip: IP, kind: 'chat' }).ok, true);
  });

  test('global cap → 503 busy scope global, regardless of ip', () => {
    quotas.configure({ IP_MAX_INFLIGHT: 10, MAX_INFLIGHT: 2 });
    quotas.acquire('10.0.0.1');
    quotas.acquire('10.0.0.2');
    const r = quotas.check({ sessionId: SID, ip: '10.0.0.3', kind: 'chat' });
    assert.equal(r.status, 503);
    assert.equal(r.error, 'busy');
    assert.equal(r.scope, 'global');
    assert.equal(r.reason, 'inflight_global');
    assert.equal(r.retryAfterSec, 60);

    quotas.release('10.0.0.1');
    assert.equal(quotas.check({ sessionId: SID, ip: '10.0.0.3', kind: 'chat' }).ok, true);
  });
});

// ---------------------------------------------------------------------------
// Robustness + snapshot
// ---------------------------------------------------------------------------
describe('robustness', () => {
  test('record() never throws on missing or malformed input', () => {
    assert.doesNotThrow(() => quotas.record());
    assert.doesNotThrow(() => quotas.record(null));
    assert.doesNotThrow(() => quotas.record('nope'));
    assert.doesNotThrow(() => quotas.record({ usd: 'x' }));
    assert.doesNotThrow(() => quotas.record({ sessionId: { weird: true }, ip: 42, kind: Symbol('k') }));
    assert.doesNotThrow(() => quotas.hydrateSession({}, [{ kind: 'chat', count: 1 }]));
  });

  test('keys are trimmed strings; blank keys are ignored', () => {
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 1 });
    quotas.record({ sessionId: '  sess_a  ', ip: ' 10.0.0.1 ', kind: 'chat', usd: 0.1 });
    assert.equal(quotas.check({ sessionId: 'sess_a', ip: '10.0.0.1', kind: 'chat' }).reason, 'chat_turns');
    quotas.record({ sessionId: '   ', ip: '', kind: 'chat', usd: 0.1 });
    const snap = quotas.snapshot();
    assert.equal(snap.sessions.tracked, 1);
    assert.equal(snap.ips.tracked, 1);
  });

  test('snapshot() reports the admin view', () => {
    quotas.configure({ SESSION_DAILY_LESSON_TURNS: 1, IP_DAILY_NEW_SESSIONS: 1 });
    quotas.record({ sessionId: 'sess_a', ip: IP, kind: 'lesson', usd: 0.1 });
    quotas.record({ sessionId: 'sess_b', ip: IP, kind: 'chat', usd: 0.2 });
    quotas.noteNewSession(IP);
    quotas.hydrateSession('sess_b', []);
    quotas.acquire(IP);
    quotas.acquire(IP);
    quotas.acquire('10.0.0.2');

    const snap = quotas.snapshot();
    assert.equal(typeof snap.day, 'string');
    assert.match(snap.day, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(snap.limits.SESSION_DAILY_LESSON_TURNS, 1);
    assert.deepEqual(snap.sessions, {
      tracked: 2,
      hydrated: 1,
      totals: { lessonTurns: 1, chatTurns: 1, images: 0, usd: 0.3 },
      exhausted: { lessonTurns: 1, chatTurns: 0, images: 0, usd: 0 },
    });
    assert.deepEqual(snap.ips, {
      tracked: 1, usd: 0.3, newSessions: 1, exhaustedUsd: 0, exhaustedNewSessions: 1,
    });
    assert.deepEqual(snap.inflight, { global: 3, ips: 2, maxPerIp: 2 });
  });
});
