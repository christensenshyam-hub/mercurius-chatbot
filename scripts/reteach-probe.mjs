#!/usr/bin/env node
/**
 * reteach-probe.mjs — does a wrong pick in Unit 1 Lesson 1 cost the lesson
 * one of its ideas? Measured on a LOCAL eval server against the real API.
 *
 * CURRICULUM_PROMPT (server.js) teaches a lesson in 2–3 teach replies, one
 * idea each, then the exercise. In the round-1 transcripts a wrong pick on the
 * second check got a reteach, the reteach was counted as the third teach
 * reply, and the exercise came next: attention and embeddings, both on
 * Lesson 1.1's "Teach:" line, were never taught.
 *
 * One trial: a fresh session in the shipped iOS wire shape (blocks_v1, the
 * hidden opener + completion contract, responseMode 'balanced' as for the
 * opener and a [Q] tap), the real Lesson 1.1 opener, then a tap on every [Q]
 * exactly as CheckQuizCard sends it: the right option, except the
 * `--wrong-at`-th check (2 by default, as in eval-pacing's
 * curriculum-blocks-1; 0 = never wrong). The trial stops at the first reply
 * with no [Q] (the exercise, or a teach reply whose check is an open [CHECK])
 * or after `--max-replies`.
 *
 * Usage:
 *   BASE_URL=http://localhost:3720 node scripts/reteach-probe.mjs \
 *     --label before [--trials 4] [--wrong-at 2] [--max-replies 6] [--concurrency 2] [--out file.json]
 *   node scripts/reteach-probe.mjs --rescore file.json [--out file.json]   (score a saved run again; no model calls)
 *
 * BASE_URL must be localhost: this script never talks to production. Start
 * the server with EVAL_EXPOSE_USAGE=1 so each turn's cost can be reported.
 */
import { readFileSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';
import { iosChatBody, pickFromQuiz } from './eval-pacing.mjs';
import { quizzesIn, streamChat } from './quiz-length-probe.mjs';

const require = createRequire(import.meta.url);
const { costUsd } = require('../lib/pricing.js');

/** Curriculum.swift's Unit 1 Lesson 1 starter, verbatim. */
export const U1L1_STARTER = '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise.';

/**
 * Lesson 1.1's ideas, matched against what a teach reply is ABOUT (see
 * replyFocus). A mention anywhere else in a teach reply ("That's called
 * attention.") is reported as `named` and doesn't count as taught.
 */
export const IDEAS = Object.freeze({
  tokens: /\btokens?\b|tokeni[sz]/i,
  embeddings: /embedding|meaning space|map of meaning/i,
  attention: /\battention\b|\battends?\b/i,
  prediction: /predict|next token|next-token|likel(?:y|iest) (?:next|to come)|probabilit/i,
});

/** Saying how much of the lesson is left, or that it ran out (the prompt's
 *  STUDENT-FACING WORDS rule bans both). Checked with [Q] blocks removed:
 *  a distractor like "It ran out of training data" is not the tutor talking. */
export const BUDGET_TALK_RE = /\b(?:run|ran|running) out\b|\bout of (?:time|steps|ideas|room)\b|\bno (?:more|time) (?:left|for)\b|\bone more (?:idea|thing|concept|step|piece)\b|\b(?:last|final) (?:idea|concept|step|piece)\b|\bwe(?:['’]ve| have) (?:covered|used up|got through) (?:all|every|everything)|\b(?:that['’]s|that is) all (?:we|i) (?:have|had) (?:time )?for\b/i;

/** Words that settle which "bank" is meant, money or river. */
const BANK_SENSE_RE = /\b(?:rivers?|riverside|streams?|creek|lake|water|shore|fish(?:ing|ed)?|boats?|cash|money|deposit(?:ed|ing)?|checks?|cheques?|loans?|account|paycheck|teller|savings)\b/i;

/**
 * Quoted "bank" examples whose deciding word comes AFTER "bank" ("I sat on
 * the bank of the river"). In a GPT-style model a word can only look back at
 * the words before it, so "river" there can't shift "bank" itself. [Q]
 * blocks count: the student reads them too. Hand-check what this returns: a
 * reply may quote such a sentence to say exactly that.
 */
export function laterContextExamples(raw) {
  const quotes = [...String(raw ?? '').matchAll(/["“]([^"“”\n]+)["”]/g)].map((m) => m[1]);
  return quotes.filter((quote) => {
    const at = quote.search(/\bbank\b/i);
    return at > -1 && BANK_SENSE_RE.test(quote.slice(at + 4));
  });
}

const Q_BLOCK_RE = /\[Q\][\s\S]*?(?:\[\/Q\]|$)/g;

const EXERCISE_RE = /\bexercise\b|put (?:this|it|that|them|these) to work/i;

/** What one reply teaches: its [KEY] takeaway and its check ([Q] stem or
 *  [CHECK] text). A bold term alone can sit in the reaction to the last
 *  answer ("That's called **attention**.") and only names the idea. */
export function replyFocus(raw) {
  const text = String(raw ?? '');
  const keys = [...text.matchAll(/\[KEY\]([\s\S]*?)\[\/KEY\]/g)].map((m) => m[1].trim());
  const checks = [...text.matchAll(/\[CHECK\]([\s\S]*?)\[\/CHECK\]/g)].map((m) => m[1].trim());
  const stems = quizzesIn(text).map((q) => q.stem);
  return [...keys, ...stems, ...checks].join(' | ');
}

/**
 * Score one trial (pure; unit-tested). `replies` are the tutor's replies in
 * order, each { raw, wrong? } where `wrong` marks the reply that answered a
 * deliberately wrong pick. The exercise is the first later reply with no [Q]
 * that gives it ("exercise", "put this/it/them to work"); every reply before it is a
 * teach reply. A later reply with no [Q] that is not the exercise (a teach
 * reply whose check is an open [CHECK]) ends the trial: the probe can't
 * answer it, so it counts as the last teach reply and `exerciseAt` is null.
 */
export function scoreTrial(replies) {
  const raws = replies.map((r) => String(r.raw ?? ''));
  const endIdx = raws.findIndex((raw, i) => i > 0 && quizzesIn(raw).length === 0);
  const isExercise = endIdx > 0 && EXERCISE_RE.test(raws[endIdx]);
  const teach = endIdx < 0 ? raws : raws.slice(0, isExercise ? endIdx : endIdx + 1);
  const focus = teach.map(replyFocus);
  const prose = teach.map((raw) => raw.replace(Q_BLOCK_RE, ' ')).join('\n');
  const taught = {};
  const named = {};
  for (const [name, re] of Object.entries(IDEAS)) {
    taught[name] = focus.some((f) => re.test(f));
    named[name] = re.test(prose);
  }
  const wrongIdx = replies.findIndex((r) => r.wrong);
  const budgetTalk = raws
    .map((raw) => raw.replace(Q_BLOCK_RE, ' ').match(BUDGET_TALK_RE)?.[0] ?? null)
    .map((hit, i) => (hit ? { reply: i + 1, text: hit } : null))
    .filter(Boolean);
  const laterContext = raws.flatMap((raw, i) => laterContextExamples(raw).map((text) => ({ reply: i + 1, text })));
  return {
    replies: raws.length,
    exerciseAt: isExercise ? endIdx + 1 : null,
    stoppedOnCheck: endIdx > 0 && !isExercise,
    teachReplies: teach.length,
    // Teach replies after the one that answered the wrong pick: the ideas the
    // lesson still had room for once the reteach was done.
    teachAfterReteach: wrongIdx < 0 ? null : Math.max(0, teach.length - wrongIdx - 1),
    taught,
    named,
    bothTaught: taught.attention && taught.embeddings,
    eitherTaught: taught.attention || taught.embeddings,
    focus,
    budgetTalk,
    laterContext,
    completed: raws.some((raw) => raw.includes('[LESSON_COMPLETE]')),
  };
}

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name);
  return i > -1 ? process.argv[i + 1] : dflt;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function runTrial(base, model, label, trial, { wrongAt, maxReplies }) {
  const sessionId = `probe-reteach-${label}-${trial}-${randomBytes(4).toString('hex')}`;
  const visible = [];
  const replies = [];
  let checks = 0;
  let wrongNext = false;
  for (let t = 0; t < maxReplies; t++) {
    if (t > 0) {
      const last = replies.at(-1).raw;
      if (!quizzesIn(last).length) break; // the exercise (or no check): stop
      checks += 1;
      wrongNext = checks === wrongAt;
      visible.push({ role: 'user', content: pickFromQuiz(last, { wrong: wrongNext }) });
    }
    const body = iosChatBody({ sessionId, visible, lessonStarter: U1L1_STARTER, responseMode: 'balanced' });
    const r = await streamChat(base, body);
    if (r.error) {
      const msg = JSON.stringify(r.error);
      if (/credit balance/i.test(msg)) throw new Error(`credit balance too low: ${msg}`);
      replies.push({ user: visible.at(-1)?.content ?? '(opener)', raw: '', error: r.error });
      break;
    }
    replies.push({
      user: visible.at(-1)?.content ?? '(opener)',
      raw: r.text,
      wrong: t > 0 && wrongNext,
      usage: r.usage,
      cost: r.usage ? costUsd(model, r.usage) : 0,
    });
    visible.push({ role: 'assistant', content: r.text });
    await sleep(500);
  }
  return { trial, sessionId, replies, score: scoreTrial(replies.filter((x) => !x.error)) };
}

/** The summary line set for a finished (or re-scored) run. */
function report(results, meta) {
  const scores = results.map((r) => r.score);
  const count = (f) => scores.filter(f).length;
  const spend = results.flatMap((r) => r.replies).reduce((s, x) => s + (x.cost || 0), 0);
  const errors = results.flatMap((r) => r.replies).filter((x) => x.error).length;
  const n = results.length;
  const summary = {
    ...meta,
    trials: n,
    reachedExercise: count((s) => s.exerciseAt !== null),
    stoppedOnCheck: count((s) => s.stoppedOnCheck),
    attentionTaught: count((s) => s.taught.attention),
    embeddingsTaught: count((s) => s.taught.embeddings),
    bothTaught: count((s) => s.bothTaught),
    eitherTaught: count((s) => s.eitherTaught),
    teachReplies: scores.map((s) => s.teachReplies),
    teachAfterReteach: scores.map((s) => s.teachAfterReteach),
    budgetTalk: scores.flatMap((s, i) => s.budgetTalk.map((b) => ({ trial: i + 1, ...b }))),
    laterContext: scores.flatMap((s, i) => (s.laterContext ?? []).map((b) => ({ trial: i + 1, ...b }))),
    completedEarly: count((s) => s.completed),
    errors,
    spendUsd: Number(spend.toFixed(4)),
  };
  const idea = (s, k) => (s.taught[k] ? 'taught' : s.named[k] ? 'named only' : 'no');
  const lines = [`Unit 1 Lesson 1, ${n} trial(s), wrong pick at check ${meta.wrongAt || 'never'}, model ${meta.model}, ${errors} error(s)`];
  for (const r of results) {
    const s = r.score;
    const end = s.exerciseAt ? `exercise at reply ${s.exerciseAt}` : s.stoppedOnCheck ? `stopped on an open [CHECK] at reply ${s.teachReplies}` : 'no exercise';
    lines.push(`  trial ${r.trial}: ${end}, ${s.teachReplies} teach replies (${s.teachAfterReteach ?? '-'} after the reteach); attention ${idea(s, 'attention')}, embeddings ${idea(s, 'embeddings')}${s.budgetTalk.length ? `; budget talk: ${s.budgetTalk.map((b) => `"${b.text}" (reply ${b.reply})`).join(', ')}` : ''}${s.laterContext.length ? `; "bank" before its deciding word: ${s.laterContext.map((b) => `"${b.text}" (reply ${b.reply})`).join(', ')}` : ''}`);
  }
  lines.push(`attention taught ${summary.attentionTaught}/${n}, embeddings taught ${summary.embeddingsTaught}/${n}, both ${summary.bothTaught}/${n}; a teach reply after the reteach in ${count((s) => s.teachAfterReteach > 0)}/${n}; budget talk in ${summary.budgetTalk.length} reply(ies) (${count((s) => s.budgetTalk.length > 0)}/${n} trials); "bank" before its deciding word in ${count((s) => s.laterContext.length > 0)}/${n} trials`);
  lines.push(`spend ≈ $${spend.toFixed(4)}`);
  return { summary, lines };
}

async function main() {
  // --rescore <file>: score a saved run again (no model calls).
  const rescore = arg('--rescore', '');
  if (rescore) {
    const saved = JSON.parse(readFileSync(rescore, 'utf8'));
    const results = saved.results.map((r) => ({ ...r, score: scoreTrial(r.replies.filter((x) => !x.error)) }));
    const { label, model, baseUrl, generatedAt, wrongAt, maxReplies } = saved.summary;
    const { summary, lines } = report(results, { label, model, baseUrl, generatedAt, wrongAt, maxReplies });
    const out = arg('--out', '');
    if (out) await writeFile(out, JSON.stringify({ summary, results }, null, 2));
    console.log(lines.join('\n'));
    return;
  }
  const base = process.env.BASE_URL || '';
  if (!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(base)) {
    console.error('BASE_URL must be http://localhost:<port> (a local eval server).');
    process.exit(2);
  }
  const label = arg('--label', 'probe');
  const trials = Math.max(1, Number(arg('--trials', 4)) || 4);
  const concurrency = Math.max(1, Number(arg('--concurrency', 2)) || 2);
  const wrongAt = Math.max(0, Number(arg('--wrong-at', 2)) || 0);
  const maxReplies = Math.max(2, Number(arg('--max-replies', 6)) || 6);
  const out = arg('--out', '');
  const model = (await fetch(`${base}/api/health`).then((r) => r.json()).catch(() => ({}))).model || 'claude-sonnet-4-6';

  // Trial 1 runs alone first, so the cached prompt prefix is written once,
  // not once per worker.
  const results = [];
  let next = 1;
  async function worker() {
    while (next <= trials) {
      const t = next++;
      results.push(await runTrial(base, model, label, t, { wrongAt, maxReplies }));
      process.stderr.write(`  trial ${t} done\n`);
    }
  }
  results.push(await runTrial(base, model, label, next++, { wrongAt, maxReplies }));
  process.stderr.write('  trial 1 done\n');
  await Promise.all(Array.from({ length: concurrency }, worker));
  results.sort((a, b) => a.trial - b.trial);

  const { summary, lines } = report(results, { label, model, baseUrl: base, generatedAt: new Date().toISOString(), wrongAt, maxReplies });
  if (out) await writeFile(out, JSON.stringify({ summary, results }, null, 2));
  console.log(lines.join('\n'));
}

const isDirectRun = (() => {
  try {
    return process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
})();

if (isDirectRun) {
  main().catch((err) => {
    console.error(`probe failed: ${err.message}`);
    process.exit(1);
  });
}
