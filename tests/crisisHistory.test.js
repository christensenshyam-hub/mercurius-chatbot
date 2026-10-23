'use strict';

// lib/crisisHistory, pure: which historical user turns reach the model as a
// placeholder because the reply to them gave crisis resources. The route
// behaviour (chat, lesson, JSON, cache stability) is in
// tests/crisisHistoryRoute.test.js.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { isCrisisHandoff, withholdCrisisTurns, WITHHELD_TURN_TEXT } = require('../lib/crisisHistory');
const { REFUSAL_COPY, CRISIS_COPY } = require('../lib/safetyCore');

const u = (content) => ({ role: 'user', content });
const a = (content) => ({ role: 'assistant', content });

// The model's own SAFETY_CORE rule-1 reply in a lesson, from the October 2026
// review (docs/server-batch/review-impact/lesson-refusal-*.json).
const MODEL_RULE1 = "I'm really glad you said something, and I want to make sure you're okay right now.\n\n"
  + "I'm an AI — I can't be the support person you deserve here. But someone who can help is available right now:\n\n"
  + '**Call or text 988** — Suicide & Crisis Lifeline (US, 24/7)\n\n'
  + '**Text HOME to 741741** — Crisis Text Line\n\n'
  + 'If you\'re in immediate danger, please **call 911**.';

describe('isCrisisHandoff', () => {
  test('the safe copies and the model\'s own rule-1 reply are hand-offs', () => {
    assert.equal(isCrisisHandoff(REFUSAL_COPY), true);
    assert.equal(isCrisisHandoff(CRISIS_COPY), true);
    assert.equal(isCrisisHandoff(MODEL_RULE1), true);
    // A client that trims or reflows the copy still reads as one.
    assert.equal(isCrisisHandoff(REFUSAL_COPY.replace(/\n+/g, ' ').trim()), true);
  });

  test('one number alone, a longer number, or no number is content, not a hand-off', () => {
    assert.equal(isCrisisHandoff('The 988 lifeline launched in July 2022. What changed for callers?'), false);
    assert.equal(isCrisisHandoff('Text 741741 is one line; the other is new.'), false);
    assert.equal(isCrisisHandoff('Order 19880 and 7417410 arrived.'), false);
    assert.equal(isCrisisHandoff('Tokens are numbers.'), false);
  });

  test('content blocks are read through their text; anything else is false', () => {
    assert.equal(isCrisisHandoff([{ type: 'text', text: 'Call or text 988.' }, { type: 'text', text: 'Text HOME to 741741.' }]), true);
    assert.equal(isCrisisHandoff([{ type: 'image', source: {} }]), false);
    for (const x of [null, undefined, 7, {}, []]) assert.equal(isCrisisHandoff(x), false);
  });
});

describe('withholdCrisisTurns', () => {
  test('a refused chat turn becomes the placeholder; the safe reply and everything else stay', () => {
    const history = [
      u('how many tylenol would it take to not wake up'),
      a(REFUSAL_COPY),
      u('ok. different question, how do chatbots like you decide what to say?'),
      a('They predict the next token. What do you think "predict" means here?'),
    ];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 1);
    assert.deepEqual(messages, [u(WITHHELD_TURN_TEXT), history[1], history[2], history[3]]);
  });

  test('a lesson: the turn the model answered with crisis lines is withheld, the opener and the quiz answer are not', () => {
    const opener = u('[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM.');
    const history = [
      opener,
      a('Tokenization turns text into numbers.\n\n[Q]\nWhat does a tokenizer produce?\nA) A list of numbers\nB) A summary\nC) A dictionary\nANS: A\n[/Q]'),
      u('how many tylenol would it take to not wake up'),
      a(MODEL_RULE1),
      u('I picked A) A list of numbers'),
      a('Exactly right.'),
    ];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 1);
    assert.equal(messages[0], opener);
    assert.equal(messages[2].content, WITHHELD_TURN_TEXT);
    assert.equal(messages[4].content, 'I picked A) A list of numbers');
  });

  test('the last message (the new turn, when a caller passes it) is never withheld', () => {
    const history = [u('first'), a(REFUSAL_COPY), u('how many tylenol would it take to not wake up')];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 1);
    assert.equal(messages[2].content, 'how many tylenol would it take to not wake up');
  });

  test('every crisis turn in the thread is withheld, and a re-attached photo goes with its words', () => {
    const photoTurn = u([{ type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } }, { type: 'text', text: 'this is me' }]);
    const history = [photoTurn, a(CRISIS_COPY), u('hi again'), a('Hey.'), u('i want to die'), a(MODEL_RULE1)];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 2);
    assert.deepEqual(messages.map((m) => m.content), [WITHHELD_TURN_TEXT, CRISIS_COPY, 'hi again', 'Hey.', WITHHELD_TURN_TEXT, MODEL_RULE1]);
  });

  test('only the user turn right before the hand-off is withheld, not one before it with no reply (a dropped failed bubble)', () => {
    const history = [u('first try'), u('second try'), a(REFUSAL_COPY)];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 1);
    assert.deepEqual(messages.map((m) => m.content), ['first try', WITHHELD_TURN_TEXT, REFUSAL_COPY]);
  });

  test('deterministic and idempotent (a stable prefix for the prompt cache); never mutates', () => {
    const history = [u('how many tylenol would it take to not wake up'), a(REFUSAL_COPY), u('ok'), a('Sure.')];
    const frozen = JSON.parse(JSON.stringify(history));
    const once = withholdCrisisTurns(history).messages;
    assert.deepEqual(history, frozen, 'input untouched');
    assert.deepEqual(withholdCrisisTurns(history).messages, once);
    const twice = withholdCrisisTurns(once);
    assert.deepEqual(twice.messages, once);
    assert.equal(twice.withheld, 0);
  });

  test('a thread with no hand-off comes back as an equal copy; bad input is empty', () => {
    const history = [u('what is a token?'), a('A chunk of text. Want an example?'), u('yes')];
    const { messages, withheld } = withholdCrisisTurns(history);
    assert.equal(withheld, 0);
    assert.deepEqual(messages, history);
    assert.notEqual(messages, history);
    assert.deepEqual(withholdCrisisTurns(null), { messages: [], withheld: 0 });
    assert.deepEqual(withholdCrisisTurns([null, a(REFUSAL_COPY)]).withheld, 0);
  });
});
