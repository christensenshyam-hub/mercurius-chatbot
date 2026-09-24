'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  CLUB_V1, wantsClub, staticClubBlock, dynamicClubBlock, makeTtlCache,
} = require('../lib/clubContext');

const CAP = ['club_v1'];

// A manually-resolved promise so a test can hold a loader "in flight".
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

// Injected clock: `t` is the current time in ms, advanced by the test.
function fakeClock(start = 1_000_000) {
  const clock = { t: start, now: () => clock.t, advance: (ms) => { clock.t += ms; } };
  return clock;
}

describe('clubContext', () => {
  describe('wantsClub', () => {
    test('true only for an array containing the exact token', () => {
      assert.equal(CLUB_V1, 'club_v1');
      assert.equal(wantsClub(['club_v1']), true);
      assert.equal(wantsClub(['blocks_v1', 'club_v1']), true, 'alongside other capabilities');
      assert.equal(wantsClub(['club_v2']), false);
      assert.equal(wantsClub(['CLUB_V1']), false, 'case-sensitive');
      assert.equal(wantsClub(['club_v1 ']), false, 'no trimming');
    });

    test('false for non-arrays, strings and empty', () => {
      assert.equal(wantsClub([]), false);
      assert.equal(wantsClub(undefined), false);
      assert.equal(wantsClub(null), false);
      assert.equal(wantsClub('club_v1'), false, 'a bare string is not a capabilities list');
      assert.equal(wantsClub({ 0: 'club_v1', length: 1 }), false, 'array-like object');
      assert.equal(wantsClub(new Set(['club_v1'])), false);
      assert.equal(wantsClub(true), false);
      assert.equal(wantsClub(0), false);
    });
  });

  describe('staticClubBlock', () => {
    test('empty unless the capability is declared', () => {
      assert.equal(staticClubBlock({ capabilities: [], clubKnowledge: 'K' }), '');
      assert.equal(staticClubBlock({ capabilities: undefined, clubKnowledge: 'K' }), '');
      assert.equal(staticClubBlock({ capabilities: ['blocks_v1'], clubKnowledge: 'K' }), '');
      assert.equal(staticClubBlock({ capabilities: 'club_v1', clubKnowledge: 'K' }), '');
      assert.equal(staticClubBlock(), '', 'no args at all');
    });

    test('wraps the trimmed knowledge in the exact tag shape', () => {
      const out = staticClubBlock({ capabilities: CAP, clubKnowledge: '\n\nThe club meets Thursdays.\n' });
      assert.equal(out, '\n\n<club_knowledge>\nThe club meets Thursdays.\n</club_knowledge>');
    });

    test('byte-stable: identical inputs (modulo surrounding whitespace) give identical bytes', () => {
      const a = staticClubBlock({ capabilities: ['club_v1'], clubKnowledge: 'Body text.' });
      const b = staticClubBlock({ capabilities: ['blocks_v1', 'club_v1'], clubKnowledge: '\n  Body text.\n\n' });
      const c = staticClubBlock({ capabilities: CAP, clubKnowledge: 'Body text.' });
      assert.equal(a, b, 'leading/trailing whitespace in the source must not fork the cache');
      assert.equal(a, c);
      assert.equal(Buffer.from(a).equals(Buffer.from(b)), true);
      // Repeated calls are pure.
      for (let i = 0; i < 5; i++) {
        assert.equal(staticClubBlock({ capabilities: CAP, clubKnowledge: 'Body text.' }), a);
      }
    });

    test('does not throw on missing knowledge', () => {
      assert.equal(staticClubBlock({ capabilities: CAP }), '\n\n<club_knowledge>\n\n</club_knowledge>');
      assert.equal(staticClubBlock({ capabilities: CAP, clubKnowledge: null }), '\n\n<club_knowledge>\n\n</club_knowledge>');
    });
  });

  describe('dynamicClubBlock', () => {
    test('empty unless the capability is declared', () => {
      assert.equal(dynamicClubBlock({ capabilities: [], meetingContext: 'M', blogContext: 'B' }), '');
      assert.equal(dynamicClubBlock({ capabilities: undefined, meetingContext: 'M', blogContext: 'B' }), '');
      assert.equal(dynamicClubBlock({ capabilities: 'club_v1', meetingContext: 'M', blogContext: 'B' }), '');
      assert.equal(dynamicClubBlock(), '');
    });

    test('both contexts present: meeting first, then blog, each in its own tag', () => {
      const out = dynamicClubBlock({ capabilities: CAP, meetingContext: '\n\n### SCHEDULE\nThursdays\n', blogContext: '\n\n### BLOG\nPost one\n' });
      assert.equal(out, '<meeting_context>\n### SCHEDULE\nThursdays\n</meeting_context>\n<blog_context>\n### BLOG\nPost one\n</blog_context>');
    });

    test('omits empty parts', () => {
      assert.equal(
        dynamicClubBlock({ capabilities: CAP, meetingContext: 'Thursdays', blogContext: '' }),
        '<meeting_context>\nThursdays\n</meeting_context>',
      );
      assert.equal(
        dynamicClubBlock({ capabilities: CAP, meetingContext: '', blogContext: 'Post one' }),
        '<blog_context>\nPost one\n</blog_context>',
      );
      assert.equal(
        dynamicClubBlock({ capabilities: CAP, meetingContext: undefined, blogContext: 'Post one' }),
        '<blog_context>\nPost one\n</blog_context>',
        'undefined counts as empty',
      );
      assert.equal(
        dynamicClubBlock({ capabilities: CAP, meetingContext: '  \n\n ', blogContext: 'Post one' }),
        '<blog_context>\nPost one\n</blog_context>',
        'whitespace-only counts as empty',
      );
    });

    test('both empty gives an empty string, not empty tags', () => {
      assert.equal(dynamicClubBlock({ capabilities: CAP, meetingContext: '', blogContext: '' }), '');
      assert.equal(dynamicClubBlock({ capabilities: CAP }), '');
      const out = dynamicClubBlock({ capabilities: CAP, meetingContext: null, blogContext: '\n' });
      assert.equal(out, '');
      assert.ok(!out.includes('<meeting_context>') && !out.includes('<blog_context>'));
    });
  });

  describe('makeTtlCache', () => {
    test('validates its arguments', () => {
      assert.throws(() => makeTtlCache(1000, 'not a function'), TypeError);
      assert.throws(() => makeTtlCache(-1, async () => 1), TypeError);
      assert.throws(() => makeTtlCache(NaN, async () => 1), TypeError);
      assert.throws(() => makeTtlCache(Infinity, async () => 1), TypeError);
      assert.throws(() => makeTtlCache(1000, async () => 1, { now: 'nope' }), TypeError);
      assert.equal(typeof makeTtlCache(0, async () => 1), 'function');
    });

    test('calls the loader once within the ttl and shares the value', async () => {
      const clock = fakeClock();
      let calls = 0;
      const get = makeTtlCache(60_000, async () => { calls += 1; return { n: calls }; }, { now: clock.now });

      assert.equal(get.peek(), undefined, 'nothing cached before the first load');
      const a = await get();
      clock.advance(10_000);
      const b = await get();
      clock.advance(49_999);
      const c = await get();
      assert.equal(calls, 1);
      assert.equal(a, b);
      assert.equal(b, c);
      assert.deepEqual(a, { n: 1 });
      assert.equal(get.peek(), a, 'peek returns the fresh value synchronously');
    });

    test('refreshes once the ttl has elapsed', async () => {
      const clock = fakeClock();
      let calls = 0;
      const get = makeTtlCache(60_000, async () => { calls += 1; return calls; }, { now: clock.now });

      assert.equal(await get(), 1);
      clock.advance(60_000); // exactly at expiry → stale
      assert.equal(get.peek(), undefined, 'peek is undefined once expired');
      assert.equal(await get(), 2);
      assert.equal(calls, 2);
      clock.advance(59_999);
      assert.equal(await get(), 2, 'still fresh just inside the new window');
      clock.advance(1);
      assert.equal(await get(), 3);
      assert.equal(calls, 3);
    });

    test('ttl of 0 dedupes concurrent callers but never serves a stale value', async () => {
      let calls = 0;
      const get = makeTtlCache(0, async () => { calls += 1; return calls; });
      assert.equal(await get(), 1);
      assert.equal(await get(), 2);
      assert.equal(get.peek(), undefined);
      const both = await Promise.all([get(), get()]);
      assert.deepEqual(both, [3, 3]);
      assert.equal(calls, 3);
    });

    test('concurrent callers share the single in-flight load', async () => {
      const clock = fakeClock();
      const d = deferred();
      let calls = 0;
      const get = makeTtlCache(60_000, () => { calls += 1; return d.promise; }, { now: clock.now });

      const p1 = get();
      const p2 = get();
      const p3 = get();
      assert.equal(calls, 1, 'only one loader call while the first is pending');
      assert.equal(get.peek(), undefined, 'nothing cached until the load resolves');
      d.resolve('events');
      const results = await Promise.all([p1, p2, p3]);
      assert.deepEqual(results, ['events', 'events', 'events']);
      assert.equal(calls, 1);
      assert.equal(await get(), 'events', 'subsequent call served from cache');
      assert.equal(calls, 1);
    });

    test('a rejected load is not cached: waiters see the error, the next call reloads', async () => {
      const clock = fakeClock();
      let calls = 0;
      let fail = true;
      const get = makeTtlCache(60_000, async () => {
        calls += 1;
        if (fail) throw new Error('db down');
        return 'ok';
      }, { now: clock.now });

      // Every concurrent waiter gets the same rejection.
      const r = await Promise.allSettled([get(), get()]);
      assert.deepEqual(r.map((x) => x.status), ['rejected', 'rejected']);
      assert.equal(r[0].reason.message, 'db down');
      assert.equal(calls, 1, 'the failing load was shared, not duplicated');
      assert.equal(get.peek(), undefined, 'error left nothing cached');

      // Still failing → still not cached, loader called again.
      await assert.rejects(get(), /db down/);
      assert.equal(calls, 2);

      fail = false;
      assert.equal(await get(), 'ok');
      assert.equal(calls, 3);
      assert.equal(await get(), 'ok', 'success is cached');
      assert.equal(calls, 3);
    });

    test('a synchronous throw in the loader becomes a rejection, not a sync throw', async () => {
      let calls = 0;
      const get = makeTtlCache(60_000, () => {
        calls += 1;
        if (calls === 1) throw new Error('sync boom');
        return 'recovered';
      });
      let p;
      assert.doesNotThrow(() => { p = get(); });
      await assert.rejects(p, /sync boom/);
      assert.equal(await get(), 'recovered', 'the rejected promise was not left in flight');
      assert.equal(calls, 2);
    });

    test('a failed load does not overwrite an expired value with garbage, and does not resurrect it', async () => {
      const clock = fakeClock();
      let calls = 0;
      const get = makeTtlCache(1_000, async () => {
        calls += 1;
        if (calls === 2) throw new Error('transient');
        return `v${calls}`;
      }, { now: clock.now });

      assert.equal(await get(), 'v1');
      clock.advance(1_000);
      await assert.rejects(get(), /transient/);
      assert.equal(get.peek(), undefined, 'expired value stays expired after a failed refresh');
      assert.equal(await get(), 'v3');
    });

    test('falsy loader results are cached, not refetched', async () => {
      const clock = fakeClock();
      let calls = 0;
      const get = makeTtlCache(60_000, async () => { calls += 1; return null; }, { now: clock.now });
      assert.equal(await get(), null);
      assert.equal(await get(), null);
      assert.equal(calls, 1, 'null is a legitimate cached value (no events row)');
      assert.equal(get.peek(), null);
    });

    test('invalidate() drops the cached value so the next call reloads', async () => {
      const clock = fakeClock();
      let calls = 0;
      const get = makeTtlCache(60_000, async () => { calls += 1; return calls; }, { now: clock.now });
      assert.equal(await get(), 1);
      assert.equal(get.peek(), 1);
      get.invalidate();
      assert.equal(get.peek(), undefined);
      assert.equal(await get(), 2);
      assert.equal(calls, 2);
      get.invalidate();
      get.invalidate();
      assert.equal(await get(), 3, 'idempotent');
    });

    test('invalidate() during an in-flight load discards that load\'s result', async () => {
      const clock = fakeClock();
      const d = deferred();
      let calls = 0;
      const get = makeTtlCache(60_000, () => {
        calls += 1;
        return calls === 1 ? d.promise : Promise.resolve('fresh');
      }, { now: clock.now });

      const pending = get();
      get.invalidate(); // e.g. admin just rewrote the events row
      d.resolve('stale');
      assert.equal(await pending, 'stale', 'the waiter still receives what it was promised');
      assert.equal(get.peek(), undefined, 'but the pre-invalidation read is not stored');
      assert.equal(await get(), 'fresh');
      assert.equal(calls, 2);
      assert.equal(get.peek(), 'fresh');
    });

    test('uses Date.now by default', async () => {
      let calls = 0;
      const get = makeTtlCache(10 * 60_000, async () => { calls += 1; return calls; });
      assert.equal(await get(), 1);
      assert.equal(await get(), 1);
      assert.equal(calls, 1);
    });
  });
});
