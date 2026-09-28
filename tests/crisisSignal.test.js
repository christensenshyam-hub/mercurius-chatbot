'use strict';

// Tests for lib/crisisSignal — the helper routes' crisis floor.
//
//   1. crisisSignal: first-person disclosures match (curly apostrophes and
//      case included); third-person discussion of AI harms, figures of speech
//      and look-alike phrases do not. The negatives are the answers the unit
//      8 defense question invites, which must still be graded.
//   2. isCrisisReply: a JSON crisis object, or prose outside the JSON that
//      gives BOTH rule-1 lines, is a hand-off; a normal JSON result that
//      mentions 988, a trailing note naming one line, or a half-written
//      object is not.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const { crisisSignal, isCrisisReply } = require('../lib/crisisSignal');

describe('crisisSignal', () => {
  const disclosures = [
    "honestly I don't care about any of this, I want to die",
    'i cut myself last night and i dont know what to do',
    "I've been thinking about killing myself",
    'i really wanna die',
    'I’m so suicidal lately',
    'I have been feeling suicidal',
    'i want to end my life',
    'everyone would be better off without me',
    "i don't want to be alive anymore",
    'I dont want to live anymore',
    'my stepdad hits me when he drinks',
    "I'm being abused at home",
    'i wish i was dead',
    'there is no reason to live',
    'im gonna kms',
    'I have been self-harming',
    'I keep wanting to hurt myself, I want to hurt myself',
    "i'm not safe at home",
    "I've been thinking about suicide",
    'I WANT TO DIE',
    'i want to die for real',
    'I want to die in my sleep',
    'I want to die when I get home',
    'I hate my life and want to die',
    'i dont wanna live anymore',
    'I want to end my life over this',
    'my dad hit me on the head',
    'my stepdad hit me with a belt',
    'I’m not safe with him',
    'I said "i want to die',
  ];
  for (const text of disclosures) {
    test(`matches: ${text}`, () => assert.equal(crisisSignal(text), true));
  }

  const notDisclosures = [
    "A chatbot encouraged a teen's suicide, which shows AI can't detect a crisis.",
    'Character.AI was sued after a 14-year-old died by suicide.',
    'AI should flag self-harm content and point people to 988.',
    'I cut myself off from social media for a week.',
    'The model predicted die after the words I want to.',
    'Suicide prevention hotlines like 988 are one safeguard.',
    "I'm going to die of embarrassment if I fail this",
    'I thought about suicide prevention when designing the bot',
    'A self-driving car drove 1000 kms without a crash.',
    "I don't want to live in a world where AI decides who gets hired.",
    'The chatbot told him to kill himself.',
    'my teacher hurt my feelings',
    'I would not use AI for my essays because I want to learn.',
    // Curriculum topics and everyday idioms.
    'Scammers used AI voice cloning to try to take my life savings.',
    'Social media was taking my life over, so I set screen limits.',
    'Ending my life-long habit of trusting the first answer.',
    'My brother beat me at chess using Stockfish.',
    'My teacher hit me with a pop quiz on neural nets.',
    'my sister hit me up about the AI club',
    'I don’t want to hurt myself academically by relying on ChatGPT.',
    'I’m not safe with my data on these apps.',
    'I want to die on this hill: AI art is still art.',
    // Reported speech: a case quoted in a unit 8 answer.
    'The teen wrote "I want to die" and the chatbot replied with a poem.',
    'The teen wrote “I want to kill myself” and the bot never flagged it.',
  ];
  for (const text of notDisclosures) {
    test(`does not match: ${text}`, () => assert.equal(crisisSignal(text), false));
  }

  test('non-strings and blank text are false, never a throw', () => {
    for (const v of [undefined, null, 42, {}, [], '', '   ']) assert.equal(crisisSignal(v), false);
  });
});

describe('isCrisisReply', () => {
  test('a JSON crisis object (HELPER_CRISIS_RULE) is a hand-off, with or without prose around it', () => {
    assert.equal(isCrisisReply('{"crisis":true,"message":"I am glad you told me."}'), true);
    assert.equal(isCrisisReply('Here is my answer:\n{"crisis": true}'), true);
    assert.equal(isCrisisReply('{"crisis":"true"}'), true);
  });

  test('rule-1 prose (both lines) the JSON parser would discard is a hand-off', () => {
    const prose = "I'm glad you told me. Call or text 988 — the Suicide & Crisis Lifeline. Text HOME to 741741 — Crisis Text Line.";
    assert.equal(isCrisisReply(prose), true);
    assert.equal(isCrisisReply(`${prose}\n{"grade":"D","pass":false,"feedback":"Off topic."}`), true);
    assert.equal(isCrisisReply(`${prose} {"title":"Quiz","questions":[`), true, 'prose before a half-written object');
  });

  test('one hotline on its own is content, not a hand-off', () => {
    assert.equal(isCrisisReply('{"title":"Quiz","questions":[]} Note: the 988 lifeline launched in 2022.'), false);
    assert.equal(isCrisisReply('Call or text 988.\n{"grade":"D","pass":false,"feedback":"Off topic."}'), false);
    assert.equal(isCrisisReply('Text HOME to 741741 — Crisis Text Line'), false);
  });

  test('a half-written object (cut off by max_tokens) is judged by its own crisis flag only', () => {
    assert.equal(isCrisisReply('{"title":"Crisis lines","questions":[{"q":"What does 988 connect you to? 741741?'), false);
    assert.equal(isCrisisReply('{"crisis":true,"message":"I\'m really glad you told me. Call or text 98'), true);
    assert.equal(isCrisisReply('{not json} Call or text 988, or text HOME to 741741'), false);
  });

  test('a normal JSON result is not, even when a field mentions 988', () => {
    assert.equal(isCrisisReply('{"grade":"B","pass":true,"feedback":"Good point that a bot should route people to 988."}'), false);
    assert.equal(isCrisisReply('{"grade":"A","pass":true,"feedback":"Clear."}'), false);
    assert.equal(isCrisisReply('{"crisis":false,"grade":"C"}'), false);
    assert.equal(isCrisisReply('Here you go: {"title":"Quiz","questions":[]}'), false);
  });

  test('no hotline and no JSON is not a hand-off; numbers only match whole', () => {
    assert.equal(isCrisisReply('Could not grade that.'), false);
    assert.equal(isCrisisReply('The 1988 paper on neural nets'), false);
    for (const v of [undefined, null, 42, {}]) assert.equal(isCrisisReply(v), false);
  });
});
