'use strict';

/**
 * Unit smoke tests for the metric functions exported by
 * `scripts/eval-pacing.mjs`. The script itself needs a running server
 * (and an Anthropic key behind it); these tests only exercise the pure
 * measurement layer on fixture strings, so a metric regression is
 * caught before anyone burns an eval run on it.
 *
 * The script is ESM (.mjs); this suite is CJS like the rest of tests/,
 * so it loads the module via dynamic import once and shares the promise.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const modP = import('../scripts/eval-pacing.mjs');

describe('eval-pacing metrics', () => {
  test('countSentences: plain sentences', async () => {
    const { countSentences } = await modP;
    assert.equal(countSentences('Tokens are chunks of text.'), 1);
    assert.equal(countSentences('Tokens are chunks. Models see numbers. Want to see how?'), 3);
    assert.equal(countSentences(''), 0);
  });

  test('countSentences: decimals and trailing fragments', async () => {
    const { countSentences } = await modP;
    // "3.5" must not split into two sentences.
    assert.equal(countSentences('GPT-3.5 came first. Then GPT-4 followed.'), 2);
    // A cut-off fragment still counts as one (its truncation is flagged separately).
    assert.equal(countSentences('The model predicts the next'), 1);
  });

  test('countSentences: ignores contract markers', async () => {
    const { countSentences } = await modP;
    assert.equal(
      countSentences('Nice work. [CHECK]Why does that matter?[/CHECK]'),
      2,
    );
  });

  test('endsWithQuestion: handles markers and trailing decoration', async () => {
    const { endsWithQuestion } = await modP;
    assert.equal(endsWithQuestion('Short setup. What breaks first?'), true);
    assert.equal(endsWithQuestion('Setup. [CHECK]What breaks first?[/CHECK]'), true);
    assert.equal(endsWithQuestion('Ends with a question in quotes: "Want the next layer?"'), true);
    assert.equal(endsWithQuestion('A plain statement.'), false);
    assert.equal(endsWithQuestion('A question? Then a statement.'), false);
  });

  test('countQuestionMarks: strips markers first', async () => {
    const { countQuestionMarks } = await modP;
    assert.equal(countQuestionMarks('One? Two? [CHECK]Three?[/CHECK]'), 3);
    assert.equal(countQuestionMarks('No questions here.'), 0);
  });

  test('isTruncated: flags missing terminal punctuation', async () => {
    const { isTruncated } = await modP;
    assert.equal(isTruncated('This reply was cut off mid'), true);
    assert.equal(isTruncated('This reply finished cleanly.'), false);
    assert.equal(isTruncated('Finished with a question?'), false);
    assert.equal(isTruncated('Finished with emphasis.**'), false);
    assert.equal(isTruncated(''), true);
    // [LESSON_COMPLETE] on its own final line must not read as truncation.
    assert.equal(isTruncated('You nailed it. Great work!\n[LESSON_COMPLETE]'), false);
  });

  test('previewHit: catches roadmapping language', async () => {
    const { previewHit } = await modP;
    assert.equal(previewHit("There are three factors that matter here."), true);
    assert.equal(previewHit("Next we look at training data."), true);
    assert.equal(previewHit("We'll cover bias after this."), true);
    assert.equal(previewHit('Later we’ll get to attention.'), true);
    assert.equal(previewHit('First, tokens get split. Second, they become numbers.'), true);
  });

  test('previewHit: leaves normal teaching prose alone', async () => {
    const { previewHit } = await modP;
    assert.equal(previewHit('A token is a chunk of text the model sees as one unit.'), false);
    assert.equal(previewHit('Why do you think the model chose that word?'), false);
    assert.equal(previewHit('The first token matters most here.'), false);
  });

  test('stripMarkers removes [SOURCE:...] tags', async () => {
    const { stripMarkers } = await modP;
    assert.equal(
      stripMarkers('ProPublica found bias. [SOURCE: propublica-2016] What follows?'),
      'ProPublica found bias. What follows?',
    );
  });

  test('median and percentile helpers', async () => {
    const { median, percentile } = await modP;
    assert.equal(median([1, 2, 3, 4, 5]), 3);
    assert.equal(median([1, 2, 3, 4]), 2.5);
    assert.equal(median([]), 0);
    assert.equal(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90), 9);
    assert.equal(percentile([4], 90), 4);
  });

  test('computeMetrics: a well-paced socratic reply passes across the board', async () => {
    const { computeMetrics } = await modP;
    const m = computeMetrics(
      'Close — it predicts tokens, not words. That difference matters for spelling tasks. What do you think happens with a rare name?',
    );
    assert.equal(m.sentenceCount, 3);
    assert.equal(m.questionMarks, 1);
    assert.equal(m.endsWithQuestion, true);
    assert.equal(m.truncated, false);
    assert.equal(m.previewHit, false);
  });

  test('computeMetrics: a roadmapping lecture fails the right checks', async () => {
    const { computeMetrics } = await modP;
    const m = computeMetrics(
      "Great question! There are three factors: data, compute, and algorithms. First, data shapes what the model can know. Second, compute bounds how much it can learn. Third, algorithms decide how efficiently it learns. Next we can look at each in detail. Does that make sense? Which one interests you?",
    );
    assert.ok(m.sentenceCount > 4, 'lecture should exceed the sentence budget');
    assert.equal(m.previewHit, true, 'roadmapping should be flagged');
    assert.equal(m.questionMarks, 2, 'double question should be counted');
  });

  test('countQuestionMarks: quoted and italicized rhetorical questions are not asks', async () => {
    const { countQuestionMarks } = await modP;
    assert.equal(
      countQuestionMarks('I keep asking myself: "what token comes next?" — then I repeat that. What does that tell you about my answers?'),
      1,
      'quoted inner-monologue question must not count',
    );
    assert.equal(
      countQuestionMarks('I run *given the context, what fits best?* over and over. Where could that go wrong?'),
      1,
      'italicized rhetorical question must not count',
    );
    assert.equal(countQuestionMarks('First ask? Second ask?'), 2, 'real double asks still count');
  });

  test('evaluateCriteria: discussion scoring replies leave the sentence pool and get their own contract', async () => {
    const { evaluateCriteria, computeMetrics } = await modP;
    const scoring =
      "Here's how your reasoning scored:\n\n**Claim Clarity: 4/5** — clear stance\n**Evidence: 3/5** — one real case\n**Nuance: 3/5** — saw one tradeoff\n**Logic: 4/5** — follows\n**Originality: 2/5** — standard take\n\n**Overall: 16/25** — Solid. Anchor the bias claim in a real case next time.\n\nWant to revise with that in mind, or take a new question?";
    const results = [{
      id: 'discussion-1', mode: 'discussion', sessionId: 's',
      replies: [{ user: 'my take', responseMode: 'concise', raw: scoring, metrics: computeMetrics(scoring) }],
    }];
    const criteria = evaluateCriteria(results);
    const medianC = criteria.find((c) => c.name.startsWith('median sentences'));
    assert.equal(medianC.value, 0, 'scoring reply must not enter the sentence pool');
    const contract = criteria.find((c) => c.name.startsWith('discussion scoring block'));
    assert.equal(contract.pass, true, `scoring contract should pass: ${contract.value}`);
  });

  test('aggregateCriteria: majority vote with median values', async () => {
    const { aggregateCriteria } = await modP;
    const runs = [
      [{ name: 'a', value: 4, pass: true }, { name: 'b', value: '8/8', pass: true }],
      [{ name: 'a', value: 7, pass: false }, { name: 'b', value: '8/8', pass: true }],
      [{ name: 'a', value: 3, pass: true }, { name: 'b', value: '7/8', pass: false }],
    ];
    const agg = aggregateCriteria(runs);
    assert.equal(agg[0].pass, true, 'a passes 2/3 runs');
    assert.ok(String(agg[0].value).startsWith('4'), 'numeric value is the median');
    assert.equal(agg[1].pass, true, 'b passes 2/3 runs');
    assert.ok(String(agg[1].value).includes('2/3 runs pass'));
  });
});
