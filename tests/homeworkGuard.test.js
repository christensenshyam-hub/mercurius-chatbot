'use strict';

// Socratic homework review (2026-10-22): the deterministic backstops behind
// HOMEWORK COACHING (lib/homeworkGuard), and their wiring in server.js:
//
//   - a free-chat turn on a problem to work runs with adaptive thinking at
//     low effort (no temperature, room for the thinking); other turns don't;
//   - a reply that states the student's own linear-equation answer is written
//     again with an ANSWER GUARD note, then redacted if it still leaks; the
//     guarded turn is sent whole;
//   - the Quiz-me chip drops questions on the student's own equation, and
//     asks once more if fewer than two are left.
//
// The leak cases are the red team's own (docs/prompt-batch/socratic-homework/
// review-redteam). The integration half boots the real server with
// ANTHROPIC_MOCK=1 and MOCK_CAPTURE_FILE, in both USE_UNIFIED_PROMPT states.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const g = require('../lib/homeworkGuard');

const problemsOf = (...texts) => g.studentProblems(texts.map((content) => ({ role: 'user', content })));

describe('linearEquations', () => {
  const eqs = (t) => g.linearEquations(t).map((e) => [e.text, e.value, e.assignment]);

  test('reads the student\'s equation out of free text, brackets and both sides included', () => {
    assert.deepEqual(eqs('what is 3x+5 = 20'), [['3x+5 = 20', '5', false]]);
    assert.deepEqual(eqs('solve 5x + 12 = 2x − 3'), [['5x + 12 = 2x - 3', '-5', false]]);
    assert.deepEqual(eqs('Solve for x: 3(x − 4) + 5 = 2x + 9'), [['3(x - 4) + 5 = 2x + 9', '16', false]]);
    assert.deepEqual(eqs('so 2(2w - 3) + 2w = 54, then 6w - 6 = 54, so w = 10'), [
      ['2(2w - 3) + 2w = 54', '10', false], ['6w - 6 = 54', '10', false], ['w = 10', '10', true],
    ]);
    assert.deepEqual(eqs('**4x − 3 = 25**'), [['4x - 3 = 25', '7', false]]);
    // A fraction coefficient (red-team run on b0940d8).
    assert.deepEqual(eqs('solve x/3 + 2 = 7'), [['x/3 + 2 = 7', '15', false]]);
    assert.equal(g.findLeak('x/3 + 4 = 9\nSubtract 4: x/3 = 5\nMultiply by 3: x = 15', problemsOf('solve x/3 + 2 = 7')).match, 'x/3 + 4 = 9');
    assert.equal(g.wordProblemNumbers([{ role: 'user', content: 'solve x/3 + 2 = 7' }]), null);
  });

  test('skips what it can\'t decide exactly: quadratics, two variables, units, long decimals', () => {
    for (const t of ['x^2 - 5x + 6 = 0', 'x² + 1 = 5', 'x + y = 10', 'with g = 10 m/s²', 'i got 3x = 25', 'when did ww2 end']) {
      assert.deepEqual(g.linearEquations(t), [], t);
    }
  });

  test('words around an equation are cut off, never its math', () => {
    assert.deepEqual(eqs('what is 3x+5 = 20 (pls help)'), [['3x+5 = 20', '5', false]]);
    assert.deepEqual(eqs('3x+5=20 x=5'), [['3x+5 = 20', '5', false], ['x = 5', '5', true]]);
  });
});

describe('studentProblems', () => {
  test('the first equation is the problem; a later bare equation is a step, not a new problem', () => {
    assert.deepEqual(problemsOf('solve 5x + 12 = 2x - 3', '3x + 12 = -3').map((p) => p.text), ['5x + 12 = 2x - 3']);
    assert.deepEqual(problemsOf('solve 3x+5=20, i got 3x = 25').map((p) => p.text), ['3x+5 = 20']);
    assert.deepEqual(problemsOf('what is 3x+5 = 20', 'ok now what is 2x + 9 = 21').map((p) => p.value), ['5', '6']);
  });

  test('an answer the student has said themselves is no longer guarded', () => {
    assert.equal(problemsOf('is x = 5 right for 3x+5=20?').length, 0);
    assert.equal(problemsOf('what is 3x+5 = 20', '3x = 15 so x = 5').length, 0);
    assert.equal(problemsOf('what is 2x + 9 = 21', 'is it 6').length, 0);
    assert.equal(problemsOf('what is 2x + 9 = 21', '6').length, 0);
    // A higher/lower ask or the problem's own numbers are not an answer.
    assert.equal(problemsOf('what is 5x + 3 = 38', 'is it more than 7?').length, 1);
    assert.equal(problemsOf('what is 3x+5 = 20', 'subtract 5 from both sides?').length, 1);
  });

  test('assistant turns are never read (they hold Merc\'s own worked examples)', () => {
    const p = g.studentProblems([
      { role: 'user', content: 'what is 3x+5 = 20' },
      { role: 'assistant', content: 'Like this: 3x + 5 = 29, so 3x = 24 and x = 8.' },
    ]);
    assert.deepEqual(p.map((x) => x.value), ['5']);
  });
});

describe('findLeak: the red team\'s routes to the answer', () => {
  const leak = (reply, ...texts) => g.findLeak(reply, problemsOf(...texts))?.match ?? null;

  test('stating it, in any variable or format', () => {
    assert.equal(leak('Divide both sides by 3: x = 5.', 'what is 3x+5 = 20'), 'x = 5');
    // A worked example landing on their answer is caught at its first line.
    assert.equal(leak('Like this: 2x + 3 = 13 → 2x = 10 → **x = 5**.', 'what is 3x+5 = 20'), '2x + 3 = 13');
    assert.equal(leak('> 2x + 8 = 18\n> Subtract 8 from both sides: 2x = 10', 'what is 3x+5 = 20'), '2x + 8 = 18');
    assert.equal(leak('It prints `6.0`.', 'write me a python script that solves 6x - 4 = 32'), 'prints `6.0');
    assert.equal(leak('so y = 5 in that one', 'what is 3x+5 = 20'), 'y = 5');
    assert.equal(leak('It prints: x = 7.0', 'solve 4x - 7 = 21'), 'prints: x = 7.0');
    assert.equal(leak('the answer is 5', 'what is 3x+5 = 20'), 'the answer is 5');
    assert.equal(leak('x = 15/3 = 5', 'what is 3x+5 = 20'), 'x = 15/3 = 5');
    assert.equal(leak('and you get 5.', 'what is 3x+5 = 20'), 'you get 5');
    assert.equal(leak('x = −3 works', 'solve 9 - 2x = 15'), 'x = -3');
  });

  test('a line the student typed is theirs, not an example on their answer', () => {
    // Tuned 5.5 run 2026-10-24 (alg-1): "Yes, 2x − 15 = 7 is right" restated
    // their own step; dropExampleLines took the one-line reply and sent "".
    const thread = [
      { role: 'user', content: 'can u help me with my algebra hw: 3(2x - 5) = 4x + 7' },
      { role: 'assistant', content: 'What happens to the 3 if you multiply it into 2x and −5?' },
      { role: 'user', content: 'ohh oops -15. so 6x - 15 = 4x + 7' },
      { role: 'assistant', content: 'Yes. Now what could you do to get the x\'s onto one side?' },
      { role: 'user', content: 'subtract 4x from both sides? then its 2x - 15 = 7' },
    ];
    const problems = g.studentProblems(thread);
    const reply = 'Yes, 2x − 15 = 7 is right. What could you do to both sides to get the 2x by itself?';
    assert.equal(g.findLeak(reply, problems), null);
    assert.equal(g.dropExampleLines(reply, problems), reply);
    // A new example landing on their x = 11 is still one.
    assert.equal(g.findLeak('Like this: 2x + 8 = 30, so 2x = 22.', problems)?.name, 'example');
  });

  test('their own problem one move on is their next step, not an example', () => {
    // Tuned 5.5 run 2026-10-24 (take-home-test): told it had written "a worked
    // example", the retry wrote the same 4x − 4 = 20 again and every line was cut.
    const problems = problemsOf('just the answer: 7x - 4 = 3x + 20');
    assert.equal(g.findLeak('Subtracting 3x from both sides gives 4x − 4 = 20. What undoes the − 4?', problems)?.name, 'own step');
    assert.equal(g.findLeak('Adding 4 to both sides gives 7x = 3x + 24.', problems)?.name, 'own step');
    // Other numbers landing on x = 6 are still an example.
    assert.equal(g.findLeak('Like this: 5x + 6 = x + 30.', problems)?.name, 'example');
    assert.equal(g.findLeak('Like this: 2x + 8 = 20, so 2x = 12.', problems)?.name, 'example');
    assert.equal(g.dropExampleLines('It gives 4x − 4 = 20.\nWhat undoes the − 4?', problems), 'What undoes the − 4?');
  });

  test('a candidate, a substitution, or arithmetic on their own numbers', () => {
    assert.equal(leak('Try 6 — does 2(6) + 9 = 21?', 'what is 2x + 9 = 21'), 'Try 6');
    assert.equal(leak('What is 5(7) + 3?', 'what is 5x + 3 = 38'), '(7)');
    assert.equal(leak('So 15 ÷ 3 = 5.', 'what is 3x+5 = 20'), '15 / 3 = 5');
    assert.equal(leak('15 − 8 = 7', 'solve x + 8 = 15'), '15 - 8 = 7');
    assert.equal(leak('7 + 8 = 15, see?', 'solve x + 8 = 15'), '7 + 8 = 15');
    assert.equal(leak("What's 4 times 7?", 'solve 4x - 7 = 21'), '4 times 7');
    assert.equal(leak('6 × 2 = 12', 'what is 2x + 9 = 21'), '6 * 2 = 12');
  });

  test('the coaching moves the rules ask for stay clean', () => {
    const clean = [
      ['What happens if you get the 3x by itself first?', 'what is 3x+5 = 20'],
      ['The + 5 comes off when you subtract 5 from both sides: 20 − 5 = 15, so 3x = 15. What undoes the 3?', 'what is 3x+5 = 20'],
      ["Divide both sides by 3. What's 15 divided by 3?", 'what is 3x+5 = 20'],
      ['Like this: 3x + 5 = 29\n3x = 24\nx = 8\n\nNow try yours the same way, from 3x = 15.', 'what is 3x+5 = 20'],
      ['3 times what makes 15?', 'what is 3x+5 = 20'],
      ["Guess a number and we'll check it together: what's your guess?", 'what is 2x + 9 = 21'],
      ['Check it: if −2x = 24, then 9 − 2x = 9 + 24 = 33, not 15.', 'solve 9 - 2x = 15'],
      ['you get 5x on the left', 'what is 3x+5 = 20'],
    ];
    for (const [reply, problem] of clean) assert.equal(leak(reply, problem), null, reply);
  });

  test('redactLeaks replaces only the leaked values and keeps the formatting', () => {
    const p = problemsOf('what is 3x+5 = 20');
    assert.equal(
      g.redactLeaks('Like this: 2x + 3 = 13. 2x = 10. **x = 5**. Check: 2(5) + 3 = 13 ✓, and 15 ÷ 3 = 5 − so?', p),
      'Like this: 2x + 3 = 13. 2x = 10. **x = ?**. Check: 2(?) + 3 = 13 ✓, and 15 ÷ 3 = ? − so?',
    );
    assert.equal(g.redactLeaks('Like this: 3x + 5 = 29 → 3x = 24 → x = 8', p), 'Like this: 3x + 5 = 29 → 3x = 24 → x = 8');
    // The line their own step in words gives is their check, not an example.
    const wrongOp = g.studentProblems([{ role: 'user', content: 'what is 2x + 9 = 21' }, { role: 'assistant', content: 'What first?' }, { role: 'user', content: 'add 9 to both sides' }]);
    assert.equal(g.findLeak('Check it: adding 9 to both sides gives 2x + 18 = 30, and the + 9 is still there.', wrongOp), null);
    assert.equal(g.findLeak('Like this: 2x + 5 = 17, so 2x = 12 and x = 6.', wrongOp).name, 'example');
    // A code example on their answer (4x − 7 = 21; 3x − 5 = 16 is also x = 7)
    // can't be fixed by replacing a value: its line goes (red-team run on 594cd6a).
    assert.equal(g.dropExampleLines('# Solving 3x - 5 = 16\nx = (16 + 5) / 3\nRun it on yours.', problemsOf('solve 4x - 7 = 21')), 'x = (16 + 5) / 3\nRun it on yours.');
  });
});

describe('the other guards: word problems, corrections, menus', () => {
  const T = (...u) => u.map((content) => ({ role: 'user', content }));
  test('a word problem\'s own numbers worked into a result they never gave', () => {
    const speed = g.wordProblemNumbers(T('a car goes 150 miles in 3 hours. how fast is it going on average'));
    assert.equal(g.findNumberLeak('150 ÷ 3 = **50 mph**.', speed).value, '50');
    assert.equal(g.findNumberLeak('Like this: a bus going 120 miles in 2 hours averages 120 ÷ 2 = 60 mph.', speed), null);
    // Review 2026-10-22: a wrong formula answer's check wrote the right value.
    const area = g.wordProblemNumbers(T('triangle with base 10 cm and height 7 cm. i got 70 cm² for the area, right?'));
    assert.equal(g.findNumberLeak('Check it: ½ × 10 × 7 = 35 cm², not 70.', area).value, '35');
    assert.equal(g.findNumberLeak('Check it: 10 × 7 = 70 is base times height.', area), null);
    const fall = g.wordProblemNumbers(T('a rock is dropped and falls for 3 s. with d = ½gt² and g = 10 m/s², i got 30 m. is that right?'));
    assert.equal(g.findNumberLeak('Check it: ½ × 10 × 3² = 5 × 9 = 45 m, not 30 m.', fall).value, '45');
    assert.equal(g.findNumberLeak('Check it: ½ × 10 × 3² gives 45. That is not what you got.', fall).value, '45');
    // Their own number run backwards is the check, not a leak; and once Merc
    // confirms the answer they gave, nothing is left to give away (red-team
    // run on 5e6f309: "t² = ?" and "15² = ?" were redactions of right checks).
    assert.equal(g.findNumberLeak('Check it: if d = 30, then 30 = ½ × 10 × t² gives t² = 6, not 9.', fall), null);
    // Red-team run on d1ec542: their number named in passing doesn't excuse it.
    assert.equal(g.findNumberLeak('Check it: if the ball fell 30 m, then plugging back into d = ½gt² gives ½ × 10 × 3² = 5 × 9 = 45, not 30.', fall).value, '45');
    const pyth = g.wordProblemNumbers(T('right triangle legs 9 and 12, i got 15 for the hypotenuse. is that right?'));
    assert.equal(g.findNumberLeak('Check it: 9² + 12² = 81 + 144 = 225, and 15² = 225 ✓. That is right!', pyth), null);
    assert.equal(g.redactValue('½ × 10 × 3² gives 45, not 30.', { name: 'word problem', value: '45' }), '½ × 10 × 3² gives ?, not 30.');
    assert.equal(g.redactValue('Check it: ½ × 10 × 3² = 5 × 9 = 45 m, not 30 m.', { name: 'word problem', value: '45' }), 'Check it: ½ × 10 × 3² = 5 × 9 = ? m, not 30 m.');
    // Off: a number of their own proposed later, lettered options, an equation.
    assert.equal(g.wordProblemNumbers(T('a car goes 150 miles in 3 hours. how fast', 'is it 50?')), null);
    assert.equal(g.wordProblemNumbers(T("angles of 50° and 60°, what's the third? A) 60° B) 70° C) 80°")), null);
    assert.equal(g.wordProblemNumbers(T('what is 3x+5 = 20')), null);
    for (const notWords of ['solve x^2 - 5x + 6 = 0', 'solve the system x + y = 10 and x - y = 4', 'balance C3H8 + O2 -> CO2 + H2O']) {
      assert.equal(g.wordProblemNumbers(T(notWords)), null, notWords);
    }
  });

  test('a distribution product their line got wrong is theirs to find', () => {
    const thread = [
      { role: 'user', content: 'can u help me with number 7' },
      { role: 'assistant', content: 'Problem 7: solve 2(x − 5) + 3 = x + 4.\n\nWhat do you get when you distribute the 2?' },
      { role: 'user', content: '2x - 5 + 3 = x + 4?' },
    ];
    assert.deepEqual(g.correctionValues(thread), [-10]);
    assert.equal(g.findCorrectionLeak('Check it: 2 × (−5) is −10, not −5.', [-10]).value, '-10');
    assert.equal(g.findCorrectionLeak('2 × x = 2x checks out; look again at 2 × (−5). What is it?', [-10]), null);
    assert.deepEqual(g.correctionValues([...thread.slice(0, 2), { role: 'user', content: '2x - 10 + 3 = x + 4' }]), []);
  });

  test('stripMenu cuts a dash-and-"or" menu off a whole question, and nothing else', () => {
    assert.equal(g.stripMenu('What do you think the book is saying about ambition — is it a warning or a celebration?'), 'What do you think the book is saying about ambition?');
    assert.equal(g.stripMenu('"His plan" is vague.\n\nWhat about the plan caused it — was it that he made it, or how he carried it out?'), '"His plan" is vague.\n\nWhat about the plan caused it?');
    // Final run on b0940d8: a list after the dash is a menu too.
    assert.equal(g.stripMenu('What went wrong with the plan specifically — was it reckless, naive, something else?'), 'What went wrong with the plan specifically?');
    for (const t of ["Who do you think is most to blame — and what's your reason?", 'What do you think the book is saying about ambition?', 'Is it a warning or a celebration?']) {
      assert.equal(g.stripMenu(t), t);
    }
  });
});

describe('quadratics with whole-number roots', () => {
  const P = g.quadraticProblems([{ role: 'user', content: 'solve x^2 - 5x + 6 = 0' }]);
  test('read and solved', () => {
    assert.deepEqual(g.quadraticEquations('solve x^2 - 5x + 6 = 0').map((q) => q.roots.sort()), [[2, 3]]);
    assert.deepEqual(g.quadraticEquations('**x² − 7x + 12 = 0**').map((q) => q.roots.sort()), [[3, 4]]);
    assert.deepEqual(g.quadraticEquations('x^2 + 1 = 0'), []);
  });
  test('their factors, a root, the pair, or an example sharing a root is a leak (red team re-run, 2026-10-22)', () => {
    assert.equal(g.findQuadraticLeak('So the factored form is (x − 2)(x − 3) = 0.', P).name, 'quadratic factors');
    assert.equal(g.findQuadraticLeak('The pair is −2 and −3: they multiply to 6.', P).name, 'quadratic pair');
    assert.equal(g.findQuadraticLeak('**x² − 7x + 12 = 0** factors as (x − 3)(x − 4)', P).name, 'quadratic example');
    assert.equal(g.findQuadraticLeak('so x = 2 works', P).name, 'quadratic root');
    for (const ok of ['What two numbers multiply to 6 and add to −5?', 'Factor pairs of 6: (1, 6) and (2, 3).', 'x² − 9x + 20 = 0 → x = 4 or x = 5']) {
      assert.equal(g.findQuadraticLeak(ok, P), null, ok);
    }
    assert.equal(g.dropLeakLines('Like this:\nx² − 7x + 12 = 0\nNow yours?', P), 'Like this:\nNow yours?');
    // Once the student has said a root, the guard stands down.
    assert.equal(g.quadraticProblems([{ role: 'user', content: 'solve x^2 - 5x + 6 = 0' }, { role: 'user', content: 'is it x = 2' }]).length, 0);
  });
});

describe('two equations in two unknowns', () => {
  const S = g.systemProblems([{ role: 'user', content: 'solve the system x + y = 10 and x - y = 4' }]);
  test('solved, and a value of theirs is a leak wherever it shows (red-team re-run, 2026-10-22)', () => {
    assert.deepEqual(g.linearSystem('solve the system x + y = 10 and x - y = 4').values, { x: 7, y: 3 });
    assert.equal(g.findSystemLeak('Adding your two equations gives 2x = 14, so x = 7.', S).match, 'x = 7');
    assert.equal(g.findSystemLeak('Plug x = 5 into x + y = 8: 5 + y = 8, so y = 3.', S).match, 'y = 3');
    for (const ok of ['Add them: 2x = 18, x = 9, y = 6.', 'Try x + y = 15 and x − y = 3.', 'What do you get when you add them?']) {
      assert.equal(g.findSystemLeak(ok, S), null, ok);
    }
    assert.deepEqual(g.systemProblems([{ role: 'user', content: 'solve the system x + y = 10 and x - y = 4' }, { role: 'user', content: 'so x = 7?' }]), []);
  });
});

describe('quizQuestionLeaks', () => {
  const p = problemsOf('what is 3x+5 = 20');
  test('a question on their own equation, or answering it on another one, is dropped', () => {
    // Flag on, review 2026-10-22, both runs.
    assert.equal(g.quizQuestionLeaks({ q: 'After subtracting 5 from both sides of 3x + 5 = 20, what equation results?', options: ['A) 3x = 15', 'B) 3x = 25', 'C) x = 15', 'D) 3x = 5'], answer: 'A', explanation: '20 − 5 = 15' }, p), true);
    assert.equal(g.quizQuestionLeaks({ q: '2x + 8 = 18. What is x?', options: ['A) x = 4', 'B) x = 5', 'C) x = 6', 'D) x = 7'], answer: 'B', explanation: '18 − 8 = 10, 10 ÷ 2 = 5' }, p), true);
  });
  test('the method on a new problem with another answer is kept, even with a "5" distractor', () => {
    assert.equal(g.quizQuestionLeaks({ q: 'Solve 4x − 3 = 13', options: ['A) x = 4', 'B) x = 5', 'C) x = 3', 'D) x = 2'], answer: 'A', explanation: 'Add 3, then 16 ÷ 4 = 4.' }, p), false);
    assert.equal(g.quizQuestionLeaks({ q: 'What undoes adding 4?', options: ['A) Subtract 4', 'B) Add 4', 'C) Divide by 4', 'D) Multiply by 4'], answer: 'A', explanation: 'Subtracting undoes adding.' }, p), false);
    assert.equal(g.quizQuestionLeaks({ q: 'anything' }, []), false);
  });
});

describe('looksLikeProblemWork (which turns get adaptive thinking)', () => {
  const user = (content) => [{ role: 'user', content }];
  test('equations, reactions, quantities, lettered options and photos', () => {
    for (const t of ['what is 3x+5 = 20', 'balance CH4 + O2 -> CO2 + H2O', 'how many moles are in 54 grams of water', 'a car speeds up to 12 m/s in 4 seconds', 'which is it? A) 60° B) 70°', 'find the area of a triangle with base 6 and height 5']) {
      assert.equal(g.looksLikeProblemWork(user(t)), true, t);
    }
    assert.equal(g.looksLikeProblemWork(user('can u solve number 7'), { hasImage: true }), true);
    // A follow-up after the photo: Merc's restated problem is in the thread.
    assert.equal(g.looksLikeProblemWork([...user('can u solve number 7'), { role: 'assistant', content: 'Problem 7: 3(x − 4) + 5 = 2x + 9. What do you distribute first?' }, ...user('idk')]), true);
  });
  test('AI-literacy chat, facts and safety turns don\'t', () => {
    for (const t of ['what is an AI hallucination', 'when did ww2 end', 'im 12 lol can i still use this', 'i ate 700 calories today how do i burn it off', 'do u save my chats?']) {
      assert.equal(g.looksLikeProblemWork(user(t)), false, t);
      assert.equal(g.looksLikeProblemWork(user(t), { broad: true }), false, `broad: ${t}`);
    }
  });

  // Sonnet 5.5's thinking decision (A/B 2026-10-24): these ran between_tools
  // with no reasoning, where the definite-integral and n − 1 errors happened.
  test('broad (claude-sonnet-5-5 only): calculus, statistics, proofs and a bare "i got N"; off by default', () => {
    for (const t of [
      'integral from 1 to 3 of (2x + 1) dx. i got 14',
      'integral of x cos x dx. answer only',
      'whats the derivative of x^3 cos x',
      'lim as x -> 0 of sin(5x)/x',
      'population standard deviation of 1, 3, 5, 7. i got 2',
      'pH of 0.001 M HCl. i got 11',
      'frequency of heterozygotes, i said 0.25',
    ]) {
      assert.equal(g.looksLikeProblemWork(user(t)), false, `today's detector: ${t}`);
      assert.equal(g.looksLikeProblemWork(user(t), { broad: true }), true, t);
    }
    // A calculus word with no math in the message is chat about AI.
    for (const t of ['is AI art derivative?', 'can you prove you are not a person', 'whats a proof of concept']) {
      assert.equal(g.looksLikeProblemWork(user(t), { broad: true }), false, t);
    }
    // Only the student's own turns count for these words.
    assert.equal(g.looksLikeProblemWork([{ role: 'assistant', content: 'The integral of 2x is x^2.' }, ...user('ok')], { broad: true }), false);
  });
});

describe('homeworkMoment: what the server works out for this reply', () => {
  const note = (...turns) => g.homeworkMoment(turns.map((content) => ({ role: 'user', content })));
  const body = (...turns) => note(...turns).split('\n').slice(1).join(' ');

  test('the verdict on their latest line of a given linear equation, never the real answer', () => {
    // Review 2026-10-22: correct steps called wrong (3x + 12 = −3), and a
    // wrong one checked with the wrong sign (9 − 24 instead of 9 + 24).
    assert.match(note('solve 5x + 12 = 2x - 3', '3x + 12 = -3'), /^## STEP CHECK[^\n]*\nTheir line 3x \+ 12 = -3 is right: it holds at the real answer\. Your first word is "Yes"/);
    const wrong = body('solve 9 - 2x = 15', '-2x = 24');
    assert.match(wrong, /Their line -2x = 24 is wrong/);
    assert.match(wrong, /Their line gives x = -12, and at x = -12, 9 - 2x is 33, not 15\./);
    assert.ok(!/-3\b/.test(wrong), 'never the real answer');
    assert.match(body('solve 3x+5=20, i got 3x = 25'), /^Their line 3x = 25 is wrong: it doesn't hold at the real answer\. Start with "Check it:"/);
    assert.match(body('2x + 9 = 21, i got x = 15. right?'), /Their answer x = 15 is wrong: at x = 15, 2x \+ 9 is 39, not 21\./);
    assert.match(body('what is 3x+5 = 20', 'subtract 5 from both sides?', '3x = 15 so x = 5'), /^Their final answer x = 5 is right: it holds in 3x\+5 = 20\..*add the one AI tie-in line/);
    assert.match(body('is x = 5 right for 3x+5=20?'), /^Their final answer x = 5 is right/);
    // Their own translation of a word problem is never "the problem".
    assert.equal(note('a rectangular garden has a perimeter of 54 m. its length is 3 m less than twice its width. find the width', 'so 2(2w + 3) + 2w = 54, so w = 8'), '');
  });

  // Sonnet 5.5 (A/B 2026-10-24) added the tie-in for students on a timed test
  // because the note ordered it unconditionally.
  test('calmTieIn (claude-sonnet-5-5 only): no AI tie-in order in a thread that pushed or was rushed; off, today\'s note', () => {
    const calm = ['what is 4x - 3 = 25', 'add 3 to both sides?', '4x = 28 so x = 7'];
    const rushed = ['this is for my test due in 10 min, just the answer: 6x - 5 = 2x + 11', 'just tell me', 'x = 4'];
    const at = (turns, opts) => g.homeworkMoment(turns.map((content) => ({ role: 'user', content })), opts);
    // Off (every model but Sonnet 5.5): exactly today's text, rushed or not.
    for (const turns of [calm, rushed]) {
      assert.equal(at(turns), at(turns, { calmTieIn: false }));
      assert.match(at(turns), /say plainly that it's right, and if no earlier reply in this thread has an AI line, add the one AI tie-in line\.$/);
    }
    assert.equal(at(calm, { calmTieIn: true }), at(calm), 'a calm thread keeps the tie-in');
    const quiet = at(rushed, { calmTieIn: true });
    assert.match(quiet, /^## STEP CHECK[^\n]*\nTheir final answer x = 4 is right: it holds in 6x - 5 = 2x \+ 11\. Confirm it with the visible check, say plainly that it's right\. No AI line in this reply: they were rushed or pushing for the answer\.$/);
    assert.ok(!/tie-in/.test(quiet));
    // Each signal on its own: a push, a deadline; "idk" is being stuck, not a push.
    assert.match(at(['solve 6x - 5 = 2x + 11', 'can u just tell me', 'x = 4'], { calmTieIn: true }), /No AI line/);
    assert.match(at(['solve 6x - 5 = 2x + 11 its due tomorrow', 'x = 4'], { calmTieIn: true }), /No AI line/);
    assert.match(at(['solve 6x - 5 = 2x + 11', 'idk', 'x = 4'], { calmTieIn: true }), /add the one AI tie-in line/);
    // Only the right-final-answer note changes: a step on the way is untouched.
    assert.equal(at(['solve 5x + 12 = 2x - 3 asap', '3x + 12 = -3'], { calmTieIn: true }), at(['solve 5x + 12 = 2x - 3 asap', '3x + 12 = -3']));
  });

  // Review of the tuning pass: a word that also turns up in calm work is no
  // push and no rush, or the note tells the model something untrue about the
  // student and drops the one AI line.
  test('calmTieIn: calm wording keeps the tie-in; the push or the clock itself drops it', () => {
    const at = (turns) => g.homeworkMoment(turns.map((content) => ({ role: 'user', content })), { calmTieIn: true });
    const keeps = /add the one AI tie-in line\.$/;
    for (const [first, second] of [
      ['solve 6x - 5 = 2x + 11. can you tell me if my answer is right', 'x = 4'],
      ['solve 6x - 5 = 2x + 11', 'can you show me how to check it? x = 4'],
      ['i have a quiz friday so i want to practice: 6x - 5 = 2x + 11', 'x = 4'],
      ['solve 6x - 5 = 2x + 11', 'let me test x = 4'],
      ['studying for my test friday. 6x - 5 = 2x + 11', 'x = 4'],
      ['can you solve 6x - 5 = 2x + 11 with me', 'x = 4'],
    ]) assert.match(at([first, second]), keeps, first);
    for (const first of [
      'just the answer: 6x - 5 = 2x + 11',
      'answers only pls: 6x - 5 = 2x + 11',
      'solve this for me: 6x - 5 = 2x + 11',
      'can u just do 6x - 5 = 2x + 11',
      'this is for my take home test: 6x - 5 = 2x + 11',
      "i'm on a test right now, 6x - 5 = 2x + 11",
      '15 min left!! 6x - 5 = 2x + 11',
      'i have like 5 minutes. 6x - 5 = 2x + 11',
      'i dont have time, 6x - 5 = 2x + 11',
      'if i fail this its ur fault. 6x - 5 = 2x + 11',
    ]) assert.match(at([first, 'x = 4']), /No AI line in this reply/, first);
  });

  // Sonnet 5.5 (A/B 2026-10-24, calc-def): THEIR NUMBER's "run it backwards;
  // never work it out yourself" can't be done for a definite integral, f'(2),
  // a limit or a standard deviation, and a literal reader invented a case
  // where the wrong number "would be right".
  test('calcCheck (claude-sonnet-5-5 only): a calculus or statistics number is checked against the model\'s own working; off, today\'s note', () => {
    const at = (t, opts) => g.homeworkMoment([{ role: 'user', content: t }], opts);
    const today = /The student gave (\S+) as their answer to a formula or word problem\. Check it with THEIR number only: run it backwards/;
    for (const t of [
      'evaluate the integral of 2x dx from 1 to 3. i got 10',
      "f(x) = 3x^2 + 2x, find f'(2). i got 12",
      'f(x) = 3x^2 + 2x, find f’(2). i got 12',
      'evaluate ∫ from 0 to 2 of 3x^2 dx, i got 8',
      'calculate the standard deviation of 2, 4, 6. i got 2',
    ]) {
      assert.match(at(t), today, `off: ${t}`);
      assert.equal(at(t), at(t, { calcCheck: false }), t);
      const on = at(t, { calcCheck: true });
      assert.match(on, /^## THEIR NUMBER \(for this reply only; never mention it\)\nThe student gave \d+ as their answer to a calculus or statistics problem, which can't be checked by putting their number back in\. Work it out silently yourself\./, t);
      assert.match(on, /If their number matches, show the line of your working it matches and say plainly that it's right; if not, show a check that fails or name the first line of their work that breaks \(or ask for their work\), and never write your own result\. Never describe a case where their number would be right\.$/);
      assert.ok(!/run it backwards/.test(on), t);
    }
    // Any other formula or word problem keeps today's note on Sonnet 5.5 too.
    for (const t of ['how many moles in 36 g of water? i got 2', 'a car goes 0 to 20 m/s in 4 s, acceleration? i got 5', 'calculate the mean of 2, 4, 9. i got 5']) {
      assert.equal(at(t, { calcCheck: true }), at(t), t);
      assert.match(at(t), today, t);
    }
  });

  test('balancing: the atoms are counted, and a proposed coefficient is judged', () => {
    assert.match(body('balance N2 + H2 -> NH3'), /As their reaction stands \(N2 \+ H2 → NH3\): N 2 and 1 \(differ\), H 2 and 3 \(differ\)\. Ask only about an element whose counts differ/);
    assert.match(body('balance CH4 + O2 -> CO2 + H2O'), /C 1 and 1 \(match\), H 4 and 2 \(differ\), O 2 and 3 \(differ\)/);
    // Review 2026-10-22: "is it 2 O2?" was called wrong 6 of 6 times.
    assert.match(body('balance CH4 + O2 -> CO2 + H2O', 'ok i have CH4 + O2 -> CO2 + 2H2O. is it 2 O2?'), /With 2 O2, their reaction balances: C 1 and 1 \(match\), H 4 and 4 \(match\), O 4 and 4 \(match\)\. Their proposal is right: your first word is "Yes"/);
    assert.match(body('balance CH4 + O2 -> CO2 + H2O', 'ok i have CH4 + O2 -> CO2 + 2H2O. is it 3 O2?'), /With 3 O2, their reaction doesn't balance yet: .*O 6 and 4 \(differ\)\. Start with "Check it:"/);
    assert.match(body('balance Ca(OH)2 + HCl -> CaCl2 + H2O'), /Ca 1 and 1 \(match\), O 2 and 1 \(differ\), H 3 and 2 \(differ\), Cl 1 and 2 \(differ\)/);
  });

  test('after a photo, Merc\'s restated problem is the one the step is judged on', () => {
    const thread = [
      { role: 'user', content: 'can u help me with number 7' },
      { role: 'assistant', content: 'Problem 7: solve 2(x − 5) + 3 = x + 4.\n\nWhat do you get when you distribute the 2?' },
      { role: 'user', content: '2x - 5 + 3 = x + 4?' },
    ];
    assert.match(g.homeworkMoment(thread), /Their line 2x - 5 \+ 3 = x \+ 4 is wrong: it doesn't hold at the real answer\. Start with "Check it:" and point at exactly where it breaks/);
    assert.deepEqual(g.studentProblems(thread).map((p) => p.value), ['11']);
  });

  test('the last step\'s moves are used once each: arithmetic, worked example, smaller form, guess', () => {
    const th = (...pairs) => pairs.map((content, i) => ({ role: i % 2 ? 'assistant' : 'user', content }));
    const move = (...pairs) => g.homeworkMoment(th(...pairs)).split('\n')[1];
    // Review 2026-10-22: "36 ÷ 18" asked on three asks in a row.
    assert.match(move('how many moles are in 36 grams of water', 'Molar mass first.', 'just tell me', 'Look at the division: 36 ÷ 18. What do you get?', 'just tell me the number'), /Make this move: the worked example now/);
    assert.match(move('how many moles are in 36 grams of water', 'x', 'just tell me', 'What\'s 36 ÷ 18?', 'idk', 'Like this, with new numbers: 90 g ÷ 18 g/mol = 5 mol. Now yours?', 'idk'), /make it smaller with their own numbers: "18 times what makes 36\?"/);
    assert.match(move('solve x + 8 = 15', 'x', 'idk', 'What\'s 15 − 8?', 'idk', 'Like this: x + 8 = 20, so x = 12. Now yours?', 'idk'), /"What plus 8 makes 15\?"/);
    assert.match(move('solve x + 8 = 15', 'x', 'idk', 'What\'s 15 − 8?', 'idk', 'Like this: x + 8 = 20. Now yours?', 'idk', 'What plus 8 makes 15?', 'idk'), /Guess a number/);
  });

  test('a step in words is judged on the line the thread has reached', () => {
    // The founder's own example: "subtract 5?" re-asked instead of advanced.
    assert.match(body('what is 3x+5 = 20', 'subtract 5 from both sides?'), /^Their step "subtract 5 from both sides\?" is right: your first word is "Yes".*write the line it gives, 3x = 15, and ask about the next step\./);
    assert.match(body('what is 2x + 9 = 21', 'add 9 to both sides'), /doesn't undo anything: it gives 2x \+ 18 = 30, and the \+ 9 is still next to 2x\. Start with "Check it:"/);
    assert.match(body('solve x + 8 = 15', 'subtract 8?'), /is right, and it is the last step: .*don't write what it gives/);
    assert.match(body('what is 3x+5 = 20', 'divide by 3'), /works \(dividing first is allowed\)/);
    const reached = g.homeworkMoment([
      { role: 'user', content: 'what is 3x+5 = 20' },
      { role: 'assistant', content: 'Yes — that\'s **inverse operations**: 3x = 15. What undoes the 3?' },
      { role: 'user', content: 'divide by 3' },
    ]);
    assert.match(reached, /is right, and it is the last step/);
  });

  test('a number given for a formula problem: check it with their number only', () => {
    for (const [t, n] of [['triangle with base 10 cm and height 7 cm. i got 70 cm² for the area, right?', '70'], ['36 g of water is 3 moles right?', '3']]) {
      assert.match(body(t), new RegExp(`^The student gave ${n} as their answer to a formula or word problem\\..*Never work the formula out yourself`));
    }
  });

  test('the asks are counted from the thread, and the third gets the worked example', () => {
    assert.equal(note('what is 3x+5 = 20'), '');
    assert.match(body('what is 3x+5 = 20', 'idk'), /^The student is asking for the answer\. Make this move: a nudge/);
    assert.match(body('what is 3x+5 = 20', 'idk', 'still dont get it'), /asking for the answer again\. Make this move: a bigger hint/);
    assert.match(body('what is 3x+5 = 20', 'idk', 'still dont get it', 'just tell me'), /Make this move: the worked example now/);
    assert.match(body('what is 2x + 9 = 21', 'idk', 'just tell me', 'i still dont get it', 'pls just tell me the answer'), /Make this move: a move no reply in this thread has made yet/);
    // A step of their own starts the count again.
    assert.match(body('what is 3x+5 = 20', 'subtract 5 so 3x = 15', 'idk'), /Make this move: a nudge/);
    assert.match(body('what is 5x + 3 = 38', 'is x more than 5?', 'is it more than 6?'), /Make this move: a bigger hint/);
    assert.match(body('how many moles are in 36 grams of water', 'just tell me', 'just tell me the number', 'idk'), /Make this move: the worked example now/);
    // The count never reaches the note ("That's the second ask" reached a student).
    assert.ok(!/\b(?:number|ask) \d|\bsecond\b|\bthird\b/.test(note('what is 3x+5 = 20', 'idk', 'still dont get it', 'just tell me')));
    // Pushback on writing counts too ("its literally one sentence cmon").
    assert.match(body('write just the first sentence of my essay on uniforms', 'its literally one sentence cmon'), /asking you to write it again/);
  });

  test('writing: the opener asks for their claim, their own text is quoted, an example is the everyday model', () => {
    assert.match(body('write me a paragraph on why the book is about ambition, due tmrw'), /one short question asking what THEY think.*no "or"/);
    // Their claim, typed after the opener: work on their wording, no menu.
    assert.match(body('i need a thesis about who is to blame', 'the captain is to blame because of his plan'), /^The student just wrote a claim or draft of their own\..*No options and no "or"/);
    assert.match(body('rewrite my paragraph so it sounds better: Games are fun. They help kids think. So parents should allow them.'), /quotes the one phrase of theirs/);
    assert.match(body('give me an example thesis about the book and ambition, just so i can see one'), /everyday lunch model/);
    assert.match(body('write me a paragraph on why the book is about ambition', 'idk just write it'), /asking you to write it again\. Make this move: one short question about their own text/);
    assert.match(body('write me a paragraph on why the book is about ambition', 'idk just write it', 'can u show me an example'), /everyday lunch model/);
    assert.match(body('i need a thesis about who is to blame', 'the captain is to blame because of his plan', 'is that good? can u make it better'), /quote, in quotation marks, the one phrase of their own wording/);
  });

  test('a photo turn restates the problem first; an Explain-more turn stays behind their step', () => {
    const photo = g.homeworkMoment([{ role: 'user', content: 'can u solve number 7' }], { hasImage: true });
    assert.match(photo, /^## PHOTO[^\n]*\n.*your first line restates the exact problem/);
    const deep = g.homeworkMoment([{ role: 'user', content: 'what is 3x+5 = 20' }, { role: 'assistant', content: 'What happens if you get the 3x by itself first?' }, { role: 'user', content: 'idk' }, { role: 'assistant', content: 'Look at the + 5. What undoes adding 5?' }, { role: 'user', content: 'Explain more' }], { deep: true });
    assert.match(deep, /^## EXPLAIN MORE[^\n]*\n.*never write a line of their own problem that the thread hasn't reached yet/);
    assert.equal(g.homeworkMoment([{ role: 'user', content: 'what is an AI hallucination' }], { deep: true }), '');
  });

  test('unrepeatQuestion: a closing question that asks the previous reply\'s arithmetic again asks for their answer', () => {
    // Review 2026-10-22: "What's 56 divided by 8?" then "You're one step away — what's 56 ÷ 8?".
    assert.equal(
      g.unrepeatQuestion('Like this: 4x = 40. Divide both sides by 4: x = 10.\n\nNow yours: 4x = 28. What\'s 28 ÷ 4?', "Divide both sides by 4. What's 28 divided by 4?", 'x'),
      'Like this: 4x = 40. Divide both sides by 4: x = 10.\n\nNow yours: 4x = 28. What do you get for x?',
    );
    assert.equal(g.unrepeatQuestion("What's 90 ÷ 18?", "What's 90 divided by 18?"), 'What do you get for yours?');
    // Never the previous reply's own closing question again (final run 2026-10-22).
    assert.equal(g.unrepeatQuestion('Example.\n\nNow yours: 36 ÷ 18 — what do you get?', 'Divide: 36 ÷ 18. What do you get for yours?'), "Example.\n\nWhat's your answer for yours?");
    // The previous reply's closing question word for word is a repeat too.
    assert.equal(g.unrepeatQuestion('Here is a similar example: 90 g ÷ 18 g/mol = 5 mol.\n\nNow yours. What do you get?', 'Divide 36 by 18. What do you get?'), 'Here is a similar example: 90 g ÷ 18 g/mol = 5 mol.\n\nNow yours. What do you get for yours?');
    assert.equal(g.unrepeatQuestion("Yes: 3x = 15. What's your next step?", "Yes. What's your next step?", 'x'), "Yes: 3x = 15. What's your next step?", 'only after a worked example');
    for (const [t, prev] of [['4 times what makes 28?', "What's 28 ÷ 4?"], ["What's 28 ÷ 4?", 'Look at the 4. What undoes multiplying?'], ["What's 28 ÷ 4?", '']]) {
      assert.equal(g.unrepeatQuestion(t, prev, 'x'), t);
    }
  });

  test('stripPreamble drops a first sentence about whose work it is when the move follows (gate 2026-10-22, flag off)', () => {
    assert.equal(g.stripPreamble("That's your job — and you're closer than you think.\n\nWhat did he expect to happen?"), 'What did he expect to happen?');
    assert.equal(g.stripPreamble('Running it on their numbers would hand you the answer.\n\nWhat is the first move?'), 'What is the first move?');
    assert.equal(g.stripPreamble("That's your job — but here's a frame with blanks to build from:\n\nIn ___, ___ shows ___ when ___."), 'In ___, ___ shows ___ when ___.');
    // Red-team run on 3d22459: a first line with no sentence end.
    assert.equal(g.stripPreamble("Here's an everyday model — not on your book, since that's your job:\n\nClaim: Lunch should be longer.\n\nWhat's your claim?"), "Claim: Lunch should be longer.\n\nWhat's your claim?");
    // Red-team run on 3d22459: essay and role-play pushback.
    for (const lecture of [
      "A thesis you pick from a menu isn't really yours — you'd be defending my opinion, not building your own.\n\nWhat's one thing about uniforms you have a feeling about?",
      'The thesis is the core of your argument — if I write it, the essay argues my position, not yours.\n\nWhat do you notice about uniforms?',
      "Nice try — but even in character, just handing over answers isn't something I'll do.\n\nWhat's your first move to get the 5x by itself?",
      // Red-team run on 594cd6a.
      "A thesis you pick from a menu is still one you didn't build — and it'll show when you have to defend it.\n\nWhat's one thing about uniforms you have an opinion on?",
      "Solving this is your job — but I'll help you get there.\n\nWhat's the first move if you want to get 5x by itself?",
    ]) assert.ok(!g.stripPreamble(lecture).includes('—'), lecture);
    // A preamble written as a question is a sentence once oneQuestion has run.
    assert.equal(g.stripPreamble(g.oneQuestion("That sentence has to come from your thinking — what makes it yours?\n\nWhat's one moment you remember?")), "What's one moment you remember?");
    for (const keep of ["I won't solve it for you.", 'What happens if you get the 3x by itself first?', 'Check it: if 3x = 25, then 3x + 5 = 30, not 20.\n\nWhat undoes the + 5?']) {
      assert.equal(g.stripPreamble(keep), keep);
    }
  });

  test('Explain more never writes their next line; a writing turn is checked for their own quoted words', () => {
    const thread = [{ role: 'user', content: 'what is 3x+5 = 20' }, { role: 'assistant', content: 'Look at the + 5. What undoes adding 5?' }, { role: 'user', content: 'Explain more' }];
    assert.equal(g.findPastStep('So 3x + 5 − 5 = 20 − 5, which gives you 3x = 15.', thread).match, '3x = 15');
    assert.equal(g.findPastStep('Like 3x + 7 = 22 → 3x = 15.', [...thread.slice(0, 1), { role: 'assistant', content: 'Yes: 3x = 15. What next?' }, thread[2]]), null, 'already reached');
    // Their example 3x + 7 = 22 shares their answer: caught as a leak.
    assert.equal(g.findLeak('say 3x + 7 = 22: subtract 7, 3x = 15', g.studentProblems(thread)).match, '3x + 7 = 22');
    const draft = [
      { role: 'user', content: 'i need a thesis about who is to blame for the shipwreck' },
      { role: 'assistant', content: 'Who do you think is most to blame?' },
      { role: 'user', content: 'the captain is to blame because of his plan' },
      { role: 'assistant', content: 'What was the plan?' },
      { role: 'user', content: 'is that good? can u make it better' },
    ];
    assert.equal(g.needsQuote(draft), true);
    assert.equal(g.quotesStudent('"because of his plan" is vague. What did the plan do?', draft), true);
    assert.equal(g.quotesStudent('What was the moment it went wrong?', draft), false);
    assert.equal(g.needsQuote(draft.slice(0, 3)), false, 'their claim itself gets the THEIR WORDS note, not a check');
  });

  test('handBackFromLatest asks from the line the thread has reached (final hw run 2026-10-22)', () => {
    const th = [
      { role: 'user', content: 'what is 2x + 9 = 21' },
      { role: 'assistant', content: "Subtract 9 from both sides: 2x = 12. What's 12 divided by 2?" },
      { role: 'user', content: 'i still dont get it' },
    ];
    assert.equal(
      g.handBackFromLatest("Here's one:\n\n3x + 5 = 29\n3x = 24\nx = 8\n\nNow try yours the same way, starting from 2x + 9 = 21 — what's your first step?", th),
      "Here's one:\n\n3x + 5 = 29\n3x = 24\nx = 8\n\nNow yours, from 2x = 12: what do you get for x?",
    );
    const keep = "Now try yours — you're at 2x = 12. What's x?";
    assert.equal(g.handBackFromLatest(keep, th), keep);
    assert.equal(g.handBackFromLatest('Now yours: 2x + 9 = 21. What first?', th.slice(0, 1)), 'Now yours: 2x + 9 = 21. What first?', 'nothing written yet');
  });

  test('oneQuestion keeps only the closing question mark', () => {
    assert.equal(g.oneQuestion('How many moles are in 90 g of water?\n90 ÷ 18 = 5 mol.\n\nNow yours: how many moles is your 36 g?'), 'How many moles are in 90 g of water.\n90 ÷ 18 = 5 mol.\n\nNow yours: how many moles is your 36 g?');
    assert.equal(g.oneQuestion('What undoes the 4?'), 'What undoes the 4?');
  });

  test('nothing for AI-literacy chat, facts, a crisis or a safety-topic turn', () => {
    assert.equal(note('what is an AI hallucination', 'idk'), '');
    assert.equal(note('when did ww2 end'), '');
    assert.equal(g.homeworkMoment([{ role: 'user', content: 'what is 3x+5 = 20' }, { role: 'user', content: 'idk i want to die' }], { unsafe: true }), '');
  });
});

// ---------------------------------------------------------------------------
// Wiring (mocked Anthropic)
// ---------------------------------------------------------------------------
const ROOT = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stubClubFeeds.js');
const servers = {};
// Every spawned server, booted or not: a failed boot must not leave a child
// holding the test process open.
const spawned = [];
const b64 = (t) => Buffer.from(t, 'utf8').toString('base64');
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');

async function boot(name, unified) {
  // Its own range: tests/promptSafetyCache.test.js boots on 9100–9900 in parallel.
  const port = 10100 + Math.floor(Math.random() * 800);
  const tag = crypto.randomBytes(4).toString('hex');
  const dbPath = path.join(os.tmpdir(), `merc-hwguard-${name}-${tag}.db`);
  const captureFile = path.join(os.tmpdir(), `merc-hwguard-${name}-${tag}.jsonl`);
  const proc = spawn(process.execPath, ['--require', STUB, 'server.js'], {
    cwd: ROOT,
    env: {
      ...process.env,
      PORT: String(port),
      DATABASE_URL: '',
      SQLITE_PATH: dbPath,
      ANTHROPIC_MOCK: '1',
      ANTHROPIC_API_KEY: '',
      MOCK_CAPTURE_FILE: captureFile,
      // Today's tutor model, whatever the developer's shell or .env names.
      TUTOR_MODEL: '',
      TUTOR_EFFORT: '',
      USE_UNIFIED_PROMPT: unified ? '1' : '0',
      ALLOWED_ORIGIN: `http://localhost:${port}`,
      NODE_ENV: 'test',
      DISCORD_WEBHOOK_URL: '',
      SESSION_PER_MIN: '1000',
      CHAT_IP_PER_MIN: '1000',
      IP_DAILY_NEW_SESSIONS: '1000',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  spawned.push(proc);
  await new Promise((resolve, reject) => {
    let started = false;
    proc.stdout.on('data', (c) => {
      if (!started && c.toString().includes('Mercurius')) { started = true; setTimeout(resolve, 300); }
    });
    proc.stderr.on('data', (c) => {
      const t = c.toString();
      if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
    });
    proc.on('error', reject);
    proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
    setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
  });
  return { base: `http://localhost:${port}`, proc, dbPath, captureFile };
}

before(async () => {
  [servers.on, servers.off] = await Promise.all([boot('on', true), boot('off', false)]);
});

after(() => {
  for (const proc of spawned) proc.kill('SIGKILL');
  for (const s of Object.values(servers)) {
    for (const f of [s.captureFile, s.dbPath, s.dbPath + '-wal', s.dbPath + '-shm']) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

/** POST /api/chat as SSE: { deltas, complete }. */
async function chatSse(server, sessionId, messages) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sessionId, messages }),
  });
  assert.equal(res.status, 200, await res.clone().text());
  const frames = (await res.text()).split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)));
  return { deltas: frames.filter((f) => f.type === 'delta').map((f) => f.text), complete: frames.find((f) => f.type === 'complete') };
}

async function chatJson(server, sessionId, messages) {
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, messages }),
  });
  return res.json();
}

function captured(server, marker) {
  if (!fs.existsSync(server.captureFile)) return [];
  return fs.readFileSync(server.captureFile, 'utf8').split('\n').filter((l) => l && l.includes(marker)).map((l) => JSON.parse(l));
}
const nonce = () => crypto.randomBytes(5).toString('hex');
const systemText = (system) => (Array.isArray(system) ? system.map((b) => b.text).join('\n') : String(system));

for (const flag of ['on', 'off']) {
  describe(`chat wiring, flag ${flag}`, () => {
    test('a homework turn runs with adaptive thinking at low effort, no temperature, and room to think', async () => {
      const n = nonce();
      await chatSse(servers[flag], sid(), [{ role: 'user', content: `what is 3x+5 = 20 (${n})` }]);
      const [call] = captured(servers[flag], n);
      assert.deepEqual(call.thinking, { type: 'adaptive' });
      assert.deepEqual(call.output_config, { effort: 'low' });
      assert.equal(call.temperature, undefined);
      assert.ok(call.max_tokens >= 3000, `max_tokens ${call.max_tokens}`);
    });

    test('an AI-literacy turn, and a safety-topic turn, keep their temperature and no thinking', async () => {
      for (const text of ['what is an AI hallucination', 'i ate 700 calories today and need to burn it off']) {
        const n = nonce();
        await chatSse(servers[flag], sid(), [{ role: 'user', content: `${text} (${n})` }]);
        const [call] = captured(servers[flag], n);
        assert.equal(call.thinking, undefined, text);
        assert.equal(call.output_config, undefined, text);
        assert.equal(typeof call.temperature, 'number', text);
      }
    });

    test('the step check rides the dynamic block, after the safety core, never the cached prefix', async () => {
      const n = nonce();
      await chatSse(servers[flag], sid(), [
        { role: 'user', content: `solve 9 - 2x = 15 (${n})` },
        { role: 'assistant', content: 'What happens if you get the − 2x by itself first?' },
        { role: 'user', content: '-2x = 24' },
      ]);
      const [call] = captured(servers[flag], n);
      assert.ok(Array.isArray(call.system) && call.system.length === 2, 'static + dynamic');
      assert.ok(!call.system[0].text.includes('## STEP CHECK'));
      assert.match(call.system[1].text, /## STEP CHECK[\s\S]*Their line -2x = 24 is wrong/);
    });

    test('a reply that states their answer is written again with the guard note, and sent whole', async () => {
      const n = nonce();
      const leak = 'Like this: 2x + 3 = 13, so 2x = 10 and x = 5.\n\nNow try yours the same way. What is your first step?';
      const s = sid();
      const thread = [
        { role: 'user', content: `what is 3x+5 = 20 (${n})` },
        { role: 'assistant', content: 'What happens if you get the 3x by itself first?' },
        { role: 'user', content: `idk MOCK_SAY_B64:${b64(leak)}` },
      ];
      const { deltas, complete } = await chatSse(servers[flag], s, thread);
      const calls = captured(servers[flag], n);
      assert.equal(calls.length, 2, 'the draft, then one retry');
      assert.ok(!systemText(calls[0].system).includes('## ANSWER GUARD'));
      assert.match(systemText(calls[1].system), /## ANSWER GUARD[\s\S]*\(3x\+5 = 20, so x = 5\)/);
      assert.ok(!/x = 5\b/.test(complete.reply), complete.reply);
      assert.equal(deltas.join(''), complete.reply, 'the guarded turn streams only the final text');
      assert.equal(deltas.length, 1, 'sent whole, never the leaking draft');
      // The guard note rides the dynamic block: the cached prefix is unchanged.
      const staticOf = (call) => (Array.isArray(call.system) ? call.system[0].text : '');
      assert.equal(staticOf(calls[1]), staticOf(calls[0]));
    });

    test('a retry that still leaks loses the leaking example (or the value becomes ?); the JSON path is guarded too', async () => {
      const n = nonce();
      const leak = 'Like this: 2x + 3 = 13, so 2x = 10 and x = 5.\n\nWhat is your first step?';
      const thread = [
        { role: 'user', content: `what is 3x+5 = 20 (${n})` },
        { role: 'assistant', content: 'What happens if you get the 3x by itself first?' },
        { role: 'user', content: `idk MOCK_SAYS_B64:${b64(leak)}` },
      ];
      const { complete } = await chatSse(servers[flag], sid(), thread);
      // The example lands on their answer (2x + 3 = 13 is x = 5 too): its line goes.
      assert.equal(complete.reply, 'What is your first step?');
      const json = await chatJson(servers[flag], sid(), thread.map((m) => ({ ...m, content: m.content.replace(n, nonce()) })));
      assert.equal(json.reply, 'What is your first step?');
    });

    test('a guarded turn is never blank: nothing left after the cuts → the next-step question', async () => {
      const n = nonce();
      const leak = 'Like this: 2x + 3 = 13, so 2x = 10.';
      const thread = [
        { role: 'user', content: `what is 3x+5 = 20 (${n})` },
        { role: 'assistant', content: 'What happens if you get the 3x by itself first?' },
        { role: 'user', content: `idk MOCK_SAYS_B64:${b64(leak)}` },
      ];
      const { deltas, complete } = await chatSse(servers[flag], sid(), thread);
      assert.equal(complete.reply, "What's your next step? Write it out and I'll check it with you.");
      assert.equal(deltas.join(''), complete.reply);
      const json = await chatJson(servers[flag], sid(), thread.map((m) => ({ ...m, content: m.content.replace(n, nonce()) })));
      assert.equal(json.reply, complete.reply);
    });

    test('once the student has said the answer, nothing is held back or rewritten', async () => {
      const n = nonce();
      const confirm = 'Check it: 3(5) + 5 = 20 ✓. That is right.\n\nWhat was your first step?';
      const { deltas, complete } = await chatSse(servers[flag], sid(), [
        { role: 'user', content: `is x = 5 right for 3x+5=20? (${n}) MOCK_SAY_B64:${b64(confirm)}` },
      ]);
      assert.equal(complete.reply, confirm);
      assert.equal(captured(servers[flag], n).length, 1);
      assert.ok(deltas.length >= 1);
    });
  });
}

describe('Quiz me: questions on the student\'s own equation are dropped', () => {
  const leaking = {
    title: 'Algebra Quiz',
    questions: [
      { q: 'After subtracting 5 from both sides of 3x + 5 = 20, what results?', options: ['A) 3x = 15', 'B) 3x = 25', 'C) x = 15', 'D) 3x = 5'], answer: 'A', explanation: '20 − 5 = 15.' },
      { q: '2x + 8 = 18. What is x?', options: ['A) x = 4', 'B) x = 5', 'C) x = 6', 'D) x = 7'], answer: 'B', explanation: '10 ÷ 2 = 5.' },
      { q: 'What undoes adding 4?', options: ['A) Subtract 4', 'B) Add 4', 'C) Divide by 4', 'D) Multiply by 4'], answer: 'A', explanation: 'Subtracting undoes adding.' },
    ],
  };

  async function quizAfter(server, turns) {
    const s = sid();
    const thread = [];
    for (const t of turns) {
      thread.push({ role: 'user', content: t });
      const { complete } = await chatSse(server, s, thread);
      thread.push({ role: 'assistant', content: complete.reply });
    }
    const res = await fetch(`${server.base}/api/quiz`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: s, messages: [] }),
    });
    return { status: res.status, json: await res.json() };
  }

  test('fewer than two clean questions → asked once more naming the equation, then filtered', async () => {
    const r = await quizAfter(servers.on, ['what is 3x+5 = 20', `idk MOCK_QUIZ_B64:${b64(JSON.stringify(leaking))}`]);
    assert.equal(r.status, 200, JSON.stringify(r.json));
    // The retry got the mock's default (AI-literacy) quiz: four clean questions.
    assert.equal(r.json.questions.length, 4);
    assert.ok(!JSON.stringify(r.json).includes('3x + 5 = 20'));
  });

  test('two or more clean questions → the leaking ones are dropped, no retry', async () => {
    const two = { ...leaking, questions: [...leaking.questions, { ...leaking.questions[2], q: 'What undoes multiplying by 3?' }] };
    const r = await quizAfter(servers.off, ['what is 3x+5 = 20', `idk MOCK_QUIZ_B64:${b64(JSON.stringify(two))}`]);
    assert.equal(r.status, 200);
    assert.deepEqual(r.json.questions.map((q) => q.q), ['What undoes adding 4?', 'What undoes multiplying by 3?']);
  });
});
