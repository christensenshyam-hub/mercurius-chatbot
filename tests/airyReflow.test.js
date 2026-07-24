'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { createReflow, reflowText, reflowLimit } = require('../lib/airyReflow');

/** Feed `text` through a streaming reflower in chunks of `size` chars. */
function streamed(text, limit, size) {
  const r = createReflow({ limit });
  let out = '';
  for (let i = 0; i < text.length; i += size) out += r.push(text.slice(i, i + size));
  return out + r.flush();
}

describe('airyReflow', () => {
  test('splits a packed paragraph at the sentence limit', () => {
    assert.equal(reflowText('One. Two. Three. Four.', 2), 'One. Two.\n\nThree. Four.');
    // limit 1: every sentence its own paragraph (single capitals are treated
    // as initials by the abbreviation guard, so use real words)
    assert.equal(reflowText('Go now. Stop it. Look up.', 1), 'Go now.\n\nStop it.\n\nLook up.');
  });

  test('respects existing paragraph breaks and resets the counter', () => {
    const text = 'One. Two.\n\nThree. Four.';
    assert.equal(reflowText(text, 2), text);
  });

  test('limit 3 allows three-sentence paragraphs', () => {
    const text = 'One. Two. Three.\n\nFour.';
    assert.equal(reflowText(text, 3), text);
    assert.equal(reflowText('One. Two. Three. Four.', 3), 'One. Two. Three.\n\nFour.');
  });

  test('question and exclamation terminals count', () => {
    assert.equal(reflowText('Really? Yes! And then some.', 2), 'Really? Yes!\n\nAnd then some.');
  });

  test('decimals and abbreviations do not split', () => {
    assert.equal(reflowText('GPT-4 has 1.8 trillion parameters. It is big. Dr. Smith agrees. Fine.', 2),
      'GPT-4 has 1.8 trillion parameters. It is big.\n\nDr. Smith agrees. Fine.');
  });

  test('bullet lists are exempt', () => {
    const text = 'Intro.\n- one bullet. two sentences. three here.\n- another.\nOutro one. Outro two. Outro three.';
    const out = reflowText(text, 2);
    assert.ok(out.includes('- one bullet. two sentences. three here.'), 'bullet line untouched');
  });

  test('code fences are exempt', () => {
    const text = 'Look.\n\n```\nx = 1. y = 2. z = 3. w = 4.\n```\n\nDone. Really. Truly.';
    const out = reflowText(text, 2);
    assert.ok(out.includes('x = 1. y = 2. z = 3. w = 4.'), 'fence interior untouched');
    assert.ok(out.includes('Done. Really.\n\nTruly.'), 'prose after fence reflowed');
  });

  test('[CHECK] spans are exempt and tags survive', () => {
    const text = 'Teach one. Teach two. [CHECK]Why is this true? Think hard. Answer well.[/CHECK]';
    const out = reflowText(text, 2);
    assert.ok(out.includes('[CHECK]Why is this true? Think hard. Answer well.[/CHECK]'), 'check span untouched');
  });

  test('[LESSON_COMPLETE] survives and stays server-strippable', () => {
    // The single newline before the marker may be upgraded to a paragraph
    // break (the paragraph hit its limit) — that is contract-compatible:
    // the marker stays on its own line and the server's end-anchored strip
    // regex tolerates the extra newline.
    const out = reflowText('Done one. Done two.\n[LESSON_COMPLETE]', 2);
    assert.ok(/\n\[LESSON_COMPLETE\]$|\n\n\[LESSON_COMPLETE\]$/.test(out), `marker on its own line: ${JSON.stringify(out)}`);
    assert.ok(/(?:\n?\s*\[LESSON_COMPLETE\]\s*)+$/.test(out), 'lessonOutcome strip regex still matches');
  });

  test('CHUNK-BOUNDARY INDEPENDENCE: any chunking equals one-shot', () => {
    const text = 'First sentence here. Second one lands. Third begins now! Fourth asks why? ' +
      'Fifth continues.\n\nNew para one. New para two. New para three. ' +
      '[CHECK]Q one? Q two.[/CHECK] After check. More text. Even more.\n' +
      '- bullet a. still bullet.\n- bullet b.\n\n```\ncode. code. code. code.\n```\nTail one. Tail two. Tail three.';
    const oneShot = reflowText(text, 2);
    for (const size of [1, 2, 3, 5, 7, 11, 50, text.length]) {
      assert.equal(streamed(text, 2, size), oneShot, `chunk size ${size} must match one-shot`);
    }
  });

  test('reflowLimit: 3 for curriculum/deep, 2 otherwise, debate exempt', () => {
    assert.equal(reflowLimit({ isCurriculum: true, responseMode: 'balanced' }), 3);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'deep' }), 3);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'concise' }), 2);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'concise', mode: 'debate' }), Infinity);
    // Infinity limit = pass-through
    const debate = '**Claim:** A. **Warrant:** B. **Impact:** C. **Rebuttal:** D.';
    assert.equal(reflowText(debate, Infinity), debate);
  });

  test('empty and marker-only inputs are stable', () => {
    assert.equal(reflowText('', 2), '');
    assert.equal(reflowText('[LESSON_COMPLETE]', 2), '[LESSON_COMPLETE]');
  });
});
