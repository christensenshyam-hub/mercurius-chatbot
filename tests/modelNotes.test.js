'use strict';

// lib/modelNotes: Sonnet 5.5's prompt notes (the tuning pass after the A/B of
// 2026-10-24). Unit level: which models get them, that they are a byte-stable
// constant safe to cache and to stream, and where the prefix composition puts
// them (after the source library, before the app facts and the safety core,
// which stays LAST). tests/tutorModel.test.js checks the real prefixes on the
// wire, both flag states, and that no Sonnet 4.6 request ever carries them.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const notes = require('../lib/modelNotes');
const sb = require('../lib/systemBlocks');
const { SAFETY_CORE, SAFETY_CORE_TAGGED } = require('../lib/safetyCore');
const { APP_FACTS, APP_FACTS_TAGGED } = require('../lib/appFacts');

const { SONNET_55_NOTES, SONNET_55_NOTES_TAGGED, modelNotesFor } = notes;
const S55 = 'claude-sonnet-5-5';

describe('modelNotesFor: claude-sonnet-5-5 only', () => {
  test('Sonnet 5.5 and its dated ids get the block, plain or tagged', () => {
    for (const id of [S55, `${S55}-20261001`, '  Claude-Sonnet-5-5 ']) {
      assert.equal(modelNotesFor(id), SONNET_55_NOTES, id);
      assert.equal(modelNotesFor(id, { tagged: true }), SONNET_55_NOTES_TAGGED, id);
    }
  });

  test('every other model gets null, which composeStatic skips', () => {
    for (const id of ['claude-sonnet-4-6', 'claude-haiku-4-5', 'claude-opus-4-6', 'claude-sonnet-5', 'claude-sonnet-5-55', 'claude-opus-5-5', 'claude-haiku-5-5', '', undefined, null]) {
      assert.equal(modelNotesFor(id), null, String(id));
      assert.equal(modelNotesFor(id, { tagged: true }), null, String(id));
    }
  });
});

describe('the notes are a byte-stable constant, safe to cache and to stream', () => {
  test('the same bytes on every call and every load', () => {
    assert.ok(Object.isFrozen(notes));
    assert.equal(modelNotesFor(S55), modelNotesFor(S55));
    // A fresh load (a restart, another replica) builds the same bytes.
    delete require.cache[require.resolve('../lib/modelNotes')];
    const again = require('../lib/modelNotes');
    assert.notEqual(again, notes, 'a fresh module instance');
    assert.equal(again.SONNET_55_NOTES, SONNET_55_NOTES);
    assert.equal(again.SONNET_55_NOTES_TAGGED, SONNET_55_NOTES_TAGGED);
  });

  test('its own heading, no outer whitespace; the tagged form wraps it whole', () => {
    assert.ok(SONNET_55_NOTES.startsWith('## MODEL NOTES'));
    assert.equal(SONNET_55_NOTES, SONNET_55_NOTES.trim());
    assert.equal(SONNET_55_NOTES_TAGGED, `<model_notes>\n${SONNET_55_NOTES}\n</model_notes>`);
  });

  test('no template braces and no brackets (the clients act on [CHECK], [Q], [LESSON_COMPLETE] …)', () => {
    assert.ok(!SONNET_55_NOTES.includes('{{'));
    assert.ok(!/[[\]]/.test(SONNET_55_NOTES));
  });

  test('short: one heading and one line per rule, under 4,000 characters', () => {
    // Sonnet 5.5 follows instructions literally: each rule once, plainly,
    // with its scope (the review's additions took it from about 3,100).
    const lines = SONNET_55_NOTES.split('\n');
    assert.ok(lines.slice(1).every((l) => l.startsWith('- ')), 'one bullet per line');
    assert.ok(lines.length <= 14, `${lines.length} lines`);
    assert.ok(SONNET_55_NOTES.length < 4000, `${SONNET_55_NOTES.length} chars`);
    assert.equal(new Set(lines).size, lines.length, 'no line twice');
  });

  test('never names the model (APP FACTS: "exact version unknown")', () => {
    assert.ok(!/sonnet|claude|anthropic|5\.5|4\.6/i.test(SONNET_55_NOTES));
  });

  test('examples carry no numbers (the only digits are the length rule\'s), and none of the eval\'s problems', () => {
    // PLAIN WORDS: a number from an instruction's example must never reach a
    // reply, and an example on the eval's own problem would teach to it.
    assert.deepEqual(SONNET_55_NOTES.match(/\d+/g), ['4', '3']);
    assert.ok(!/3x\s*\+\s*5|2x\s*\+\s*9|x\s*\+\s*8|5x\s*\+\s*12|gatsby|1945|jake/i.test(SONNET_55_NOTES));
  });

  test('each miss the A/B found has its rule', () => {
    const rules = [
      /at most 4 sentences, its closing question included/, // median 5 sentences
      /no sentence only announces or labels a point/, // "Here's the tension."
      /closing question is the reply's last sentence/, // a hint after the opener's question
      /concede in one short sentence with no source/, // the cut-off Debate reply
      /opens with the line "Here's how your reasoning scored:"/, // a scoring block under its own lead-in
      /the first word is "Yes", in the same sentence as your next move \(Confirm and advance says what that move holds\)/, // hw-step-both-sides 0/3
      /That "Yes" is part of the move, not preamble/,
      /A push for the answer .* is not being lost/, // proof-ind, calc-int, sys-1
      /the student writes every line of their solution/,
      /can't be checked by putting it back in .* is checked silently against your own working/, // calc-def
      /never a case where it would be right/,
      /when they lean on a reason \(theirs or a teacher's\) for a step or a fact, check it before you build on it/, // stats-sd
      /An answer you have confirmed is settled/, // molarity-1
      /never call their slip an AI's/, // calc-rr, stoich-1, newton-fric
      /AI tie-in belongs only in the reply that confirms a final answer they worked out themselves/, // 27 of 48 chats
      /never when they were rushed or pushing for the answer/,
    ];
    for (const re of rules) assert.match(SONNET_55_NOTES, re);
  });

  test('the SAFETY CORE still comes first, and its replies keep their own shape', () => {
    const [heading, first] = SONNET_55_NOTES.split('\n');
    assert.match(heading, /the SAFETY CORE still comes first/);
    // Read first: a crisis or sextortion reply is never squeezed into the
    // length rule or given a closing question.
    assert.match(first, /^- A reply the SAFETY CORE governs \(a crisis, a safety topic, a refusal, a privacy warning, an age notice\) keeps the length, content and ending that block gives it; none of these notes apply to it\.$/);
  });

  // Review of the first draft: a literal reader applies a rule to every case
  // it doesn't exclude, so each rule names its exceptions.
  test('each rule is scoped so a literal reading can\'t overrule what it doesn\'t mention', () => {
    const rule = (re) => SONNET_55_NOTES.split('\n').find((l) => re.test(l)) || '';
    // A ceiling, not a floor: a one-question opener and a one-line confirm fit.
    assert.ok(!/2–4 sentences/.test(SONNET_55_NOTES));
    // hw-example-first (5.5 passed it 3/3): an asked-for worked example is
    // not a bare new problem.
    const opener = rule(/first reply is one question/);
    assert.match(opener, /with no work, no answer and no request for a worked example or code/);
    assert.match(opener, /A request for a worked example or for code gets it now, on new numbers, as the hint ladder says\./);
    // A push: every rung spelled out, and a deadline or permission gets a word.
    const push = rule(/A push for the answer/);
    for (const re of [/The first push gets the technique named and the exact piece it acts on/, /the second, how that technique works in general, ending in a question about their piece/, /the third, a worked example on a different problem/, /after that, alternate a narrower question on their latest line with another worked example/, /A deadline or a teacher's permission gets a few calm words inside the move, never a bigger step and never an argument/]) {
      assert.match(push, re);
    }
    // Numbers: an antiderivative checks by differentiating (5.5's calc-int
    // strength); a match is shown before it is confirmed.
    const numbers = rule(/can't be checked by putting it back in/);
    assert.match(numbers, /\(a definite integral, a derivative at a point, a limit, a standard deviation\)/);
    assert.match(numbers, /if it matches, show the line of yours it matches, then say it's right/);
    assert.match(numbers, /An antiderivative is checked by differentiating it\./);
    // A reason is judged on schoolwork only, and only a wrong part is named
    // (Debate's lead-in and Discussion's "not verdicts" keep their rules).
    assert.match(rule(/lean on a reason/), /^- On schoolwork, .*if part of it is wrong, say which part\.$/);
    // Settled, unless they bring something new; a thanks still deals with
    // what came with it (stats-sd's last turn had a reason and a thanks).
    const settled = rule(/An answer you have confirmed is settled/);
    assert.match(settled, /asked again with nothing new, confirm it in one line; new work or a reason it might be wrong gets checked, and if your confirmation was wrong, say so plainly/);
    assert.match(settled, /A thanks or "I'm done" gets one short closing line and no question, after you deal with any answer or reason in the same message\./);
  });

  test('no quoted opener a reply could copy (safetyCore\'s history: a quoted example leaked into replies)', () => {
    for (const s of ['Right, and the word doing the work', 'Yes — so what undoes', "Here's the tension"]) {
      assert.ok(!SONNET_55_NOTES.includes(s), s);
    }
  });
});

describe('composition: the notes sit before the app facts and the safety core, which stays LAST', () => {
  // The free-chat shapes server.js composes (v2Static, legacyStatic), with
  // stand-in text for the large prompts, as tests/appFacts.test.js does.
  const SHAPES = {
    v2App: [['UNIFIED PROMPT', 'SOURCE BLOCK'], SONNET_55_NOTES_TAGGED, SAFETY_CORE_TAGGED, APP_FACTS_TAGGED],
    v2Widget: [['UNIFIED PROMPT', 'CLUB BLOCK', 'SOURCE BLOCK'], SONNET_55_NOTES_TAGGED, SAFETY_CORE_TAGGED, APP_FACTS_TAGGED],
    legacyApp: [['QUALITY PREFIX', 'SOCRATIC PROMPT', null, 'SOURCE BLOCK'], SONNET_55_NOTES, SAFETY_CORE, APP_FACTS],
    legacyWidget: [['QUALITY PREFIX', 'DEBATE PROMPT', 'CLUB BLOCK', 'SOURCE BLOCK'], SONNET_55_NOTES, SAFETY_CORE, APP_FACTS],
  };

  for (const [name, [head, block, safety, facts]] of Object.entries(SHAPES)) {
    test(`${name}: notes → app facts → safety core LAST; without notes, today's prefix byte for byte`, () => {
      const withNotes = sb.composeStaticWithAppFacts([...head, block, safety]);
      assert.ok(withNotes.endsWith(`\n\n${block}\n\n${facts}\n\n${safety}`));
      assert.equal(withNotes.split('## MODEL NOTES').length, 2, 'once');
      assert.equal(withNotes, sb.composeStaticWithAppFacts([...head, block, safety]), 'byte-stable');
      // Every other model: modelNotesFor returns null, which composeStatic skips.
      const without = sb.composeStaticWithAppFacts([...head, null, safety]);
      assert.equal(without, sb.composeStaticWithAppFacts([...head, safety]));
      assert.equal(withNotes.replace(`\n\n${block}`, ''), without);
    });
  }
});
