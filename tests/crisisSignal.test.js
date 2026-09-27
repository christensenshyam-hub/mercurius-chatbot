'use strict';

// Tests for lib/crisisSignal — the helper routes' crisis floor.
//
//   1. crisisSignal: first-person disclosures match (curly apostrophes and
//      case included); third-person discussion of AI harms, figures of speech
//      and look-alike phrases do not. The negatives are the answers the unit
//      8 defense question invites, which must still be graded.
//   2. isCrisisReply: a JSON crisis object or hotline prose outside the JSON
//      is a hand-off; a normal JSON result that mentions 988 is not.

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

  test('hotline prose the JSON parser would discard is a hand-off', () => {
    assert.equal(isCrisisReply("I'm glad you told me. Call or text 988 — the Suicide & Crisis Lifeline."), true);
    assert.equal(isCrisisReply('Text HOME to 741741 — Crisis Text Line'), true);
    assert.equal(isCrisisReply('{not json} Call or text 988'), true);
    assert.equal(isCrisisReply('Call or text 988.\n{"grade":"D","pass":false,"feedback":"Off topic."}'), true);
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
