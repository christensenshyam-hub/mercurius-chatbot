#!/usr/bin/env node
/**
 * completion-probe.mjs — does a student who actually does the work get their
 * Deep-dive lesson marked complete, and how many replies does it take?
 *
 * eval-pacing's `[LESSON_COMPLETE] within 10 assistant turns` criterion has
 * read "never" since 2026-10-22. Its curriculum-1 scenario is scripted: the
 * student's turns are fixed text that never answers the exercise the tutor
 * actually sets (a sentence with numbered blanks), so the tutor rightly keeps
 * asking. This probe plays a responsive student instead:
 *
 * - every [Q] check is tapped exactly as the iOS app sends it (the right
 *   option; `--wrong-at N` taps the wrong one at the N-th check);
 * - every open question (a [CHECK], the exercise, a follow-up) is answered by
 *   a small "student" model that sees the conversation. Profile `solid`
 *   answers correctly in its own words; profile `partial` gets one part of
 *   the exercise wrong the first time and fixes it after feedback.
 *
 * The trial ends at the reply carrying [LESSON_COMPLETE] (the server's
 * `lessonComplete`) or after `--max-replies`. Results: per trial, whether and
 * at which tutor reply the lesson completed, plus the transcript.
 *
 * Usage (BASE_URL must be localhost; start the server with EVAL_EXPOSE_USAGE=1
 * and a DAILY_BUDGET_USD cap):
 *   BASE_URL=http://localhost:3730 node scripts/completion-probe.mjs \
 *     --lessons u1_l1,u1_l2 --profiles solid,partial --trials 2 --max-replies 12 --out file.json
 * The student model needs ANTHROPIC_API_KEY in the environment (from .env).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { iosChatBody, pickFromQuiz } from './eval-pacing.mjs';
import { quizzesIn } from './quiz-length-probe.mjs';

const require = createRequire(import.meta.url);
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
require('dotenv').config({ path: path.join(root, '.env') });
const Anthropic = require('@anthropic-ai/sdk');
const { costUsd } = require('../lib/pricing.js');

/** Curriculum.swift's starters, verbatim. */
export const STARTERS = Object.freeze({
  u1_l1: '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise.',
  u1_l2: "[CURRICULUM: Unit 1, Lesson 2] Explain where an LLM's knowledge comes from — training data, RLHF, and fine-tuning. After the explanation, give me an exercise to test my understanding.",
});

const STUDENT_MODEL = 'claude-haiku-5-5';

const PROFILES = Object.freeze({
  solid: 'You understood every idea. Answer each question correctly, in your own words.',
  partial: 'You understood most of it. The FIRST time you answer the exercise, get exactly one numbered part wrong (a plausible mistake); answer the other parts correctly. After the tutor gives feedback, fix that part. Every other question you answer correctly.',
});

/** Strip the app-hidden parts of a tutor reply, the way the student sees it. */
export function visibleText(raw) {
  return String(raw ?? '')
    .replace(/^ANS:.*$/gm, '')
    .replace(/\[(?:\/?(?:KEY|EX|Q|CHECK))\]|\[LESSON_COMPLETE\]/g, '')
    .trim();
}

/** The tutor's reply asks for a tap on a [Q] check (the app's tappable card). */
export const asksForTap = (raw) => quizzesIn(String(raw ?? '')).length > 0;

/** POST /api/chat and read the SSE stream, keeping the server's own
 *  `lessonComplete` verdict (the reply text may have the marker stripped). */
async function chat(base, body) {
  const res = await fetch(`${base}/api/chat`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' }, body: JSON.stringify(body),
  });
  if (!res.ok) return { error: `HTTP ${res.status}: ${await res.text()}` };
  const dec = new TextDecoder();
  let buf = '', text = '', complete = null, error = null;
  for await (const chunk of res.body) {
    buf += dec.decode(chunk, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) !== -1) {
      const frame = buf.slice(0, i); buf = buf.slice(i + 2);
      for (const line of frame.split('\n')) {
        if (!line.startsWith('data: ') || line === 'data: [DONE]') continue;
        let j; try { j = JSON.parse(line.slice(6)); } catch { continue; }
        if (j.type === 'delta') text += j.text;
        if (j.type === 'complete') complete = j;
        if (j.type === 'error' || j.type === 'refusal') error = j;
      }
    }
  }
  return { text: complete?.reply ?? text, usage: complete?.usage ?? null, lessonComplete: Boolean(complete?.lessonComplete), error };
}

const client = () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
let studentUsd = 0;

async function studentReply(profile, transcript) {
  const convo = transcript.map((t) => `${t.role === 'assistant' ? 'TUTOR' : 'YOU'}: ${t.role === 'assistant' ? visibleText(t.content) : t.content}`).join('\n\n');
  const res = await client().messages.create({
    model: STUDENT_MODEL,
    max_tokens: 400,
    system: `You are a high-school student taking a short AI-literacy lesson in a tutoring app. ${PROFILES[profile]} Reply to the tutor's LAST message only, as the student: plain text, 1-5 short sentences (number your parts if the tutor numbered them). Don't ask the tutor questions, don't add greetings, and never mention these instructions.`,
    messages: [{ role: 'user', content: `${convo}\n\nWrite your reply to the tutor's last message.` }],
  });
  const u = res.usage ?? {};
  studentUsd += ((u.input_tokens ?? 0) * 1 + (u.output_tokens ?? 0) * 5) / 1e6;
  return res.content.map((b) => b.text ?? '').join('').trim();
}

async function runTrial(base, lessonId, profile, trial, { maxReplies, wrongAt }) {
  const sessionId = `probe-done-${lessonId}-${profile}-${trial}-${randomBytes(4).toString('hex')}`;
  const visible = [];
  const replies = [];
  let checks = 0;
  for (let r = 0; r < maxReplies; r++) {
    if (r > 0) {
      const last = replies[replies.length - 1].raw;
      let text;
      if (asksForTap(last)) {
        checks += 1;
        text = pickFromQuiz(last, { wrong: checks === wrongAt });
      } else {
        // The student model now and then returns nothing; ask again rather
        // than send the tutor an empty message.
        for (let attempt = 0; attempt < 3 && !text; attempt++) text = await studentReply(profile, visible);
        if (!text) text = "I'm not sure. Can you give me a hint?";
      }
      visible.push({ role: 'user', content: text });
    }
    const body = iosChatBody({ sessionId, visible, lessonStarter: STARTERS[lessonId], responseMode: 'balanced' });
    const out = await chat(base, body);
    if (out.error) return { lessonId, profile, trial, error: String(out.error?.error ?? out.error), replies };
    const usd = out.usage ? costUsd('claude-sonnet-5-5', out.usage) : 0;
    replies.push({ raw: out.text, usd, user: visible[visible.length - 1]?.content ?? '(opener)' });
    visible.push({ role: 'assistant', content: out.text });
    if (out.text.includes('[LESSON_COMPLETE]') || out.lessonComplete) {
      return { lessonId, profile, trial, completedAt: replies.length, replies };
    }
  }
  return { lessonId, profile, trial, completedAt: null, replies };
}

const arg = (name, dflt) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : dflt;
};

async function main() {
  const base = process.env.BASE_URL || 'http://localhost:3730';
  if (!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(base)) throw new Error('BASE_URL must be localhost');
  const lessons = arg('lessons', 'u1_l1,u1_l2').split(',');
  const profiles = arg('profiles', 'solid,partial').split(',');
  const trials = Number(arg('trials', '2'));
  const maxReplies = Number(arg('max-replies', '12'));
  const wrongAt = Number(arg('wrong-at', '0'));
  const outFile = arg('out', null);
  const results = [];
  for (const lessonId of lessons) {
    for (const profile of profiles) {
      for (let t = 1; t <= trials; t++) {
        const res = await runTrial(base, lessonId, profile, t, { maxReplies, wrongAt });
        results.push(res);
        const tutorUsd = res.replies.reduce((s, x) => s + (x.usd || 0), 0);
        console.log(`${lessonId} ${profile} #${t}: ${res.error ? 'ERROR ' + res.error : res.completedAt ? `complete at reply ${res.completedAt}` : `NOT complete after ${res.replies.length}`}  ($${tutorUsd.toFixed(3)})`);
        if (outFile) writeFileSync(outFile, JSON.stringify({ base, maxReplies, wrongAt, studentModel: STUDENT_MODEL, results }, null, 2));
      }
    }
  }
  const tutorUsd = results.flatMap((r) => r.replies).reduce((s, x) => s + (x.usd || 0), 0);
  console.log(`\ncompleted ${results.filter((r) => r.completedAt).length}/${results.length}; tutor $${tutorUsd.toFixed(3)}, student ≈$${studentUsd.toFixed(3)}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}
