'use strict';

// scripts/reteach-probe.mjs — the pure scoring of the Unit 1 Lesson 1 reteach
// probe. The probe itself only
// runs against a local eval server; nothing here calls a model.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const modP = import('../scripts/reteach-probe.mjs');
const CURRICULUM_SWIFT = path.join(__dirname, '..', 'ios/Packages/CurriculumFeature/Sources/Curriculum.swift');

// The round-1 transcripts (2026-10-29, claude-sonnet-5-5, both flag states):
// the wrong pick on the second check got a reteach, then the exercise.
const ROUND1 = ['on', 'off'].map((flag) => {
  const file = path.join(__dirname, '..', 'docs/evals', `pacing-quiz-length-v1-lessons-flag-${flag}.json`);
  const run = JSON.parse(fs.readFileSync(file, 'utf8')).results.find((r) => r.id === 'curriculum-blocks-1');
  // Reply 3 answered the deliberately wrong pick.
  return run.replies.map((r, i) => ({ raw: r.raw, wrong: i === 2 }));
});

const q = (stem, answer = 'A') => `[Q]\n${stem}\nA) one\nB) two\nC) three\nANS: ${answer}\n[/Q]`;

describe('reteach-probe', () => {
  test('the starter is Curriculum.swift\'s Unit 1 Lesson 1 opener, verbatim', async () => {
    const { U1L1_STARTER } = await modP;
    assert.ok(fs.readFileSync(CURRICULUM_SWIFT, 'utf8').includes(`starter: "${U1L1_STARTER}"`));
  });

  test('round-1 transcripts: the reteach took the last teach reply; attention and embeddings never taught', async () => {
    const { scoreTrial } = await modP;
    for (const replies of ROUND1) {
      const s = scoreTrial(replies);
      assert.equal(s.exerciseAt, 4);
      assert.equal(s.teachReplies, 3);
      assert.equal(s.teachAfterReteach, 0);
      assert.equal(s.taught.attention, false);
      assert.equal(s.taught.embeddings, false);
      assert.equal(s.taught.tokens, true);
      assert.equal(s.taught.prediction, true);
      assert.equal(s.bothTaught, false);
      assert.equal(s.completed, false);
    }
  });

  test('a reteach followed by the missing ideas scores them as taught', async () => {
    const { scoreTrial } = await modP;
    const s = scoreTrial([
      { raw: `Hook.\n\n[KEY]Text becomes **tokens**, then numbers.[/KEY]\n\n${q('What does a tokenizer output?')}` },
      { raw: `Right.\n\n**Next-token prediction**: the model scores every token.\n\n${q('What does it predict?')}` },
      { raw: `Not quite.\n\nIt never searches.\n\n${q('Try a fresh case: what fits here?')}`, wrong: true },
      { raw: `Yes.\n\nEach token becomes a point in a space of meanings, and the words around it move it.\n\n[KEY]Embeddings place tokens by meaning, and attention lets "river" steer "bank".[/KEY]\n\n${q('What sorts out "bank"?')}` },
      { raw: 'Now let\'s put this to work. Here\'s your exercise...' },
    ]);
    assert.equal(s.exerciseAt, 5);
    assert.equal(s.stoppedOnCheck, false);
    assert.equal(s.teachAfterReteach, 1);
    assert.equal(s.bothTaught, true);
  });

  test('a later teach reply with an open [CHECK] ends the trial as a teach reply, not the exercise', async () => {
    const { scoreTrial } = await modP;
    const s = scoreTrial([
      { raw: `[KEY]Text becomes tokens.[/KEY]\n\n${q('What does a tokenizer output?')}` },
      { raw: `Not quite.\n\n${q('Fresh case: what fits here?')}`, wrong: true },
      { raw: 'Right.\n\nThe model uses **attention**.\n\n[CHECK]In "I went to the bank", would attention settle which bank is meant?[/CHECK]' },
    ]);
    assert.equal(s.exerciseAt, null);
    assert.equal(s.stoppedOnCheck, true);
    assert.equal(s.teachReplies, 3);
    assert.equal(s.teachAfterReteach, 1);
    assert.equal(s.taught.attention, true);
  });

  test('"Now let\'s put it to work." with no word "exercise" is the exercise too', async () => {
    const { scoreTrial } = await modP;
    const s = scoreTrial([
      { raw: q('What does a tokenizer output?') },
      { raw: 'Yes, score, pick one, repeat.\n\nNow let\'s put it to work.\n\n1. "The capital of France is ___."' },
    ]);
    assert.equal(s.exerciseAt, 2);
    assert.equal(s.stoppedOnCheck, false);
  });

  test('a passing mention in the prose is not teaching; a [Q] distractor is not budget talk', async () => {
    const { scoreTrial } = await modP;
    const s = scoreTrial([
      { raw: `**Tokens** first. Attention to "river" sorts out "bank" later.\n\n[Q]\nWhy?\nA) It splits text\nB) It ran out of training data\nANS: A\n[/Q]` },
      { raw: 'Exercise time.' },
    ]);
    assert.equal(s.taught.attention, false);
    assert.equal(s.named.attention, true);
    assert.deepEqual(s.budgetTalk, []);
  });

  test('budget talk: saying the lesson ran out, or how much is left', async () => {
    const { BUDGET_TALK_RE } = await modP;
    for (const s of ['We have run out of steps for today.', "That's one more idea to go.", "We've covered everything, so here's the exercise.", 'Here is the last idea.']) {
      assert.ok(BUDGET_TALK_RE.test(s), s);
    }
    for (const s of ['Let\'s keep going.', 'Now let\'s put this to work.', 'The model ran a prediction.']) {
      assert.ok(!BUDGET_TALK_RE.test(s), s);
    }
  });
});
