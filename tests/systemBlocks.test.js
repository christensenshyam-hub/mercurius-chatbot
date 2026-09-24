'use strict';

// Tests for lib/systemBlocks — the one place that shapes the `system`
// parameter of a model call.
//
//   1. buildSystem: block shape, cache_control on the static block ONLY, the
//      dynamic block omitted when empty/whitespace/non-string, TypeError on an
//      empty static, byte-for-byte pass-through of the static text, and no
//      mutation of inputs (fresh objects on every call).
//   2. composeStatic: byte-stability across repeated calls (the property the
//      cache prefix depends on), skipping null/undefined/empty parts, outer
//      trimming, '\n\n' joins, and the TypeError guards.
//   3. staticSize / isCacheable: the chars/3.8 estimate and the exact
//      MIN_CACHEABLE_TOKENS boundary.
//   4. describe: both the array form and the legacy plain-string form, prefix
//      semantics (unmarked blocks BEFORE the breakpoint count as cached), and
//      tolerance of junk input.
//   5. Round-trip through lib/anthropicMock: the array buildSystem produces is
//      what the mock (and the real API) bills as a cache write on the first
//      call and a cache read on the next, with the dynamic block left uncached.

const { describe: suite, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const sb = require('../lib/systemBlocks');
const {
  buildSystem,
  composeStatic,
  staticSize,
  isCacheable,
  describe,
  MIN_CACHEABLE_TOKENS,
  CHARS_PER_TOKEN,
} = sb;

// Smallest char count that rounds up to MIN_CACHEABLE_TOKENS:
// ceil(3888 / 3.8) = 1024, ceil(3887 / 3.8) = 1023.
const CACHEABLE_CHARS = 3888;
const BIG_STATIC = 'S'.repeat(CACHEABLE_CHARS * 2);

// ---------------------------------------------------------------------------
// buildSystem
// ---------------------------------------------------------------------------
suite('buildSystem', () => {
  test('static + dynamic → two text blocks, cache_control on the FIRST only', () => {
    const system = buildSystem({ staticText: 'STATIC', dynamicText: 'DYNAMIC' });
    assert.deepEqual(system, [
      { type: 'text', text: 'STATIC', cache_control: { type: 'ephemeral' } },
      { type: 'text', text: 'DYNAMIC' },
    ]);
    assert.equal(Object.hasOwn(system[1], 'cache_control'), false, 'dynamic block must not carry a breakpoint');
  });

  test('the static block is always index 0 (the cached prefix comes first)', () => {
    const system = buildSystem({ staticText: 'STATIC', dynamicText: 'DYNAMIC' });
    assert.equal(system[0].cache_control.type, 'ephemeral');
    assert.equal(system[0].text, 'STATIC');
  });

  test('dynamic omitted when empty, whitespace-only, missing, null, or not a string', () => {
    const expected = [{ type: 'text', text: 'STATIC', cache_control: { type: 'ephemeral' } }];
    for (const dynamicText of ['', '   ', '\n\t\n', undefined, null, 42, {}, []]) {
      assert.deepEqual(
        buildSystem({ staticText: 'STATIC', dynamicText }),
        expected,
        `dynamicText=${JSON.stringify(dynamicText)} should yield a single block`
      );
    }
    assert.deepEqual(buildSystem({ staticText: 'STATIC' }), expected);
  });

  test('TypeError when staticText is empty, whitespace, missing, or not a string', () => {
    for (const staticText of ['', '   ', '\n', undefined, null, 123, ['x'], { text: 'x' }]) {
      assert.throws(
        () => buildSystem({ staticText, dynamicText: 'd' }),
        TypeError,
        `staticText=${JSON.stringify(staticText)} must throw`
      );
    }
    assert.throws(() => buildSystem(), TypeError);
    assert.throws(() => buildSystem(null), TypeError);
    assert.throws(() => buildSystem('STATIC'), TypeError);
  });

  test('static text is passed through byte-for-byte (not trimmed or normalised)', () => {
    const staticText = '\n  # Prompt\r\n\n  body  \n';
    const dynamicText = '  Mode: chat  ';
    const system = buildSystem({ staticText, dynamicText });
    assert.equal(system[0].text, staticText);
    assert.equal(system[1].text, dynamicText, 'dynamic text is sent as given too');
  });

  test('never mutates its input', () => {
    const input = Object.freeze({ staticText: 'STATIC', dynamicText: 'DYNAMIC' });
    const before = JSON.stringify(input);
    buildSystem(input);
    assert.equal(JSON.stringify(input), before);
  });

  test('returns fresh objects on every call (a caller mutating one cannot poison the next)', () => {
    const a = buildSystem({ staticText: 'STATIC', dynamicText: 'DYNAMIC' });
    a[0].text = 'TAMPERED';
    a[0].cache_control.type = 'nope';
    a.push({ type: 'text', text: 'extra' });
    const b = buildSystem({ staticText: 'STATIC', dynamicText: 'DYNAMIC' });
    assert.notEqual(a, b);
    assert.notEqual(a[0], b[0]);
    assert.deepEqual(b, [
      { type: 'text', text: 'STATIC', cache_control: { type: 'ephemeral' } },
      { type: 'text', text: 'DYNAMIC' },
    ]);
  });

  test('identical inputs produce deep-equal output (what the cache key sees)', () => {
    const a = buildSystem({ staticText: BIG_STATIC, dynamicText: 'd' });
    const b = buildSystem({ staticText: BIG_STATIC, dynamicText: 'd' });
    assert.deepEqual(a, b);
    assert.equal(JSON.stringify(a), JSON.stringify(b));
  });
});

// ---------------------------------------------------------------------------
// composeStatic
// ---------------------------------------------------------------------------
suite('composeStatic', () => {
  test('joins trimmed parts with a blank line', () => {
    assert.equal(composeStatic(['a', 'b', 'c']), 'a\n\nb\n\nc');
  });

  test('trims each part\'s OUTER whitespace only; inner newlines survive', () => {
    const out = composeStatic(['  \n# Heading\n\nline one\nline two\n\n  ', '\t rule \r\n']);
    assert.equal(out, '# Heading\n\nline one\nline two\n\nrule');
  });

  test('skips null, undefined, empty and whitespace-only parts', () => {
    assert.equal(composeStatic([null, 'a', undefined, '', '   ', '\n\n', 'b', null]), 'a\n\nb');
  });

  test('all-empty input → empty string (no stray separators)', () => {
    assert.equal(composeStatic([]), '');
    assert.equal(composeStatic([null, undefined, '', '  ']), '');
  });

  test('byte-stable: the same logical parts always yield identical bytes', () => {
    const parts = ['  Identity  ', '\nRules\n', null, 'Safety\r\n', undefined, '', 'Format'];
    const first = composeStatic(parts);
    const firstBytes = Buffer.from(first, 'utf8');
    for (let i = 0; i < 50; i++) {
      const again = composeStatic([...parts]);
      assert.equal(again, first);
      assert.equal(Buffer.compare(Buffer.from(again, 'utf8'), firstBytes), 0);
    }
  });

  test('whitespace noise around parts does not change the result', () => {
    const clean = composeStatic(['Identity', 'Rules', 'Safety']);
    const noisy = composeStatic(['\n\nIdentity\n', '   Rules', 'Safety\t\n\n']);
    assert.equal(noisy, clean);
    const withEmpties = composeStatic([null, 'Identity', '', 'Rules', '   ', 'Safety', undefined]);
    assert.equal(withEmpties, clean);
  });

  test('is pure: does not mutate the input array', () => {
    const parts = ['  a  ', null, 'b'];
    const snapshot = [...parts];
    composeStatic(parts);
    assert.deepEqual(parts, snapshot);
  });

  test('TypeError on a non-array', () => {
    for (const bad of [undefined, null, 'a', 42, { 0: 'a' }]) {
      assert.throws(() => composeStatic(bad), TypeError, `parts=${JSON.stringify(bad)}`);
    }
  });

  test('TypeError on a non-string part (never bake "[object Object]" into the cache)', () => {
    for (const bad of [42, {}, ['nested'], true, Symbol('s')]) {
      assert.throws(() => composeStatic(['ok', bad]), TypeError);
    }
  });
});

// ---------------------------------------------------------------------------
// staticSize / isCacheable
// ---------------------------------------------------------------------------
suite('staticSize and isCacheable', () => {
  test('constants', () => {
    assert.equal(MIN_CACHEABLE_TOKENS, 1024);
    assert.equal(CHARS_PER_TOKEN, 3.8);
  });

  test('staticSize reports chars and ceil(chars / 3.8)', () => {
    assert.deepEqual(staticSize(''), { chars: 0, approxTokens: 0 });
    assert.deepEqual(staticSize('abc'), { chars: 3, approxTokens: 1 });
    assert.deepEqual(staticSize('x'.repeat(38)), { chars: 38, approxTokens: 10 });
    assert.deepEqual(staticSize('x'.repeat(39)), { chars: 39, approxTokens: 11 }, 'rounds UP, never down');
    assert.deepEqual(staticSize('x'.repeat(3800)), { chars: 3800, approxTokens: 1000 });
  });

  test('staticSize treats non-strings as empty', () => {
    for (const bad of [undefined, null, 42, {}, []]) {
      assert.deepEqual(staticSize(bad), { chars: 0, approxTokens: 0 });
    }
  });

  test('isCacheable boundary at exactly MIN_CACHEABLE_TOKENS', () => {
    const below = 'x'.repeat(CACHEABLE_CHARS - 1);
    const at = 'x'.repeat(CACHEABLE_CHARS);
    assert.equal(staticSize(below).approxTokens, MIN_CACHEABLE_TOKENS - 1);
    assert.equal(staticSize(at).approxTokens, MIN_CACHEABLE_TOKENS);
    assert.equal(isCacheable(below), false);
    assert.equal(isCacheable(at), true);
    assert.equal(isCacheable('x'.repeat(CACHEABLE_CHARS + 1)), true);
  });

  test('isCacheable is false for empty and non-string input', () => {
    assert.equal(isCacheable(''), false);
    assert.equal(isCacheable(undefined), false);
    assert.equal(isCacheable(null), false);
  });
});

// ---------------------------------------------------------------------------
// describe
// ---------------------------------------------------------------------------
suite('describe', () => {
  test('array form from buildSystem: static vs dynamic tokens, cached when big enough', () => {
    const dynamic = 'Mode: chat. Date: 2026-09-23.';
    const d = describe(buildSystem({ staticText: BIG_STATIC, dynamicText: dynamic }));
    assert.deepEqual(d, {
      blocks: 2,
      staticApproxTokens: staticSize(BIG_STATIC).approxTokens,
      dynamicApproxTokens: staticSize(dynamic).approxTokens,
      cached: true,
    });
  });

  test('array form with a static block below the minimum → cached:false', () => {
    const small = 'x'.repeat(CACHEABLE_CHARS - 1);
    const d = describe(buildSystem({ staticText: small, dynamicText: 'd' }));
    assert.equal(d.blocks, 2);
    assert.equal(d.staticApproxTokens, MIN_CACHEABLE_TOKENS - 1);
    assert.equal(d.cached, false, 'a breakpoint on a too-short prefix is silently ignored by the API');
  });

  test('array form, static only → one block, zero dynamic', () => {
    const d = describe(buildSystem({ staticText: BIG_STATIC }));
    assert.deepEqual(d, {
      blocks: 1,
      staticApproxTokens: staticSize(BIG_STATIC).approxTokens,
      dynamicApproxTokens: 0,
      cached: true,
    });
  });

  test('legacy plain string → one block, all dynamic, never cached', () => {
    const d = describe(BIG_STATIC);
    assert.deepEqual(d, {
      blocks: 1,
      staticApproxTokens: 0,
      dynamicApproxTokens: staticSize(BIG_STATIC).approxTokens,
      cached: false,
    });
  });

  test('prefix semantics: unmarked blocks BEFORE the last breakpoint count as static', () => {
    const a = 'a'.repeat(3800); // 1000 tokens, no marker
    const b = 'b'.repeat(380);  // 100 tokens, marker
    const c = 'c'.repeat(38);   // 10 tokens, after the marker
    const d = describe([
      { type: 'text', text: a },
      { type: 'text', text: b, cache_control: { type: 'ephemeral' } },
      { type: 'text', text: c },
    ]);
    assert.deepEqual(d, { blocks: 3, staticApproxTokens: 1100, dynamicApproxTokens: 10, cached: true });
  });

  test('array with no breakpoint at all → everything dynamic, cached:false', () => {
    const d = describe([{ type: 'text', text: BIG_STATIC }, { type: 'text', text: 'd' }]);
    assert.equal(d.blocks, 2);
    assert.equal(d.staticApproxTokens, 0);
    assert.equal(d.dynamicApproxTokens, staticSize(BIG_STATIC).approxTokens + 1);
    assert.equal(d.cached, false);
  });

  test('ignores non-text and malformed entries, never throws on junk', () => {
    const zeros = { blocks: 0, staticApproxTokens: 0, dynamicApproxTokens: 0, cached: false };
    assert.deepEqual(describe(undefined), zeros);
    assert.deepEqual(describe(null), zeros);
    assert.deepEqual(describe(42), zeros);
    assert.deepEqual(describe({ type: 'text', text: 'not an array' }), zeros);
    assert.deepEqual(describe([]), zeros);
    const d = describe([
      null,
      { type: 'image', source: {} },
      { type: 'text', text: 123 },
      { type: 'text', text: 'ok', cache_control: { type: 'ephemeral' } },
    ]);
    assert.deepEqual(d, { blocks: 1, staticApproxTokens: 1, dynamicApproxTokens: 0, cached: false });
  });

  test('empty string → one empty block', () => {
    assert.deepEqual(describe(''), { blocks: 1, staticApproxTokens: 0, dynamicApproxTokens: 0, cached: false });
  });
});

// ---------------------------------------------------------------------------
// Round-trip through the Anthropic mock — the shape is what gets billed
// ---------------------------------------------------------------------------
suite('buildSystem output round-trips through lib/anthropicMock', () => {
  const mock = require('../lib/anthropicMock');
  beforeEach(() => mock.__resetForTest());

  function params(system, userText) {
    return {
      model: 'claude-sonnet-4-6',
      max_tokens: 200,
      system,
      messages: [{ role: 'user', content: userText }],
    };
  }

  test('first call writes the static block to cache, the second reads it; dynamic stays uncached', async () => {
    const client = mock.createMockClient({ delayMs: 1 });
    const dynamic = 'Mode: chat. Date: 2026-09-23.';
    const system = buildSystem({ staticText: BIG_STATIC, dynamicText: dynamic });

    const first = await client.messages.create(params(system, 'What is a token?'));
    assert.ok(first.usage.cache_creation_input_tokens > 0, 'first call must create the cache entry');
    assert.equal(first.usage.cache_read_input_tokens, 0);

    const second = await client.messages.create(params(system, 'And a prompt?'));
    assert.equal(second.usage.cache_creation_input_tokens, 0);
    assert.ok(second.usage.cache_read_input_tokens > 0, 'second call must be served from cache');
    assert.equal(second.usage.cache_read_input_tokens, first.usage.cache_creation_input_tokens);

    // The dynamic block is billed as plain input on BOTH calls — changing it
    // must not disturb the cached prefix.
    const changed = buildSystem({ staticText: BIG_STATIC, dynamicText: 'Mode: debate. Date: 2026-09-24.' });
    const third = await client.messages.create(params(changed, 'Hi'));
    assert.equal(third.usage.cache_creation_input_tokens, 0);
    assert.equal(third.usage.cache_read_input_tokens, first.usage.cache_creation_input_tokens);
    assert.ok(third.usage.input_tokens > 0, 'dynamic block + user turn are billed as uncached input');
  });

  test('a byte change in the static text is a cache miss (why composeStatic must be deterministic)', async () => {
    const client = mock.createMockClient({ delayMs: 1 });
    const a = buildSystem({ staticText: composeStatic(['Identity', 'Rules']), dynamicText: 'd' });
    const b = buildSystem({ staticText: composeStatic(['Identity', 'Rules ']), dynamicText: 'd' });
    assert.equal(a[0].text, b[0].text, 'composeStatic absorbs the trailing space');

    const c = buildSystem({ staticText: 'Identity\n\nRules ', dynamicText: 'd' });
    await client.messages.create(params(a, 'x'));
    const hit = await client.messages.create(params(b, 'x'));
    const miss = await client.messages.create(params(c, 'x'));
    assert.ok(hit.usage.cache_read_input_tokens > 0);
    assert.equal(miss.usage.cache_read_input_tokens, 0, 'one trailing space → a different prefix → a miss');
    assert.ok(miss.usage.cache_creation_input_tokens > 0);
  });
});
