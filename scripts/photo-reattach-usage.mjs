#!/usr/bin/env node
/**
 * photo-reattach-usage.mjs — what photo re-attach (AUD-10) costs per turn,
 * measured on a LOCAL eval server against the real API.
 *
 * Usage:
 *   BASE_URL=http://localhost:3371 node scripts/photo-reattach-usage.mjs <image> [--out file.json]
 *
 * The server must run with EVAL_EXPOSE_USAGE=1 (the 'complete' frame then
 * carries the settled usage). BASE_URL must be localhost: this script never
 * talks to production.
 *
 * Two sessions, driven like iOS build 16 (capabilities blocks_v1, concise):
 *   A (photo):    turn 1 carries the photo's imageId; turns 2–4 are
 *                 follow-ups that send the thread as text, as every shipped
 *                 build does. The server re-attaches the photo to turn 1.
 *   B (baseline): the SAME wire threads as A (A's own replies included), from
 *                 a session that never uploaded anything, so nothing is
 *                 re-attached. Turn 1 is sent without the image.
 * A one-line warm-up call goes first so both sessions read the shared system
 * prompt from cache. Per turn, prompt tokens = input + cache read + cache
 * write. A − B is the
 * image's token count on that turn; the cost delta prices the input side
 * only (the two sessions' output lengths differ and are not the subject).
 */
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { costUsd } = require('../lib/pricing.js');

const BASE = process.env.BASE_URL || '';
if (!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(BASE)) {
  console.error('BASE_URL must be http://localhost:<port> (a local eval server).');
  process.exit(2);
}
const MODEL = 'claude-sonnet-4-6'; // server.js MODEL
const imagePath = process.argv[2];
if (!imagePath) {
  console.error('usage: BASE_URL=http://localhost:<port> node scripts/photo-reattach-usage.mjs <image> [--out file.json]');
  process.exit(2);
}
const outIdx = process.argv.indexOf('--out');
const outPath = outIdx > -1 ? process.argv[outIdx + 1] : null;

const TURNS = [
  'i got x = 16 for number 7, is that right?',
  'i plugged it in tho. 3(16-4)+5 = 41 and 2(16)+9 = 41',
  'ok and what does number 8 say again',
  "can you read me number 7 exactly as it's written on the sheet?",
];
const CAPS = ['blocks_v1'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sid = (tag) => `photo-usage-${tag}-${randomBytes(8).toString('hex')}`;

function contentTypeOf(file) {
  const ext = path.extname(file).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.webp') return 'image/webp';
  throw new Error(`unsupported image type: ${ext}`);
}

async function upload(sessionId, file) {
  const data = (await readFile(file)).toString('base64');
  const res = await fetch(`${BASE}/api/images`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, contentType: contentTypeOf(file), data, fileName: path.basename(file) }),
  });
  const body = await res.json();
  if (res.status !== 201) throw new Error(`upload ${res.status} ${JSON.stringify(body)}`);
  return body.id;
}

async function chat(sessionId, messages, imageId) {
  const body = { sessionId, messages, capabilities: CAPS, responseMode: 'concise' };
  if (imageId) body.imageId = imageId;
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  const frames = text.split('\n')
    .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
    .map((l) => { try { return JSON.parse(l.slice(6)); } catch { return null; } })
    .filter(Boolean);
  const complete = frames.find((f) => f.type === 'complete');
  if (!complete) throw new Error(`no complete frame (${res.status}): ${text.slice(0, 300)}`);
  if (!complete.usage) throw new Error('no usage on the complete frame: start the server with EVAL_EXPOSE_USAGE=1');
  return { reply: complete.reply, usage: complete.usage };
}

const promptTokens = (u) => (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
const inputCost = (u) => costUsd(MODEL, { ...u, output_tokens: 0 });

async function main() {
  const A = sid('a');
  const B = sid('b');
  const thread = [];
  const wires = [];
  const a = [];
  // Warm the shared system-prompt cache first, so turn 1 of A and of B both
  // read it and the turn-1 delta is the image, not who paid the cache write.
  await chat(sid('warm'), [{ role: 'user', content: 'hi' }]);
  await sleep(800);
  const imageId = await upload(A, imagePath);
  for (let k = 0; k < TURNS.length; k++) {
    thread.push({ role: 'user', content: TURNS[k] });
    const wire = thread.map((m) => ({ ...m }));
    wires.push(wire);
    const r = await chat(A, wire, k === 0 ? imageId : undefined);
    thread.push({ role: 'assistant', content: r.reply });
    a.push(r);
    process.stderr.write(`A turn ${k + 1}: ${JSON.stringify(r.usage)}\n`);
    await sleep(800);
  }
  const b = [];
  for (let k = 0; k < wires.length; k++) {
    const r = await chat(B, wires[k]);
    b.push(r);
    process.stderr.write(`B turn ${k + 1}: ${JSON.stringify(r.usage)}\n`);
    await sleep(800);
  }
  const rows = TURNS.map((turn, k) => {
    const ua = a[k].usage;
    const ub = b[k].usage;
    return {
      turn: k + 1,
      student: turn,
      photo: { usage: ua, promptTokens: promptTokens(ua), inputUsd: +inputCost(ua).toFixed(6), totalUsd: +costUsd(MODEL, ua).toFixed(6) },
      baseline: { usage: ub, promptTokens: promptTokens(ub), inputUsd: +inputCost(ub).toFixed(6) },
      imageTokens: promptTokens(ua) - promptTokens(ub),
      addedInputUsd: +(inputCost(ua) - inputCost(ub)).toFixed(6),
      reply: a[k].reply,
    };
  });
  const result = { base: BASE, image: path.basename(imagePath), model: MODEL, at: new Date().toISOString(), rows };
  console.log('turn | photo prompt tok (in / read / write) | baseline prompt tok | image tok | added input $');
  for (const r of rows) {
    const u = r.photo.usage;
    console.log(`${r.turn} | ${r.photo.promptTokens} (${u.input_tokens} / ${u.cache_read_input_tokens} / ${u.cache_creation_input_tokens}) | ${r.baseline.promptTokens} | ${r.imageTokens} | ${r.addedInputUsd}`);
  }
  const spent = a.concat(b).reduce((s, r) => s + costUsd(MODEL, r.usage), 0);
  console.log(`spent on this run: $${spent.toFixed(4)}`);
  result.spentUsd = +spent.toFixed(4);
  if (outPath) await writeFile(outPath, JSON.stringify(result, null, 2) + '\n');
}

main().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
