#!/usr/bin/env node
// Drive one lesson turn in the shipped iOS wire shape (mirrors eval-pacing iosChatBody).
//   node turn.mjs <state.json> --start "<starter>"     -> opener (balanced)
//   node turn.mjs <state.json> "<student text>" [--tap] -> typed (concise) or [Q] tap (balanced)
import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
const BASE = process.env.BASE || 'http://localhost:3343';
const CONTRACT = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.";
const PRICE = { in: 3, out: 15, cw: 3.75, cr: 0.30 };
const cost = (u) => !u ? 0 : ((u.input_tokens || 0) * PRICE.in + (u.output_tokens || 0) * PRICE.out
  + (u.cache_creation_input_tokens || 0) * PRICE.cw + (u.cache_read_input_tokens || 0) * PRICE.cr) / 1e6;
const [file, a1, a2] = process.argv.slice(2);
let st;
if (a1 === '--start') {
  st = { sessionId: `rf-${randomBytes(6).toString('hex')}`, starter: a2, visible: [], turns: [], usd: 0, flag: process.env.FLAG || '?' };
} else {
  st = JSON.parse(await readFile(file, 'utf8'));
}
const isOpener = a1 === '--start';
const tap = a2 === '--tap';
const responseMode = isOpener || tap ? 'balanced' : 'concise';
if (!isOpener) st.visible.push({ role: 'user', content: a1 });
let messages = [{ role: 'user', content: st.starter + CONTRACT }, ...st.visible.map((m) => ({ ...m }))];
const tag = st.starter.slice(0, st.starter.indexOf(']') + 1);
const last = messages.length - 1;
if (last > 0 && messages[last].role === 'user' && !messages[last].content.startsWith('[CURRICULUM')) {
  messages[last] = { role: 'user', content: `${tag} ${messages[last].content}` };
}
const body = { messages, sessionId: st.sessionId, responseMode, capabilities: ['blocks_v1'] };
const res = await fetch(`${BASE}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' }, body: JSON.stringify(body) });
if (!res.ok) { console.error('HTTP', res.status, await res.text()); process.exit(1); }
const raw = await res.text();
let text = ''; let usage = null; let lessonComplete = null; let finalReply = null;
for (const line of raw.split('\n')) {
  if (!line.startsWith('data: ')) continue;
  const p = line.slice(6); if (p === '[DONE]') continue;
  let j; try { j = JSON.parse(p); } catch { continue; }
  if (j.type === 'delta' && typeof j.text === 'string') text += j.text;
  if (j.type === 'complete') { usage = j.usage || null; lessonComplete = j.lessonComplete; finalReply = j.reply ?? null; }
  if (j.type === 'error') { console.error('SSE error', j); process.exit(1); }
}
st.visible.push({ role: 'assistant', content: text });
const usd = cost(usage); st.usd += usd;
const n = st.turns.length + 1;
st.turns.push({ n, user: isOpener ? '(opener)' : a1, responseMode, reply: text, lessonComplete, usd, words: text.replace(/\[\/?(KEY|EX|Q|CHECK)\]|^ANS:.*$/gm, '').split(/\s+/).filter(Boolean).length });
await writeFile(file, JSON.stringify(st, null, 2));
console.log(`--- assistant turn ${n} (${responseMode}) lessonComplete=${lessonComplete} usd=${usd.toFixed(4)} total=${st.usd.toFixed(3)}`);
console.log(text);
