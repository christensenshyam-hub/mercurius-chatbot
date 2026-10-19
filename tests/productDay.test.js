'use strict';

// lib/productDay: the server's one definition of "a day" (AUD-30), midnight
// to midnight in STREAK_TZ. Quotas, the spend cap, the per-session hydrate
// and the streaks all read it.

const { describe, test, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const productDay = require('../lib/productDay');

const savedTz = process.env.STREAK_TZ;
function withTz(tz) {
  if (tz === undefined) delete process.env.STREAK_TZ;
  else process.env.STREAK_TZ = tz;
  productDay.__resetForTest();
}
const iso = (ms) => new Date(ms).toISOString();

describe('productDay', () => {
  afterEach(() => withTz(savedTz));

  test('the audit capture in Chicago: today until 05:00Z, not 00:00Z', () => {
    withTz('America/Chicago');
    const t = Date.parse('2026-10-18T21:10:57Z'); // 4:10 PM CDT
    assert.equal(productDay.timeZone(), 'America/Chicago');
    assert.equal(productDay.dayKey(t), '2026-10-18');
    assert.equal(iso(productDay.startOfDayMs(t)), '2026-10-18T05:00:00.000Z');
    assert.equal(iso(productDay.nextDayStartMs(t)), '2026-10-19T05:00:00.000Z');
    assert.equal(productDay.secondsUntilNextDay(t), 28143);
    // After UTC midnight it is still the 18th in Chicago.
    assert.equal(productDay.dayKey(Date.parse('2026-10-19T04:59:59Z')), '2026-10-18');
    assert.equal(productDay.dayKey(Date.parse('2026-10-19T05:00:00Z')), '2026-10-19');
  });

  test('unset or blank STREAK_TZ is America/New_York (the streaks\' default)', () => {
    for (const tz of [undefined, '', '   ']) {
      withTz(tz);
      assert.equal(productDay.timeZone(), 'America/New_York');
      assert.equal(productDay.secondsUntilNextDay(Date.parse('2026-10-18T21:10:57Z')), 24543);
    }
  });

  test('an unknown zone falls back to the default instead of throwing', () => {
    withTz('Mars/Olympus_Mons');
    assert.equal(productDay.timeZone(), 'America/New_York');
    assert.equal(productDay.dayKey(Date.parse('2026-10-19T03:00:00Z')), '2026-10-18');
  });

  test('UTC gives the UTC day', () => {
    withTz('UTC');
    const t = Date.UTC(2026, 9, 18, 21, 10, 57);
    assert.equal(productDay.dayKey(t), '2026-10-18');
    assert.equal(productDay.secondsUntilNextDay(t), 10143);
  });

  test('DST: the spring-forward day is 23 h and the fall-back day is 25 h', () => {
    withTz('America/New_York');
    const spring = Date.parse('2026-03-08T12:00:00Z');
    assert.equal(iso(productDay.startOfDayMs(spring)), '2026-03-08T05:00:00.000Z');
    assert.equal(iso(productDay.nextDayStartMs(spring)), '2026-03-09T04:00:00.000Z');
    const fall = Date.parse('2026-11-01T12:00:00Z');
    assert.equal(iso(productDay.startOfDayMs(fall)), '2026-11-01T04:00:00.000Z');
    assert.equal(iso(productDay.nextDayStartMs(fall)), '2026-11-02T05:00:00.000Z');
    assert.equal(productDay.secondsUntilNextDay(Date.parse('2026-11-01T04:00:00Z')), 25 * 3600);
  });

  test('a zone whose clocks skip midnight starts its day at the jump', () => {
    // Chile moves 23:59:59 → 01:00 on 6 Sep 2026; there is no 00:00 that day.
    withTz('America/Santiago');
    const t = Date.parse('2026-09-06T12:00:00Z');
    const start = productDay.startOfDayMs(t);
    assert.equal(iso(start), '2026-09-06T04:00:00.000Z');
    assert.equal(productDay.dayKey(start - 1000), '2026-09-05');
    assert.equal(productDay.dayKey(start), '2026-09-06');
  });

  test('every instant of a day maps to the same edges, and the next day starts where this one ends', () => {
    withTz('America/Chicago');
    const start = Date.parse('2026-10-18T05:00:00Z');
    for (const offsetS of [0, 1, 3600, 43_200, 86_399]) {
      const t = start + offsetS * 1000;
      assert.equal(productDay.startOfDayMs(t), start, `+${offsetS}s`);
      assert.equal(productDay.nextDayStartMs(t), start + 86_400_000, `+${offsetS}s`);
    }
    assert.equal(productDay.startOfDayMs(start + 86_400_000), start + 86_400_000);
  });

  test('the zone is read per call, so a changed STREAK_TZ takes effect', () => {
    const t = Date.parse('2026-10-19T03:30:00Z');
    withTz('America/Chicago');
    assert.equal(productDay.dayKey(t), '2026-10-18');
    withTz('Europe/London');
    assert.equal(productDay.dayKey(t), '2026-10-19');
  });
});
