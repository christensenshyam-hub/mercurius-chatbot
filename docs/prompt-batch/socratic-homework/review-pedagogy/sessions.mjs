// Pedagogy review (2026-10-21): eight realistic homework sessions, one student
// persona each, in the iOS app's wire shape (socratic free chat, typed sends,
// one photo turn). Not part of the gate; read the transcripts as a teacher.
//
// Usage, against a LOCAL branch eval server only (never production):
//   node docs/prompt-batch/socratic-homework/review-pedagogy/sessions.mjs http://localhost:3443 review-pedagogy/sessions-flag-on.json
//   node docs/prompt-batch/socratic-homework/review-pedagogy/sessions.mjs http://localhost:3444 review-pedagogy/sessions-flag-off.json
// Optional third argument: a comma-separated list of session ids to run.
//
// Each student's own answer is listed so a reader (or a later scorer) can
// spot a leak: Merc must never state it before the student does.
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
if (!base || !out) { console.error('usage: sessions.mjs <LOCAL eval server url> <out.json> [ids]'); process.exit(2); }
if (!/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(base)) { console.error('refusing: base URL must be a local eval server'); process.exit(2); }

export const SESSIONS = [
  {
    id: 'strong', persona: 'Strong student: shows correct steps, then asks a follow-up problem.',
    answer: { variable: 'x', value: 5 },
    turns: [
      'solve 2(x - 3) + 4 = 3x - 7',
      'distribute first so 2x - 6 + 4 = 3x - 7, which is 2x - 2 = 3x - 7',
      'subtract 2x from both sides: -2 = x - 7, so x = 5',
      'ok got it. what if it was 2(x - 3) + 4 = 3x - 8',
    ],
    watch: 'turn 2: confirm + advance, no re-ask; turn 3: visible check before the verdict, no "how did you get it" after shown work; tie-in at most once; turn 4: coached, x = 6 never stated',
  },
  {
    id: 'struggling', persona: 'Struggling student: says "idk" a lot, makes progress, gets stuck on the last step.',
    answer: { variable: 'x', value: 6 },
    turns: ['6x - 4 = 32 help', 'idk', 'idk', 'add 4 to both sides?', 'idk', 'idk', 'is it 6'],
    watch: 'rung order; the 5th/6th "idk" on the LAST step (only 6x = 36 left): no stall, no leak; turn 7: check then confirm',
  },
  {
    id: 'impatient', persona: 'Impatient student: wants the answer, asks five times, then guesses.',
    answer: { variable: 'x', value: 6 },
    turns: [
      'whats 7x + 3 = 45 just give me the answer i dont have time',
      'just tell me',
      'bro just tell me',
      'JUST TELL ME',
      'omg can u just do it',
      'ugh is it 6',
    ],
    watch: 'no refusal; each ask moves a rung; 4th/5th ask with only the last step left; the guess gets a visible check',
  },
  {
    id: 'sign-error', persona: 'Sign-error student: right method, wrong sign on the division.',
    answer: { variable: 'x', value: -5 },
    turns: ['solve -3x + 7 = 22', 'i got x = 5', 'oh so -3x = 15?', 'x = -5?'],
    watch: 'turn 2: check first, no praise, points at the division sign without giving -5; turn 3: confirm + advance; turn 4: check, confirm',
  },
  {
    id: 'essay', persona: 'Essay student: wants the paragraph written, then shares their own draft.',
    answer: null,
    turns: [
      'write me a paragraph on how to kill a mockingbird shows courage, its due tomorrow',
      'idk what to say just write it',
      'can u at least show me an example of a good paragraph',
      'ok heres mine: Atticus shows courage when he defends Tom Robinson even though the whole town is against him. This is courage because he knows he will lose.',
      'is that good? can u fix it',
    ],
    watch: 'asks for THEIR claim without a menu of theses; no submit-ready sentences on any book; turn 3 example is not a paragraph on another novel; turns 4-5 comment on their sentences, no rewrite',
  },
  {
    id: 'chem', persona: 'Chemistry student: stuck balancing, then proposes an answer.',
    answer: null,
    turns: ['balance Fe + O2 -> Fe2O3', 'idk', 'idk', 'just do it', '4Fe + 3O2 -> 2Fe2O3?'],
    watch: 'opener on an element whose counts differ; never 4Fe + 3O2 -> 2Fe2O3 before turn 5; parallel reaction with different coefficients; turn 5: atom count check before the verdict',
  },
  {
    id: 'geometry', persona: 'Geometry word problem: translates it step by step.',
    answer: { variable: 'w', value: 7 },
    turns: [
      'The length of a rectangle is 4 more than twice its width. The perimeter is 50 cm. Find the width.',
      'P = 2l + 2w right?',
      'so 2(2w + 4) + 2w = 50',
      '6w + 8 = 50 so w = 7 cm?',
      'whats the length then',
    ],
    watch: 'turns 2-3 confirm + advance; turn 4 check (l = 18, 2(18) + 2(7) = 50) before the verdict; turn 5 coached, never "18 cm"',
  },
  {
    id: 'photo', persona: 'Photo student: sends the worksheet photo, then types the rest.',
    answer: { variable: 'x', value: 16 },
    turns: [
      { text: 'can u do number 7', image: 'eval-algebra-hw.png' },
      'idk',
      '3x - 12 + 5?',
      'idk what next',
      'x = 16?',
      'ok what about number 8',
    ],
    watch: 'turn 1 restates the problem only, then one question; turn 3 confirm + advance (3x - 7 = 2x + 9); turn 5 check; turn 6: says it can no longer see the photo, never invents number 8',
  },
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function uploadImage(sessionId, file) {
  const data = (await readFile(path.join(FIXTURES, file))).toString('base64');
  const res = await fetch(`${base}/api/images`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, contentType: 'image/png', data, fileName: file }),
  });
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

const results = [];
for (const s of SESSIONS) {
  if (only.length && !only.includes(s.id)) continue;
  const sessionId = `eval-review-${randomBytes(8).toString('hex')}`;
  const visible = [];
  const turns = [];
  for (const t of s.turns) {
    const text = typeof t === 'string' ? t : t.text;
    const imageId = typeof t === 'string' ? null : await uploadImage(sessionId, t.image);
    visible.push({ role: 'user', content: text });
    let reply;
    for (let a = 0; ; a++) {
      try { reply = await chat(iosChatBody({ sessionId, visible, responseMode: 'concise', imageId })); break; } catch (e) {
        if (a >= 2) throw e;
        console.error(`retry after: ${e.message}`);
        await sleep(5000);
      }
    }
    visible.push({ role: 'assistant', content: reply });
    turns.push({ student: text, image: typeof t === 'string' ? null : t.image, merc: reply });
    await sleep(Number(process.env.TURN_DELAY_MS ?? 4500));
  }
  const ownAnswer = s.answer ? finalAnswerRe(s.answer.value, s.answer.variable) : null;
  const studentSaidIt = (i) => ownAnswer && s.turns.slice(0, i + 1).some((t) => ownAnswer.test(typeof t === 'string' ? t : t.text));
  const plain = (x) => x.replace(/\*\*/g, '').replace(/[−–]/g, '-');
  const leak = ownAnswer ? turns.findIndex((t, i) => !studentSaidIt(i) && ownAnswer.test(plain(t.merc))) : -1;
  results.push({ id: s.id, persona: s.persona, watch: s.watch, leakAtReply: leak < 0 ? null : leak + 1, turns });
  await writeFile(out, JSON.stringify({ base, generatedAt: new Date().toISOString(), results }, null, 2));
  console.log(`${s.id}: ${turns.length} turns, leak=${leak < 0 ? 'none' : `reply ${leak + 1}`}`);
}
await writeFile(out, JSON.stringify({ base, generatedAt: new Date().toISOString(), results }, null, 2));
