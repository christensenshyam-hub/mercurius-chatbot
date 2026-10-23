#!/usr/bin/env node
// Replay recorded lesson turns (audit 2026-10 lesson-quality transcripts, read-only)
// N times against a local server and count [LESSON_COMPLETE].
// Wire shape copied from docs/audits/2026-10/lesson-quality-verify/replay.mjs.
//   BASE=http://localhost:3313 node replay.mjs <label> id:turn[:N] ...
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { randomBytes } from 'node:crypto';

const TX = '/Users/shyamchristensen/Desktop/mercurius-chatbot/.claude/worktrees/audit-2026-10/docs/audits/2026-10/lesson-quality/transcripts';
const OUT = path.join(path.dirname(new URL(import.meta.url).pathname), 'out');
const BASE = process.env.BASE || 'http://localhost:3313';
const CONTRACT = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.";
const PRICE = { in: 3, out: 15, cw: 3.75, cr: 0.30 };
const cost = (u) => !u ? 0 : ((u.input_tokens || 0) * PRICE.in + (u.output_tokens || 0) * PRICE.out
  + (u.cache_creation_input_tokens || 0) * PRICE.cw + (u.cache_read_input_tokens || 0) * PRICE.cr) / 1e6;

const [label, ...specs] = process.argv.slice(2);
await mkdir(OUT, { recursive: true });

async function once(messages, responseMode) {
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ messages, sessionId: `cfx-${randomBytes(5).toString('hex')}`, responseMode, capabilities: ['blocks_v1'] }),
  });
  const text = await res.text();
  const frame = text.split('\n').filter((l) => l.startsWith('data: ') && l.includes('"complete"')).map((l) => JSON.parse(l.slice(6)))[0];
  if (!frame) return { error: `status ${res.status}: ${text.slice(0, 200)}` };
  return { lessonComplete: Boolean(frame.lessonComplete), usd: cost(frame.usage), reply: frame.reply };
}

const summary = [];
for (const spec of specs) {
  const [id, turnStr, nStr] = spec.split(':');
  const rec = JSON.parse(await readFile(path.join(TX, `${id}.json`), 'utf8'));
  const turnIdx = Number(turnStr);
  const N = Number(nStr || 4);
  const target = rec.turns[turnIdx];
  const thread = rec.thread.slice(0, 2 * turnIdx);
  const opener = rec.lesson.starter + CONTRACT;
  const tag = opener.slice(0, opener.indexOf(']') + 1);
  const messages = [{ role: 'user', content: opener }, ...thread.map((m) => ({ role: m.role, content: m.content }))];
  const last = messages.length - 1;
  messages[last] = { role: 'user', content: `${tag} ${messages[last].content}` };
  const results = [];
  for (let i = 0; i < N; i++) {
    // Sequential with a small gap: stays well under any per-IP limiter.
    results.push(await once(messages, target.responseMode));
    await new Promise((r) => setTimeout(r, 1500));
  }
  const out = {
    label, lessonId: id, turnIdx, studentMessage: thread[thread.length - 1].content, original: target.lessonComplete,
    completes: results.filter((r) => r.lessonComplete).length, n: N,
    errors: results.filter((r) => r.error).map((r) => r.error),
    usd: results.reduce((a, r) => a + (r.usd || 0), 0),
    replies: results,
  };
  await writeFile(path.join(OUT, `${label}-${id}-t${turnIdx}.json`), JSON.stringify(out, null, 2));
  const line = `${label} ${id} t${turnIdx}: original=${out.original} complete ${out.completes}/${N} errors=${out.errors.length} ($${out.usd.toFixed(3)})`;
  summary.push(line);
  console.log(line);
}
await writeFile(path.join(OUT, `${label}-summary.txt`), summary.join('\n') + '\n');
