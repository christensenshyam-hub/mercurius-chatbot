'use strict';

// Tests for lib/pricing — the rate card and the usage → USD arithmetic that
// the daily spend cap (lib/spendCap) accumulates.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const pricing = require('../lib/pricing');
const { PRICES, priceFor, hasRateCard, costUsd, normalizeUsage, estimateTokens } = pricing;

const SONNET = PRICES['claude-sonnet-4-6'];
const SONNET_55 = PRICES['claude-sonnet-5-5'];
const HAIKU = PRICES['claude-haiku-4-5'];

// Floating-point dollar sums: compare to the cent-of-a-cent.
function close(actual, expected, msg) {
  assert.ok(Math.abs(actual - expected) < 1e-9, msg || `expected ${expected}, got ${actual}`);
}

describe('PRICES', () => {
  test('carries the two allowlisted families at list price', () => {
    assert.deepEqual(SONNET, { in: 3, out: 15, cacheWrite: 3.75, cacheRead: 0.30 });
    assert.deepEqual(HAIKU, { in: 1, out: 5, cacheWrite: 1.25, cacheRead: 0.10 });
  });

  test('carries Claude Sonnet 5.5 (TUTOR_MODEL) and Sonnet 5 at $2 / $10, cache write $2.50, read $0.20', () => {
    assert.deepEqual(SONNET_55, { in: 2, out: 10, cacheWrite: 2.50, cacheRead: 0.20 });
    assert.deepEqual(PRICES['claude-sonnet-5'], { in: 2, out: 10, cacheWrite: 2.50, cacheRead: 0.20 });
    assert.deepEqual(Object.keys(PRICES).sort(), ['claude-haiku-4-5', 'claude-sonnet-4-6', 'claude-sonnet-5', 'claude-sonnet-5-5']);
  });

  test('the fallback card is still the most expensive one, so a mis-priced id only over-counts', () => {
    const fallback = PRICES[pricing.FALLBACK_MODEL];
    for (const [id, p] of Object.entries(PRICES)) {
      assert.ok(p.in <= fallback.in && p.out <= fallback.out, id);
    }
  });

  test('cache weighting: write = 1.25× input, read = 0.1× input, on every card', () => {
    for (const [id, p] of Object.entries(PRICES)) {
      close(p.cacheWrite, p.in * 1.25, `${id} cacheWrite`);
      close(p.cacheRead, p.in * 0.1, `${id} cacheRead`);
    }
  });

  test('is frozen — a caller cannot mutate the rate card', () => {
    assert.ok(Object.isFrozen(PRICES));
    assert.ok(Object.isFrozen(SONNET));
    assert.throws(() => { 'use strict'; SONNET.in = 0; });
  });
});

describe('priceFor', () => {
  test('exact ids resolve to their card', () => {
    assert.equal(priceFor('claude-sonnet-4-6'), SONNET);
    assert.equal(priceFor('claude-haiku-4-5'), HAIKU);
  });

  test('dated snapshots and -latest aliases resolve by prefix', () => {
    assert.equal(priceFor('claude-haiku-4-5-20251001'), HAIKU);
    assert.equal(priceFor('claude-haiku-4-5-latest'), HAIKU);
    assert.equal(priceFor('claude-sonnet-4-6-20260101'), SONNET);
    assert.equal(priceFor('claude-sonnet-4-6-latest'), SONNET);
  });

  test('Sonnet 5.5 resolves exactly and by prefix, never to the shorter Sonnet 5 key', () => {
    assert.equal(priceFor('claude-sonnet-5-5'), SONNET_55);
    assert.equal(priceFor('claude-sonnet-5-5-20261001'), SONNET_55);
    assert.equal(priceFor('claude-sonnet-5'), PRICES['claude-sonnet-5']);
    assert.equal(priceFor('claude-sonnet-5-20260101'), PRICES['claude-sonnet-5']);
    assert.equal(priceFor('claude-sonnet-5-55'), PRICES['claude-sonnet-5'], '"5-55" is Sonnet 5 plus a suffix, not "5-5" (the prefix ends at a "-" boundary)');
  });

  test('matching is case/whitespace tolerant', () => {
    assert.equal(priceFor('  Claude-Haiku-4-5  '), HAIKU);
  });

  test('unknown models fall back to Sonnet rates (conservative)', () => {
    assert.equal(priceFor('claude-4-opus-extra-expensive'), SONNET);
    assert.equal(priceFor('claude-3-5-haiku-latest'), SONNET);
    assert.equal(priceFor('claude-haiku-4-55'), SONNET, 'prefix must end at a "-" boundary');
    assert.equal(priceFor(''), SONNET);
    assert.equal(priceFor(undefined), SONNET);
    assert.equal(priceFor(null), SONNET);
  });
});

describe('hasRateCard', () => {
  test('true for each card and its dated ids; false for anything priced by the fallback', () => {
    for (const id of ['claude-sonnet-4-6', 'claude-sonnet-5-5', 'claude-sonnet-5-5-20261001', 'claude-haiku-4-5-20251001', 'claude-sonnet-5']) {
      assert.equal(hasRateCard(id), true, id);
    }
    for (const id of ['claude-opus-5-5', 'claude-sonet-5-5', '', undefined]) assert.equal(hasRateCard(id), false, String(id));
  });
});

describe('costUsd', () => {
  test('one million of each class costs exactly the card rate (Sonnet)', () => {
    const M = 1_000_000;
    close(costUsd('claude-sonnet-4-6', { input_tokens: M }), 3);
    close(costUsd('claude-sonnet-4-6', { output_tokens: M }), 15);
    close(costUsd('claude-sonnet-4-6', { cache_creation_input_tokens: M }), 3.75);
    close(costUsd('claude-sonnet-4-6', { cache_read_input_tokens: M }), 0.30);
  });

  test('one million of each class costs exactly the card rate (Haiku)', () => {
    const M = 1_000_000;
    close(costUsd('claude-haiku-4-5', { input_tokens: M }), 1);
    close(costUsd('claude-haiku-4-5', { output_tokens: M }), 5);
    close(costUsd('claude-haiku-4-5', { cache_creation_input_tokens: M }), 1.25);
    close(costUsd('claude-haiku-4-5', { cache_read_input_tokens: M }), 0.10);
  });

  test('sums the four disjoint classes', () => {
    const usage = {
      input_tokens: 1000,
      output_tokens: 500,
      cache_read_input_tokens: 20_000,
      cache_creation_input_tokens: 4000,
    };
    const expected = (1000 * 3 + 500 * 15 + 20_000 * 0.30 + 4000 * 3.75) / 1e6;
    close(costUsd('claude-sonnet-4-6', usage), expected);
  });

  test('a typical cached chat turn is dominated by output, not the cached prefix', () => {
    // 8k-token system prompt served from cache + 300 fresh input + 400 output.
    const usage = { cache_read_input_tokens: 8000, input_tokens: 300, output_tokens: 400 };
    const cachedPart = 8000 * 0.30 / 1e6;
    const outputPart = 400 * 15 / 1e6;
    assert.ok(cachedPart < outputPart, 'cache reads must be the cheap part');
    close(costUsd('claude-sonnet-4-6', usage), cachedPart + outputPart + 300 * 3 / 1e6);
  });

  test('missing, NaN, negative and non-object usage all count as $0', () => {
    assert.equal(costUsd('claude-sonnet-4-6', undefined), 0);
    assert.equal(costUsd('claude-sonnet-4-6', null), 0);
    assert.equal(costUsd('claude-sonnet-4-6', {}), 0);
    assert.equal(costUsd('claude-sonnet-4-6', { input_tokens: NaN, output_tokens: 'x' }), 0);
    assert.equal(costUsd('claude-sonnet-4-6', { input_tokens: -500 }), 0);
    assert.equal(costUsd('claude-sonnet-4-6', 'not-an-object'), 0);
  });

  test('unknown model is priced at Sonnet rates', () => {
    close(costUsd('claude-mystery-9', { input_tokens: 1_000_000 }), 3);
  });

  test('one million of each class costs exactly the card rate (Sonnet 5.5)', () => {
    const M = 1_000_000;
    close(costUsd('claude-sonnet-5-5', { input_tokens: M }), 2);
    close(costUsd('claude-sonnet-5-5', { output_tokens: M }), 10);
    close(costUsd('claude-sonnet-5-5', { cache_creation_input_tokens: M }), 2.50);
    close(costUsd('claude-sonnet-5-5', { cache_read_input_tokens: M }), 0.20);
  });

  test('the same cached turn on Sonnet 5.5 costs 2/3 of Sonnet 4.6 per token', () => {
    const usage = { cache_read_input_tokens: 8000, cache_creation_input_tokens: 200, input_tokens: 300, output_tokens: 400 };
    close(costUsd('claude-sonnet-5-5', usage), costUsd('claude-sonnet-4-6', usage) * 2 / 3);
  });
});

describe('normalizeUsage', () => {
  test('maps SDK field names to the four classes with NaN → 0', () => {
    assert.deepEqual(
      normalizeUsage({ input_tokens: 10, output_tokens: '20', cache_read_input_tokens: NaN }),
      { input: 10, output: 20, cacheRead: 0, cacheWrite: 0 }
    );
    assert.deepEqual(normalizeUsage(undefined), { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  });
});

describe('estimateTokens', () => {
  test('is ceil(length / 3.8)', () => {
    assert.equal(estimateTokens('a'.repeat(38)), 10);
    assert.equal(estimateTokens('a'.repeat(39)), 11); // 10.26 → ceil → 11
    assert.equal(estimateTokens('a'), 1);
  });

  test('empty / missing / non-string input', () => {
    assert.equal(estimateTokens(''), 0);
    assert.equal(estimateTokens(undefined), 0);
    assert.equal(estimateTokens(null), 0);
    assert.equal(estimateTokens(12345), 2); // String(12345).length === 5 → ceil(1.3)
  });

  test('Sonnet 4.6, Haiku 4.5 and unknown models count as before', () => {
    for (const model of ['claude-sonnet-4-6', 'claude-haiku-4-5', 'claude-mystery-9', undefined]) {
      assert.equal(estimateTokens('a'.repeat(38), model), 10, String(model));
      assert.equal(estimateTokens('a'.repeat(39), model), 11, String(model));
    }
  });

  test('Sonnet 5.5 and Sonnet 5 count ~30% more tokens for the same text (their tokenizer)', () => {
    assert.equal(pricing.TOKENIZER_RATIO['claude-sonnet-5-5'], 1.3);
    assert.equal(estimateTokens('a'.repeat(38), 'claude-sonnet-5-5'), 13, 'exactly 13, no float-noise extra token');
    assert.equal(estimateTokens('a'.repeat(38), 'claude-sonnet-5-5-20261001'), 13);
    assert.equal(estimateTokens('a'.repeat(39), 'claude-sonnet-5'), 14); // 10.26 × 1.3 = 13.34 → 14
    assert.equal(estimateTokens('', 'claude-sonnet-5-5'), 0);
  });
});
