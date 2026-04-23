'use strict';

/**
 * Unit tests for lib/modelAllowlist.js. The integration-level 400
 * behavior (caller supplies an off-allowlist model on /api/chat) is
 * covered inside tests/server.test.js. Here we drive the pure logic.
 */

const { describe, test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const { pickModel, allowedSet, _DEFAULT_ALLOWED } = require('../lib/modelAllowlist');

const ORIGINAL_ENV = process.env.MODEL_ALLOWLIST;

beforeEach(() => {
  delete process.env.MODEL_ALLOWLIST;
});

afterEach(() => {
  if (ORIGINAL_ENV === undefined) {
    delete process.env.MODEL_ALLOWLIST;
  } else {
    process.env.MODEL_ALLOWLIST = ORIGINAL_ENV;
  }
});

describe('allowedSet', () => {
  test('falls back to DEFAULT_ALLOWED when MODEL_ALLOWLIST is unset', () => {
    const set = allowedSet();
    for (const m of _DEFAULT_ALLOWED) {
      assert.ok(set.has(m), `default allowlist should contain ${m}`);
    }
  });

  test('parses a comma-separated env var', () => {
    process.env.MODEL_ALLOWLIST = 'alpha, beta ,gamma';
    const set = allowedSet();
    assert.ok(set.has('alpha'));
    assert.ok(set.has('beta'));
    assert.ok(set.has('gamma'));
    assert.equal(set.size, 3);
  });

  test('trims whitespace and drops empties', () => {
    process.env.MODEL_ALLOWLIST = ' a , ,b ,';
    const set = allowedSet();
    assert.equal(set.size, 2);
    assert.ok(set.has('a'));
    assert.ok(set.has('b'));
  });

  test('empty MODEL_ALLOWLIST falls back to defaults, not an empty set', () => {
    // Real risk: an operator sets MODEL_ALLOWLIST='' to wipe it, and
    // ends up locking the server out of every model. We guard against
    // this by treating empty → fall back to DEFAULT_ALLOWED.
    process.env.MODEL_ALLOWLIST = '';
    const set = allowedSet();
    assert.ok(set.size >= _DEFAULT_ALLOWED.length);
    for (const m of _DEFAULT_ALLOWED) {
      assert.ok(set.has(m));
    }
  });
});

describe('pickModel', () => {
  test('falls back to the default when no model is requested', () => {
    const out = pickModel(undefined, 'server-default');
    assert.equal(out.model, 'server-default');
    assert.equal(out.error, null);
  });

  test('treats empty-string / null like "no model requested"', () => {
    assert.equal(pickModel('', 'x').model, 'x');
    assert.equal(pickModel(null, 'x').model, 'x');
  });

  test('accepts a requested model that is on the default allowlist', () => {
    const out = pickModel('claude-sonnet-4-6', 'claude-sonnet-4-6');
    assert.equal(out.model, 'claude-sonnet-4-6');
    assert.equal(out.error, null);
  });

  test('rejects a requested model that is not on the allowlist', () => {
    const out = pickModel('gpt-5-turbo-ultra', 'claude-sonnet-4-6');
    assert.equal(out.model, null);
    assert.ok(/not on the allowlist/.test(out.error));
  });

  test('rejects even when the requested model is only one letter off', () => {
    // Typosquatting defense — no fuzzy matching.
    const out = pickModel('claude-sonnet-4-5', 'claude-sonnet-4-6');
    assert.equal(out.model, null);
  });

  test('respects MODEL_ALLOWLIST when set', () => {
    process.env.MODEL_ALLOWLIST = 'custom-model-one,custom-model-two';
    // Default allowlist's model is now OFF the list.
    const offList = pickModel('claude-sonnet-4-6', 'custom-model-one');
    assert.equal(offList.model, null);
    // A custom one is on the list.
    const onList = pickModel('custom-model-two', 'custom-model-one');
    assert.equal(onList.model, 'custom-model-two');
  });

  test('does not allow empty-string model override to reach the allowlist check', () => {
    // "" means "no model" → fall back to default; should NOT try to
    // look up "" in the allowlist.
    process.env.MODEL_ALLOWLIST = 'only-allowed';
    const out = pickModel('', 'only-allowed');
    assert.equal(out.model, 'only-allowed');
    assert.equal(out.error, null);
  });
});
