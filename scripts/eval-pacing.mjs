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

import { mkdir, readFile, writeFile } from 'node:fs/promises';
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
  // The contract is "never barrage the STUDENT with multiple questions" —
  // a question mark inside a quoted or italicized span ("what token comes
  // next?" as the model narrates its own inner loop) is rhetoric, not a
  // second ask. Strip those spans before counting; the closing question the
  // modes mandate is never wrapped in quotes or italics.
  const withoutQuoted = stripMarkers(text)
    .replace(/\*\*[^*]*\*\*/g, ' ')
    .replace(/\*[^*\n]*\*/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/“[^”\n]*”/g, ' ');
  return (withoutQuoted.match(/\?/g) || []).length;
}

export function endsWithQuestion(text) {
  return trimTrailingDecoration(stripMarkers(text)).endsWith('?');
}

/** True when the reply has no terminal .!? — i.e. a token-cap cutoff. */
export function isTruncated(text) {
  // A reply whose RAW text ends with a control marker was terminated
  // deliberately ([LESSON_COMPLETE] on its own final line is the sanctioned
  // ending for the completion turn) — never a token-cap cutoff, even when the
  // words before the marker lack terminal punctuation ("Grade: A").
  const raw = String(text ?? '').trim();
  if (/(\[CHECK\]|\[\/CHECK\]|\[LESSON_COMPLETE\]|\[SOURCE:[^\]]*\])$/.test(raw)) return false;
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
      "For the exercise, concretely: the model is most confident at the end of a strong collocation — in your sentence, the slot right after the last two words, where one continuation dominates training text. It's least confident at an open slot like right after the opening word, where several continuations ('a', 'the', a noun) are all plausible. Strong learned pattern → high confidence; open choice → low confidence.",
      "Naming the exact spots: high confidence — the final word of your sentence, because the phrase leading into it is a fixed expression the model has seen thousands of times. Low confidence — immediately after the first word, because almost any word class could follow there.",
      "Right — and that's why it can be confidently wrong: plausible isn't the same as true. It optimizes for likely text, not verified facts.",
      "My takeaway: prompt → tokens → embeddings → attention weighs context → the model predicts one token at a time. That's why it feels fluent but doesn't 'know' things the way a database does.",
      "Yes — one more concrete pair: after 'sat on the' the model would bet on 'mat'-type continuations; right after 'She said' it would hesitate, since a quote, a name, or 'that' are all live options.",
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

    // One retry on transient server errors (the 45s generation watchdog
    // occasionally fires on a slow curriculum turn) — a multi-run gate
    // shouldn't die 100 calls in on a single hiccup.
    let reply;
    try {
      reply = await streamChat(baseUrl, body);
    } catch (err) {
      if (!/timed out|overloaded|rate.?limit/i.test(String(err?.message))) throw err;
      process.stderr.write(`    turn ${replies.length + 1} transient error (${err.message}) — retrying once\n`);
      await sleep(Math.max(delayMs, 10_000));
      reply = await streamChat(baseUrl, body);
    }
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

  // Length stats over conversational (non-curriculum, non-deep) replies.
  // Debate is ALSO excluded from the sentence pool and measured by its own
  // shipped contract instead — MODE_RULES.debate mandates a 4-line labeled
  // Claim/Warrant/Impact/Rebuttal structure with "Total length: 4–7 lines";
  // sentence-counting penalizes exactly the format we require. Debate gets a
  // dedicated ≤7-line criterion below. Discussion SCORING replies get the
  // same treatment for the same reason: DISCUSSION_PROMPT mandates a labeled
  // 5-dimension rubric block, so they're pulled from the sentence pool and
  // held to their own line-count contract instead.
  const isScoringReply = (x) => /how your reasoning scored/i.test(x.raw);
  const chatReplies = allReplies.filter(
    (x) => x.mode !== 'curriculum' && x.mode !== 'debate' && x.responseMode !== 'deep' &&
      !isScoringReply(x),
  );
  const sentences = chatReplies.map((x) => x.metrics.sentenceCount);

  const debateReplies = allReplies.filter((x) => x.mode === 'debate');
  const debateLineMax = Math.max(0, ...debateReplies.map((x) => x.metrics.lineCount));

  // Discussion scoring contract: header + 5 dimension lines + Overall + one
  // follow-up question ≈ 8 non-blank lines; ≤10 leaves headroom without
  // letting the old "What worked / What to strengthen" trailer back in.
  const scoringReplies = allReplies.filter((x) => x.mode === 'discussion' && isScoringReply(x));
  const scoringLineMax = Math.max(0, ...scoringReplies.map((x) => x.metrics.lineCount));

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
    // Debate's own contract: 4-line CWIR + hand-back, "Total length: 4–7 lines".
    { name: 'debate replies ≤ 7 lines (contract)', value: debateLineMax, pass: debateLineMax <= 7 },
    {
      name: 'discussion scoring block ≤ 10 lines, ends with one question',
      value: scoringReplies.length
        ? `lines=${scoringLineMax} endQ=${scoringReplies.every((x) => x.metrics.endsWithQuestion)}`
        : 'none',
      pass: scoringReplies.length > 0 && scoringLineMax <= 10 &&
        scoringReplies.every((x) => x.metrics.endsWithQuestion),
    },
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

/**
 * Aggregate one criteria list per run into a single verdict per criterion:
 * pass = passed in a strict majority of runs (the plan's "3 runs, medians"
 * gate — single runs at temperature flip 1–3 criteria per run on noise).
 * Numeric values are reported as their median; all per-run values are shown.
 */
export function aggregateCriteria(perRunCriteria) {
  const runs = perRunCriteria.length;
  return perRunCriteria[0].map((first, i) => {
    const runsForCriterion = perRunCriteria.map((c) => c[i]);
    const passes = runsForCriterion.filter((c) => c.pass).length;
    const values = runsForCriterion.map((c) => c.value);
    const numeric = values.filter((v) => typeof v === 'number');
    const value = numeric.length === runs
      ? `${median(numeric)} (runs: ${values.join(', ')})`
      : `${passes}/${runs} runs pass (${values.join(' | ')})`;
    return { name: first.name, value, pass: passes * 2 > runs };
  });
}

function parseArgs(argv) {
  const args = { label: '', delay: 4500, only: '', rescore: '', runs: 1 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--label') args.label = argv[++i] ?? '';
    else if (argv[i] === '--delay') args.delay = Number(argv[++i]) || 4500;
    else if (argv[i] === '--only') args.only = argv[++i] ?? '';
    else if (argv[i] === '--rescore') args.rescore = argv[++i] ?? '';
    else if (argv[i] === '--runs') args.runs = Math.max(1, Number(argv[++i]) || 1);
  }
  if (!args.label) args.label = new Date().toISOString().replace(/[:.]/g, '-');
  return args;
}

/**
 * Offline re-judge: recompute metrics + criteria from the raw reply texts in
 * an existing pacing-<label>.json — no server, no API calls. Used after a
 * metric-definition fix so before/after runs stay comparable without respend.
 */
async function rescore(file) {
  const data = JSON.parse(await readFile(file, 'utf8'));
  const runResults = data.perRun ? data.perRun.map((r) => r.results) : [data.results];
  for (const results of runResults) {
    for (const convo of results) {
      for (const reply of convo.replies) reply.metrics = computeMetrics(reply.raw);
    }
  }
  const perRunCriteria = runResults.map(evaluateCriteria);
  if (data.perRun) {
    data.perRun.forEach((r, i) => {
      r.criteria = perRunCriteria[i].map(({ name, value, pass }) => ({ name, value, pass }));
    });
  }
  const criteria = runResults.length > 1 ? aggregateCriteria(perRunCriteria) : perRunCriteria[0];
  data.criteria = criteria.map(({ name, value, pass }) => ({ name, value, pass }));
  data.rescoredAt = new Date().toISOString();
  await writeFile(file, JSON.stringify(data, null, 2));
  console.log(`\n=== PACING EVAL — ${data.label} (rescored) ===`);
  for (const c of criteria) {
    console.log(`${c.pass ? 'PASS' : 'FAIL'}  ${c.name.padEnd(52)} ${c.value}`);
  }
  const failed = criteria.filter((c) => !c.pass).length;
  console.log(failed ? `\n${failed} criterion(s) failed.` : '\nall criteria passed.');
  process.exitCode = failed ? 1 : 0;
}

async function main() {
  const baseUrl = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
  const { label, delay, only, rescore: rescoreFile, runs } = parseArgs(process.argv.slice(2));
  if (rescoreFile) return rescore(rescoreFile);
  const scenarios = SCENARIOS.filter((s) => !only || s.id.startsWith(only));

  process.stderr.write(`eval-pacing → ${baseUrl} label=${label} scenarios=${scenarios.length} delay=${delay}ms runs=${runs}\n`);

  const allRuns = [];
  for (let run = 1; run <= runs; run++) {
    if (runs > 1) process.stderr.write(`── run ${run}/${runs}\n`);
    const results = [];
    for (const scenario of scenarios) {
      process.stderr.write(`  ${scenario.id} (${scenario.mode})\n`);
      results.push(await runScenario(baseUrl, scenario, delay));
    }
    allRuns.push(results);
  }

  const perRunCriteria = allRuns.map(evaluateCriteria);
  const criteria = runs > 1 ? aggregateCriteria(perRunCriteria) : perRunCriteria[0];

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const outDir = path.join(scriptDir, '..', 'docs', 'evals');
  await mkdir(outDir, { recursive: true });
  const outFile = path.join(outDir, `pacing-${label}.json`);
  await writeFile(outFile, JSON.stringify({
    label,
    baseUrl,
    generatedAt: new Date().toISOString(),
    runs,
    criteria: criteria.map(({ name, value, pass }) => ({ name, value, pass })),
    // Single run keeps the flat `results` shape (older rescore files match);
    // multi-run adds perRun so each run stays independently rescoreable.
    ...(runs === 1
      ? { results: allRuns[0] }
      : {
          perRun: allRuns.map((results, i) => ({
            criteria: perRunCriteria[i].map(({ name, value, pass }) => ({ name, value, pass })),
            results,
          })),
        }),
  }, null, 2));

  // Summary table
  const w = Math.max(...criteria.map((c) => c.name.length)) + 2;
  console.log(`\n=== PACING EVAL — ${label}${runs > 1 ? ` (majority of ${runs} runs)` : ''} ===`);
  console.log(`replies: ${allRuns.flat().reduce((n, r) => n + r.replies.length, 0)} across ${allRuns.flat().length} conversations\n`);
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
