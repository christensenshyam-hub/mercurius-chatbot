'use strict';

// scripts/quiz-length-probe.mjs — the pure parts of the [Q] length-tell
// probe: which lessons it opens and how it scores a set of checks. The probe
// itself only runs against a local eval server; nothing here calls a model.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const modP = import('../scripts/quiz-length-probe.mjs');
const CURRICULUM_SWIFT = path.join(__dirname, '..', 'ios/Packages/CurriculumFeature/Sources/Curriculum.swift');

const q = (answer, options) => `[Q]\nWhich one?\n${options.map((o, i) => `${'ABCD'[i]}) ${o}`).join('\n')}\nANS: ${answer}\n[/Q]`;

describe('quiz-length-probe', () => {
  test('deepDiveStarters: every non-Review Deep-dive lesson, the starter verbatim', async () => {
    const { deepDiveStarters } = await modP;
    const starters = deepDiveStarters(fs.readFileSync(CURRICULUM_SWIFT, 'utf8'));
    const ids = Object.keys(starters);
    assert.equal(ids.length, 27, ids.join(' '));
    assert.ok(!ids.includes('u1_l4') && !ids.includes('u6_l5') && !ids.includes('u8_l5'), 'Review lessons are left out');
    assert.equal(starters.u1_l1, '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise.');
  });

  test('quizLengthStats: the right option strictly longest, the always-longest and always-shortest picks, chance', async () => {
    const { quizzesIn, quizLengthStats } = await modP;
    const reply = [
      q('B', ['short', 'the longest option by far', 'mid one']), // right is longest
      q('A', ['tie tie', 'tie tie', 'x']), // right ties for longest: half a hit
      q('C', ['a long wrong option', 'mid wrong', 'right']), // right is shortest
    ].join('\n\n');
    const quizzes = quizzesIn(reply);
    assert.equal(quizzes.length, 3);
    const s = quizLengthStats(quizzes);
    assert.equal(s.n, 3);
    assert.equal(s.strictLongest, 1);
    assert.equal(s.longestPickHits, 1.5);
    assert.equal(s.shortestPickHits, 1);
    assert.equal(s.chance, 1);
  });

  test('quizzesIn skips a malformed [Q] (no ANS line)', async () => {
    const { quizzesIn, quizLengthStats } = await modP;
    assert.deepEqual(quizzesIn('[Q]\nWhy?\nA) one\nB) two\n[/Q]'), []);
    assert.deepEqual(quizLengthStats([]), { n: 0, strictLongest: 0, longestPickHits: 0, shortestPickHits: 0, chance: 0, lengthRatio: null });
  });
});
