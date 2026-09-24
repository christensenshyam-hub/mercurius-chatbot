#!/usr/bin/env node
/**
 * load-rehearsal.mjs — pre-kickoff load rehearsal for the Mercurius server.
 *
 * Boots `server.js` the way production runs it — the documented limits from
 * `.env.example`, verbatim, nothing loosened — but with the in-process
 * Anthropic mock (`ANTHROPIC_MOCK=1`, no key, no spend) on a throwaway SQLite
 * file, then throws the day-one traffic shapes at it and prints a verdict
 * table. Every scenario is a question the kickoff is going to ask for real:
 *
 *   1. Classroom        30 students behind ONE school NAT each run a 5-turn
 *                       lesson at the same time. Zero refusals, every stream
 *                       ends with a `complete` frame. (30 × 5 = 150 is exactly
 *                       CHAT_IP_PER_MIN — the scenario also measures the
 *                       headroom left in that minute.)
 *   2. Hostile session  one session fires 40 chat turns at once; the
 *                       per-session minute limit (SESSION_PER_MIN) refuses the
 *                       overflow with the documented 429 rate_limited shape and
 *                       the server stays healthy.
 *   3. Hostile rotation one IP mints 80 fresh session ids; the per-IP daily
 *                       new-session cap (IP_DAILY_NEW_SESSIONS) trips with the
 *                       documented 429 daily_limit / scope ip shape.
 *   4. Spike            200 first turns from 200 distinct IPs at once; beyond
 *                       MAX_INFLIGHT the rest are refused 503 busy, every
 *                       request is answered, health stays 200.
 *   5. Drain            10 lesson streams are open when the server gets
 *                       SIGTERM (what every Railway deploy sends): the streams
 *                       finish, /api/health reports 503 draining, new
 *                       connections are refused, the process exits 0 inside
 *                       DRAIN_TIMEOUT_MS.
 *
 * Exit status is non-zero only when Classroom or Drain fails (or the server
 * crashes) — those are the two that would wreck a real class. The hostile
 * scenarios print FAIL loudly but are informational.
 *
 * Usage:
 *   npm run load-rehearsal                       # the five mock scenarios
 *   node scripts/load-rehearsal.mjs --delay 80   # slower mock streams
 *   node scripts/load-rehearsal.mjs --real --concurrency 10
 *       # NO mock: spawns the server with the real ANTHROPIC_API_KEY (from the
 *       # environment or ./.env) and streams ONE real curriculum first turn
 *       # from N concurrent sessions. Costs real money (cents). Runs only
 *       # this smoke — never the hostile/drain scenarios.
 *   node scripts/load-rehearsal.mjs --real --concurrency 10 --base https://host
 *       # same smoke against an already-running server (nothing is spawned)
 *
 * Flags:
 *   --delay <ms>        MOCK_STREAM_DELAY_MS for the spawned mock server
 *                       (default 40: a lesson turn streams for ~1.4 s, long
 *                       enough for streams to overlap and for SIGTERM to land
 *                       mid-stream; keep it >= 20)
 *   --real              real upstream smoke (see above)
 *   --concurrency <n>   sessions in the real smoke (default 10; the per-IP
 *                       in-flight cap is 40, so stay at or below that)
 *   --base <url>        target an existing server instead of spawning one
 *                       (real smoke only — the mock scenarios need to own the
 *                       process to send it SIGTERM)
 *
 * No new dependencies: global fetch, node:net, node:child_process.
 */

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// Production defaults — verbatim from .env.example. They are set EXPLICITLY on
// the child so neither the operator's shell (an eval run exports
// IP_DAILY_NEW_SESSIONS=1000) nor a local ./.env (dotenv fills only unset
// variables) can loosen what the rehearsal proves.
// ---------------------------------------------------------------------------
const PROD_LIMITS = Object.freeze({
  API_IP_PER_MIN: 400,
  CHAT_IP_PER_MIN: 150,
  UPLOAD_IP_PER_MIN: 60,
  REPORT_IP_PER_MIN: 60,
  SESSION_PER_MIN: 10,
  SESSION_DAILY_LESSON_TURNS: 40,
  SESSION_DAILY_CHAT_TURNS: 60,
  SESSION_DAILY_USD: 0.75,
  SESSION_DAILY_IMAGES: 20,
  IP_DAILY_USD: 10,
  IP_DAILY_NEW_SESSIONS: 60,
  IP_DAILY_IMAGES: 200,
  IP_DAILY_IMAGE_BYTES: 524288000,
  IP_MAX_INFLIGHT: 40,
  MAX_INFLIGHT: 80,
  DAILY_BUDGET_USD: 15,
  DRAIN_TIMEOUT_MS: 30000,
});

// Scenario sizes. Each scenario gets its own forwarded-for address so the
// per-IP state of one never bleeds into another (`trust proxy` is 1, so the
// X-Forwarded-For header IS the client IP to the server).
const CLASSROOM_STUDENTS = 30;
const LESSON_TURNS = 5;
const HOSTILE_TURNS = 40;
const ROTATION_SESSIONS = 80;
const SPIKE_CLIENTS = 200;
const DRAIN_STREAMS = 10;

const IPS = Object.freeze({
  health: '10.99.0.1',
  classroom: '10.1.0.1',
  hostileSession: '10.2.0.1',
  rotation: '10.3.0.1',
  drain: '10.5.0.1',
  spike: (i) => `10.7.${Math.floor(i / 250)}.${(i % 250) + 1}`,
});

// A real lesson thread: the iOS opener tag, then four student follow-ups. The
// mock emits [LESSON_COMPLETE] on the fifth user turn, so a full run also
// proves the lesson-outcome path under load.
const OPENER = '[CURRICULUM: Unit 1, Lesson 1] Explain what a language model is and give me an exercise.';
const FOLLOW_UPS = [
  'I think it predicts the next word from patterns it learned.',
  'So it does not look anything up — it guesses from its training data?',
  'An example would be the autocomplete on my phone keyboard.',
  'It would break if the input was about something missing from the training data.',
];
const FIRST_TURN = 'What is a language model, really?';

// SSE refusal frames carry the code the JSON path would put next to its HTTP
// status; map them back so the table has one vocabulary.
const CODE_STATUS = Object.freeze({
  daily_limit: 429,
  rate_limited: 429,
  busy: 503,
  spend_cap: 503,
  service_disabled: 503,
  restarting: 503,
});

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const opts = { real: false, concurrency: 10, base: null, delay: 40, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--real') opts.real = true;
    else if (a === '--concurrency') opts.concurrency = Number(argv[++i]);
    else if (a === '--base') opts.base = String(argv[++i] || '').replace(/\/+$/, '');
    else if (a === '--delay') opts.delay = Number(argv[++i]);
    else if (a === '--help' || a === '-h') opts.help = true;
    else throw new Error(`unknown argument: ${a} (try --help)`);
  }
  if (!Number.isInteger(opts.concurrency) || opts.concurrency < 1) throw new Error('--concurrency must be a positive integer');
  if (!Number.isFinite(opts.delay) || opts.delay < 1) throw new Error('--delay must be a positive number of milliseconds');
  if (opts.base && !opts.real) throw new Error('--base is only for the real smoke (--real): the mock scenarios must own the server process');
  return opts;
}

function usage() {
  return [
    'Usage: node scripts/load-rehearsal.mjs [--delay <ms>]',
    '       node scripts/load-rehearsal.mjs --real [--concurrency <n>] [--base <url>]',
    '',
    'Mock rehearsal (default): spawns server.js with ANTHROPIC_MOCK=1 and the',
    'production-default limits, runs Classroom / Hostile session / Hostile',
    'rotation / Spike / Drain, prints a verdict table. Exit 1 if Classroom or',
    'Drain fails. See docs/LOAD_REHEARSAL.md.',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
const sid = () => 'sess_' + randomBytes(8).toString('hex');
const now = () => performance.now();
const round = (n) => Math.round(n);

function percentile(sortedMs, p) {
  if (!sortedMs.length) return 0;
  const i = Math.min(sortedMs.length - 1, Math.max(0, Math.ceil(p * sortedMs.length) - 1));
  return sortedMs[i];
}

async function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} exceeded its ${ms} ms budget`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// ---------------------------------------------------------------------------
// HTTP client — one chat request, classified into the table's vocabulary:
//   '200'                a served turn (JSON reply, or an SSE stream that
//                        ended with a `complete` frame AND [DONE])
//   '429:<code>'         a refusal with that code (JSON status, or the SSE
//                        error frame's code mapped through CODE_STATUS)
//   '503:<code>'
//   'other:<what>'       anything else — 500s, truncated streams, timeouts,
//                        socket errors. Never expected; always reported.
// ---------------------------------------------------------------------------
async function chatRequest({ base, ip, sessionId, messages, stream = true, onFirstDelta = null, timeoutMs = 60000 }) {
  const started = now();
  const headers = { 'Content-Type': 'application/json' };
  if (stream) headers.Accept = 'text/event-stream';
  if (ip) headers['X-Forwarded-For'] = ip;
  const out = { kind: 'other:unknown', ms: 0, ttfbMs: null, status: null, body: null, events: [], done: false, complete: null, retryAfter: null };
  try {
    const res = await fetch(`${base}/api/chat`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ sessionId, messages }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    out.status = res.status;
    out.retryAfter = res.headers.get('retry-after');
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('text/event-stream')) {
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let raw = '';
      let firstDelta = false;
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        raw += decoder.decode(value, { stream: true });
        if (!firstDelta && raw.includes('"type":"delta"')) {
          firstDelta = true;
          out.ttfbMs = now() - started;
          if (onFirstDelta) onFirstDelta();
        }
      }
      const frames = raw.split('\n').filter((l) => l.startsWith('data: ')).map((l) => l.slice(6));
      out.done = frames.includes('[DONE]');
      out.events = frames.filter((f) => f !== '[DONE]').map((f) => {
        try { return JSON.parse(f); } catch { return { type: 'unparseable', raw: f }; }
      });
      const complete = out.events.find((e) => e.type === 'complete');
      const error = out.events.find((e) => e.type === 'error');
      if (complete && out.done) {
        out.kind = '200';
        out.complete = complete;
      } else if (error) {
        out.body = error;
        const status = CODE_STATUS[error.code];
        out.kind = status ? `${status}:${error.code}` : `other:sse_error:${error.code || 'no_code'}`;
      } else {
        out.kind = 'other:truncated_stream';
      }
    } else {
      const text = await res.text();
      try { out.body = JSON.parse(text); } catch { out.body = null; }
      if (res.status === 200) {
        out.kind = out.body && typeof out.body.reply === 'string' ? '200' : 'other:200_without_reply';
      } else {
        out.kind = `${res.status}:${(out.body && out.body.error) || 'no_error_field'}`;
      }
    }
  } catch (err) {
    const code = (err && err.cause && err.cause.code) || (err && err.name) || 'fetch_failed';
    out.kind = `other:${code}`;
  }
  out.ms = now() - started;
  return out;
}

async function health(base) {
  try {
    const res = await fetch(`${base}/api/health`, { headers: { 'X-Forwarded-For': IPS.health }, signal: AbortSignal.timeout(5000) });
    const json = await res.json().catch(() => null);
    return { status: res.status, json };
  } catch (err) {
    return { status: 'refused', code: (err && err.cause && err.cause.code) || (err && err.name) };
  }
}

// A health probe on a brand-new TCP connection (no pooling) — during a drain
// the listener is closed, so this is the "what does the platform see" probe.
function freshHealth(port) {
  return new Promise((resolve) => {
    const req = http.request(
      { host: '127.0.0.1', port, path: '/api/health', method: 'GET', agent: false, headers: { 'X-Forwarded-For': IPS.health } },
      (res) => {
        let body = '';
        res.on('data', (d) => { body += d; });
        res.on('end', () => {
          let json = null;
          try { json = JSON.parse(body); } catch { /* not json */ }
          resolve({ status: res.statusCode, json });
        });
      },
    );
    req.setTimeout(3000, () => { req.destroy(new Error('timeout')); });
    req.on('error', (err) => resolve({ status: 'refused', code: err.code || err.message }));
    req.end();
  });
}

// A health probe whose request is opened BEFORE the drain and completed
// DURING it. On SIGTERM the server flips `draining` and calls server.close()
// plus closeIdleConnections() in the same tick, so a probe on a new
// connection is refused before it can ever see the 503. A connection whose
// request line has been parsed but whose headers are not yet complete is
// active, not idle: it survives, and finishing it while the streams drain
// observes the 503 the health route really answers.
async function openHeldHealthProbe(port) {
  const sock = net.connect({ port, host: '127.0.0.1' });
  await once(sock, 'connect');
  sock.setNoDelay(true);
  sock.write(`GET /api/health HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nX-Forwarded-For: ${IPS.health}\r\nConnection: close\r\n`);
  let buf = '';
  sock.on('data', (d) => { buf += d.toString(); });
  const closed = new Promise((resolve) => {
    sock.on('close', resolve);
    sock.on('error', resolve);
  });
  return {
    async finish(timeoutMs = 5000) {
      sock.write('\r\n');
      await Promise.race([closed, sleep(timeoutMs)]);
      sock.destroy();
      const [head = '', body = ''] = buf.split('\r\n\r\n');
      const status = Number((head.split('\r\n')[0] || '').split(' ')[1]) || null;
      let json = null;
      const m = body.match(/\{[\s\S]*\}/);
      if (m) { try { json = JSON.parse(m[0]); } catch { /* not json */ } }
      return { status, json };
    },
  };
}

// ---------------------------------------------------------------------------
// Server process
// ---------------------------------------------------------------------------
function hasRealKey() {
  const fromEnv = process.env.ANTHROPIC_API_KEY;
  if (fromEnv && fromEnv.startsWith('sk-')) return true;
  try {
    const dotenv = fs.readFileSync(path.join(ROOT, '.env'), 'utf8');
    const m = dotenv.match(/^\s*ANTHROPIC_API_KEY\s*=\s*"?(sk-[^\s"]+)/m);
    return Boolean(m);
  } catch {
    return false;
  }
}

async function spawnServer({ real, delay, tmpDir }) {
  const port = await freePort();
  const dbPath = path.join(tmpDir, 'rehearsal.db');
  const logPath = path.join(tmpDir, 'server.log');
  const log = fs.createWriteStream(logPath);

  const limitsEnv = {};
  for (const [k, v] of Object.entries(PROD_LIMITS)) limitsEnv[k] = String(v);

  const env = {
    ...process.env,
    ...limitsEnv,
    PORT: String(port),
    NODE_ENV: 'development',
    SQLITE_PATH: dbPath,
    DATABASE_URL: '',            // never a shared Postgres — the rehearsal mints hundreds of sessions
    SCHEDULER_ENABLED: '0',
    DISCORD_WEBHOOK_URL: '',
    ADMIN_PASSWORD: randomBytes(12).toString('hex'),
    CLAUDE_DISABLED: 'false',
    MOCK_SCENARIO: 'ok',
    LOG_LEVEL: process.env.LOAD_REHEARSAL_LOG_LEVEL || 'warn',
  };
  if (real) {
    env.ANTHROPIC_MOCK = '0';
    delete env.MOCK_STREAM_DELAY_MS;
  } else {
    env.ANTHROPIC_MOCK = '1';
    env.ANTHROPIC_API_KEY = '';
    env.MOCK_STREAM_DELAY_MS = String(delay);
  }

  const proc = spawn(process.execPath, ['server.js'], { cwd: ROOT, env, stdio: ['ignore', 'pipe', 'pipe'] });
  const stderrTail = [];
  proc.stdout.pipe(log, { end: false });
  proc.stderr.on('data', (chunk) => {
    log.write(chunk);
    for (const line of chunk.toString().split('\n')) {
      if (!line.trim()) continue;
      stderrTail.push(line);
      if (stderrTail.length > 40) stderrTail.shift();
    }
  });

  const server = {
    proc,
    port,
    base: `http://127.0.0.1:${port}`,
    dbPath,
    logPath,
    exited: null,
    exitPromise: null,
    stderrTail,
    limits: PROD_LIMITS,
  };
  server.exitPromise = new Promise((resolve) => {
    proc.on('exit', (code, signal) => {
      server.exited = { code, signal, at: now() };
      log.end();
      resolve(server.exited);
    });
  });

  const deadline = now() + 20000;
  while (now() < deadline) {
    if (server.exited) throw new Error(`server exited during boot (code ${server.exited.code}, signal ${server.exited.signal})\n${stderrTail.join('\n')}`);
    const h = await health(server.base);
    if (h.status === 200) return server;
    await sleep(100);
  }
  throw new Error(`server did not answer /api/health within 20 s\n${stderrTail.join('\n')}`);
}

async function stopServer(server) {
  if (!server || server.exited) return;
  server.proc.kill('SIGTERM');
  await Promise.race([server.exitPromise, sleep(PROD_LIMITS.DRAIN_TIMEOUT_MS + 5000)]);
  if (!server.exited) server.proc.kill('SIGKILL');
}

// ---------------------------------------------------------------------------
// Scenarios — each returns { name, results, verdict, notes, gate }
// ---------------------------------------------------------------------------
const refusalShapeOk = (r) => {
  const b = r.body || {};
  return typeof b.error === 'string' && b.error.length > 0
    && typeof (b.message || b.reply || b.error) === 'string';
};

async function scenarioClassroom(ctx) {
  const { base } = ctx;
  const ip = IPS.classroom;
  const results = [];
  const notes = [];
  const t0 = now();
  let lessonsCompleted = 0;
  let firstIssue = null;

  const students = Array.from({ length: CLASSROOM_STUDENTS }, () => ({ id: sid(), thread: [] }));
  await Promise.all(students.map(async (s) => {
    const turns = [OPENER, ...FOLLOW_UPS].slice(0, LESSON_TURNS);
    for (let t = 0; t < turns.length; t++) {
      s.thread.push({ role: 'user', content: turns[t] });
      const r = await chatRequest({ base, ip, sessionId: s.id, messages: s.thread, stream: true });
      r.turn = t + 1;
      results.push(r);
      if (r.kind !== '200') {
        // The student's lesson is over: a refused turn has no assistant reply
        // to append, and the next turn would be two user messages in a row.
        if (!firstIssue) firstIssue = `turn ${t + 1} of session ${s.id} → ${r.kind}`;
        break;
      }
      s.thread.push({ role: 'assistant', content: r.complete.reply });
      if (r.complete.lessonComplete) lessonsCompleted += 1;
    }
  }));
  const elapsedMs = now() - t0;

  const expected = CLASSROOM_STUDENTS * LESSON_TURNS;
  const refused = results.filter((r) => r.kind !== '200');
  const verdict = refused.length === 0 && results.length === expected ? 'PASS' : 'FAIL';
  notes.push(`${results.length}/${expected} turns served in ${(elapsedMs / 1000).toFixed(1)} s; lessons reaching [LESSON_COMPLETE] on turn ${LESSON_TURNS}: ${lessonsCompleted}/${CLASSROOM_STUDENTS}`);
  if (firstIssue) notes.push(`first non-200: ${firstIssue}`);

  // Headroom: 30 × 5 = 150 is exactly CHAT_IP_PER_MIN. One more /api/chat
  // from the same NAT inside the limiter window shows what a retry, a sixth
  // turn, or a quiz call would get. (The window is 60 s, aligned to server
  // boot, so if the classroom straddled a reset this probe can pass.)
  const s0 = students[0];
  const probe = await chatRequest({
    base, ip, sessionId: s0.id,
    messages: [...s0.thread, { role: 'user', content: 'One more question before the bell.' }],
    stream: false,
  });
  notes.push(`CHAT_IP_PER_MIN headroom: request #${expected + 1} from the classroom NAT inside the same minute → ${probe.kind} (limit ${ctx.limits.CHAT_IP_PER_MIN} = ${CLASSROOM_STUDENTS} students × ${LESSON_TURNS} turns exactly)`);

  return { name: `Classroom (${CLASSROOM_STUDENTS} sessions × ${LESSON_TURNS}-turn lesson, one NAT)`, results, verdict, notes, gate: true };
}

async function scenarioHostileSession(ctx) {
  const { base } = ctx;
  const ip = IPS.hostileSession;
  const sessionId = sid();
  const notes = [];
  const results = await Promise.all(Array.from({ length: HOSTILE_TURNS }, (_, i) => chatRequest({
    base, ip, sessionId,
    messages: [{ role: 'user', content: `Question ${i + 1}: what is a token?` }],
    stream: false,
  })));
  const served = results.filter((r) => r.kind === '200');
  const limited = results.filter((r) => r.kind === '429:rate_limited');
  const unexpected = results.filter((r) => r.kind !== '200' && r.kind !== '429:rate_limited');
  const badShape = limited.filter((r) => !refusalShapeOk(r));
  const h = await health(base);
  const alive = !ctx.server.exited;

  const ok = unexpected.length === 0
    && served.length <= ctx.limits.SESSION_PER_MIN
    && limited.length >= HOSTILE_TURNS - ctx.limits.SESSION_PER_MIN
    && badShape.length === 0
    && h.status === 200
    && alive;
  notes.push(`served ${served.length} (SESSION_PER_MIN ${ctx.limits.SESSION_PER_MIN}), refused ${limited.length} as 429 {error:"rate_limited"}; health after: ${h.status}; process alive: ${alive}`);
  if (limited[0]) notes.push(`refusal body: ${JSON.stringify(limited[0].body)}`);
  if (unexpected.length) notes.push(`unexpected: ${[...new Set(unexpected.map((r) => r.kind))].join(', ')}`);
  return { name: `Hostile session (${HOSTILE_TURNS} turns at once, one session)`, results, verdict: ok ? 'PASS' : 'FAIL', notes, gate: false };
}

async function scenarioHostileRotation(ctx) {
  const { base } = ctx;
  const ip = IPS.rotation;
  const notes = [];
  const results = [];
  // Sequential on purpose: one script rotating ids sends one turn at a time,
  // and the answer must be exact — the 61st fresh id is the first refused.
  for (let i = 0; i < ROTATION_SESSIONS; i++) {
    results.push(await chatRequest({
      base, ip, sessionId: sid(),
      messages: [{ role: 'user', content: 'Hi — what is AI?' }],
      stream: false,
    }));
  }
  const cap = ctx.limits.IP_DAILY_NEW_SESSIONS;
  const firstRefused = results.findIndex((r) => r.kind !== '200');
  const before = results.slice(0, cap);
  const after = results.slice(cap);
  const capHeld = before.every((r) => r.kind === '200') && after.length > 0 && after.every((r) => r.kind === '429:daily_limit');
  const shapeOk = after.every((r) => refusalShapeOk(r) && r.body.scope === 'ip' && Number(r.body.retryAfterSec) > 0 && r.retryAfter);
  const h = await health(base);
  const ok = capHeld && shapeOk && h.status === 200 && !ctx.server.exited;
  notes.push(`first refusal at fresh session #${firstRefused + 1} (IP_DAILY_NEW_SESSIONS ${cap}); ${after.filter((r) => r.kind === '429:daily_limit').length}/${after.length} beyond the cap refused 429 {error:"daily_limit", scope:"ip"}; health after: ${h.status}`);
  if (after[0]) notes.push(`refusal body: ${JSON.stringify(after[0].body)} Retry-After: ${after[0].retryAfter}`);
  return { name: `Hostile rotation (${ROTATION_SESSIONS} fresh session ids, one IP)`, results, verdict: ok ? 'PASS' : 'FAIL', notes, gate: false };
}

async function scenarioSpike(ctx) {
  const { base } = ctx;
  const notes = [];
  const results = await Promise.all(Array.from({ length: SPIKE_CLIENTS }, (_, i) => chatRequest({
    base, ip: IPS.spike(i), sessionId: sid(),
    messages: [{ role: 'user', content: FIRST_TURN }],
    stream: true,
  })));
  const served = results.filter((r) => r.kind === '200');
  const busy = results.filter((r) => r.kind === '503:busy');
  const unexpected = results.filter((r) => r.kind !== '200' && r.kind !== '503:busy');
  const h = await health(base);
  const ok = unexpected.length === 0 && h.status === 200 && !ctx.server.exited;
  notes.push(`served ${served.length}, refused ${busy.length} as busy (MAX_INFLIGHT ${ctx.limits.MAX_INFLIGHT}); every request answered: ${unexpected.length === 0}; health after: ${h.status}`);
  if (busy.length === 0) notes.push('in-flight never reached MAX_INFLIGHT — streams finished faster than requests arrived; raise --delay to reproduce the cap');
  if (busy[0]) notes.push(`busy frame: ${JSON.stringify(busy[0].body)}`);
  if (unexpected.length) notes.push(`unexpected: ${[...new Set(unexpected.map((r) => r.kind))].join(', ')}`);
  return { name: `Spike (${SPIKE_CLIENTS} first turns, ${SPIKE_CLIENTS} IPs at once)`, results, verdict: ok ? 'PASS' : 'FAIL', notes, gate: false };
}

async function scenarioDrain(ctx) {
  const { base, server } = ctx;
  const ip = IPS.drain;
  const notes = [];
  const drainMs = ctx.limits.DRAIN_TIMEOUT_MS;

  const streams = [];
  const firstDeltas = [];
  for (let i = 0; i < DRAIN_STREAMS; i++) {
    let fire;
    firstDeltas.push(new Promise((resolve) => { fire = resolve; }));
    streams.push(chatRequest({
      base, ip, sessionId: sid(),
      messages: [{ role: 'user', content: OPENER }],
      stream: true, onFirstDelta: fire,
      timeoutMs: drainMs + 10000,
    }));
  }
  // Mid-stream = every stream has delivered at least one delta (a refused
  // stream never will; racing against its own completion keeps this bounded).
  await Promise.all(firstDeltas.map((p, i) => Promise.race([p, streams[i]])));

  const held = await openHeldHealthProbe(server.port);
  await sleep(50);
  const t0 = now();
  server.proc.kill('SIGTERM');
  await sleep(150);
  const heldResult = await held.finish();

  // From here the process is draining: what does a NEW connection see?
  const fresh = [];
  const poller = (async () => {
    while (!server.exited && fresh.length < 200) {
      fresh.push(await freshHealth(server.port));
      await sleep(100);
    }
  })();

  const results = await Promise.all(streams);
  const exit = await Promise.race([server.exitPromise, sleep(drainMs + 5000).then(() => null)]);
  const exitMs = now() - t0;
  await poller;

  const finished = results.filter((r) => r.kind === '200');
  const heldOk = heldResult.status === 503 && heldResult.json && heldResult.json.status === 'draining';
  const fresh200 = fresh.filter((p) => p.status === 200);
  const exitOk = exit && exit.code === 0 && exitMs <= drainMs;
  const ok = finished.length === DRAIN_STREAMS && heldOk && fresh200.length === 0 && exitOk;

  notes.push(`${finished.length}/${DRAIN_STREAMS} streams open at SIGTERM finished with complete + [DONE]`);
  notes.push(`/api/health during drain (request opened before SIGTERM): ${heldResult.status} ${JSON.stringify(heldResult.json)}`);
  const freshKinds = {};
  for (const p of fresh) { const k = p.status === 'refused' ? `refused (${p.code})` : String(p.status); freshKinds[k] = (freshKinds[k] || 0) + 1; }
  notes.push(`/api/health on new connections during drain: ${Object.entries(freshKinds).map(([k, n]) => `${n} × ${k}`).join(', ') || 'none sampled'} — server.close() runs in the same tick as draining=true`);
  notes.push(`process exit: ${exit ? `code ${exit.code}${exit.signal ? ` signal ${exit.signal}` : ''}` : 'NOT within budget'} after ${round(exitMs)} ms (DRAIN_TIMEOUT_MS ${drainMs})`);
  if (!exitOk && !exit) {
    server.proc.kill('SIGKILL');
  }
  return { name: `Drain (${DRAIN_STREAMS} lesson streams open, SIGTERM mid-stream)`, results, verdict: ok ? 'PASS' : 'FAIL', notes, gate: true };
}

async function scenarioRealSmoke(ctx, concurrency) {
  const { base } = ctx;
  const notes = [];
  if (concurrency > PROD_LIMITS.IP_MAX_INFLIGHT) notes.push(`WARNING: ${concurrency} concurrent streams from one IP exceeds IP_MAX_INFLIGHT ${PROD_LIMITS.IP_MAX_INFLIGHT} — expect busy refusals`);
  const t0 = now();
  const results = await Promise.all(Array.from({ length: concurrency }, () => chatRequest({
    base, ip: null, sessionId: sid(),
    messages: [{ role: 'user', content: OPENER }],
    stream: true, timeoutMs: 180000,
  })));
  const served = results.filter((r) => r.kind === '200');
  const ttfb = served.map((r) => r.ttfbMs).filter((n) => n != null).sort((a, b) => a - b);
  const ok = served.length === concurrency;
  notes.push(`${served.length}/${concurrency} real first turns streamed to complete in ${((now() - t0) / 1000).toFixed(1)} s; time to first delta p50 ${round(percentile(ttfb, 0.5))} ms / p95 ${round(percentile(ttfb, 0.95))} ms`);
  if (served[0]) notes.push(`sample reply: ${JSON.stringify(String(served[0].complete.reply).slice(0, 120))}…`);
  const failures = results.filter((r) => r.kind !== '200');
  if (failures.length) notes.push(`non-200: ${[...new Set(failures.map((r) => r.kind))].join(', ')}`);
  return { name: `Real smoke (${concurrency} concurrent real first turns)`, results, verdict: ok ? 'PASS' : 'FAIL', notes, gate: true };
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------
function summarize(results) {
  const counts = { ok: 0, 429: {}, 503: {}, other: {} };
  for (const r of results) {
    if (r.kind === '200') { counts.ok += 1; continue; }
    const [status, ...rest] = r.kind.split(':');
    const code = rest.join(':') || status;
    const bucket = status === '429' ? counts[429] : status === '503' ? counts[503] : counts.other;
    const key = status === '429' || status === '503' ? code : r.kind;
    bucket[key] = (bucket[key] || 0) + 1;
  }
  const ms = results.map((r) => r.ms).sort((a, b) => a - b);
  return { n: results.length, counts, p50: percentile(ms, 0.5), p95: percentile(ms, 0.95) };
}

const fmtCodes = (obj) => Object.entries(obj).map(([code, n]) => `${n} ${code}`).join(', ') || '-';

function renderTable(rows) {
  const header = ['Scenario', 'Requests', '200', '429 (by code)', '503 (by code)', 'Other', 'p50 / p95 ms', 'Verdict'];
  const lines = rows.map((row) => {
    const s = summarize(row.results);
    return [
      row.name,
      String(s.n),
      String(s.counts.ok),
      fmtCodes(s.counts[429]),
      fmtCodes(s.counts[503]),
      fmtCodes(s.counts.other),
      `${round(s.p50)} / ${round(s.p95)}`,
      row.verdict,
    ];
  });
  const all = [header, ...lines];
  const widths = header.map((_, c) => Math.max(...all.map((r) => r[c].length)));
  const fmt = (r) => r.map((cell, c) => cell.padEnd(widths[c])).join('  ').trimEnd();
  return [fmt(header), widths.map((w) => '-'.repeat(w)).join('  '), ...lines.map(fmt)].join('\n');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    console.error(usage());
    return 2;
  }
  if (opts.help) {
    console.log(usage());
    return 0;
  }
  if (opts.real && !opts.base && !hasRealKey()) {
    console.error('--real needs a real ANTHROPIC_API_KEY in the environment or in ./.env (nothing was spawned, nothing was spent).');
    return 2;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'merc-load-rehearsal-'));
  let server = null;
  let base = opts.base;
  const rows = [];
  let crashed = false;
  const onSignal = () => { if (server && !server.exited) server.proc.kill('SIGKILL'); process.exit(130); };
  process.on('SIGINT', onSignal);
  process.on('SIGTERM', onSignal);

  try {
    if (!base) {
      server = await spawnServer({ real: opts.real, delay: opts.delay, tmpDir });
      base = server.base;
    }
    const ctx = { base, server: server || { exited: null }, limits: PROD_LIMITS };

    console.log(`Mercurius load rehearsal — ${opts.real ? 'REAL upstream (spend!)' : 'mock upstream'}`);
    if (server) {
      console.log(`server: pid ${server.proc.pid} on ${base}  db: ${server.dbPath}  log: ${server.logPath}`);
      console.log(`limits: ${Object.entries(PROD_LIMITS).map(([k, v]) => `${k}=${v}`).join(' ')}`);
      if (!opts.real) console.log(`mock: MOCK_STREAM_DELAY_MS=${opts.delay}`);
    } else {
      console.log(`target: ${base} (not spawned — its limits are whatever it runs with)`);
    }
    console.log('');

    const plan = opts.real
      ? [['Real smoke', (c) => scenarioRealSmoke(c, opts.concurrency), 400000]]
      : [
        ['Classroom', scenarioClassroom, 180000],
        ['Hostile session', scenarioHostileSession, 60000],
        ['Hostile rotation', scenarioHostileRotation, 120000],
        ['Spike', scenarioSpike, 120000],
        ['Drain', scenarioDrain, PROD_LIMITS.DRAIN_TIMEOUT_MS + 30000],
      ];

    for (const [label, fn, budgetMs] of plan) {
      if (server && server.exited) {
        crashed = true;
        rows.push({ name: label, results: [], verdict: 'FAIL', gate: true, notes: [`skipped: the server had already exited (code ${server.exited.code}, signal ${server.exited.signal})`] });
        continue;
      }
      process.stdout.write(`running ${label}… `);
      const t0 = now();
      let row;
      try {
        row = await withTimeout(fn(ctx), budgetMs, label);
      } catch (err) {
        row = { name: label, results: [], verdict: 'FAIL', gate: true, notes: [`scenario error: ${err.message}`] };
      }
      console.log(`${row.verdict} (${((now() - t0) / 1000).toFixed(1)} s)`);
      rows.push(row);
      // An exit at any point other than the drain's own SIGTERM is a crash.
      if (server && server.exited && label !== 'Drain') {
        crashed = true;
        row.verdict = 'FAIL';
        row.notes.push(`server exited during this scenario (code ${server.exited.code}, signal ${server.exited.signal})`);
      }
    }

    console.log('');
    console.log(renderTable(rows));
    console.log('');
    for (const row of rows) {
      for (const n of row.notes) console.log(`  [${row.name.split(' (')[0]}] ${n}`);
    }

    const gateFailures = rows.filter((r) => r.gate && r.verdict !== 'PASS');
    const otherFailures = rows.filter((r) => !r.gate && r.verdict !== 'PASS');
    console.log('');
    if (crashed) console.log('SERVER CRASHED — see the log below.');
    if (gateFailures.length) console.log(`GATE FAIL: ${gateFailures.map((r) => r.name).join('; ')}`);
    if (otherFailures.length) console.log(`WARN (informational scenarios failed): ${otherFailures.map((r) => r.name).join('; ')}`);
    if (!gateFailures.length && !otherFailures.length && !crashed) console.log('ALL SCENARIOS PASS');

    const keepLog = Boolean(server) && (crashed || gateFailures.length > 0 || otherFailures.length > 0);
    if (server && keepLog) {
      console.log(`server log kept: ${server.logPath}`);
      if (server.stderrTail.length) {
        console.log('--- last stderr lines ---');
        console.log(server.stderrTail.join('\n'));
      }
    }
    return crashed || gateFailures.length ? 1 : 0;
  } finally {
    await stopServer(server);
    process.off('SIGINT', onSignal);
    process.off('SIGTERM', onSignal);
    const keep = rows.some((r) => r.verdict !== 'PASS') || crashed;
    if (!keep) fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(err && err.stack ? err.stack : String(err));
    process.exit(1);
  },
);
