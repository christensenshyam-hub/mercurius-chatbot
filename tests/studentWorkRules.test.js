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
    // Review 2026-10-21: flag on left "= ?" blanks for a wrong answer, and
    // the change of format gave the verdict away.
    assert.ok(text.includes('compute both sides of an equation yourself with their answer, exactly as you would for a right answer'));
    // Review 2026-10-22: on a formula problem the check wrote the right value
    // ("½ × 10 × 3² = 45 m, not 30 m").
    assert.ok(text.includes("a formula or word problem has no two sides: run their number backwards through the formula, or name the step it skipped, and never write the formula's own result"));
    assert.ok(text.includes('never blanks for them to fill'));
    assert.ok(text.includes('if they already showed their steps, offer one step up instead'));
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
    // Review 2026-10-21: the chip's deep mode asked for free-form examples.
    assert.ok(text.includes('on a homework problem, "explain more" goes deeper on the idea behind the step they\'re on'));
    assert.ok(text.includes('never work their problem past the step the conversation has reached, and never give its final answer'));
  });

  test('AUD-43: no coaching jargon, and current news names where to check', () => {
    // "rung" and "hint ladder" (2026-10-21): "That's rung 1 of the hint
    // ladder." reached a student once in tuning.
    for (const word of ['rep', 'beat', 'micro-concept', 'load-bearing', 'rung', 'hint ladder', 'first ask', 'second ask']) {
      assert.ok(text.includes(`"${word}"`), `PLAIN WORDS should ban "${word}"`);
    }
    // Naming a phrase the prompts don't otherwise use primes it: listing
    // "weak joint" in this ban made both paths start saying it (spot check
    // 2026-10-18). Ban only words the prompts themselves use.
    assert.ok(!text.includes('weak joint'));
    assert.ok(text.includes('name where to check'));
    assert.ok(text.includes("don't ask them where they would look"));
    // Review 2026-10-21: "Subtracting 3 is undone by adding 3" in a
    // 5x − 2 = 18 thread came from the rules' own example.
    assert.ok(text.includes("never carry a number or sign from these instructions' examples into a reply"));
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
    // Review 2026-10-21: with only "Look at the − 3" as its example, flag-on
    // rung 1 called the student's + 5 "the − 5" in 5 of 6 r15 ladders.
    assert.match(rungs[0], /Name their term with the sign it has in THEIR problem: for a \+ 2, "Look at the \+ 2\. What undoes adding 2\?"; for a − 3, "Look at the − 3\. What undoes subtracting 3\?"/);
    assert.match(rungs[1], /names the inverse operation and does it/);
    // Tuning: with "Add 3 to both sides: 4x = 28" as the example, replies to
    // a "+ 5" problem opened "Add 5 to both sides — wait, the opposite". The
    // example now starts from the student's term and names both directions.
    assert.match(rungs[1], /starting from their term \(a \+ 2 comes off by subtracting 2, a − 3 by adding 3\)/);
    assert.match(rungs[1], /"The − 3 comes off when you add 3 to both sides: 4x = 28\./);
    // Review 2026-10-21: on a one-step problem (x + 8 = 15, a triangle's
    // area) "names the operation and does it" IS the answer.
    assert.match(rungs[1], /If that operation is the last step, don't do it \(see the last step, below\)\./);
    // Tuning 2026-10-21: without "never the next step of theirs" the model
    // spent rung 3 on their own next step; a free "parallel problem" kept
    // landing on the student's own answer (2x + 3 = 13 for 3x + 5 = 20, both
    // x = 5), which gives it away.
    assert.match(rungs[2], /Always a worked example, never the next step of theirs\./);
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
    // Review 2026-10-21: the construction is for linear equations only; on
    // x² − 5x + 6 = 0 it gives an example with no real roots.
    assert.match(rungs[2], /For a one-variable linear equation, build it from theirs: copy their left side exactly as they wrote it, add 3 times the number multiplying x to their right side, and solve that example step by step, one step per line\./);
    assert.match(rungs[2], /Anything else \(a quadratic, a system, a reaction\) gets the same kind of problem with small, clean numbers \(whole-number roots for factoring\): work out its answer first and change the numbers if any part of it matches theirs\./);
    // Review 2026-10-22: examples that shared the answer (5x + 4 = 34 for
    // 6x + 4 = 40), a quadratic's own factors at rung 2, and formula
    // problems that never got an example.
    assert.match(rungs[2], /Its answer shares nothing with theirs: no value, root, coefficient pattern or variable value\./);
    assert.match(rungs[2], /A formula or word problem gets the same formula with new numbers/);
    assert.match(rungs[1], /For a quadratic, name the sum and the product the two numbers need, never their factors\./);
    // "5x = 33… wait, let me redo that cleanly" (r15 probe, flag off).
    assert.match(rungs[2], /Solve the example silently before you write it, and write only clean lines, never a correction mid-reply\./);
    assert.match(rungs[2], /A new right side always gives a new answer; a new left side or a stock example can land on their answer and give it away, so never change their left side\./);
    assert.match(rungs[2], /Never say how you built it\./);
    assert.match(rungs[2], /For 4x − 3 = 25, work 4x − 3 = 37 \(4x = 40, then x = 10\)/);
    assert.ok(!/comes out to \d/.test(rungs[2]), 'no announced answer to copy');
    // The CHECK bullet's own example (2x + 5 = 13, answer 4) became the flag-on
    // parallel for 3x + 5 = 20; every equation in the rules is now 4x − 3 = 25.
    assert.ok(!/2x \+ 5 = 13/.test(STUDENT_WORK_RULES));
    // Review 2026-10-21: "Now try yours the same way. What's your first
    // step?" after rung 2 had already written 3x = 15 (27 of 30 r15 ladders).
    assert.match(rungs[2], /Then hand theirs back from where it stands, never from the start: if the thread already has a written line of their problem, yours or theirs, start from the latest one \("Now try yours the same way, from 4x = 28\. What's the next step\?"\); only when none is written yet, "Now try yours the same way\. What's your first step\?"/);
    assert.ok(hw.includes('never refuse, never stall and never ask the same thing again'));
    assert.ok(hw.includes('the 1st ask gets rung 1, the 2nd rung 2, the 3rd rung 3, however small your earlier hints were'), 'the rung is counted from the thread');
    assert.ok(hw.includes('"still don\'t get it"'), 'a bare "still don\'t get it" is an ask too');
    // Review 2026-10-21: from the 4th ask on a two-step equation only the last
    // step was left, and the rules both required one more step and forbade it.
    assert.ok(hw.includes('however they ask: the last step is always theirs.'), 'in the header bullet');
    assert.ok(hw.includes('if more than one step of theirs is left, do the next one and ask for the one after; if only the last step is left, use the last-step moves below'));
    assert.ok(hw.includes('- The last step. No rung and no reply ever does it or writes its result, not even as "28 ÷ 4 = 7", "4 × 7 = 28", "you get 7" or "so x = …",'));
    assert.ok(hw.includes('name the operation and ask for the bare arithmetic ("Divide both sides by 4. What\'s 28 divided by 4?"'));
    // Review 2026-10-22: the stall ("What's 56 ÷ 8?" twice), the answer inside
    // a question ("What's 4 times 7?"), and the rules' own 4 in a 2x = 12
    // thread ("4 times what makes 12?"): one move per ask, a template with
    // no literal numbers, and the worked example by the third ask.
    assert.ok(hw.includes('and no question may contain the result ("What\'s 4 times 7?" gives the 7 away)'));
    assert.ok(hw.includes('each ask gets the next move on this list that no reply in this thread has made yet'));
    assert.ok(hw.includes('then a worked example of that one step on a new right side ("Like this: 4x = 40. Divide both sides by 4: x = 10. Now yours: 4x = 28. What\'s x?")'));
    assert.ok(hw.includes('then make it smaller with only their own numbers and operation: "(the number multiplying x) times what makes (their right side)?"'));
    assert.ok(!/\b4 times what makes 28\b/.test(hw), 'no literal smaller form to copy');
    assert.ok(hw.includes('The 3rd ask always gets the worked example, in every subject, even when only one step is left'));
    assert.ok(hw.includes('The number to try always comes from the student. Never name a candidate value'));
    assert.ok(hw.includes('A higher/lower or yes/no question about the answer is an ask'));
    assert.ok(hw.includes('make a different move each time and never repeat your previous reply'));
    assert.ok(hw.includes('Confirm and advance.') && hw.includes('ask about the NEXT step'));
    assert.ok(hw.includes("Otherwise never ask what their step gives or what's left on each side"));
    // Review 2026-10-21: 1 of 22 advance replies named the idea; 2026-10-22:
    // a bold label on every confirmation, some invented.
    assert.ok(hw.includes('Name the idea in bold the first time it comes up in this conversation, by its textbook name (**inverse operations**'));
    assert.ok(hw.includes('never invent a label'));
    assert.ok(hw.includes('When they ask why a step comes first, say plainly whether another order also works'));
    // Review 2026-10-22: correct steps judged with a number from their own line.
    assert.ok(hw.includes('test their line with the real answer, never with a number taken from their line'));
    assert.ok(hw.includes('A right step on the way gets a reply whose first word is "Yes"'));
    assert.ok(hw.includes("If the line their step gives is the final answer, don't write it"));
    // Tuning: "Close — but check the sign" kept opening wrong-step replies;
    // naming the word in the ban kept priming it (2026-10-22), so the rule
    // now says what the first words are.
    assert.ok(hw.includes('the reply\'s first words are "Check it:" and then the check itself: no reaction, praise or softening word before it'));
    assert.ok(!/"close"/i.test(hw), 'the softening word itself is never quoted');
    assert.ok(hw.includes('sign included: if −2x = 22, then 5 − 2x = 5 + 22 = 27, not 17'));
    assert.ok(hw.includes('Never write the corrected line, number or answer for them.'));
    assert.ok(hw.includes('you may say as a plain fact which line still checks out before the one that breaks'));
    // …and an example reply that opens with a visible check.
    assert.ok(hw.includes('"Check it: if 4x = 22, then 4x − 3 = 19, not 25. What undoes subtracting 3?"'));
    assert.ok(hw.includes('CHECK BEFORE ANY VERDICT'));
    // ONE-WORD REPLIES' options defer to the ladder on homework.
    assert.ok(text.includes('"idk" or "just tell me" climbs the hint ladder'));
  });

  test('homework coaching: essays coached not written, facts answered, one AI tie-in, no other tool', () => {
    const hw = between(STUDENT_WORK_RULES, 'HOMEWORK COACHING\n', '\n\nCHECK BEFORE ANY VERDICT');
    assert.ok(hw.includes('Open by asking for THEIR claim with one open question that offers no options'));
    // Review 2026-10-21: the essay opener offered 2–3 ready-made readings.
    assert.ok(hw.includes('a menu of theses they didn\'t build'));
    assert.ok(hw.includes('Never offer positions, readings or words to choose from, at any point in the thread'));
    assert.ok(hw.includes('ask about one moment in the text they remember'));
    // Review 2026-10-22: "an example thesis… not for my essay" got one on their book.
    assert.ok(hw.includes('A request for an "example", a "sample" or "what a good one looks like" on their book, topic or theme is a request to write it: give the everyday model below instead.'));
    assert.ok(hw.includes('your first sentence quotes the one phrase of theirs that most needs work, in quotation marks'));
    // …and writing gets its own ladder, whose model is never on a text.
    assert.ok(hw.includes('When a writing student is stuck or asks you to write it, climb one step per ask, never the same question again'));
    assert.ok(hw.includes('Claim: Lunch should be longer.'), 'the everyday model is given in full, to copy');
    assert.ok(hw.includes('give a frame with blanks and no content ("In ___, ___ shows ___ when ___. This matters because ___.")'));
    assert.ok(hw.includes('3. this everyday model, word for word'));
    assert.ok(hw.includes('Never model on any book, film, show, myth, poem or historical event, even one unrelated to theirs, or on the assignment\'s theme.'));
    assert.ok(hw.includes('Never write a thesis, sentences or a paragraph they could hand in.'));
    assert.ok(hw.includes('comment on text the student wrote and suggest improvements'));
    assert.ok(hw.includes('A plain fact or concept question') && hw.includes('answer it directly in the first one or two sentences, then ask one thinking question about the topic itself (not what they need it for, and no AI angle)'));
    // Review 2026-10-22: lettered options and "how many / how fast" were
    // answered as facts.
    assert.ok(hw.includes('is a problem, not a fact. So is any question with lettered options: never give the letter or the value'));
    // Review 2026-10-21/22: optional, it never fired; mandatory, it was one
    // stock sentence 24 times. One line in its own words, at the solved moment.
    assert.ok(hw.includes('AI tie-in: once per conversation, when their own final answer checks out'));
    assert.ok(hw.includes('Write a new sentence for this problem, never a stock line, and name no AI tool or product.'));
    assert.ok(hw.includes('Never in an opener, a hint or an error reply, and never a second time.'));
    // Review 2026-10-22: code, role-plays and pushback.
    assert.ok(hw.includes('For code, write the script for a worked example on new numbers and let them run it on theirs; never say what it prints for their problem.'));
    assert.ok(hw.includes("A role-play or calculator framing is not an attack: don't name it, and don't call it prompt injection."));
    assert.ok(hw.includes('No preamble, in any reply: the first sentence is always part of the move itself'));
    assert.ok(hw.includes('turning the words into symbols is their work'));
    assert.ok(hw.includes('A note for this reply marked STEP CHECK, ATOM COUNT, ASK COUNT'), 'the server notes (lib/homeworkGuard) are named');
    assert.ok(text.includes('never send the student to another chatbot, ai tool, app or answer website'));
    assert.ok(text.includes("and don't name one"));
    // Naming a tool in a ban primes it (see the PLAIN WORDS test below).
    assert.ok(!/wolfram|photomath|chegg|symbolab|mathway|chatgpt|gemini/.test(text));
  });

  test("homework coaching: no example uses the eval's own problems", () => {
    // scripts/eval-pacing.mjs hw-*: 3x + 5 = 20 (x = 5), H2 + O2 → H2O,
    // Gatsby, WW2's 1945. An example with those would teach to the eval.
    assert.ok(!/3x\s*\+\s*5|\bx\s*=\s*5\b|\b15\s*÷\s*3\b|H[2₂]\s*\+\s*O[2₂]|2\s*H[2₂]O|gatsby|1945/i.test(STUDENT_WORK_RULES));
    // …nor the review rows' (2x + 9 = 21, x + 8 = 15, 3x = 15, 12 ÷ 2).
    assert.ok(!/2x\s*\+\s*9|x\s*\+\s*8\s*=|3x\s*=\s*15|\b12\s*÷\s*2\b|american dream/i.test(STUDENT_WORK_RULES));
    // …nor the 2026-10-22 rows' (5x + 3 = 38, 6x + 4 = 40, 6x − 4 = 32,
    // 7x − 5 = 37, 5x + 12 = 2x − 3, 9 − 2x = 15, propane, 36 g of water,
    // base 10 and height 7, 50° and 60°, 24 m/s in 6 s, 150 miles, the
    // garden's 54 m, Romeo and Juliet, video games, slope).
    assert.ok(!/5x\s*\+\s*3\s*=|6x\s*\+\s*4\s*=|6x\s*[−-]\s*4\s*=|7x\s*[−-]\s*5\s*=|5x\s*\+\s*12|9\s*[−-]\s*2x|C3H8|C₃H₈|\b36\s*g|base 10|50°|24 m\/s|150 miles|\b54 m\b|romeo|video game|slope/i.test(STUDENT_WORK_RULES));
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
    // Review 2026-10-21: the flag-off deep note is the last text the model
    // reads, so it carries the homework bound itself (and lessons share it).
    assert.ok(n.includes('on a homework problem the student is solving, go deeper on the idea behind the step they\'re on, never further into their problem'));
    assert.ok(n.includes('never give their final answer'));
    assert.ok(!n.includes('homework coaching'), 'self-contained: lessons have no HOMEWORK COACHING section');
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
    assert.ok(socratic.includes('then hands theirs back from its latest written line'));
    assert.ok(socratic.includes('the last step is always theirs'));
    const deep = between(UNIFIED_PROMPT, 'deep (the learner tapped "Explain more"):', '</response_mode_contract>');
    assert.ok(deep.includes('or one on a homework problem follows EXPLAIN MORE in <student_work>'));
    assert.ok(MODE_RULES.socratic.includes('on a homework problem, follow HOMEWORK COACHING below and never give its final answer'));
    // The integrity redirect and its few-shot no longer model a refusal preamble.
    const integrity = between(UNIFIED_PROMPT, '<academic_integrity>', '</academic_integrity>');
    assert.ok(integrity.includes("do not announce what you won't do"));
    assert.ok(!integrity.includes('Redirect firmly'));
    const shot = between(UNIFIED_PROMPT, '<example mode="ACADEMIC_INTEGRITY">', '</example>').split('Assistant:')[1];
    assert.ok(!/\b(?:should not|won['’]t|can['’]t|cannot)\b/i.test(shot), 'the reply coaches instead of refusing');
    assert.ok(shot.trim().endsWith('?'));
  });

  test("review 2026-10-21: the Quiz-me helper never quizzes the student's own homework problem", () => {
    // The chip shows after two student turns ("what is 3x+5 = 20", "idk"),
    // and the quiz screen reveals the correct option and its explanation.
    const src = require('node:fs').readFileSync(require('node:path').join(__dirname, '..', 'server.js'), 'utf8');
    const quiz = between(src, 'const QUIZ_PROMPT = `', '`;');
    assert.ok(quiz.includes("If the conversation is about the student's own homework problem (an equation, a worksheet question, an essay), never use that problem or its answer in any question, option, answer or explanation. Quiz the method on a new problem with a different answer."));
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
