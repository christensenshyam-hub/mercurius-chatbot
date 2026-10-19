#!/usr/bin/env node
// Replay one live turn N times on a recorded thread prefix (iOS wire shape).
//   node replay.mjs <state.json> <keepTurns> "<student text>" <runs> <out.json> [--tap]
import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
const BASE = process.env.BASE || 'http://localhost:3343';
const CONTRACT = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.";
const [file, keepStr, text, runsStr, out, flag] = process.argv.slice(2);
const st = JSON.parse(await readFile(file, 'utf8'));
const keep = Number(keepStr); // number of assistant turns to keep (incl. opener)
const visible = st.visible.slice(0, keep * 2 - 1); // opener reply is visible[0]; then user/assistant pairs
const tag = st.starter.slice(0, st.starter.indexOf(']') + 1);
const results = [];
for (let r = 0; r < Number(runsStr); r++) {
  const v = [...visible, { role: 'user', content: text }];
  const messages = [{ role: 'user', content: st.starter + CONTRACT }, ...v];
  messages[messages.length - 1] = { role: 'user', content: `${tag} ${text}` };
  const body = { messages, sessionId: `rfr-${randomBytes(6).toString('hex')}`, responseMode: flag === '--tap' ? 'balanced' : 'concise', capabilities: ['blocks_v1'] };
  const res = await fetch(`${BASE}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' }, body: JSON.stringify(body) });
  const raw = await res.text();
  let reply = ''; let lc = null;
  for (const line of raw.split('\n')) { if (!line.startsWith('data: ')) continue; const p = line.slice(6); if (p === '[DONE]') continue; let j; try { j = JSON.parse(p); } catch { continue; } if (j.type === 'delta') reply += j.text; if (j.type === 'complete') lc = j.lessonComplete; }
  results.push({ run: r, lessonComplete: lc, reply });
  console.log(`=== run ${r} lessonComplete=${lc}\n${reply}\n`);
}
await writeFile(out, JSON.stringify({ base: file, keepTurns: keep, student: text, flag: process.env.FLAG, results }, null, 2));
