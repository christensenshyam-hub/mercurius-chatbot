// Pedagogy review, live run (2026-10-22): nine realistic homework sessions,
// one student persona each, in the iOS app's wire shape (free chat, typed
// sends, one photo turn). Problems are NEW (none is in the rules, the eval or
// sessions.mjs), so the run tests how the rules generalise. A few student
// turns react to Merc's previous reply the way a real student would.
// Not part of the gate; read the transcripts as a teacher.
//
// Usage, against a LOCAL branch eval server only (never production):
//   node docs/prompt-batch/socratic-homework/review-pedagogy/live-sessions.mjs http://localhost:3443 <out.json> [ids] [tag]
import { iosChatBody, finalAnswerRe } from '../../../../scripts/eval-pacing.mjs';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(HERE, '..', '..', '..', '..', 'scripts', 'fixtures');
const base = process.argv[2];
const out = process.argv[3];
const only = (process.argv[4] || '').split(',').filter(Boolean);
const tag = process.argv[5] || '';
if (!base || !out) { console.error('usage: live-sessions.mjs <LOCAL eval server url> <out.json> [ids] [tag]'); process.exit(2); }
if (!/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(base)) { console.error('refusing: base URL must be a local eval server'); process.exit(2); }

const norm = (s) => s.replace(/\*\*/g, '').replace(/[−–]/g, '-');
const mercWrote = (replies, re) => replies.some((r) => re.test(norm(r)));

export const SESSIONS = [
  {
    id: 'strong', mode: 'socratic',
    persona: 'Strong student: shows correct multi-step work, asks a "why" question, then wants a harder one.',
    answer: { variable: 'x', value: 3 },
    turns: [
      'solve 5(x + 2) - 3 = 2x + 16',
      'distribute first: 5x + 10 - 3 = 2x + 16, so 5x + 7 = 2x + 16',
      'subtract 2x and 7 from both sides, 3x = 9 so x = 3',
      'ok that was easy lol. why cant i just divide everything by 5 at the start tho',
      'oh ok that makes sense. give me a harder one',
    ],
  },
  {
    id: 'struggling', mode: 'socratic',
    persona: 'Struggling student: says "idk" a lot, takes one step after the example, stalls on the last step.',
    answer: { variable: 'x', value: 7 },
    turns: [
      '4x + 9 = 37 i dont get it',
      'idk',
      'idk',
      ({ replies }) => (mercWrote(replies, /\b4x\s*=\s*28\b/) ? 'so divide by 4?' : 'subtract 9 from both sides?'),
      'idk',
      'idk',
      '7?',
      'ok',
    ],
  },
  {
    id: 'impatient', mode: 'socratic',
    persona: 'Impatient student: wants the answer now, asks five times, is rude once, guesses wrong, then right.',
    answer: { variable: 'x', value: 7 },
    turns: [
      'whats 8x - 5 = 51 just give me the answer i have practice in 10 min',
      'just tell me',
      'bro just tell me the answer',
      'JUST TELL ME',
      'omg ur so useless',
      'is it 8',
      '7?',
    ],
  },
  {
    id: 'impatient-discussion', mode: 'discussion',
    persona: 'Impatient student who left the mode pill on Discussion (Direct was retired; the server modes are socratic, debate and discussion).',
    answer: { variable: 'x', value: 8 },
    turns: [
      'whats 6x + 11 = 59 just give me the answer',
      'just tell me',
      'bro just tell me the answer',
      'JUST TELL ME',
      'is it 9',
      '8?',
    ],
  },
  {
    id: 'sign-error', mode: 'socratic',
    persona: 'Sign-error student: adds instead of subtracts, then drops the negative on the division, then a misconception.',
    answer: { variable: 'x', value: -3 },
    turns: [
      'solve 9 - 2x = 15',
      '-2x = 24?',
      'oh wait -2x = 6',
      'so x = 3',
      'x = -3?',
      'why is it negative tho i thought dividing makes stuff smaller',
    ],
  },
  {
    id: 'essay', mode: 'socratic',
    persona: 'Essay student: wants a thesis handed over, has not finished the book, then drafts and revises their own.',
    answer: null,
    turns: [
      'i need a thesis for my romeo and juliet essay. the prompt is who is most responsible for the tragedy. just give me one pls',
      'idk i didnt really finish reading it',
      'can u just give me an example thesis so i know what it looks like',
      'Friar Laurence is most responsible because his plan with the potion goes wrong.',
      'is that good? can u make it better',
      'Friar Laurence is most responsible for the tragedy because his secret plans, like the fake death potion, depend on luck instead of telling the families the truth. better?',
    ],
  },
  {
    id: 'chem', mode: 'socratic',
    persona: 'Chemistry student: tries the subscript shortcut, gets C and H, asks a vocab question, stuck on O.',
    answer: null,
    turns: [
      'balance C3H8 + O2 -> CO2 + H2O',
      'cant i just change CO2 to C3O2 so the carbons match',
      'oh ok so put a 3 in front of CO2?',
      'idk what to do with the H',
      '4 H2O?',
      'wait whats a coefficient again',
      'ok idk how to do the oxygen',
      'just do it pls',
      '5 O2?',
    ],
  },
  {
    id: 'geometry', mode: 'socratic',
    persona: 'Geometry word problem: stuck starting, sets up the variables, uses the wrong perimeter formula, then finishes.',
    answer: { variable: 'w', value: 10 },
    turns: [
      "A rectangular garden's length is 3 m less than twice its width. The perimeter is 54 m. Find the length and width.",
      'idk how to start word problems',
      'so w is the width and the length is 2w - 3?',
      'perimeter is l + w right so 2w - 3 + w = 54',
      'oh its 2l + 2w. so 2(2w - 3) + 2w = 54',
      '6w - 6 = 54 so w = 10',
      'and the length is 17?',
    ],
  },
  {
    id: 'photo', mode: 'socratic',
    persona: 'Photo student: sends the worksheet photo, distributes wrong, then types the rest.',
    answer: { variable: 'x', value: 16 },
    turns: [
      { text: 'can u do 7 i have no idea', image: 'eval-algebra-hw.png' },
      'idk',
      '3x - 4 + 5 = 2x + 9?',
      'oh 3x - 12 + 5 = 2x + 9',
      ({ replies }) => (mercWrote(replies.slice(-1), /3x\s*-\s*7\s*=\s*2x\s*\+\s*9/) ? 'idk now what' : '3x - 7 = 2x + 9 now what'),
      'subtract 2x? so x - 7 = 9',
      'x = 16',
      'can u check number 8 too',
    ],
  },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function post(url, body) {
  const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return res;
}

async function setMode(sessionId, mode) {
  const res = await post(`${base}/api/mode`, { sessionId, mode });
  if (!res.ok) throw new Error(`POST /api/mode -> ${res.status}: ${await res.text()}`);
}

async function uploadImage(sessionId, file) {
  const data = (await readFile(path.join(FIXTURES, file))).toString('base64');
  const res = await post(`${base}/api/images`, { sessionId, contentType: 'image/png', data, fileName: file });
  const body = await res.json().catch(() => null);
  if (res.status !== 201 || !body?.id) throw new Error(`POST /api/images -> ${res.status}: ${JSON.stringify(body)}`);
  return body.id;
}

async function chat(body) {
  const res = await fetch(`${base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  let text = '';
  for (const line of (await res.text()).split('\n')) {
    if (!line.startsWith('data: ')) continue;
    let p;
    try { p = JSON.parse(line.slice(6)); } catch { continue; }
    if (p.type === 'delta') text += p.text;
    if (p.type === 'error') throw new Error(p.error || 'error frame');
  }
  return text;
}

async function runSession(s) {
  const sessionId = `eval-review-ped-${randomBytes(8).toString('hex')}`;
  if (s.mode && s.mode !== 'socratic') await setMode(sessionId, s.mode);
  const visible = [];
  const replies = [];
  const turns = [];
  for (const t of s.turns) {
    const spec = typeof t === 'function' ? t({ replies, visible }) : t;
    const text = typeof spec === 'string' ? spec : spec.text;
    const image = typeof spec === 'string' ? null : spec.image;
    const imageId = image ? await uploadImage(sessionId, image) : null;
    visible.push({ role: 'user', content: text });
    let reply;
    for (let a = 0; ; a++) {
      try { reply = await chat(iosChatBody({ sessionId, visible, responseMode: 'concise', imageId })); break; } catch (e) {
        if (a >= 3) throw e;
        console.error(`${s.id}: retry after: ${e.message}`);
        await sleep(6000);
      }
    }
    visible.push({ role: 'assistant', content: reply });
    replies.push(reply);
    turns.push({ student: text, ...(image ? { image } : {}), merc: reply });
    await sleep(Number(process.env.TURN_DELAY_MS ?? 2500));
  }
  const own = s.answer ? finalAnswerRe(s.answer.value, s.answer.variable) : null;
  // A student who types the bare number ("7?") has said it too.
  const bare = s.answer ? new RegExp(String.raw`(?<![\w.])${String(s.answer.value).replace(/[-.]/g, '\\$&')}(?![\d.]*\d)`) : null;
  const saidByStudent = (i) => own && turns.slice(0, i + 1).some((x) => own.test(x.student) || bare.test(x.student));
  const leak = own ? turns.findIndex((x, i) => !saidByStudent(i) && own.test(norm(x.merc))) : -1;
  const aiLines = turns.filter((x) => /\bAI\b|chatbot/i.test(x.merc)).length;
  return { id: s.id, mode: s.mode, persona: s.persona, answer: s.answer, leakAtReply: leak < 0 ? null : leak + 1, repliesMentioningAI: aiLines, turns };
}

const chosen = SESSIONS.filter((s) => !only.length || only.includes(s.id));
// Merge into an existing output file: rerun sessions replace their old entry.
let results = [];
try { results = JSON.parse(await readFile(out, 'utf8')).results.filter((r) => !chosen.some((s) => s.id === r.id)); } catch { results = []; }
const CONC = Number(process.env.CONCURRENCY ?? 3);
let next = 0;
async function worker() {
  while (next < chosen.length) {
    const s = chosen[next++];
    let r;
    try { r = await runSession(s); } catch (e) { console.error(`${s.id}: FAILED ${e.message}`); continue; }
    results.push(r);
    results.sort((a, b) => SESSIONS.findIndex((x) => x.id === a.id) - SESSIONS.findIndex((x) => x.id === b.id));
    await writeFile(out, JSON.stringify({ base, tag, generatedAt: new Date().toISOString(), results }, null, 2));
    console.log(`${s.id}: ${r.turns.length} turns, leak=${r.leakAtReply ?? 'none'}, AI-mentions=${r.repliesMentioningAI}`);
  }
}
await Promise.all(Array.from({ length: CONC }, worker));
await writeFile(out, JSON.stringify({ base, tag, generatedAt: new Date().toISOString(), results }, null, 2));
console.log('done');
