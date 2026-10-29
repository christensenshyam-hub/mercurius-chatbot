#!/usr/bin/env node
/**
 * quiz-length-probe.mjs — is the right answer of a Deep-dive [Q] check the
 * longest option? Measured on a LOCAL eval server against the real API.
 *
 * lib/quizShuffle.js fixed where the right answer sits (AUD-18), but it moves
 * options, never their text, so it can't touch the other tell: the right
 * option is the longest, most carefully explained one. A student who always
 * taps the longest option should be right about 1 time in 3 on a 3-option
 * check; this probe measures how often they actually are.
 *
 * Usage:
 *   BASE_URL=http://localhost:3710 node scripts/quiz-length-probe.mjs \
 *     --label before [--trials 1] [--turns 2] [--lessons u1_l1,u6_l3] [--concurrency 2] [--out file.json]
 *
 * BASE_URL must be localhost: this script never talks to production. Start
 * the server with EVAL_EXPOSE_USAGE=1 so each turn's cost can be reported.
 *
 * For each non-Review Deep-dive lesson (the starters in the iOS app's
 * Curriculum.swift, verbatim) and each trial: one fresh session in the
 * shipped iOS wire shape (blocks_v1, the hidden opener + completion contract,
 * responseMode 'balanced' as for the opener and a [Q] tap), the opener, then
 * (unless --turns 1) a tap of the right option exactly as CheckQuizCard
 * sends it. Every well-formed [Q] in the replies is scored by
 * quizLengthStats().
 */
import { readFileSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';
import { iosChatBody, pickFromQuiz } from './eval-pacing.mjs';

const require = createRequire(import.meta.url);
const { parseQuizInterior } = require('../lib/blockMarkup.js');
const { costUsd } = require('../lib/pricing.js');

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const CURRICULUM_SWIFT = path.join(ROOT, 'ios/Packages/CurriculumFeature/Sources/Curriculum.swift');

/** The Deep-dive starters the app sends, keyed u<unit>_l<lesson>; Review
 *  lessons are left out (their first reply is the exercise, never a [Q]). */
export function deepDiveStarters(swiftSource) {
  const out = {};
  for (const m of swiftSource.matchAll(/starter:\s*"(\[CURRICULUM: Unit (\d+), Lesson (\d+)([^\]]*)\][^"]*)"/g)) {
    if (/review/i.test(m[4])) continue;
    out[`u${m[2]}_l${m[3]}`] = m[1];
  }
  return out;
}

/** Every well-formed [Q] in a reply, parsed. */
export function quizzesIn(raw) {
  return [...String(raw ?? '').matchAll(/\[Q\]\n?([\s\S]*?)\[\/Q\]/g)]
    .map((m) => parseQuizInterior(m[1]))
    .filter((q) => q.wellFormed);
}

/**
 * The length tell over a set of parsed checks (pure; unit-tested):
 *   strictLongest   the right option is longer than every other one;
 *   longestPickHits how many checks a student who always taps the longest
 *                   option gets right (a tie split evenly between the tied);
 *   shortestPickHits the same for always tapping the shortest option (a fix
 *                   that overshoots turns the tell around);
 *   chance          what blind guessing gets (1/options, summed);
 *   lengthRatio     mean of right length / mean wrong length.
 * Lengths are characters: what a student sees on the card.
 */
export function quizLengthStats(quizzes) {
  let strictLongest = 0;
  let longestPickHits = 0;
  let shortestPickHits = 0;
  let chance = 0;
  let ratioSum = 0;
  for (const q of quizzes) {
    const lens = q.options.map((o) => o.length);
    const max = Math.max(...lens);
    const min = Math.min(...lens);
    const tied = lens.filter((l) => l === max).length;
    const right = lens[q.answerIndex];
    if (right === max && tied === 1) strictLongest += 1;
    if (right === max) longestPickHits += 1 / tied;
    if (right === min) shortestPickHits += 1 / lens.filter((l) => l === min).length;
    chance += 1 / lens.length;
    const wrong = lens.filter((_, i) => i !== q.answerIndex);
    ratioSum += right / (wrong.reduce((a, b) => a + b, 0) / wrong.length);
  }
  const n = quizzes.length;
  return {
    n,
    strictLongest,
    longestPickHits: Number(longestPickHits.toFixed(2)),
    shortestPickHits: Number(shortestPickHits.toFixed(2)),
    chance: Number(chance.toFixed(2)),
    lengthRatio: n ? Number((ratioSum / n).toFixed(2)) : null,
  };
}

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name);
  return i > -1 ? process.argv[i + 1] : dflt;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function streamChat(base, body) {
  const res = await fetch(`${base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  if (!res.ok) return { error: `HTTP ${res.status}: ${await res.text()}` };
  const dec = new TextDecoder();
  let buf = '';
  let text = '';
  let complete = null;
  let error = null;
  for await (const chunk of res.body) {
    buf += dec.decode(chunk, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) !== -1) {
      const frame = buf.slice(0, i);
      buf = buf.slice(i + 2);
      for (const line of frame.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        const p = line.slice(6);
        if (p === '[DONE]') continue;
        let j;
        try { j = JSON.parse(p); } catch { continue; }
        if (j.type === 'delta') text += j.text;
        if (j.type === 'complete') complete = j;
        if (j.type === 'error' || j.type === 'refusal') error = j;
      }
    }
  }
  return { text: complete?.reply ?? text, usage: complete?.usage ?? null, error };
}

async function runLesson(base, model, label, id, starter, trial, maxTurns) {
  const sessionId = `probe-qlen-${label}-${id}-${trial}-${randomBytes(4).toString('hex')}`;
  const visible = [];
  const turns = [];
  // The opener is the hidden first wire message alone; then one tap.
  for (let t = 0; t < maxTurns; t++) {
    if (t === 1) {
      const last = turns[0]?.reply ?? '';
      if (!quizzesIn(last).length) break;
      visible.push({ role: 'user', content: pickFromQuiz(last) });
    }
    const body = iosChatBody({ sessionId, visible, lessonStarter: starter, responseMode: 'balanced' });
    const r = await streamChat(base, body);
    if (r.error) {
      const msg = JSON.stringify(r.error);
      if (/credit balance/i.test(msg)) throw new Error(`credit balance too low: ${msg}`);
      turns.push({ error: r.error });
      break;
    }
    turns.push({ user: visible.at(-1)?.content ?? '(opener)', reply: r.text, usage: r.usage, cost: r.usage ? costUsd(model, r.usage) : 0 });
    visible.push({ role: 'assistant', content: r.text });
    await sleep(500);
  }
  return { id, trial, sessionId, turns };
}

async function main() {
  const base = process.env.BASE_URL || '';
  if (!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(base)) {
    console.error('BASE_URL must be http://localhost:<port> (a local eval server).');
    process.exit(2);
  }
  const label = arg('--label', 'probe');
  const trials = Math.max(1, Number(arg('--trials', 1)) || 1);
  const concurrency = Math.max(1, Number(arg('--concurrency', 2)) || 2);
  const maxTurns = Number(arg('--turns', 2)) === 1 ? 1 : 2;
  const out = arg('--out', '');
  const starters = deepDiveStarters(readFileSync(CURRICULUM_SWIFT, 'utf8'));
  const only = arg('--lessons', '');
  const ids = only ? only.split(',').filter((id) => starters[id]) : Object.keys(starters);
  const model = (await fetch(`${base}/api/health`).then((r) => r.json()).catch(() => ({}))).model || 'claude-sonnet-4-6';

  const jobs = [];
  for (let t = 1; t <= trials; t++) for (const id of ids) jobs.push([id, t]);
  const results = [];
  let next = 0;
  async function worker() {
    while (next < jobs.length) {
      const [id, t] = jobs[next++];
      results.push(await runLesson(base, model, label, id, starters[id], t, maxTurns));
      process.stderr.write(`  ${id} trial ${t} done\n`);
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  results.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }) || a.trial - b.trial);

  const quizzes = results.flatMap((r) => r.turns.flatMap((t) => quizzesIn(t.reply)));
  const stats = quizLengthStats(quizzes);
  const spend = results.flatMap((r) => r.turns).reduce((s, t) => s + (t.cost || 0), 0);
  const errors = results.flatMap((r) => r.turns).filter((t) => t.error).length;
  const summary = { label, model, baseUrl: base, generatedAt: new Date().toISOString(), lessons: ids.length, trials, turns: maxTurns, ...stats, errors, spendUsd: Number(spend.toFixed(4)) };
  if (out) await writeFile(out, JSON.stringify({ summary, results }, null, 2));
  const pct = (x) => (stats.n ? `${Math.round((100 * x) / stats.n)}%` : 'n/a');
  console.log(`[Q] checks: ${stats.n} from ${ids.length} lessons x ${trials} trial(s), ${errors} error(s), model ${model}`);
  console.log(`right answer strictly the longest option: ${stats.strictLongest}/${stats.n} (${pct(stats.strictLongest)})`);
  console.log(`always tap the longest option: right ${stats.longestPickHits}/${stats.n} (${pct(stats.longestPickHits)}); the shortest: ${stats.shortestPickHits} (${pct(stats.shortestPickHits)}); blind guessing: ${stats.chance} (${pct(stats.chance)})`);
  console.log(`right option length / mean wrong option length: ${stats.lengthRatio}`);
  console.log(`spend ≈ $${spend.toFixed(4)}`);
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
