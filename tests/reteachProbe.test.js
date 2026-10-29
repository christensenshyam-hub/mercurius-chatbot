'use strict';

// scripts/reteach-probe.mjs — the pure scoring of the Unit 1 Lesson 1 reteach
// probe, plus the CURRICULUM_PROMPT rule it measures. The probe itself only
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

  test('"Now let\'s put them to work." (a reviewer\'s real trial) is the exercise, not a teach reply', async () => {
    const { scoreTrial } = await modP;
    const s = scoreTrial([
      { raw: q('What does a tokenizer output?') },
      { raw: `Not quite.\n\n${q('Fresh case: what fits here?')}`, wrong: true },
      { raw: q('Which blank is the model most confident about?') },
      { raw: 'Right, "star" overwhelmingly dominates that blank.\n\nYou now know the three pieces: tokens, embeddings with attention, and next-token prediction. Now let\'s put them to work.\n\n1. "The capital of France is ___"' },
    ]);
    assert.equal(s.exerciseAt, 4);
    assert.equal(s.stoppedOnCheck, false);
    assert.equal(s.teachReplies, 3);
    assert.equal(s.teachAfterReteach, 1);
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

  test('"bank" before the word that decides it: flagged; the deciding word first: not', async () => {
    const { laterContextExamples } = await modP;
    assert.deepEqual(
      laterContextExamples('In "I sat on the bank of the river," attention connects "bank" to "river".'),
      ['I sat on the bank of the river,'],
    );
    assert.deepEqual(laterContextExamples('A student types: “I went to the bank to fish.”'), ['I went to the bank to fish.']);
    for (const ok of [
      'In "We walked along the river and sat down on the bank" vs. "I put cash in the bank", attention sorts it out.',
      '"bank" (money) and "bank" (river) start as the same token.',
      'With "I got my paycheck, so" before it, "bank" is near loan and deposit.',
      'Each token gets a list of numbers. Rivers and cash come later.',
    ]) {
      assert.deepEqual(laterContextExamples(ok), [], ok);
    }
  });

  test('round 2\'s runs: every trial put "bank" before its deciding word ("I sat on the bank of the river")', async () => {
    const { scoreTrial } = await modP;
    for (const name of ['reteach-probe-branch', 'reteach-probe-review', 'reteach-probe-branch-no-wrong-pick']) {
      const { results } = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'docs/evals', `${name}.json`), 'utf8'));
      for (const r of results) {
        const s = scoreTrial(r.replies.filter((x) => !x.error));
        assert.ok(s.laterContext.some((b) => /bank of the river/.test(b.text)), `${name} trial ${r.trial}`);
      }
    }
  });
});

describe('CURRICULUM_PROMPT: a reteach is not one of the 2–3 teach replies; Lesson 1.1 names its three ideas', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
  const start = src.indexOf('const CURRICULUM_PROMPT = `');
  const guide = src.slice(start, src.indexOf('`;', start));
  const step1 = guide.slice(guide.indexOf('**STEP 1'), guide.indexOf('**STEP 2'));
  const u1l1 = guide.slice(guide.indexOf('**Lesson 1 — What happens when you type a prompt**'), guide.indexOf('**Lesson 2 — Training data'));

  test('STEP 1: a reteach doesn\'t count toward the 2–3, the untaught ideas still come before the exercise, and nothing announces what is left', () => {
    assert.match(step1, /2–3 responses, ONE micro-concept each/);
    assert.match(step1, /reteach[^\n]*doesn't count toward the 2–3/);
    assert.match(step1, /next micro-concept you haven't taught yet \(just "Let's keep going", never "one more idea"\)/);
    assert.match(step1, /exercise still waits until every micro-concept has been taught/);
  });

  test('Unit 1 Lesson 1: tokens, then embeddings + attention, then next-token prediction', () => {
    assert.match(u1l1, /^Teach: Tokenization \(words → tokens → numbers\), embedding space, attention mechanism \(simplified\), next-token prediction$/m);
    const line = u1l1.split('\n').find((l) => l.startsWith('Micro-concepts'));
    assert.ok(line, 'the entry names its micro-concepts');
    assert.match(line, /three, in this order/);
    const at = (re) => line.search(re);
    assert.ok(at(/\(1\) tokens/) < at(/\(2\) embeddings and attention/), line);
    assert.ok(at(/\(2\) embeddings and attention/) < at(/\(3\) next-token prediction/), line);
  });

  test('Unit 1 Lesson 1: attention adjusts a word from the words BEFORE it, and every "bank" example puts the deciding word first', async () => {
    const { laterContextExamples } = await modP;
    const line = u1l1.split('\n').find((l) => l.startsWith('Micro-concepts'));
    assert.match(line, /attention lets the words before it in the sentence adjust it/);
    assert.doesNotMatch(u1l1, /the other words in the sentence/);
    assert.deepEqual(laterContextExamples(u1l1), [], 'a quoted example whose deciding word comes after "bank"');
    assert.match(u1l1, /"We walked along the river and sat down on the bank" vs\. "I put cash in the bank"/);
    assert.match(u1l1, /each word can only look back at the words before it/);
  });

  test('the change touched no other lesson entry (only Lesson 1.1 names its micro-concepts)', () => {
    assert.equal(guide.split('\n').filter((l) => l.startsWith('Micro-concepts')).length, 1);
  });
});

describe('eval-pacing curriculum-blocks-1 (the merge gate\'s blocks lesson) follows the new flow', () => {
  test('four taps (three ideas + the reteach, the 2nd one wrong) before the scripted exercise answers', async () => {
    const { SCENARIOS } = await import('../scripts/eval-pacing.mjs');
    const { turns } = SCENARIOS.find((s) => s.id === 'curriculum-blocks-1');
    const taps = turns.slice(1).findIndex((t) => typeof t === 'string');
    assert.equal(taps, 4, 'dynamic [Q] taps between the opener and the first scripted exercise answer');
    assert.match(turns[1 + taps], /^For the exercise/);
    const ask = '[Q]\nWhich?\nA) right one\nB) wrong one\nANS: A\n[/Q]';
    assert.deepEqual(turns.slice(1, 1 + taps).map((t) => t.dynamic(ask)), ['I picked A) right one', 'I picked B) wrong one', 'I picked A) right one', 'I picked A) right one']);
  });
});
