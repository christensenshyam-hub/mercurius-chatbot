'use strict';

/**
 * The daily-limit copy in lib/quotas.js is read by more than the server
 * (AUD-30):
 *
 *   - Shipped iOS builds (2.0.0, 2.3.0) and the widget show it verbatim, so
 *     a network's allowance must say what to do now: switch to cellular.
 *   - PR #43's iOS client parses lib/quotas.js in its own tests
 *     (ServerRefusalQuotaContractTests) with the regexes below, tells a
 *     network's allowance from a student's by the copy when the frame has no
 *     scope, and swaps each sentence that says "tomorrow" for a local clock
 *     time. This mirrors those checks so a server-side copy edit that would
 *     break that client fails here first.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const quotas = require('../lib/quotas');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'lib', 'quotas.js'), 'utf8');

// The same patterns as ServerRefusalTests.swift.
function dailyMessages(source) {
  const tomorrow = /const TOMORROW = '([^']*)';/.exec(source);
  assert.ok(tomorrow, 'const TOMORROW = \'…\'; is still a single-quoted literal');
  const start = source.indexOf('const DAILY_MESSAGES');
  assert.ok(start >= 0);
  const end = source.indexOf('});', start);
  const messages = {};
  for (const line of source.slice(start + 'const DAILY_MESSAGES'.length, end).split('\n')) {
    const m = /^\s*(\w+):\s*[`'](.*)[`'],?\s*$/.exec(line);
    if (m) messages[m[1]] = m[2].replaceAll('${TOMORROW}', tomorrow[1]);
  }
  return messages;
}

function dailyLimitCalls(source) {
  return [...source.matchAll(/dailyLimit\('(\w+)', '(\w+)'\)/g)].map((m) => ({ scope: m[1], reason: m[2] }));
}

// ServerRefusal.isNetworkScoped without a wire scope.
const namesNetwork = (copy) => ['network', 'wi-fi', 'wifi'].some((w) => copy.toLowerCase().includes(w));

// ServerRefusal.droppingTomorrow.
function droppingTomorrow(message) {
  const sentences = [];
  let current = '';
  const chars = [...message];
  chars.forEach((c, i) => {
    current += c;
    const atBoundary = i + 1 === chars.length || /\s/.test(chars[i + 1]);
    if ('.!?'.includes(c) && atBoundary) { sentences.push(current); current = ''; }
  });
  sentences.push(current);
  const kept = sentences.map((x) => x.trim()).filter(Boolean).filter((x) => !x.toLowerCase().includes('tomorrow'));
  return kept.length ? kept.join(' ') : "You've reached today's limit.";
}

describe('daily-limit copy contract (AUD-30, PR #43)', () => {
  const messages = dailyMessages(SOURCE);
  const calls = dailyLimitCalls(SOURCE);

  test('the parse finds every message, and every dailyLimit call has one', () => {
    assert.ok(Object.keys(messages).length >= 7, JSON.stringify(messages));
    assert.ok(calls.some((c) => c.scope === 'ip') && calls.some((c) => c.scope === 'session'));
    for (const c of calls) assert.ok(messages[c.reason], `no DAILY_MESSAGES line for ${c.reason}`);
  });

  test('the parsed copy is exactly what the server sends', () => {
    quotas.__resetForTest();
    quotas.configure({ SESSION_DAILY_CHAT_TURNS: 0, IP_DAILY_NEW_SESSIONS: 0 });
    assert.equal(quotas.check({ sessionId: 's', ip: '10.1.1.1', kind: 'chat' }).message, messages.chat_turns);
    assert.equal(quotas.noteNewSession('10.1.1.1').message, messages.new_sessions);
    quotas.__resetForTest();
  });

  test("the copy alone tells the network's allowance from the student's", () => {
    for (const c of calls) {
      assert.equal(namesNetwork(messages[c.reason]), c.scope === 'ip', `${c.scope} ${c.reason}: ${messages[c.reason]}`);
    }
  });

  test('every network allowance says cellular data works now, and only those do', () => {
    for (const c of calls) {
      const copy = messages[c.reason];
      assert.equal(/cellular/i.test(copy), c.scope === 'ip', `${c.reason}: ${copy}`);
    }
  });

  test('every message says "tomorrow", and in a sentence the clock time can replace', () => {
    for (const [reason, copy] of Object.entries(messages)) {
      assert.match(copy, /tomorrow/, reason);
      const kept = droppingTomorrow(copy);
      assert.ok(!/tomorrow/i.test(kept), `${reason}: ${kept}`);
      // PR #43 adds its own cellular sentence to a network's allowance, so
      // the server's must go with the "tomorrow" sentence, not be repeated.
      assert.ok(!/cellular/i.test(kept), `${reason}: the cellular advice would show twice: ${kept}`);
      assert.ok(kept.length > 10, `${reason}: something of the copy is left (${kept})`);
    }
  });
});
