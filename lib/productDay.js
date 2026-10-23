'use strict';

/**
 * The product's calendar day (AUD-30).
 *
 * Mercurius is a US classroom app, so every "day" the server keeps runs
 * midnight to midnight in one product time zone, STREAK_TZ (default
 * America/New_York, the same default the streaks have always used). That
 * covers a streak day, a session's daily turns, a network's daily allowance
 * and the global DAILY_BUDGET_USD.
 *
 * The quotas and the budget used to roll at UTC midnight, which is 7 or 8 PM
 * in the Americas. A student who hit a limit in the afternoon was told
 * "tomorrow" and was back that evening, and one who hit it after 7 PM was
 * still locked out at the next morning's meeting.
 *
 *   timeZone()                 → the zone in use: STREAK_TZ, or the default
 *                                when it is unset or not a zone this Node
 *                                knows (warned once; never throws)
 *   dayKey(nowMs)              → 'YYYY-MM-DD' of that instant in the zone
 *   startOfDayMs(nowMs)        → the first instant of that day
 *   nextDayStartMs(nowMs)      → the first instant of the next day
 *   secondsUntilNextDay(nowMs) → whole seconds until then, rounded up, ≥ 1
 *
 * Day edges are found by bisecting on dayKey, not by assuming 24 h days or a
 * 00:00 that exists, so a 23 h or 25 h DST day and a zone whose clocks skip
 * midnight (America/Santiago, America/Havana) are both right with no
 * time-zone library. The edges are cached per zone and day.
 */

const DEFAULT_TZ = 'America/New_York';
const HOUR_S = 3600;
// Wider than any real day (25 h) plus any offset change, so the far end of
// a search is always on another date.
const SEARCH_S = 27 * HOUR_S;

const formatters = new Map(); // zone → Intl.DateTimeFormat | null (invalid)
const edges = new Map();      // `${zone}|${day}` → { start, next }
let warnedZone = null;

function formatterFor(zone) {
  if (!formatters.has(zone)) {
    let f = null;
    try {
      f = new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' });
    } catch {
      f = null;
    }
    formatters.set(zone, f);
  }
  return formatters.get(zone);
}

function timeZone() {
  const raw = String(process.env.STREAK_TZ || '').trim();
  if (!raw) return DEFAULT_TZ;
  if (formatterFor(raw)) return raw;
  if (warnedZone !== raw) {
    warnedZone = raw;
    try {
      require('./logger').warn({ STREAK_TZ: raw, using: DEFAULT_TZ }, 'STREAK_TZ is not a known time zone; using the default');
    } catch { /* logging must never break the day */ }
  }
  return DEFAULT_TZ;
}

function keyIn(zone, ms) {
  const parts = formatterFor(zone).formatToParts(new Date(ms));
  const get = (type) => (parts.find((p) => p.type === type) || {}).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

// The first whole second in (lo, hi] where pred holds, given pred(lo) is
// false and pred(hi) is true. Day edges fall on whole seconds.
function firstTrue(loS, hiS, pred) {
  let lo = loS;
  let hi = hiS;
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (pred(mid * 1000)) hi = mid;
    else lo = mid;
  }
  return hi * 1000;
}

function edgesFor(nowMs) {
  const zone = timeZone();
  const nowS = Math.floor(nowMs / 1000);
  const day = keyIn(zone, nowS * 1000);
  const cacheKey = `${zone}|${day}`;
  let e = edges.get(cacheKey);
  if (!e) {
    e = {
      start: firstTrue(nowS - SEARCH_S, nowS, (ms) => keyIn(zone, ms) === day),
      next: firstTrue(nowS, nowS + SEARCH_S, (ms) => keyIn(zone, ms) !== day),
    };
    if (edges.size > 64) edges.clear();
    edges.set(cacheKey, e);
  }
  return e;
}

function asMs(nowMs) {
  const n = Number(nowMs);
  return Number.isFinite(n) ? n : Date.now();
}

function dayKey(nowMs = Date.now()) {
  return keyIn(timeZone(), asMs(nowMs));
}

function startOfDayMs(nowMs = Date.now()) {
  return edgesFor(asMs(nowMs)).start;
}

function nextDayStartMs(nowMs = Date.now()) {
  return edgesFor(asMs(nowMs)).next;
}

function secondsUntilNextDay(nowMs = Date.now()) {
  const now = asMs(nowMs);
  return Math.max(1, Math.ceil((nextDayStartMs(now) - now) / 1000));
}

// Test-only: forget cached edges and the invalid-zone warning.
function __resetForTest() {
  edges.clear();
  warnedZone = null;
}

module.exports = {
  DEFAULT_TZ,
  timeZone,
  dayKey,
  startOfDayMs,
  nextDayStartMs,
  secondsUntilNextDay,
  __resetForTest,
};
