'use strict';

// lib/basicsVoice — the Basics replies' filler-word and label clean-up
// (2026-10). Cases from the UX review's live lessons, the edges that would
// change a sentence's meaning, and chunk-boundary independence.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const { createBasicsVoice, basicsVoiceText, LABEL_WINDOW } = require('../lib/basicsVoice');

function streamed(text, sizes) {
  const v = createBasicsVoice();
  let out = '';
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const n = sizes[k++ % sizes.length];
    out += v.push(text.slice(i, i + n));
    i += n;
  }
  return out + v.flush();
}

describe('filler words', () => {
  test('the UX review\'s live replies', () => {
    assert.equal(
      basicsVoiceText('That\'s a lovely idea to honor him. But let\'s keep "bluebird" just between you and your family.'),
      'That\'s a lovely idea to honor him. But let\'s keep "bluebird" between you and your family.',
    );
    assert.equal(
      basicsVoiceText('[KEY]A chatbot answers real questions in plain words, just like this one.[/KEY]'),
      '[KEY]A chatbot answers real questions in plain words, like this one.[/KEY]',
    );
    assert.equal(basicsVoiceText('Keep that just for your family.'), 'Keep that for your family.');
  });

  test('a sentence start gets a capital; "simply" too', () => {
    assert.equal(basicsVoiceText('Just type your question.'), 'Type your question.');
    assert.equal(basicsVoiceText('Done. Just tap the arrow.\n\nJust "hi" works.'), 'Done. Tap the arrow.\n\n"Hi" works.');
    assert.equal(basicsVoiceText('You can simply ask again.'), 'You can ask again.');
    assert.equal(basicsVoiceText('**Just** this'), '**Just** this', 'a bold word is not a whole word');
  });

  test('never flips the meaning: after a negation it becomes "only"', () => {
    assert.equal(basicsVoiceText('It\'s not just you.'), 'It\'s not only you.');
    assert.equal(basicsVoiceText('It isn\'t just for young people.'), 'It isn\'t only for young people.');
    assert.equal(basicsVoiceText('It doesn’t just guess.'), 'It doesn’t only guess.');
    assert.equal(basicsVoiceText('Never just trust it.'), 'Never only trust it.');
    assert.equal(basicsVoiceText('I said not. Just wait.'), 'I said not. Wait.', 'a negation in the last sentence does not count');
  });

  test('keeps the word where the sentence needs it', () => {
    for (const text of [
      'Just because it sounds sure doesn\'t mean it\'s right.',
      'Simply put, check it.',
      'That is just\nthe start.',
      'That is just',
      'That\'s just, well, fine.',
      'Try asking me: "Is it safe to just send it?"',
      'Try asking me: “Can I just send it?”',
    ]) assert.equal(basicsVoiceText(text), text);
  });

  test('a quote ends at the line break', () => {
    assert.equal(basicsVoiceText('He said "wait\nI just did it.'), 'He said "wait\nI did it.');
  });
});

describe('filler lead-ins at the start of a sentence (the gate\'s longest sentences)', () => {
  test('removed, with a capital after; mid-sentence and quoted ones stay', () => {
    assert.equal(
      basicsVoiceText('Not quite. Think of it this way: if someone knocked on your door, you would check first.'),
      'Not quite. If someone knocked on your door, you would check first.',
    );
    assert.equal(basicsVoiceText('Here\u2019s the thing: a voice can be faked.'), 'A voice can be faked.');
    assert.equal(basicsVoiceText("Here's another way to think about it: call back."), 'Call back.');
    for (const text of [
      'I think of it this way: slowly.',
      'Try asking me: "Think of it this way: what then?"',
      "Here's the plan: call back.",
      'Think of it this way',
    ]) assert.equal(basicsVoiceText(text), text);
  });
});

describe('guide labels at the start of a line', () => {
  test('the UX review\'s live reply', () => {
    assert.equal(
      basicsVoiceText('Some text.\n\nOne line on that: open enrollment is happening right now.\n\n**Safety point:** Cover your name and numbers.'),
      'Some text.\n\nOpen enrollment is happening right now.\n\nCover your name and numbers.',
    );
  });

  test('bold kept balanced; other labels; never mid-line or a look-alike', () => {
    assert.equal(basicsVoiceText('**Safety point: Cover your name.**'), '**Cover your name.**');
    assert.equal(basicsVoiceText('Idea 2: hang up and call back.'), 'Hang up and call back.');
    assert.equal(basicsVoiceText('  Recap: Last time, you did it.'), '  Last time, you did it.');
    assert.equal(basicsVoiceText('__Trap:__ C is the trap.'), 'C is the trap.');
    for (const text of [
      'That\'s right. Safety point: cover it.',
      'Safety points matter: yes.',
      'Try this today: Ask a chatbot.',
      'ANS: B',
      'Ideas: three of them.',
    ]) assert.equal(basicsVoiceText(text), text);
  });

  test('a short reply that is only a label line', () => {
    assert.equal(basicsVoiceText('Recap:'), '');
    assert.equal(basicsVoiceText('Recap'), 'Recap');
  });
});

describe('streaming', () => {
  const SAMPLES = [
    'Last time, you learned the postcard rule.\n\nJust type in the box. It\'s not just you.\n\n**Safety point:** Keep "bluebird" just between you.\n\n[Q]\nWhich?\nA) x\nB) y\nANS: B\n[/Q]\n\n[LESSON_COMPLETE]',
    'One line on that: open enrollment is on.\n\n__Safety point: Cover it.__\n\nTry asking me: "Can I just send it?"\n\nJust because. Simply put, no.\n\nIdea 2: just call. Simply\n\njust',
    '  Recap: Last time.\nJust\njust \nI just learned about a scam. Can we pick a code word — just for us — to use?',
    'Not quite. Think of it this way: if a caller asks. Here\u2019s the thing:  just call.\nHere\'s another way to look at it: no.\nThink of it',
  ];

  test('CHUNK-BOUNDARY INDEPENDENCE: any chunking equals one-shot', () => {
    for (const text of SAMPLES) {
      const once = basicsVoiceText(text);
      for (let size = 1; size <= 12; size++) assert.equal(streamed(text, [size]), once, `chunk size ${size}`);
    }
  });

  test('random chunkings (300 per sample) equal one-shot', () => {
    let seed = 7;
    const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (const text of SAMPLES) {
      const once = basicsVoiceText(text);
      for (let n = 0; n < 300; n++) {
        const sizes = Array.from({ length: 8 }, () => 1 + Math.floor(rand() * 20));
        assert.equal(streamed(text, sizes), once, `sizes ${sizes.join(',')}`);
      }
    }
  });

  test('holds back at most a line start and a dropped word\'s next word', () => {
    const v = createBasicsVoice();
    assert.equal(v.push('Hello there, '), 'Hello there, ', 'a line ruled out of labels streams at once');
    assert.equal(v.push('just'), '');
    assert.equal(v.push(' between'), '');
    assert.equal(v.push(' you.'), 'between ');
    assert.equal(v.flush(), 'you.');
    const w = createBasicsVoice();
    assert.equal(w.push('Safety'), '', 'a possible label waits');
    assert.equal(w.push(' first, always and every time, ok.'), 'Safety first, always and every time, ');
    assert.ok(LABEL_WINDOW >= 30);
  });
});
