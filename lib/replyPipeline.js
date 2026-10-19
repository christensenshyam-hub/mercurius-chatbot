'use strict';

/**
 * replyPipeline — the server's text transforms for a tutor reply, in one
 * place, so the SSE stream, the JSON reply and the saved message are the
 * same bytes.
 *
 * Order (each stage streams, holds back only what it can't decide yet, and
 * is chunk-boundary independent, so the chain is too):
 *   1. sourceTags (blocks_v1 clients) — "[SOURCE: label — url]" becomes
 *      "Source: label (domain)" (AUD-38). First, so the later stages see
 *      the text the student will read, and a tag is never split by a
 *      paragraph break before it is rewritten;
 *   2. quizShuffle (blocks_v1 clients) — reorders [Q] options, rewrites
 *      ANS (AUD-18);
 *   3. airyReflow — paragraph density, list and score lines (AUD-17).
 *
 * `transformReply(text, opts)` is the one-shot form: push(text) + flush()
 * on a fresh pipeline, so the JSON path can't drift from the stream.
 */

const { createReflow } = require('./airyReflow');
const { createQuizShuffler } = require('./quizShuffle');
const { createSourceRewriter } = require('./sourceTags');

/**
 * @param {object} opts
 * @param {number} opts.limit            reflow sentence limit (reflowLimit())
 * @param {boolean} [opts.rewriteSources] [SOURCE: …] → plain text (blocks_v1)
 * @param {boolean} [opts.shuffleQuiz]    reorder [Q] options (blocks_v1)
 */
function createReplyPipeline({ limit, rewriteSources = false, shuffleQuiz = false }) {
  const stages = [];
  if (rewriteSources) stages.push(createSourceRewriter());
  if (shuffleQuiz) stages.push(createQuizShuffler());
  stages.push(createReflow({ limit }));

  function push(chunk) {
    let text = String(chunk ?? '');
    for (const stage of stages) text = stage.push(text);
    return text;
  }

  function flush() {
    // Each stage's held tail goes through every stage after it.
    let carry = '';
    for (const stage of stages) carry = stage.push(carry) + stage.flush();
    return carry;
  }

  return { push, flush };
}

function transformReply(text, opts) {
  const p = createReplyPipeline(opts);
  return p.push(String(text ?? '')) + p.flush();
}

module.exports = { createReplyPipeline, transformReply };
