'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const { parseUnitTestGrade, buildGraderUserMessage } = require('../lib/unitTestGrader');

describe('parseUnitTestGrade', () => {
  test('parses a clean JSON grade and keeps the feedback', () => {
    const out = parseUnitTestGrade('{"grade":"A","pass":true,"feedback":"Great reasoning."}');
    assert.deepEqual(out, { grade: 'A', pass: true, feedback: 'Great reasoning.' });
  });

  test('pass is RE-DERIVED from the letter, not trusted from the model', () => {
    // Model says pass:false but grade B → pass must be true.
    assert.equal(parseUnitTestGrade('{"grade":"B","pass":false,"feedback":"x"}').pass, true);
    // Model says pass:true but grade C/D → pass must be false.
    assert.equal(parseUnitTestGrade('{"grade":"C","pass":true,"feedback":"x"}').pass, false);
    assert.equal(parseUnitTestGrade('{"grade":"D","pass":true,"feedback":"x"}').pass, false);
  });

  test('extracts the JSON object out of surrounding prose', () => {
    const out = parseUnitTestGrade('Here is the grade:\n{"grade":"B","pass":true,"feedback":"Solid."}\nThanks!');
    assert.equal(out.grade, 'B');
    assert.equal(out.pass, true);
  });

  test('missing feedback falls back to a non-empty default for pass and fail', () => {
    const passing = parseUnitTestGrade('{"grade":"A"}');
    assert.equal(passing.grade, 'A');
    assert.ok(passing.feedback.length > 0);
    const failing = parseUnitTestGrade('{"grade":"D"}');
    assert.ok(failing.feedback.length > 0);
  });

  test('an unparseable, grade-less, or out-of-range reply returns null', () => {
    assert.equal(parseUnitTestGrade('not json at all'), null);
    assert.equal(parseUnitTestGrade('{"feedback":"no grade here"}'), null);
    assert.equal(parseUnitTestGrade('{"grade":"Z","pass":true}'), null);
    assert.equal(parseUnitTestGrade(undefined), null);
  });
});

describe('buildGraderUserMessage', () => {
  test('includes the unit, question, and the student answer', () => {
    const msg = buildGraderUserMessage({
      unitTitle: 'Bias & Fairness',
      defensePrompt: 'Name two ways bias enters.',
      answer: 'Skewed data and biased labels.',
    });
    assert.ok(msg.includes('Bias & Fairness'));
    assert.ok(msg.includes('Name two ways bias enters.'));
    assert.ok(msg.includes('Skewed data and biased labels.'));
  });
});
