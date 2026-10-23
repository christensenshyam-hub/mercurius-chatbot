'use strict';

// lib/replyPipeline.js chains the server's reply transforms. The stream, the
// JSON reply and the saved message must be the same bytes, so the chain has
// to be chunk-boundary independent like each stage.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { createReplyPipeline, transformReply } = require('../lib/replyPipeline');
const { reflowText } = require('../lib/airyReflow');
const { shuffleQuizzes } = require('../lib/quizShuffle');
const { blocks: REAL_BLOCKS } = require('./fixtures/quizBlocksAudit2026-10.json');

const LESSON_REPLY = [
  'Exactly right — the model never looks anything up. It predicts. That is the whole trick. And it explains a lot.',
  '[KEY]An LLM continues text; it does not retrieve facts.[/KEY]',
  '[EX]Ask it for a court case and it writes something case-shaped. Lawyers learned this in 2023. It cost them.[/EX]',
  'Steps to check a claim:\n1. Find the source. Open it.\n2. Read the date. Check it.\n3. Compare two sources. Note gaps.',
  'Courts fined the lawyers. [SOURCE: Mata v. Avianca — courtlistener.com/docket/1/x] It was public [SOURCE: Reuters — reuters.com/a] news.',
  REAL_BLOCKS[1].block,
].join('\n\n');

function chunked(text, opts, sizes) {
  const p = createReplyPipeline(opts);
  let out = '';
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const n = sizes[k % sizes.length];
    out += p.push(text.slice(i, i + n));
    i += n;
    k += 1;
  }
  return out + p.flush();
}

describe('replyPipeline', () => {
  test('without the quiz stage it is exactly the reflow', () => {
    for (const limit of [2, 3, Infinity]) {
      assert.equal(transformReply(LESSON_REPLY, { limit }), reflowText(LESSON_REPLY, limit));
    }
  });

  test('with the quiz stage: [Q] reordered, prose reflowed, lists and spans whole', () => {
    const out = transformReply(LESSON_REPLY, { limit: 3, shuffleQuiz: true });
    assert.equal(out, reflowText(shuffleQuizzes(LESSON_REPLY), 3));
    assert.ok(out.includes(shuffleQuizzes(REAL_BLOCKS[1].block)), 'the reordered block');
    assert.ok(!out.includes(REAL_BLOCKS[1].block), 'not the model order');
    assert.ok(out.includes('Exactly right — the model never looks anything up. It predicts. That is the whole trick.\n\nAnd it explains a lot.'));
    assert.ok(out.includes('\n1. Find the source. Open it.\n2. Read the date. Check it.\n3. Compare two sources. Note gaps.'));
  });

  test('chunk fuzz: any chunking of the chain equals the one-shot transform', () => {
    let seed = 99;
    const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (const opts of [{ limit: 2 }, { limit: 3, shuffleQuiz: true }, { limit: Infinity, shuffleQuiz: true },
      { limit: 3, rewriteSources: true, shuffleQuiz: true }, { limit: 2, rewriteSources: true }]) {
      const oneShot = transformReply(LESSON_REPLY, opts);
      for (const sizes of [[1], [2], [3], [12], [LESSON_REPLY.length]]) {
        assert.equal(chunked(LESSON_REPLY, opts, sizes), oneShot, `${JSON.stringify(opts)} sizes ${sizes}`);
      }
      for (let run = 0; run < 100; run += 1) {
        const sizes = Array.from({ length: 8 }, () => 1 + Math.floor(rand() * 30));
        assert.equal(chunked(LESSON_REPLY, opts, sizes), oneShot, `${JSON.stringify(opts)} run ${run}`);
      }
    }
  });

  test('all three stages: sources rewritten first, then the quiz order, then the reflow', () => {
    const out = transformReply(LESSON_REPLY, { limit: 3, rewriteSources: true, shuffleQuiz: true });
    assert.ok(!out.includes('[SOURCE'));
    assert.ok(out.includes('Courts fined the lawyers. Source: Mata v. Avianca (courtlistener.com) It was public (Source: Reuters, reuters.com) news.'), out);
    assert.ok(out.includes(shuffleQuizzes(REAL_BLOCKS[1].block)));
    // Without the flag the tag is left for clients that render it.
    assert.ok(transformReply(LESSON_REPLY, { limit: 3 }).includes('[SOURCE: Mata v. Avianca — courtlistener.com/docket/1/x]'));
  });

  test('Basics options reach the reflow: a quoted practice line stays whole', () => {
    // Merge with #54: server.js passes keepQuotes/numberedLists for Basics
    // lessons in the same options object as the other stages.
    const practice = 'Good start. Try asking me: "Plan dinner for 6. One is vegetarian, one hates onions." Then see what it says.';
    const basics = { limit: 2, keepQuotes: true, numberedLists: true };
    const want = reflowText(practice, 2, { keepQuotes: true, numberedLists: true });
    assert.notEqual(want, reflowText(practice, 2), 'keepQuotes changes this text');
    assert.equal(transformReply(practice, basics), want);
    assert.equal(transformReply(practice, { ...basics, rewriteSources: true }), want);
    for (const sizes of [[1], [5], [practice.length]]) assert.equal(chunked(practice, basics, sizes), want, `sizes ${sizes}`);
  });

  test('a reply ending inside held text still comes out whole at flush', () => {
    for (const text of ['Almost done [Q', 'Unclosed [Q]\nPick\nA) one', 'Ends on a terminal.', 'Ends mid-tag [SOURCE: Gender', '']) {
      const opts = { limit: 2, rewriteSources: true, shuffleQuiz: true };
      assert.equal(transformReply(text, opts), text);
      assert.equal(chunked(text, opts, [1]), text);
    }
  });
});
