#!/usr/bin/env node
/**
 * eval-pacing.mjs — across-turns pacing eval harness.
 *
 * Drives scripted multi-turn conversations against a RUNNING Mercurius
 * server (SSE endpoint POST /api/chat) and scores every assistant reply
 * against the beat-pacing contract:
 *
 *   - one idea per turn, 2–4 sentences by default
 *   - exactly one closing question / forward invitation (Socratic)
 *   - no previews / roadmaps ("there are three factors: …")
 *   - no truncated replies (token-cap cutoffs)
 *   - curriculum delivers micro-concept beats: beat 1 has exactly one
 *     [CHECK] and no exercise; [LESSON_COMPLETE] lands within 10 turns
 *   - deep ("Explain more") replies actually go deep (≥8 sentences)
 *
 * Usage:
 *   BASE_URL=http://localhost:3000 node scripts/eval-pacing.mjs --label baseline
 *
 * Flags:
 *   --label <name>   tag for the output file (docs/evals/pacing-<label>.json)
 *   --delay <ms>     gap between /api/chat calls (default 4500 — stays under
 *                    the server's 15 req/min/IP chat limiter)
 *   --only <prefix>  run only conversations whose id starts with <prefix>
 *
 * No LLM judge, no new dependencies (global fetch, Node 18+). Exits
 * nonzero when any pass criterion fails so it can gate in CI.
 *
 * The metric functions are exported so tests/evalPacing.test.js can
 * smoke them without a live server; `main()` only runs when the file is
 * executed directly.
 */

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';

// ---------------------------------------------------------------------------
// Metrics (pure — unit-tested in tests/evalPacing.test.js)
// ---------------------------------------------------------------------------

/** Server↔client contract markers stripped before measuring prose. */
const MARKER_RE = /\[CHECK\]|\[\/CHECK\]|\[LESSON_COMPLETE\]|\[SOURCE:[^\]]*\]/g;

/** Roadmapping / preview language the pacing rules ban. */
export const PREVIEW_RE =
  /we['’]ll cover|there are (?:two|three|four|\d+)|first,[\s\S]{0,400}?second,|later (?:we|i)['’]ll|next,? we\b/i;

export function stripMarkers(text) {
  return String(text ?? '').replace(MARKER_RE, ' ').replace(/[ \t]+/g, ' ').trim();
}

/**
 * Trailing decoration (markdown emphasis, quotes, brackets) that can
 * legitimately follow the final punctuation mark of a reply.
 */
function trimTrailingDecoration(text) {
  return String(text ?? '').trim().replace(/[*_`"'”’»)\]\s]+$/g, '');
}

export function countSentences(text) {
  const t = stripMarkers(text);
  if (!t) return 0;
  // A sentence ends at .!?… followed by whitespace/end — the lookahead
  // keeps decimals ("3.5") and "U.S" mid-token splits from counting.
  const terminals = t.match(/[.!?…]+(?=[\s"'”’)*\]]|$)/g) || [];
  const endsClean = /[.!?…][*_`"'”’»)\]\s]*$/.test(t);
  // A trailing fragment with no terminal punctuation is still a sentence.
  return terminals.length + (endsClean ? 0 : 1);
}

export function countLines(text) {
  const t = String(text ?? '').replace(MARKER_RE, ' ');
  return t.split('\n').filter((l) => l.trim().length > 0).length;
}

export function countQuestionMarks(text) {
  return (stripMarkers(text).match(/\?/g) || []).length;
}

export function endsWithQuestion(text) {
  return trimTrailingDecoration(stripMarkers(text)).endsWith('?');
}

/** True when the reply has no terminal .!? — i.e. a token-cap cutoff. */
export function isTruncated(text) {
  const t = trimTrailingDecoration(stripMarkers(text));
  if (!t) return true;
  return !/[.!?…]$/.test(t);
}

export function previewHit(text) {
  return PREVIEW_RE.test(stripMarkers(text));
}

export function computeMetrics(rawText) {
  return {
    sentenceCount: countSentences(rawText),
    lineCount: countLines(rawText),
    questionMarks: countQuestionMarks(rawText),
    endsWithQuestion: endsWithQuestion(rawText),
    truncated: isTruncated(rawText),
    previewHit: previewHit(rawText),
  };
}

export function median(nums) {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

export function percentile(nums, p) {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1))];
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

const SCENARIOS = [
  {
    id: 'socratic-1', mode: 'socratic',
    turns: [
      'How does an LLM actually generate its answers?',
      "I think it predicts the next word based on patterns it learned?",
      "So it doesn't really 'know' facts — it just produces likely text?",
      'Then why does it sometimes state wrong things so confidently?',
    ],
  },
  {
    id: 'socratic-2', mode: 'socratic',
    turns: [
      "Where does an AI model's knowledge come from?",
      'From the internet, I guess — so whatever people wrote online.',
      'Does that mean gaps in the data become gaps in the model?',
      'How would I even notice a gap like that when I use it?',
    ],
  },
  {
    id: 'debate-1', mode: 'debate',
    turns: [
      "Let's debate: schools should ban AI chatbots. I'll argue for the ban — you argue against. My claim: AI makes students stop thinking for themselves.",
      'My warrant: students just copy answers, so they never practice the skill.',
      "But cheating existed before AI — doesn't that undercut your position?",
      "Okay, attack my impact: a generation that can't reason without a tool.",
    ],
  },
  {
    id: 'debate-2', mode: 'debate',
    turns: [
      'Debate me: governments should ban facial recognition in public spaces. I say ban it — privacy comes first. Your move.',
      'My warrant is chilling effects: people behave differently when watched.',
      'Your security argument ignores false positives hitting minorities hardest.',
      'Give me your strongest rebuttal so I can prep against it.',
    ],
  },
  {
    id: 'discussion-1', mode: 'discussion',
    turns: [
      "I think companies using AI to screen resumes is basically fine — it's faster and less biased than tired recruiters.",
      "Fair, but can't you audit the AI in a way you can't audit a human's gut feeling?",
      'So the real issue is accountability when the audit misses something?',
    ],
  },
  {
    id: 'discussion-2', mode: 'discussion',
    turns: [
      'AI companions for lonely people seem like a clear win to me.',
      'But if it helps someone through a bad year, does the dependency risk really matter?',
      'Where would you draw the line between support and substitution?',
    ],
  },
  {
    id: 'curriculum-1', mode: 'curriculum',
    turns: [
      '[CURRICULUM: Unit 1, Lesson 1] Start the lesson.',
      "Got it — the model first breaks my sentence into tokens and turns them into numbers, because it can only work with numbers, not raw words. The split doesn't always match word boundaries.",
      "The embeddings put similar meanings near each other, so the model can use context — like 'bank' ending up near money words or river words depending on the sentence. Attention decides which earlier tokens matter for the current one.",
      "It predicts the next token by probability — so 'The cat sat on the' makes 'mat' very likely. It's not looking up an answer, it's continuing a learned pattern.",
      "For the exercise: the high-confidence predictions are the ones with strong patterns — like 'mat' after 'the cat sat on the' — and the low-confidence ones are open choices like a person's name, because many continuations are plausible. The model is confident when its training data heavily favors one continuation.",
      "Right — and that's why it can be confidently wrong: plausible isn't the same as true. It optimizes for likely text, not verified facts.",
      "My takeaway: prompt → tokens → embeddings → attention weighs context → the model predicts one token at a time. That's why it feels fluent but doesn't 'know' things the way a database does.",
    ],
  },
  {
    id: 'deep-1', mode: 'socratic',
    turns: [
      'What is attention in a transformer?',
      'So each token looks back at the earlier tokens and decides which ones matter most?',
      { text: "Explain more — go deeper on the same topic. Don't repeat what you already said.", responseMode: 'deep' },
    ],
  },
];

// ---------------------------------------------------------------------------
// SSE client
// ---------------------------------------------------------------------------

function newSessionId() {
  return `eval-pacing-${randomBytes(8).toString('hex')}`;
}

async function setMode(baseUrl, sessionId, mode) {
  const res = await fetch(`${baseUrl}/api/mode`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, mode }),
  });
  if (!res.ok) throw new Error(`POST /api/mode → ${res.status}: ${await res.text()}`);
}

/**
 * POST /api/chat with Accept: text/event-stream; accumulate `delta`
 * frames until the `[DONE]` sentinel. Retries once on a 429 (the
 * server rate-limits 15 chat req/min/IP + 20/min/session).
 */
async function streamChat(baseUrl, body, { retries = 2 } = {}) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`${baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
      body: JSON.stringify(body),
    });
    if (res.status === 429 && attempt < retries) {
      process.stderr.write('    rate-limited (429) — sleeping 61s and retrying\n');
      await sleep(61_000);
      continue;
    }
    if (!res.ok) throw new Error(`POST /api/chat → ${res.status}: ${await res.text()}`);

    const decoder = new TextDecoder();
    let buffer = '';
    let text = '';
    let done = false;
    for await (const chunk of res.body) {
      buffer += decoder.decode(chunk, { stream: true });
      let idx;
      while ((idx = buffer.indexOf('\n\n')) !== -1) {
        const frame = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);
        for (const line of frame.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          const payload = line.slice(6);
          if (payload === '[DONE]') { done = true; continue; }
          let parsed;
          try { parsed = JSON.parse(payload); } catch { continue; }
          if (parsed.type === 'delta' && typeof parsed.text === 'string') text += parsed.text;
          if (parsed.type === 'error') throw new Error(`SSE error frame: ${parsed.error}`);
        }
      }
      if (done) break;
    }
    if (!done) throw new Error('SSE stream ended without [DONE]');
    return text;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

async function runScenario(baseUrl, scenario, delayMs) {
  const sessionId = newSessionId();
  if (scenario.mode === 'debate' || scenario.mode === 'discussion') {
    // /api/mode 404s until the session row exists; a getOrCreateSession
    // happens inside the handler, so this is a single call.
    await setMode(baseUrl, sessionId, scenario.mode);
  }

  const thread = [];
  const replies = [];
  for (const turn of scenario.turns) {
    const { text: userText, responseMode } = typeof turn === 'string' ? { text: turn } : turn;
    thread.push({ role: 'user', content: userText });
    const body = { sessionId, messages: thread };
    if (responseMode) body.responseMode = responseMode;

    const reply = await streamChat(baseUrl, body);
    thread.push({ role: 'assistant', content: reply });
    replies.push({
      user: userText,
      responseMode: responseMode || 'concise',
      raw: reply,
      metrics: computeMetrics(reply),
    });
    process.stderr.write(`    turn ${replies.length}/${scenario.turns.length} ok (${reply.length} chars)\n`);
    await sleep(delayMs);
  }
  return { id: scenario.id, mode: scenario.mode, sessionId, replies };
}

export function evaluateCriteria(results) {
  const convo = (prefix) => results.filter((r) => r.id.startsWith(prefix));
  const allReplies = results.flatMap((r) => r.replies.map((x) => ({ ...x, convoId: r.id, mode: r.mode })));

  // Length stats over conversational (non-curriculum, non-deep) replies:
  // curriculum beats and deep replies carry their own criteria below.
  const chatReplies = allReplies.filter((x) => x.mode !== 'curriculum' && x.responseMode !== 'deep');
  const sentences = chatReplies.map((x) => x.metrics.sentenceCount);

  const socraticReplies = allReplies.filter(
    (x) => x.convoId.startsWith('socratic') && x.responseMode !== 'deep',
  );

  const curriculum = convo('curriculum')[0];
  const curriculumReplies = curriculum ? curriculum.replies : [];
  const beat1 = curriculumReplies[0]?.raw ?? '';
  const beat1Checks = (beat1.match(/\[CHECK\]/g) || []).length;
  const lessonCompleteTurn =
    curriculumReplies.findIndex((r) => r.raw.includes('[LESSON_COMPLETE]')) + 1; // 1-based; 0 = never

  const deepReply = allReplies.find((x) => x.responseMode === 'deep');

  const criteria = [
    { name: 'median sentences ≤ 4 (chat replies)', value: median(sentences), pass: median(sentences) <= 4 },
    { name: 'p90 sentences ≤ 6 (chat replies)', value: percentile(sentences, 90), pass: percentile(sentences, 90) <= 6 },
    {
      name: 'socratic: 100% end with exactly one question',
      value: `${socraticReplies.filter((x) => x.metrics.endsWithQuestion && x.metrics.questionMarks === 1).length}/${socraticReplies.length}`,
      pass: socraticReplies.length > 0 &&
        socraticReplies.every((x) => x.metrics.endsWithQuestion && x.metrics.questionMarks === 1),
    },
    {
      name: 'preview hits = 0 (all replies)',
      value: allReplies.filter((x) => x.metrics.previewHit).length,
      pass: allReplies.every((x) => !x.metrics.previewHit),
    },
    {
      name: 'truncations = 0 (all replies)',
      value: allReplies.filter((x) => x.metrics.truncated).length,
      pass: allReplies.every((x) => !x.metrics.truncated),
    },
    {
      name: 'curriculum beat 1: exactly one [CHECK], no exercise',
      value: `checks=${beat1Checks} exercise=${/\bexercise\b/i.test(beat1)}`,
      pass: curriculumReplies.length > 0 && beat1Checks === 1 && !/\bexercise\b/i.test(beat1),
    },
    {
      name: '[LESSON_COMPLETE] within 10 assistant turns',
      value: lessonCompleteTurn || 'never',
      pass: lessonCompleteTurn >= 1 && lessonCompleteTurn <= 10,
    },
    {
      name: 'deep reply ≥ 8 sentences',
      value: deepReply ? deepReply.metrics.sentenceCount : 'missing',
      pass: Boolean(deepReply) && deepReply.metrics.sentenceCount >= 8,
    },
  ];
  return criteria;
}

function parseArgs(argv) {
  const args = { label: '', delay: 4500, only: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--label') args.label = argv[++i] ?? '';
    else if (argv[i] === '--delay') args.delay = Number(argv[++i]) || 4500;
    else if (argv[i] === '--only') args.only = argv[++i] ?? '';
  }
  if (!args.label) args.label = new Date().toISOString().replace(/[:.]/g, '-');
  return args;
}

async function main() {
  const baseUrl = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
  const { label, delay, only } = parseArgs(process.argv.slice(2));
  const scenarios = SCENARIOS.filter((s) => !only || s.id.startsWith(only));

  process.stderr.write(`eval-pacing → ${baseUrl} label=${label} scenarios=${scenarios.length} delay=${delay}ms\n`);

  const results = [];
  for (const scenario of scenarios) {
    process.stderr.write(`  ${scenario.id} (${scenario.mode})\n`);
    results.push(await runScenario(baseUrl, scenario, delay));
  }

  const criteria = evaluateCriteria(results);

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const outDir = path.join(scriptDir, '..', 'docs', 'evals');
  await mkdir(outDir, { recursive: true });
  const outFile = path.join(outDir, `pacing-${label}.json`);
  await writeFile(outFile, JSON.stringify({
    label,
    baseUrl,
    generatedAt: new Date().toISOString(),
    criteria: criteria.map(({ name, value, pass }) => ({ name, value, pass })),
    results,
  }, null, 2));

  // Summary table
  const w = Math.max(...criteria.map((c) => c.name.length)) + 2;
  console.log(`\n=== PACING EVAL — ${label} ===`);
  console.log(`replies: ${results.reduce((n, r) => n + r.replies.length, 0)} across ${results.length} conversations\n`);
  for (const c of criteria) {
    console.log(`${c.pass ? 'PASS' : 'FAIL'}  ${c.name.padEnd(w)} ${String(c.value)}`);
  }
  console.log(`\nresults → ${outFile}`);

  const failed = criteria.filter((c) => !c.pass);
  if (failed.length > 0) {
    console.error(`\n${failed.length} criterion(s) failed.`);
    process.exit(1);
  }
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
    console.error(`eval-pacing failed: ${err.message}`);
    process.exit(1);
  });
}
