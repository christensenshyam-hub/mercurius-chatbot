'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  BLOCKS_V1, hasBlocks, CURRICULUM_BLOCKS_APPENDIX, UNIFIED_BLOCKS_APPENDIX,
  parseQuizInterior, validateBlocks, scrubBlockMarkers,
} = require('../lib/blockMarkup');

const GOOD_Q = '[Q]\nWhich of these is a hallucination?\nA) Citing a real study accurately\nB) Inventing a plausible-looking citation\nC) Refusing to answer\nANS: B\n[/Q]';

describe('blockMarkup', () => {
  test('hasBlocks: only with the exact token', () => {
    assert.equal(hasBlocks(['blocks_v1']), true);
    assert.equal(hasBlocks(['blocks_v2', 'other']), false);
    assert.equal(hasBlocks([]), false);
    assert.equal(hasBlocks(undefined), false);
    assert.equal(BLOCKS_V1, 'blocks_v1');
  });

  test('appendices carry the exact grammar tokens', () => {
    for (const tok of ['[KEY]', '[/KEY]', '[EX]', '[/EX]', '[Q]', '[/Q]', 'ANS:', '[CHECK]']) {
      assert.ok(CURRICULUM_BLOCKS_APPENDIX.includes(tok), `curriculum appendix mentions ${tok}`);
    }
    for (const tok of ['[KEY]', '[/KEY]', '[EX]', '[/EX]']) {
      assert.ok(UNIFIED_BLOCKS_APPENDIX.includes(tok), `unified appendix mentions ${tok}`);
    }
  });

  test('parseQuizInterior: well-formed and malformed shapes', () => {
    const good = parseQuizInterior('Why?\nA) one\nB) two\nANS: A');
    assert.deepEqual([good.stem, good.options.length, good.answerIndex, good.wellFormed], ['Why?', 2, 0, true]);
    assert.equal(parseQuizInterior('Why?\nA) only one\nANS: A').wellFormed, false, 'needs >=2 options');
    assert.equal(parseQuizInterior('Why?\nA) one\nB) two').wellFormed, false, 'needs ANS');
    assert.equal(parseQuizInterior('Why?\nA) one\nB) two\nANS: D').wellFormed, false, 'ANS beyond options');
  });

  test('validateBlocks: clean reply passes', () => {
    const reply = `Hook line.\n\n[KEY]Likely is not the same as true.[/KEY]\n\n[EX]In Mata v. Avianca, lawyers filed AI-invented citations.[/EX]\n\n${GOOD_Q}`;
    const v = validateBlocks(reply);
    assert.equal(v.ok, true, v.problems.join('; '));
    assert.deepEqual([v.keyCount, v.exCount, v.quizzes.length, v.checkCount], [1, 1, 1, 0]);
  });

  test('validateBlocks: catches violations', () => {
    assert.ok(!validateBlocks('[KEY]a[/KEY] [KEY]b[/KEY]').ok, 'two KEYs');
    assert.ok(!validateBlocks('[KEY]unclosed').ok, 'unbalanced');
    assert.ok(!validateBlocks(`${GOOD_Q}\n[CHECK]And this?[/CHECK]`).ok, 'Q + CHECK');
    assert.ok(!validateBlocks('ANS: B').ok, 'ANS outside Q');
    assert.ok(validateBlocks('Plain prose reply. No blocks at all?').ok, 'prose is fine');
  });

  test('scrubBlockMarkers: unwraps cards, rewrites Q dropping ANS', () => {
    const reply = `Take. [KEY]Key idea.[/KEY]\n\n[EX]Example text.[/EX]\n\n${GOOD_Q}\n[LESSON_COMPLETE]`;
    const out = scrubBlockMarkers(reply);
    assert.ok(!out.includes('[KEY]') && !out.includes('[EX]') && !out.includes('[Q]'), 'markers gone');
    assert.ok(out.includes('Key idea.') && out.includes('Example text.'), 'content kept');
    assert.ok(out.includes('B) Inventing a plausible-looking citation'), 'options kept as prose');
    assert.ok(!/^ANS:/m.test(out), 'ANS never leaks');
    assert.ok(out.includes('[LESSON_COMPLETE]'), 'lesson marker untouched');
  });

  test('scrubBlockMarkers: no-op on prose', () => {
    const prose = 'Just a normal reply. With sentences.';
    assert.equal(scrubBlockMarkers(prose), prose);
  });
});
