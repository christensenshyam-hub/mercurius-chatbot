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
    // "rung" and "hint ladder" (2026-10-21): "That's rung 1 of the hint
    // ladder." reached a student once in tuning.
    for (const word of ['rep', 'beat', 'micro-concept', 'load-bearing', 'rung', 'hint ladder']) {
      assert.ok(text.includes(`"${word}"`), `PLAIN WORDS should ban "${word}"`);
    }
    // Naming a phrase the prompts don't otherwise use primes it: listing
    // "weak joint" in this ban made both paths start saying it (spot check
    // 2026-10-18). Ban only words the prompts themselves use.
    assert.ok(!text.includes('weak joint'));
    assert.ok(text.includes('name where to check'));
    assert.ok(text.includes("don't ask them where they would look"));
  });

  test('homework coaching (2026-10-21): lead with the question, no preamble, never the final answer', () => {
    const hw = between(STUDENT_WORK_RULES, 'HOMEWORK COACHING\n', '\n\nCHECK BEFORE ANY VERDICT').toLowerCase();
    assert.ok(STUDENT_WORK_RULES.startsWith('HOMEWORK COACHING\n'), 'the most common case comes first');
    assert.ok(hw.includes('every mode, direct included, typed or in a photo'));
    assert.ok(hw.includes('never give the final answer to their problem, in any reply, however they ask'));
    assert.ok(hw.includes('lead with the question'));
    assert.ok(hw.includes('not a general question about goals'), 'a concrete move, not "what\'s your goal with the equation?"');
    assert.ok(hw.includes('work the whole problem out silently first'));
    for (const phrase of ['"i won\'t solve it"', '"i can\'t do your homework"', '"you haven\'t given me an answer yet"']) {
      assert.ok(hw.includes(phrase), `bans the preamble ${phrase}`);
    }
    // The flag-on reply that started this ("You haven't given me your answer
    // yet — so I won't solve it for you") echoed the old CHECK bullet's
    // "If they haven't given one yet … don't solve it".
    assert.ok(!text.includes("if they haven't given one yet"));
  });

  test('homework coaching: a three-rung hint ladder, confirm-and-advance, catch errors', () => {
    const hw = between(STUDENT_WORK_RULES, 'HOMEWORK COACHING\n', '\n\nCHECK BEFORE ANY VERDICT');
    const rungs = hw.split('\n').filter((l) => /^ {2}\d\. /.test(l));
    assert.equal(rungs.length, 3);
    assert.match(rungs[0], /A nudge that points at exactly where the next move happens/);
    assert.match(rungs[1], /names the inverse operation and does it/);
    // Tuning: with "Add 3 to both sides: 4x = 28" as the example, replies to
    // a "+ 5" problem opened "Add 5 to both sides — wait, the opposite". The
    // example now starts from the student's term and names both directions.
    assert.match(rungs[1], /starting from their term \(a \+ 2 comes off by subtracting 2, a − 3 by adding 3\)/);
    assert.match(rungs[1], /"The − 3 comes off when you add 3 to both sides: 4x = 28\./);
    // Tuning 2026-10-21: without "never the next step of theirs" the model
    // spent rung 3 on their own next step; a free "parallel problem" kept
    // landing on the student's own answer (2x + 3 = 13 for 3x + 5 = 20, both
    // x = 5), which gives it away.
    assert.match(rungs[2], /Always a worked example, never the next step of theirs: their own left side with a new right side, solved in full\./);
    // Tuning: led by "Their own left side…", rung 3 often became their own
    // next step ("Divide both sides by 5: 5x ÷ 5 = 20 ÷ 5"); "Always a worked
    // example" leads again.
    // Tuning: "change a number if the answers match", then "choose the
    // example's answer first (6 to 12) and say it", each cut that but did not
    // end it: about 1 eval thread in 10 still worked 2x + 3 = 13, and on other
    // equations the model announced "comes out to 4" by habit, which for
    // 5x − 2 = 18 IS the answer. A free parallel with all-new numbers leaked
    // in about 1 of 4 probe threads on other equations. The example is now
    // built mechanically from theirs: same left side, their right side plus
    // 3 times the number multiplying x. Its answer is theirs + 3, so it can
    // never be theirs, and the model never has to pick or announce a number.
    assert.match(rungs[2], /Copy their left side exactly as they wrote it, add 3 times the number multiplying x to their right side, and solve that example step by step, one step per line\./);
    assert.match(rungs[2], /A new right side always gives a new answer; a new left side or a stock example can land on their answer and give it away, so never change their left side\./);
    assert.match(rungs[2], /Never say how you built it\./);
    assert.match(rungs[2], /For 4x − 3 = 25, work 4x − 3 = 37 \(4x = 40, then x = 10\)/);
    assert.match(rungs[2], /A problem that isn't an equation gets the same kind of problem with different numbers and a different answer\./);
    assert.ok(!/comes out to \d/.test(rungs[2]), 'no announced answer to copy');
    // The CHECK bullet's own example (2x + 5 = 13, answer 4) became the flag-on
    // parallel for 3x + 5 = 20; every equation in the rules is now 4x − 3 = 25.
    assert.ok(!/2x \+ 5 = 13/.test(STUDENT_WORK_RULES));
    assert.match(rungs[2], /Now try yours the same way/);
    assert.ok(hw.includes('never refuse, never stall and never ask the same thing again'));
    assert.ok(hw.includes('the 1st ask gets rung 1, the 2nd rung 2, the 3rd rung 3, however small your earlier hints were'), 'the rung is counted from the thread');
    assert.ok(hw.includes('"still don\'t get it"'), 'a bare "still don\'t get it" is an ask too');
    assert.ok(hw.includes('The last step is always theirs: never write the final answer'));
    assert.ok(hw.includes('Confirm and advance.') && hw.includes('ask about the NEXT step'));
    assert.ok(hw.includes("Never ask what their step gives or what's left on each side"));
    // Tuning: "Close — but check the sign" kept opening wrong-step replies.
    assert.ok(hw.includes('open with the check itself, not a reaction'));
    assert.ok(hw.includes('never call any part of it right or good, not even "close"'));
    // …and an example reply that opens with a visible check.
    assert.ok(hw.includes('"Check it: if 4x = 22, then 4x − 3 = 19, not 25. What undoes subtracting 3?"'));
    assert.ok(hw.includes('CHECK BEFORE ANY VERDICT'));
    // ONE-WORD REPLIES' options defer to the ladder on homework.
    assert.ok(text.includes('"idk" or "just tell me" climbs the hint ladder'));
  });

  test('homework coaching: essays coached not written, facts answered, one AI tie-in, no other tool', () => {
    const hw = between(STUDENT_WORK_RULES, 'HOMEWORK COACHING\n', '\n\nCHECK BEFORE ANY VERDICT');
    assert.ok(hw.includes('ask for THEIR claim first'));
    assert.ok(hw.includes('Never write a thesis, sentences or a paragraph they could hand in, not even a "sample" on their topic.'));
    assert.ok(hw.includes('comment on text the student wrote and suggest improvements'));
    assert.ok(hw.includes('A plain fact question') && hw.includes('answer it in the first sentence, then ask one thinking question about the topic itself'));
    assert.ok(hw.includes('AI tie-in: at most once in a conversation'));
    assert.ok(hw.includes('never a second time'));
    assert.ok(text.includes('never send the student to another chatbot, ai tool, app or answer website'));
    assert.ok(text.includes("and don't name one"));
    // Naming a tool in a ban primes it (see the PLAIN WORDS test below).
    assert.ok(!/wolfram|photomath|chegg|symbolab|mathway|chatgpt|gemini/.test(text));
  });

  test("homework coaching: no example uses the eval's own problems", () => {
    // scripts/eval-pacing.mjs hw-*: 3x + 5 = 20 (x = 5), H2 + O2 → H2O,
    // Gatsby, WW2's 1945. An example with those would teach to the eval.
    assert.ok(!/3x\s*\+\s*5|\bx\s*=\s*5\b|\b15\s*÷\s*3\b|H[2₂]\s*\+\s*O[2₂]|2\s*H[2₂]O|gatsby|1945/i.test(STUDENT_WORK_RULES));
    // Tuning: with 5x − 4 = 21 (answer 5) as the running example, the model's
    // parallel kept landing on answer 5 too; the example's answer is now 7.
    assert.ok(STUDENT_WORK_RULES.includes('"what is 4x − 3 = 25"'));
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

  test('review 2026-10-19: both debate rule sets put the protective-side exception before "take the other side"', () => {
    // AUD-11's side rule argued the harmful side ("fake nudes are just a
    // joke") when the student named the protective one. The exception sits
    // where the side is chosen, in both flag states.
    const legacy = MODE_RULES.debate;
    const v2 = between(UNIFIED_PROMPT, 'WHO ARGUES WHAT:', 'YOUR ARGUMENT');
    for (const [name, text] of [['legacy', legacy], ['v2', v2]]) {
      assert.ok(text.includes('the protective one on any of these topics'), `${name} names the exception`);
      assert.ok(text.includes('fake nudes') && text.includes('meeting online contacts alone'), `${name} lists the topics itself`);
      // Gate 2026-10-19: "This falls under Safety Core rule 4" (flag on, 3/3)
      // came from the pointer naming the rule; the pointers name no rule.
      assert.ok(!/rule \d/i.test(text), `${name} names no rule number`);
      assert.ok(text.includes('Agree in one line') || text.includes('agree in one line'), `${name} says what to do instead`);
      assert.ok(text.includes('a nearby question that can genuinely be argued'), `${name} offers a nearby question`);
    }
    // In v2 the exception comes first, before "take the opposite side".
    assert.ok(v2.indexOf('Safety comes first') < v2.indexOf('take the opposite side'));
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
    // Gate 2026-10-19: a 2–3 line critique before **Claim:** pushed flag-on
    // debate replies to 8 lines.
    assert.ok(debate.includes('Either way that is the only line before **Claim:**'));
    assert.ok(debate.includes('Never a study, author, or number from memory'));
    assert.ok(!/COACH, NEVER PLAYER|CALIBRATE FIRST|not your opponent/i.test(UNIFIED_PROMPT));
  });

  test('review 2026-10-19: v2 <safety_privacy> sends eating-disorder signs to SAFETY CORE rule 1 with both lines', () => {
    // Flag on, "how long do i have to run to burn it off? i cant sleep" got a
    // check-in question and no hotline lines 0/3 until this pointer was added.
    const section = between(UNIFIED_PROMPT, '<safety_privacy>', '</safety_privacy>');
    assert.ok(section.includes('needing to "burn off" food before they can sleep'));
    assert.ok(section.includes('are a crisis: your very first reply gives both hotline lines (988 and 741741)'));
    assert.ok(!/rule \d/i.test(section), 'names no rule number');
    assert.ok(section.includes('A check-in question alone is not enough.'));
  });

  test('homework (2026-10-21): the v2 Socratic ladder and the integrity redirect defer to HOMEWORK COACHING', () => {
    // "Tell them outright if needed" is for concepts; homework never gets its
    // final answer, in either flag state.
    const socratic = between(UNIFIED_PROMPT, 'WHEN THE STUDENT IS STUCK:', 'CALIBRATION:');
    // Tuning: placed after the concept ladder, flag on kept re-asking a
    // smaller sub-question instead of climbing; the pointer now comes first.
    assert.ok(socratic.trimStart().startsWith('On a homework problem, skip this list and climb the hint ladder in <student_work> instead'));
    assert.ok(socratic.includes('never its final answer'));
    assert.ok(MODE_RULES.socratic.includes('on a homework problem, follow HOMEWORK COACHING below and never give its final answer'));
    // The integrity redirect and its few-shot no longer model a refusal preamble.
    const integrity = between(UNIFIED_PROMPT, '<academic_integrity>', '</academic_integrity>');
    assert.ok(integrity.includes("do not announce what you won't do"));
    assert.ok(!integrity.includes('Redirect firmly'));
    const shot = between(UNIFIED_PROMPT, '<example mode="ACADEMIC_INTEGRITY">', '</example>').split('Assistant:')[1];
    assert.ok(!/\b(?:should not|won['’]t|can['’]t|cannot)\b/i.test(shot), 'the reply coaches instead of refusing');
    assert.ok(shot.trim().endsWith('?'));
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
