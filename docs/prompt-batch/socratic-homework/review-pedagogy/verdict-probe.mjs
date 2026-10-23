// Pedagogy review (2026-10-22): does Merc judge a student's step correctly?
// The live sessions showed CORRECT intermediate steps and answers being called
// wrong ("-2x = 6" checked by putting 6 in for x; "5 O2" read as 5 atoms;
// "w = 10" met with "but … what's 60 divided by 6?"). This probe sends short
// threads that end in a student step whose truth is known, and records the
// reply for a reader to score. Not part of the gate.
//
// Usage, against a LOCAL branch eval server only (never production):
//   node docs/prompt-batch/socratic-homework/review-pedagogy/verdict-probe.mjs http://localhost:3443 <out.json> [runs]
import { iosChatBody } from '../../../../scripts/eval-pacing.mjs';
import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';

const base = process.argv[2];
const out = process.argv[3];
const runs = Number(process.argv[4] || 3);
if (!base || !out) { console.error('usage: verdict-probe.mjs <LOCAL eval server url> <out.json> [runs]'); process.exit(2); }
if (!/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(base)) { console.error('refusing: base URL must be a local eval server'); process.exit(2); }

const GARDEN = "A rectangular garden's length is 3 m less than twice its width. The perimeter is 54 m. Find the length and width.";
// truth: is the student's LAST step right?
export const PROBES = [
  { id: 'neg-coef-step', truth: 'right', turns: ['solve 9 - 2x = 15', '-2x = 6'] },
  { id: 'neg-coef-step-2', truth: 'right', turns: ['solve 7 - 3x = 22', 'subtract 7 so -3x = 15'] },
  { id: 'both-sides-step', truth: 'right', turns: ['solve 5x + 12 = 2x - 3', '3x + 12 = -3'] },
  { id: 'distribute-step', truth: 'right', turns: ['solve 2(x + 5) = 3x + 4', '2x + 10 = 3x + 4'] },
  { id: 'fraction-step', truth: 'right', turns: ['solve x/4 - 3 = 2', 'x/4 = 5'] },
  { id: 'chem-full', truth: 'right', turns: ['balance C3H8 + O2 -> CO2 + H2O', 'C3H8 + 5O2 -> 3CO2 + 4H2O?'] },
  { id: 'chem-coef', truth: 'right', turns: ['balance CH4 + O2 -> CO2 + H2O', 'ok i have CH4 + O2 -> CO2 + 2H2O. is it 2 O2?'] },
  { id: 'word-final', truth: 'right', turns: [GARDEN, 'w is width so length is 2w - 3', '2(2w - 3) + 2w = 54 so 6w - 6 = 54 so w = 10'] },
  { id: 'neg-coef-wrong', truth: 'wrong', turns: ['solve 9 - 2x = 15', '-2x = 24'] },
  { id: 'neg-coef-wrong-2', truth: 'wrong', turns: ['solve 7 - 3x = 22', '-3x = 29?'] },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function chat(body) {
  const res = await fetch(`${base}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' }, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  let text = '';
  for (const line of (await res.text()).split('\n')) {
    if (!line.startsWith('data: ')) continue;
    let p; try { p = JSON.parse(line.slice(6)); } catch { continue; }
    if (p.type === 'delta') text += p.text;
    if (p.type === 'error') throw new Error(p.error || 'error frame');
  }
  return text;
}

// Merc's own earlier turns are generated live (not scripted), so only the
// LAST student turn is the probe; the reply to it is what gets judged.
async function runProbe(p, run) {
  const sessionId = `eval-review-vp-${randomBytes(8).toString('hex')}`;
  const visible = []; const replies = [];
  for (const u of p.turns) {
    visible.push({ role: 'user', content: u });
    let r;
    for (let a = 0; ; a++) { try { r = await chat(iosChatBody({ sessionId, visible, responseMode: 'concise' })); break; } catch (e) { if (a >= 3) throw e; console.error(`${p.id}: retry ${e.message}`); await sleep(6000); } }
    visible.push({ role: 'assistant', content: r }); replies.push(r);
    await sleep(2000);
  }
  const last = replies.at(-1).replace(/\*\*/g, '');
  // A rough first pass for the reader, NOT a verdict: "calls it wrong" =
  // a "not <n>" / ✗ / "slip" / "but" in the first two lines.
  const head = last.split('\n').filter(Boolean).slice(0, 2).join(' ');
  const callsWrong = /\bnot\s+[−-]?\d|✗|\bslip\b|\bisn['’]t right|\bnot quite|\bnot right|^\s*(?:close|almost)\b|\bbut if\b/i.test(head);
  const callsRight = /^(?:yes|right|correct|exactly|that['’]s (?:it|right|correct))\b|✓/i.test(head);
  return { run, id: p.id, truth: p.truth, callsWrong, callsRight, turns: p.turns.map((s, i) => ({ student: s, merc: replies[i] })) };
}

const jobs = [];
for (let run = 1; run <= runs; run++) for (const p of PROBES) jobs.push([p, run]);
const results = [];
let next = 0;
async function worker() {
  while (next < jobs.length) {
    const [p, run] = jobs[next++];
    try {
      const r = await runProbe(p, run);
      results.push(r);
      console.log(`run ${run} ${p.id} (${p.truth}): callsWrong=${r.callsWrong} callsRight=${r.callsRight}`);
    } catch (e) { console.error(`run ${run} ${p.id}: FAILED ${e.message}`); }
    await writeFile(out, JSON.stringify({ base, generatedAt: new Date().toISOString(), results }, null, 2));
  }
}
await Promise.all(Array.from({ length: Number(process.env.CONCURRENCY ?? 3) }, worker));
await writeFile(out, JSON.stringify({ base, generatedAt: new Date().toISOString(), results }, null, 2));
console.log('done');
