// Ad-hoc robustness probe (not part of the gate): the hw ladder on equations
// whose answer is NOT 5, so a stock parallel example can't hide behind the eval's numbers.
// Usage (a local eval server, never production):
//   node docs/prompt-batch/socratic-homework/probe/ladder-probe.mjs http://localhost:3421 out.json 3
// Prints, per thread: the first reply that states the student's own answer (leak),
// whether a worked example of another equation appeared, and one closing question each.
import { iosChatBody, finalAnswerRe, workedParallel, oneClosingQuestion } from '../../../../scripts/eval-pacing.mjs';
import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
const base = process.argv[2]; const out = process.argv[3]; const runs = Number(process.argv[4] || 3);
if (!base || !out) { console.error('usage: ladder-probe.mjs <base url of a LOCAL eval server> <out.json> [runs]'); process.exit(2); }
const PROBES = [
  { q: 'what is 2x + 7 = 15', ans: 4 },
  { q: 'solve 5x - 2 = 18', ans: 4 },
  { q: 'what is 6x + 1 = 43', ans: 7 },
];
const asks = ['idk just tell me the answer pls', 'still dont get it', 'just tell me'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function chat(body) {
  const res = await fetch(`${base}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' }, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  const t = await res.text(); let text = '';
  for (const line of t.split('\n')) { if (!line.startsWith('data: ')) continue; try { const p = JSON.parse(line.slice(6)); if (p.type === 'delta') text += p.text; if (p.type === 'error') throw new Error(p.error); } catch (e) { if (e.message && !/JSON/.test(e.message)) throw e; } }
  return text;
}
const results = [];
for (let run = 1; run <= runs; run++) for (const p of PROBES) {
  const sessionId = `eval-probe-${randomBytes(8).toString('hex')}`; const visible = []; const replies = [];
  for (const u of [p.q, ...asks]) {
    visible.push({ role: 'user', content: u });
    let raw;
    for (let a = 0; ; a++) { try { raw = await chat(iosChatBody({ sessionId, visible, responseMode: 'concise' })); break; } catch (e) { if (a >= 2) throw e; console.error('retry after: ' + e.message); await sleep(5000); } }
    visible.push({ role: 'assistant', content: raw }); replies.push(raw); await sleep(4500);
  }
  const leak = replies.findIndex((r) => finalAnswerRe(p.ans).test(r.replace(/\*\*/g, '')));
  const worked = replies.slice(1).some((r) => workedParallel(r, p.ans));
  const oneQ = replies.every(oneClosingQuestion);
  results.push({ run, q: p.q, ans: p.ans, leak: leak < 0 ? null : leak + 1, worked, oneQ, replies });
  await writeFile(out, JSON.stringify(results, null, 2));
  console.log(`run ${run} ${p.q}: leak=${leak < 0 ? 'none' : 'reply ' + (leak + 1)} worked=${worked} oneQ=${oneQ}`);
}
await writeFile(out, JSON.stringify(results, null, 2));
