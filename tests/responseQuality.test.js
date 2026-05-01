'use strict';

/**
 * Unit tests for `lib/responseQuality.js`. The module is pure — no
 * Anthropic, no DB, no network — so these run in milliseconds and
 * cover the full response-quality contract before the integration
 * suite ever spawns a server.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const {
  RESPONSE_QUALITY_PREAMBLE,
  MODE_RULES,
  RESPONSE_MODE_BUDGETS,
  EXPAND_MODE_NOTE,
  VALID_RESPONSE_MODES,
  resolveResponseMode,
  modeRulesFor,
  qualityPrefix,
} = require('../lib/responseQuality');

describe('RESPONSE_QUALITY_PREAMBLE', () => {
  test('mentions the mobile-friendly defaults', () => {
    // Reads as a "are the rules right" smoke test, not a brittle
    // string-match. If we re-word the preamble, only the keywords
    // we actually rely on need to stay.
    const text = RESPONSE_QUALITY_PREAMBLE.toLowerCase();
    assert.ok(text.includes('direct answer'),  'should ask for the direct answer first');
    assert.ok(text.includes('phone screen'),   'should mention mobile formatting');
    assert.ok(text.includes('skip filler'),    'should ban filler');
    assert.ok(text.includes('explain more'),   'should reference the Explain More flow');
  });
});

describe('MODE_RULES', () => {
  test('covers every app mode and only those modes', () => {
    const expected = ['socratic', 'direct', 'debate', 'discussion'];
    assert.deepEqual(Object.keys(MODE_RULES).sort(), [...expected].sort());
  });

  test('debate rules carry the claim/warrant/impact/rebuttal frame', () => {
    const text = MODE_RULES.debate.toLowerCase();
    for (const piece of ['claim', 'warrant', 'impact', 'rebuttal']) {
      assert.ok(text.includes(piece), `debate mode should mention ${piece}`);
    }
  });

  test('socratic rules ask one question at a time, not full answers', () => {
    const text = MODE_RULES.socratic.toLowerCase();
    assert.ok(text.includes('one strong question'), 'socratic should lead with one question');
    assert.ok(text.includes("don't dump"), 'socratic should not dump answers up front');
  });

  test('direct rules emphasize plain efficient answers', () => {
    const text = MODE_RULES.direct.toLowerCase();
    assert.ok(text.includes('plain'), 'direct should be plain');
    assert.ok(text.includes('no teaching framing') || text.includes('no socratic'),
      'direct should reject teaching/socratic framing');
  });

  test('discussion rules ask for tradeoffs and an open follow-up', () => {
    const text = MODE_RULES.discussion.toLowerCase();
    assert.ok(text.includes('tradeoff'), 'discussion should surface tradeoffs');
    assert.ok(text.includes('follow-up question') || text.includes('open thought'),
      'discussion should leave a thread to pull');
  });
});

describe('RESPONSE_MODE_BUDGETS', () => {
  test('exposes exactly the four canonical response_modes', () => {
    const expected = ['one_line', 'concise', 'balanced', 'deep'];
    assert.deepEqual(Object.keys(RESPONSE_MODE_BUDGETS).sort(), [...expected].sort());
  });

  test('token caps are monotonically increasing one_line → deep', () => {
    const order = ['one_line', 'concise', 'balanced', 'deep'];
    let prev = -Infinity;
    for (const k of order) {
      const cap = RESPONSE_MODE_BUDGETS[k].maxTokens;
      assert.ok(cap > prev, `${k}'s maxTokens (${cap}) should exceed prev (${prev})`);
      prev = cap;
    }
  });

  test('one_line cap is in the 80–120 range from the spec', () => {
    const cap = RESPONSE_MODE_BUDGETS.one_line.maxTokens;
    assert.ok(cap >= 80 && cap <= 120, `one_line cap should be 80–120, got ${cap}`);
  });

  test('concise cap is in the 200–300 range (tightened May 2026)', () => {
    // The pre-tightening cap was 400; QA found that still felt long on
    // mobile. New range pulls it to 200–300 so the model is forced to
    // land in 2–4 sentences. Drift higher than 300 = regression.
    const cap = RESPONSE_MODE_BUDGETS.concise.maxTokens;
    assert.ok(cap >= 200 && cap <= 300, `concise cap should be 200–300, got ${cap}`);
  });

  test('balanced cap is in the 500–700 range (sits comfortably above concise)', () => {
    const cap = RESPONSE_MODE_BUDGETS.balanced.maxTokens;
    assert.ok(cap >= 500 && cap <= 700, `balanced cap should be 500–700, got ${cap}`);
  });

  test('deep cap is in the 1000–1400 range from the spec', () => {
    const cap = RESPONSE_MODE_BUDGETS.deep.maxTokens;
    assert.ok(cap >= 1000 && cap <= 1400, `deep cap should be 1000–1400, got ${cap}`);
  });

  test('temperature is non-negative and bounded under 1.0', () => {
    for (const m of Object.keys(RESPONSE_MODE_BUDGETS)) {
      const t = RESPONSE_MODE_BUDGETS[m].temperature;
      assert.ok(t >= 0 && t <= 1, `${m}'s temperature (${t}) should be in [0,1]`);
    }
  });

  test('one_line + concise have the lowest temperatures (kept on-task)', () => {
    assert.ok(RESPONSE_MODE_BUDGETS.one_line.temperature <= RESPONSE_MODE_BUDGETS.balanced.temperature);
    assert.ok(RESPONSE_MODE_BUDGETS.concise.temperature  <= RESPONSE_MODE_BUDGETS.balanced.temperature);
  });

  test('VALID_RESPONSE_MODES matches the budget table keys', () => {
    assert.deepEqual([...VALID_RESPONSE_MODES].sort(),
                     Object.keys(RESPONSE_MODE_BUDGETS).sort());
  });
});

describe('resolveResponseMode', () => {
  test('passes valid modes through unchanged', () => {
    for (const m of ['one_line', 'concise', 'balanced', 'deep']) {
      assert.equal(resolveResponseMode(m), m);
    }
  });

  test('falls back to concise for missing input (mobile default)', () => {
    assert.equal(resolveResponseMode(undefined), 'concise');
    assert.equal(resolveResponseMode(null),      'concise');
    assert.equal(resolveResponseMode(''),        'concise');
  });

  test('falls back to concise for unknown / mistyped values', () => {
    assert.equal(resolveResponseMode('verbose'),  'concise');
    assert.equal(resolveResponseMode('OneLine'),  'concise');
    assert.equal(resolveResponseMode(42),         'concise');
    assert.equal(resolveResponseMode({}),         'concise');
  });
});

describe('modeRulesFor + qualityPrefix', () => {
  test('returns the right block per mode', () => {
    assert.equal(modeRulesFor('socratic'),   MODE_RULES.socratic);
    assert.equal(modeRulesFor('direct'),     MODE_RULES.direct);
    assert.equal(modeRulesFor('debate'),     MODE_RULES.debate);
    assert.equal(modeRulesFor('discussion'), MODE_RULES.discussion);
  });

  test('unknown mode falls back to socratic (the default app mode)', () => {
    assert.equal(modeRulesFor('nope'),     MODE_RULES.socratic);
    assert.equal(modeRulesFor(undefined),  MODE_RULES.socratic);
  });

  test('qualityPrefix concatenates preamble + mode rules in that order', () => {
    const prefix = qualityPrefix('debate');
    assert.ok(prefix.startsWith(RESPONSE_QUALITY_PREAMBLE),
      'preamble must come first so concision rules are read before mode rules');
    assert.ok(prefix.includes(MODE_RULES.debate),
      'mode rules must be embedded in the prefix');
  });

  test('qualityPrefix is non-trivial — guard against accidental empty', () => {
    // Catches a regression where someone refactors the constants and
    // accidentally leaves the prefix empty.
    for (const m of ['socratic', 'direct', 'debate', 'discussion']) {
      assert.ok(qualityPrefix(m).length > 100, `${m} prefix should be non-trivial`);
    }
  });
});

describe('EXPAND_MODE_NOTE', () => {
  test('asks the model to expand without repeating', () => {
    const text = EXPAND_MODE_NOTE.toLowerCase();
    assert.ok(text.includes('explain more'));
    assert.ok(text.includes("don't repeat") || text.includes('not repeat'));
  });
});
