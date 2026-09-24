'use strict';

/**
 * Daily per-session / per-IP quotas and in-flight caps (ops/safety-rails).
 *
 * lib/spendCap is the GLOBAL daily backstop and lib/rateLimiter is the
 * per-MINUTE burst limiter. This module sits between them: it bounds what
 * ONE session or ONE network can consume in a UTC day, and how many Claude
 * calls may be in flight at once, so a single abusive or runaway client can't
 * drain the global ceiling for every other student.
 *
 * Same single-replica reasoning as lib/spendCap: one Railway instance, no
 * Redis, so module-level maps ARE the deployment-wide state. The daily
 * counters are keyed by UTC date and zeroed on the first touch of a new day
 * (exactly like spendCap's roll). The in-flight counters are live and are
 * NEVER reset by the clock — only by release().
 *
 * Kinds: 'lesson' | 'chat' | 'helper' | 'image'
 *   lesson         → session lesson turns
 *   chat, helper   → session chat turns (helpers are chat-shaped calls)
 *   image          → session image uploads (POST /api/images; not a turn)
 *   USD is summed across every kind. An unrecognised kind is treated as
 *   'chat' — the conservative reading for the bill.
 *
 * Contract (everything is synchronous; nothing here throws on bad input):
 *   - check({ sessionId, ip, kind })
 *       → { ok: true }
 *       → { ok: false, status: 429, error: 'daily_limit', scope: 'session'|'ip',
 *           reason, message, retryAfterSec }      // retryAfterSec = seconds to UTC midnight
 *       → { ok: false, status: 503, error: 'busy', scope: 'ip'|'global',
 *           reason, message, retryAfterSec: 60 }
 *     Evaluation order: session turns → session usd → session images →
 *     ip usd → in-flight (ip, then global). check() is read-only. Call it and
 *     then acquire() with no `await` in between so the in-flight decision and
 *     the increment are a single synchronous step.
 *   - record({ sessionId, ip, kind, usd })
 *       → bump the day's counters after a call settles (success OR failure —
 *         a failed call still consumed a turn). `kind` omitted → usd only.
 *   - noteNewSession(ip)
 *       → { ok: true } | { ok: false, status: 429, error: 'daily_limit',
 *           scope: 'ip', reason, message, retryAfterSec }
 *         Counts the session only when ok.
 *   - acquire(ip) / release(ip)
 *       → in-flight bookkeeping around each Claude call. Put release() in a
 *         `finally`; it never drives a counter below 0, and releasing an ip
 *         that holds nothing is a no-op.
 *   - inflight() → { global, byIp: { [ip]: n } };   inflightFor(ip) → n
 *   - hydrateSession(sessionId, rows)
 *       → seed today's session counters from the usage table, where
 *         rows = [{ kind, count, usd }] (integration passes the db result).
 *         Applied at most ONCE per session per UTC day, and only ever RAISES
 *         a counter, so a late hydrate can't undo turns already recorded in
 *         memory. Returns true when applied, false when skipped.
 *   - configure(overrides) → runtime limit overrides (tests / admin), keyed by
 *     the env-var names below; returns the effective limits. limits() reads
 *     them; snapshot() is the admin-stats view; __resetForTest() wipes all.
 *
 * Env (all optional; unset/invalid → default; 0 → refuse everything):
 *   SESSION_DAILY_LESSON_TURNS=40   SESSION_DAILY_CHAT_TURNS=60
 *   SESSION_DAILY_USD=0.75          SESSION_DAILY_IMAGES=20
 *   IP_DAILY_USD=10                 IP_DAILY_NEW_SESSIONS=60
 *   IP_MAX_INFLIGHT=40              MAX_INFLIGHT=80
 */

const DEFAULTS = Object.freeze({
  SESSION_DAILY_LESSON_TURNS: 40,
  SESSION_DAILY_CHAT_TURNS: 60,
  SESSION_DAILY_USD: 0.75,
  SESSION_DAILY_IMAGES: 20,
  IP_DAILY_USD: 10,
  IP_DAILY_NEW_SESSIONS: 60,
  IP_MAX_INFLIGHT: 40,
  MAX_INFLIGHT: 80,
});
const LIMIT_KEYS = Object.keys(DEFAULTS);

const BUSY_RETRY_SEC = 60;
const BUSY_MESSAGE = 'Mercurius is helping a lot of students right now. Try again in a minute.';
const TOMORROW = 'Mercurius will be ready again tomorrow.';
const DAILY_MESSAGES = Object.freeze({
  lesson_turns: `You've used today's lesson turns. ${TOMORROW}`,
  chat_turns: `You've used today's chat turns. ${TOMORROW}`,
  session_usd: `You've reached today's usage limit. ${TOMORROW}`,
  images: `You've used today's image uploads. ${TOMORROW}`,
  ip_usd: `This network has reached today's usage limit. ${TOMORROW}`,
  new_sessions: 'Too many new sessions from this network today.',
});

// ---------------------------------------------------------------------------
// Limits — env, overridden at runtime by configure()
// ---------------------------------------------------------------------------

// Same rule as spendCap's ceiling(): finite and >= 0, else the fallback.
// Blank strings are "unset" — Number(' ') is 0, and a stray space in an env
// var must not silently become a refuse-everything limit.
function parseLimit(raw, fallback) {
  if (raw === undefined || raw === null) return fallback;
  if (typeof raw === 'string' && raw.trim() === '') return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

let overrides = {};

function limits() {
  const out = {};
  for (const key of LIMIT_KEYS) {
    out[key] = key in overrides ? overrides[key] : parseLimit(process.env[key], DEFAULTS[key]);
  }
  return out;
}

// Unknown keys and invalid values are ignored; `undefined`/`null` clears an
// override so the env/default applies again.
function configure(next) {
  if (next && typeof next === 'object') {
    for (const key of LIMIT_KEYS) {
      if (!(key in next)) continue;
      if (next[key] === undefined || next[key] === null) { delete overrides[key]; continue; }
      const n = parseLimit(next[key], NaN);
      if (Number.isFinite(n)) overrides[key] = n;
    }
  }
  return limits();
}

// ---------------------------------------------------------------------------
// State — daily maps (UTC-day keyed) + live in-flight counters
// ---------------------------------------------------------------------------

function utcDay(now = Date.now()) {
  return new Date(now).toISOString().slice(0, 10); // YYYY-MM-DD in UTC
}

function secondsUntilUtcMidnight(now = Date.now()) {
  const d = new Date(now);
  const next = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now) / 1000));
}

function freshDay() {
  return { day: utcDay(), sessions: new Map(), ips: new Map() };
}

let state = freshDay();
let inflightState = { global: 0, byIp: new Map() };

function roll() {
  const today = utcDay();
  if (state.day !== today) state = freshDay();
}

// Map keys: a non-empty trimmed string, else null (→ that scope is skipped).
function keyOf(value) {
  if (value === undefined || value === null) return null;
  const s = String(value).trim();
  return s ? s : null;
}

function normalizeKind(kind) {
  switch (String(kind)) {
    case 'lesson': return 'lesson';
    case 'image': return 'image';
    case 'chat':
    case 'helper':
    default: return 'chat';
  }
}

function sessionEntry(sessionId) {
  let e = state.sessions.get(sessionId);
  if (!e) {
    e = { lessonTurns: 0, chatTurns: 0, images: 0, usd: 0, hydrated: false };
    state.sessions.set(sessionId, e);
  }
  return e;
}

function ipEntry(ip) {
  let e = state.ips.get(ip);
  if (!e) {
    e = { usd: 0, newSessions: 0 };
    state.ips.set(ip, e);
  }
  return e;
}

function nonNegative(n) {
  const v = Number(n);
  return Number.isFinite(v) && v > 0 ? v : 0;
}

function asObject(input) {
  return input && typeof input === 'object' ? input : {};
}

// ---------------------------------------------------------------------------
// Refusal envelopes
// ---------------------------------------------------------------------------

function dailyLimit(scope, reason) {
  return {
    ok: false,
    status: 429,
    error: 'daily_limit',
    scope,
    reason,
    message: DAILY_MESSAGES[reason],
    retryAfterSec: secondsUntilUtcMidnight(),
  };
}

function busy(scope, reason) {
  return {
    ok: false,
    status: 503,
    error: 'busy',
    scope,
    reason,
    message: BUSY_MESSAGE,
    retryAfterSec: BUSY_RETRY_SEC,
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

function check(input) {
  roll();
  const { sessionId, ip, kind } = asObject(input);
  const L = limits();
  const sid = keyOf(sessionId);
  const ipKey = keyOf(ip);
  const k = normalizeKind(kind);

  if (sid) {
    const s = state.sessions.get(sid) || { lessonTurns: 0, chatTurns: 0, images: 0, usd: 0 };
    if (k === 'lesson' && s.lessonTurns >= L.SESSION_DAILY_LESSON_TURNS) return dailyLimit('session', 'lesson_turns');
    if (k === 'chat' && s.chatTurns >= L.SESSION_DAILY_CHAT_TURNS) return dailyLimit('session', 'chat_turns');
    if (s.usd >= L.SESSION_DAILY_USD) return dailyLimit('session', 'session_usd');
    if (k === 'image' && s.images >= L.SESSION_DAILY_IMAGES) return dailyLimit('session', 'images');
  }

  if (ipKey) {
    const i = state.ips.get(ipKey);
    if ((i ? i.usd : 0) >= L.IP_DAILY_USD) return dailyLimit('ip', 'ip_usd');
    if (inflightFor(ipKey) >= L.IP_MAX_INFLIGHT) return busy('ip', 'inflight_ip');
  }

  if (inflightState.global >= L.MAX_INFLIGHT) return busy('global', 'inflight_global');

  return { ok: true };
}

function record(input) {
  try {
    roll();
    const { sessionId, ip, kind, usd } = asObject(input);
    const sid = keyOf(sessionId);
    const ipKey = keyOf(ip);
    const k = kind === undefined || kind === null ? null : normalizeKind(kind);
    const cost = nonNegative(usd);

    if (sid) {
      const s = sessionEntry(sid);
      if (k === 'lesson') s.lessonTurns += 1;
      else if (k === 'chat') s.chatTurns += 1;
      else if (k === 'image') s.images += 1;
      s.usd += cost;
    }
    if (ipKey) ipEntry(ipKey).usd += cost;
  } catch {
    // Bookkeeping must never take the request down with it.
  }
}

function noteNewSession(ip) {
  roll();
  const ipKey = keyOf(ip);
  if (!ipKey) return { ok: true };
  const e = ipEntry(ipKey);
  if (e.newSessions >= limits().IP_DAILY_NEW_SESSIONS) return dailyLimit('ip', 'new_sessions');
  e.newSessions += 1;
  return { ok: true };
}

function inflightFor(ip) {
  const ipKey = keyOf(ip);
  return ipKey ? (inflightState.byIp.get(ipKey) || 0) : 0;
}

function inflight() {
  const byIp = {};
  for (const [ip, n] of inflightState.byIp) byIp[ip] = n;
  return { global: inflightState.global, byIp };
}

function acquire(ip) {
  const ipKey = keyOf(ip);
  inflightState.global += 1;
  if (ipKey) inflightState.byIp.set(ipKey, (inflightState.byIp.get(ipKey) || 0) + 1);
  return { global: inflightState.global, ip: inflightFor(ipKey) };
}

function release(ip) {
  const ipKey = keyOf(ip);
  if (ipKey) {
    const n = inflightState.byIp.get(ipKey) || 0;
    // Releasing an ip that holds nothing is a stray/double release — leave the
    // global counter alone too, so the pair stays consistent.
    if (n === 0) return { global: inflightState.global, ip: 0 };
    if (n === 1) inflightState.byIp.delete(ipKey);
    else inflightState.byIp.set(ipKey, n - 1);
  }
  if (inflightState.global > 0) inflightState.global -= 1;
  return { global: inflightState.global, ip: inflightFor(ipKey) };
}

function hydrateSession(sessionId, rows) {
  try {
    roll();
    const sid = keyOf(sessionId);
    // A non-array is not a result (e.g. a failed query) — don't burn the
    // once-per-day slot on it.
    if (!sid || !Array.isArray(rows)) return false;
    const s = sessionEntry(sid);
    if (s.hydrated) return false;
    s.hydrated = true;

    const seen = { lessonTurns: 0, chatTurns: 0, images: 0, usd: 0 };
    for (const row of rows) {
      if (!row || typeof row !== 'object') continue;
      const k = row.kind === undefined || row.kind === null ? null : normalizeKind(row.kind);
      const count = nonNegative(row.count);
      if (k === 'lesson') seen.lessonTurns += count;
      else if (k === 'chat') seen.chatTurns += count;
      else if (k === 'image') seen.images += count;
      seen.usd += nonNegative(row.usd);
    }

    s.lessonTurns = Math.max(s.lessonTurns, seen.lessonTurns);
    s.chatTurns = Math.max(s.chatTurns, seen.chatTurns);
    s.images = Math.max(s.images, seen.images);
    s.usd = Math.max(s.usd, seen.usd);
    return true;
  } catch {
    return false;
  }
}

function round6(n) {
  return Math.round(n * 1e6) / 1e6;
}

function snapshot() {
  roll();
  const L = limits();

  const totals = { lessonTurns: 0, chatTurns: 0, images: 0, usd: 0 };
  const exhausted = { lessonTurns: 0, chatTurns: 0, images: 0, usd: 0 };
  let hydrated = 0;
  for (const s of state.sessions.values()) {
    totals.lessonTurns += s.lessonTurns;
    totals.chatTurns += s.chatTurns;
    totals.images += s.images;
    totals.usd += s.usd;
    if (s.hydrated) hydrated += 1;
    if (s.lessonTurns >= L.SESSION_DAILY_LESSON_TURNS) exhausted.lessonTurns += 1;
    if (s.chatTurns >= L.SESSION_DAILY_CHAT_TURNS) exhausted.chatTurns += 1;
    if (s.images >= L.SESSION_DAILY_IMAGES) exhausted.images += 1;
    if (s.usd >= L.SESSION_DAILY_USD) exhausted.usd += 1;
  }
  totals.usd = round6(totals.usd);

  const ips = { tracked: state.ips.size, usd: 0, newSessions: 0, exhaustedUsd: 0, exhaustedNewSessions: 0 };
  for (const i of state.ips.values()) {
    ips.usd += i.usd;
    ips.newSessions += i.newSessions;
    if (i.usd >= L.IP_DAILY_USD) ips.exhaustedUsd += 1;
    if (i.newSessions >= L.IP_DAILY_NEW_SESSIONS) ips.exhaustedNewSessions += 1;
  }
  ips.usd = round6(ips.usd);

  let maxPerIp = 0;
  for (const n of inflightState.byIp.values()) if (n > maxPerIp) maxPerIp = n;

  return {
    day: state.day,
    limits: L,
    sessions: { tracked: state.sessions.size, hydrated, totals, exhausted },
    ips,
    inflight: { global: inflightState.global, ips: inflightState.byIp.size, maxPerIp },
  };
}

// Test-only: clean day, no in-flight, no overrides.
function __resetForTest() {
  state = freshDay();
  inflightState = { global: 0, byIp: new Map() };
  overrides = {};
}

module.exports = {
  check,
  record,
  noteNewSession,
  acquire,
  release,
  inflight,
  inflightFor,
  hydrateSession,
  configure,
  limits,
  snapshot,
  __resetForTest,
  DEFAULTS,
};
