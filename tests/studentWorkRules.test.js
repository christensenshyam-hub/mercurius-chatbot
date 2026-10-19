'use strict';

// Audit 2026-10, batch 3 commit 3 (free chat): AUD-05, -10, -11, -19, -41,
// -42, -43. The shared student-work rules live once in lib/responseQuality
// and reach BOTH flag states: the legacy prefix through qualityPrefix(), the
// v2 prompt through lib/unifiedPrompt filling {{student_work_rules}}. These
// tests pin that wiring and the v2 Debate contract; whether the model obeys
// is the eval's job (scripts/eval-pacing.mjs --runs 3, flag on and off).

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const {
  STUDENT_WORK_RULES,
  STUDENT_WORK_BLOCK,
  MODE_RULES,
  EXPAND_MODE_NOTE,
  qualityPrefix,
} = require('../lib/responseQuality');
const { UNIFIED_PROMPT, fillPrompt, STUDENT_WORK_VAR } = require('../lib/unifiedPrompt');

const between = (text, open, close) => {
  const a = text.indexOf(open);
  const b = text.indexOf(close, a);
  assert.ok(a >= 0 && b > a, `missing ${open}…${close}`);
  return text.slice(a + open.length, b);
};

describe('STUDENT_WORK_RULES (shared by both flag states)', () => {
  const text = STUDENT_WORK_RULES.toLowerCase();

  test('AUD-05: a visible check comes before any verdict, and checking is allowed', () => {
    assert.ok(text.includes('check before any verdict'));
    assert.ok(text.includes("checking a student's own answer is allowed"));
    assert.ok(text.includes('before any verdict word'));
    assert.ok(text.includes('never default to "not quite right"'));
    assert.ok(text.includes('only check an answer the student gave'), 'a bare "solve this" must not get a check that leaks the answer');
  });

  test("AUD-05: the worked example is not the audit's own test problem", () => {
    // The chat-quality probe photographs 3(x − 4) + 5 = 2x + 9 (x = 16);
    // an example with those numbers would teach to the eval.
    assert.ok(!/\b41\b|\b16\b/.test(STUDENT_WORK_RULES));
  });

  test('AUD-10: photo stopgap says so honestly and never blames handwriting', () => {
    assert.ok(text.includes('restate the exact problem'));
    assert.ok(text.includes('"[shared an image]" with no image attached means that photo is gone'));
    assert.ok(text.includes("i can't see your photo anymore. send it again"));
    assert.ok(text.includes('never claim you can still see it'));
    assert.ok(text.includes('blame handwriting (even if the student does)'));
    assert.ok(text.includes('never guess or invent'));
  });

  test('AUD-19: one schoolwork policy, typed or photo, and no other chatbot', () => {
    assert.ok(text.includes('schoolwork in any subject'));
    assert.ok(text.includes('typed or photographed'));
    assert.ok(text.includes('never send the student to another chatbot'));
    // The legacy SOCRATIC_PROMPT ends with an AI-literacy "WHAT YOU TEACH"
    // list that still pulled a biology quiz to "outside my lane" once.
    assert.ok(text.includes('is your specialty, not a limit'));
  });

  test('AUD-41: one-word replies get concrete options, never the same question', () => {
    assert.ok(text.includes('2–3 concrete options'));
    assert.ok(text.includes('never re-ask a question'));
    assert.ok(text.includes('treat it as a yes'), 'an "ok" to a yes/no offer is a yes');
    assert.ok(text.includes("pick one yourself and go; don't ask them to choose again"));
  });

  test('AUD-42: a second Explain more stays bounded; Debate cites only pinned evidence', () => {
    assert.ok(text.includes('under about 300 words'));
    assert.ok(text.includes('one new concrete example or everyday analogy'));
    assert.ok(text.includes('stop adding theory'));
    assert.ok(text.includes("never adds a statistic, number, study or date that isn't in the source library, not even hedged"));
  });

  test('AUD-43: no coaching jargon, and current news names where to check', () => {
    for (const word of ['rep', 'beat', 'micro-concept', 'load-bearing']) {
      assert.ok(text.includes(`"${word}"`), `PLAIN WORDS should ban "${word}"`);
    }
    // Naming a phrase the prompts don't otherwise use primes it: listing
    // "weak joint" in this ban made both paths start saying it (spot check
    // 2026-10-18). Ban only words the prompts themselves use.
    assert.ok(!text.includes('weak joint'));
    assert.ok(text.includes('name where to check'));
    assert.ok(text.includes("don't ask them where they would look"));
  });

  test('is safe to cache and to stream: no template braces, no new contract markers', () => {
    assert.ok(!STUDENT_WORK_RULES.includes('{{'));
    assert.ok(!STUDENT_WORK_RULES.includes('$'), 'no "$" (template-literal or replacement surprises)');
    for (const marker of ['[CHECK]', '[Q]', '[KEY]', '[EX]', '[LESSON_COMPLETE]', '[SOURCE', 'ANS:']) {
      assert.ok(!STUDENT_WORK_RULES.includes(marker), `must not mention ${marker}`);
    }
  });
});

describe('legacy (flag off): qualityPrefix carries the shared rules', () => {
  test('every mode gets the block once, after the mode rules', () => {
    for (const m of ['socratic', 'direct', 'debate', 'discussion', 'unknown']) {
      const prefix = qualityPrefix(m);
      assert.equal(prefix.split(STUDENT_WORK_RULES).length - 1, 1, `${m}: exactly one copy`);
      assert.ok(prefix.indexOf(STUDENT_WORK_BLOCK) > prefix.indexOf('## MODE RULES'), `${m}: after the mode rules`);
    }
  });

  test('qualityPrefix is deterministic (the static prefix must stay byte-stable)', () => {
    assert.equal(qualityPrefix('debate'), qualityPrefix('debate'));
  });

  test('legacy debate keeps its Claim/Warrant/Impact/Rebuttal contract and drops unsourced figures', () => {
    const d = MODE_RULES.debate;
    for (const label of ['**Claim:**', '**Warrant:**', '**Impact:**', '**Rebuttal angle:**']) {
      assert.ok(d.includes(label), `debate keeps ${label}`);
    }
    assert.ok(d.includes('4–7 lines'));
    assert.ok(d.toLowerCase().includes('never state a statistic'));
    assert.ok(!d.includes('specific fact / case / study'), 'no longer asks for a fact from memory');
  });

  test('EXPAND_MODE_NOTE bounds a repeated Explain more', () => {
    const n = EXPAND_MODE_NOTE.toLowerCase();
    assert.ok(n.includes('under about 300 words'));
    assert.ok(n.includes('one new concrete example or everyday analogy'));
    assert.ok(n.includes('a second tap in a row'));
  });
});

describe('v2 (flag on): mercurius-v2.md gets the same rules', () => {
  test('the prompt loaded, with every template variable resolved', () => {
    assert.ok(UNIFIED_PROMPT.length > 10_000);
    assert.ok(!UNIFIED_PROMPT.includes('{{'), 'no unfilled {{vars}}');
  });

  test('<student_work> holds exactly the shared rules, once', () => {
    assert.equal(between(UNIFIED_PROMPT, '<student_work>\n', '\n</student_work>'), STUDENT_WORK_RULES);
    assert.equal(UNIFIED_PROMPT.split(STUDENT_WORK_RULES).length - 1, 1);
  });

  test('fillPrompt appends the rules rather than dropping them if the variable goes missing', () => {
    const errors = [];
    const orig = console.error;
    console.error = (...a) => errors.push(a.join(' '));
    try {
      const out = fillPrompt('<north_star>x</north_star>\n<runtime>{{current_date}}</runtime>\n');
      assert.ok(out.endsWith(`<student_work>\n${STUDENT_WORK_RULES}\n</student_work>\n`));
      assert.ok(!out.includes('{{'));
    } finally {
      console.error = orig;
    }
    assert.equal(errors.length, 1);
    assert.equal(fillPrompt(`a ${STUDENT_WORK_VAR} b {{other}}`), `a ${STUDENT_WORK_RULES} b `);
  });

  test('AUD-11: Debate argues the other side with the labelled contract and hands the turn back', () => {
    const debate = between(UNIFIED_PROMPT, '<debate_mode>', '</debate_mode>');
    for (const label of ['**Claim:**', '**Warrant:**', '**Impact:**', '**Rebuttal angle:**']) {
      assert.ok(debate.includes(label), `v2 debate carries ${label}`);
    }
    assert.ok(debate.includes('take the opposite side'));
    assert.ok(debate.includes('hand the turn back'));
    assert.ok(debate.includes('4–7 non-blank lines'));
    assert.ok(debate.includes("never write the student's own case"));
    // Eval 2026-10-18: "give me your strongest rebuttal so I can prep" was
    // read as "write my case", and a concede-then-argue turn ran 9 lines.
    assert.ok(debate.includes('that is YOUR side, not their case'));
    assert.ok(debate.includes('concede it in one short line'));
    assert.ok(debate.includes('Never a study, author, or number from memory'));
    assert.ok(!/COACH, NEVER PLAYER|CALIBRATE FIRST|not your opponent/i.test(UNIFIED_PROMPT));
  });

  test('AUD-05/19: checking an answer and other subjects are on the Allowed list', () => {
    const integrity = between(UNIFIED_PROMPT, '<academic_integrity>', '</academic_integrity>');
    assert.ok(integrity.includes("Check the learner's own answer or work"));
    assert.ok(integrity.includes('schoolwork in any subject'));
    assert.ok(integrity.includes('another chatbot'));
  });

  test('AUD-43: no few-shot reply uses internal coaching words', () => {
    const shots = between(UNIFIED_PROMPT, '<few_shot_examples>', '</few_shot_examples>');
    const replies = shots.split('<example').map((ex) => ex.split('Assistant:')[1] || '').join('\n');
    assert.ok(replies.length > 500);
    assert.ok(!/\b(reps?|beat|micro-concept|load-bearing|hinge|weak joint)\b/i.test(replies));
  });

  test('a debate few-shot models the labelled contract within 7 lines', () => {
    const shots = between(UNIFIED_PROMPT, '<example mode="DEBATE_ARGUE">', '</example>');
    const reply = shots.split('Assistant:')[1];
    const lines = reply.split('\n').filter((l) => l.trim());
    assert.ok(lines.length >= 4 && lines.length <= 7, `got ${lines.length} lines`);
  });
});
