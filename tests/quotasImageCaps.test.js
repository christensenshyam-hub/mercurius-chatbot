'use strict';

/**
 * Per-network image caps and the non-incrementing new-session check — both
 * added after review found that rotating session ids bypassed the per-session
 * image cap (an 8 MB upload × 60/min from one address would fill Postgres),
 * and that the session row was created before the per-IP cap was evaluated.
 */

const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const quotas = require('../lib/quotas');

describe('per-IP image quota', () => {
  beforeEach(() => {
    quotas.__resetForTest();
    quotas.configure({ IP_DAILY_IMAGES: 2, IP_DAILY_IMAGE_BYTES: 1000, SESSION_DAILY_IMAGES: 100 });
  });

  test('counts uploads across rotating session ids on one IP', () => {
    assert.equal(quotas.check({ sessionId: 'a', ip: '1.1.1.1', kind: 'image' }).ok, true);
    quotas.record({ sessionId: 'a', ip: '1.1.1.1', kind: 'image', usd: 0, bytes: 10 });
    quotas.record({ sessionId: 'b', ip: '1.1.1.1', kind: 'image', usd: 0, bytes: 10 });
    const verdict = quotas.check({ sessionId: 'c', ip: '1.1.1.1', kind: 'image' });
    assert.equal(verdict.ok, false);
    assert.equal(verdict.error, 'daily_limit');
    assert.equal(verdict.scope, 'ip');
    assert.match(verdict.message, /image upload limit/i);
    // Another network is unaffected, and so is a chat call from the capped one.
    assert.equal(quotas.check({ sessionId: 'c', ip: '2.2.2.2', kind: 'image' }).ok, true);
    assert.equal(quotas.check({ sessionId: 'c', ip: '1.1.1.1', kind: 'chat' }).ok, true);
  });

  test('caps bytes as well as count', () => {
    quotas.record({ sessionId: 'a', ip: '3.3.3.3', kind: 'image', usd: 0, bytes: 999 });
    assert.equal(quotas.check({ sessionId: 'a', ip: '3.3.3.3', kind: 'image' }).ok, true, 'one byte under');
    quotas.record({ sessionId: 'a', ip: '3.3.3.3', kind: 'image', usd: 0, bytes: 1 });
    // count is 2 (= limit) and bytes is 1000 (= limit): both trip.
    assert.equal(quotas.check({ sessionId: 'b', ip: '3.3.3.3', kind: 'image' }).ok, false);
  });
});

describe('newSessionAllowed', () => {
  beforeEach(() => {
    quotas.__resetForTest();
    quotas.configure({ IP_DAILY_NEW_SESSIONS: 2 });
  });

  test('asks without counting; noteNewSession counts', () => {
    assert.equal(quotas.newSessionAllowed('5.5.5.5').ok, true);
    assert.equal(quotas.newSessionAllowed('5.5.5.5').ok, true, 'asking twice does not consume');
    assert.equal(quotas.noteNewSession('5.5.5.5').ok, true);
    assert.equal(quotas.noteNewSession('5.5.5.5').ok, true);
    const verdict = quotas.newSessionAllowed('5.5.5.5');
    assert.equal(verdict.ok, false);
    assert.equal(verdict.error, 'daily_limit');
    assert.equal(verdict.scope, 'ip');
    assert.equal(quotas.noteNewSession('5.5.5.5').ok, false);
  });

  test('no ip → always allowed', () => {
    assert.equal(quotas.newSessionAllowed(undefined).ok, true);
    assert.equal(quotas.newSessionAllowed('').ok, true);
  });
});
