#!/usr/bin/env node
/**
 * quiz-order-stats — where the right answer sits in real [Q] checks, as the
 * model wrote them and after lib/quizShuffle.js reorders them (AUD-18).
 *
 *   node scripts/quiz-order-stats.mjs <dir|file.json> [...more]
 *
 * Reads every string in every .json file under the given paths (eval
 * results, audit transcripts), pulls out each [Q]…[/Q] block, counts each
 * distinct block once, and prints:
 *   - the answer-letter spread before and after the reorder, overall and
 *     for 3-option checks (what lessons use);
 *   - how many blocks the reorder left as written, and why;
 *   - how often the right answer is the longest option (a tell the reorder
 *     can't touch: it moves options, never their text).
 * Read-only; no network.
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { parseQuizInterior } = require('../lib/blockMarkup.js');
const { shuffleQuizSpan, analyzeInterior, optionOrder } = require('../lib/quizShuffle.js');

const Q_SPAN_RE = /\[Q\][\s\S]*?\[\/Q\]/g;
const LETTERS = ['A', 'B', 'C', 'D'];

function* jsonFiles(p) {
  const st = statSync(p);
  if (st.isDirectory()) {
    for (const name of readdirSync(p).sort()) yield* jsonFiles(path.join(p, name));
  } else if (p.endsWith('.json')) {
    yield p;
  }
}

function* strings(v) {
  if (typeof v === 'string') yield v;
  else if (Array.isArray(v)) for (const x of v) yield* strings(x);
  else if (v && typeof v === 'object') for (const x of Object.values(v)) yield* strings(x);
}

function parseSpan(span) {
  return parseQuizInterior(span.slice(3, -4).replace(/^\n/, ''));
}

function spread(blocks, pick) {
  const counts = {};
  for (const b of blocks) {
    const q = pick(b);
    const letter = LETTERS[q.answerIndex];
    counts[letter] = (counts[letter] || 0) + 1;
  }
  return counts;
}

function fmt(counts, total) {
  return LETTERS.filter((l) => counts[l]).map((l) => `${l} ${counts[l]} (${Math.round((100 * counts[l]) / total)}%)`).join(', ') || 'none';
}

function longest(q) {
  const lens = q.options.map((o) => o.length);
  const max = Math.max(...lens);
  return { longest: lens[q.answerIndex] === max, strictly: lens[q.answerIndex] === max && lens.filter((l) => l === max).length === 1 };
}

/** True when the server's order for this block is the model's own. */
function sameOrder(b) {
  const q = analyzeInterior(b.span.slice(3, -4));
  if (!q) return false;
  const order = optionOrder(q.stem, q.options.map((o) => o.text));
  return order.every((v, i) => v === i);
}

function main(argv) {
  if (!argv.length) {
    console.error('usage: node scripts/quiz-order-stats.mjs <dir|file.json> [...]');
    process.exit(2);
  }
  const seen = new Set();
  const spans = [];
  for (const root of argv) {
    for (const file of jsonFiles(root)) {
      let json;
      try { json = JSON.parse(readFileSync(file, 'utf8')); } catch { continue; }
      for (const s of strings(json)) {
        for (const m of s.matchAll(Q_SPAN_RE)) {
          if (seen.has(m[0])) continue;
          seen.add(m[0]);
          spans.push({ file, span: m[0] });
        }
      }
    }
  }

  const wellFormed = [];
  for (const s of spans) {
    const before = parseSpan(s.span);
    if (!before.wellFormed) continue;
    const outSpan = shuffleQuizSpan(s.span);
    const after = parseSpan(outSpan);
    const strict = analyzeInterior(s.span.slice(3, -4));
    wellFormed.push({ ...s, before, after, changedOrder: outSpan !== s.span, strict: Boolean(strict), outSpan });
  }

  const total = wellFormed.length;
  const three = wellFormed.filter((b) => b.before.options.length === 3);
  const kept = wellFormed.filter((b) => b.outSpan === b.span);
  // Strict blocks the reorder left alone: positional wording ("both A and
  // B"), or the server's order happened to equal the model's (1 in 6 for
  // three options).
  const keptStrict = kept.filter((b) => b.strict);
  const keptPositional = keptStrict.filter((b) => !sameOrder(b));
  // The corpus repeats questions (eval reruns of the same lesson), which
  // correlates samples; one block per distinct stem is the fairer spread.
  const byStem = new Map();
  for (const b of wellFormed) {
    const key = b.before.stem.replace(/\s+/g, ' ').trim().toLowerCase();
    if (!byStem.has(key)) byStem.set(key, b);
  }
  const distinct = [...byStem.values()];
  const sameAnswer = wellFormed.every((b) => b.after.wellFormed &&
    b.after.options[b.after.answerIndex] === b.before.options[b.before.answerIndex]);

  const lb = wellFormed.map((b) => longest(b.before));
  const la = wellFormed.map((b) => longest(b.after));

  console.log(`[Q] blocks: ${spans.length} distinct, ${total} well-formed (lib/blockMarkup parseQuizInterior)`);
  console.log(`  by option count: ${[2, 3, 4].map((n) => `${n}: ${wellFormed.filter((b) => b.before.options.length === n).length}`).join(', ')}`);
  console.log('');
  console.log('Answer letter, as the model wrote it:');
  console.log(`  all      ${fmt(spread(wellFormed, (b) => b.before), total)}`);
  console.log(`  3-option ${fmt(spread(three, (b) => b.before), three.length)}`);
  console.log('Answer letter, after lib/quizShuffle.js:');
  console.log(`  all      ${fmt(spread(wellFormed, (b) => b.after), total)}`);
  console.log(`  3-option ${fmt(spread(three, (b) => b.after), three.length)}`);
  console.log(`One block per distinct stem (${distinct.length} stems):`);
  console.log(`  before   ${fmt(spread(distinct, (b) => b.before), distinct.length)}`);
  console.log(`  after    ${fmt(spread(distinct, (b) => b.after), distinct.length)}`);
  console.log('');
  console.log(`Reordered: ${wellFormed.filter((b) => b.changedOrder).length}/${total}; left as written: ${kept.length} ` +
    `(${kept.length - keptStrict.length} outside the strict shape, ${keptPositional.length} positional wording, ` +
    `${keptStrict.length - keptPositional.length} where the server's order equals the model's)`);
  console.log(`Right answer text unchanged in every block: ${sameAnswer}`);
  console.log(`Idempotent (reordering a reordered block changes nothing): ${wellFormed.every((b) => shuffleQuizSpan(b.outSpan) === b.outSpan)}`);
  console.log('');
  console.log(`Right answer is the longest option: before ${lb.filter((x) => x.longest).length}/${total} ` +
    `(strictly ${lb.filter((x) => x.strictly).length}), after ${la.filter((x) => x.longest).length}/${total} ` +
    `(strictly ${la.filter((x) => x.strictly).length})`);
  if (process.env.VERBOSE) {
    for (const b of kept.filter((k) => !k.strict || !sameOrder(k))) {
      console.log(`  kept: ${path.basename(b.file)}: ${JSON.stringify(b.span.slice(0, 160))}`);
    }
  }
}

main(process.argv.slice(2));
