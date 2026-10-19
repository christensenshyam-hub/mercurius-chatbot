'use strict';

// Photo re-attach (AUD-10) end to end, against the real server with the
// in-process mock. MOCK_CAPTURE_FILE records every model call's params, so
// each test reads back exactly what the model was shown.
//
// Threads are driven the way the shipped iOS builds send them: the photo's
// imageId rides ONE request only (the turn that carries it), photo-only
// turns read "[Shared an image]", "Explain more" is a wire-only user turn,
// lessons re-send the [CURRICULUM: …] opener first and re-tag the last user
// turn, and iOS 2.0.0 sends no capabilities.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');
const { spawnServer } = require('./support/spawnServer');
const { waitFor } = require('./support/waitFor');
const { replyKey } = require('../lib/photoReattach');

const SHARED = '[Shared an image]';
const BLOCKS = ['blocks_v1'];
const EXPLAIN_MORE = "Explain more — go deeper on the same topic. Don't repeat what you already said.";
const TAG = '[CURRICULUM: Unit 1, Lesson 1]';
const OPENER = `${TAG} Teach me what physically happens inside an LLM when I type a prompt.`;
const HOUR_MS = 3_600_000;
const PNG_MAGIC = Buffer.from('89504e470d0a1a0a', 'hex');

const tmp = (name) => path.join(os.tmpdir(), `merc-photo-${name}-${crypto.randomBytes(4).toString('hex')}`);
const servers = {};

const LIMITS = {
  MOCK_STREAM_DELAY_MS: '2',
  SESSION_PER_MIN: '1000',
  SESSION_DAILY_USD: '100',
  SESSION_DAILY_CHAT_TURNS: '1000',
  SESSION_DAILY_LESSON_TURNS: '1000',
  IP_DAILY_USD: '100',
  IP_DAILY_NEW_SESSIONS: '1000',
  EVAL_EXPOSE_USAGE: '1',
};

async function boot(key, env = {}) {
  const dbPath = tmp(`${key}.db`);
  const captureFile = tmp(`${key}.jsonl`);
  const s = spawnServer({ SQLITE_PATH: dbPath, MOCK_CAPTURE_FILE: captureFile, ...LIMITS, ...env });
  const { base } = await s.ready;
  servers[key] = { base, proc: s.proc, dbPath, captureFile };
}

before(async () => {
  await Promise.all([
    boot('on'),
    boot('off', { PHOTO_REATTACH_TURNS: '0' }),
    boot('err', { MOCK_SCENARIO: 'error' }),
  ]);
});

after(() => {
  for (const s of Object.values(servers)) {
    try { s.proc.kill('SIGKILL'); } catch { /* ignore */ }
    for (const f of [s.captureFile, s.dbPath, `${s.dbPath}-wal`, `${s.dbPath}-shm`]) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
  }
});

const sid = () => 'photo_' + crypto.randomBytes(12).toString('hex');
const nonce = () => `n${crypto.randomBytes(5).toString('hex')}`;
// A distinct "PNG" per photo (the upload route sniffs only the magic bytes).
const photo = () => Buffer.concat([PNG_MAGIC, crypto.randomBytes(48)]);

async function upload(server, sessionId, bytes) {
  const res = await fetch(`${server.base}/api/images`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, contentType: 'image/png', data: bytes.toString('base64'), fileName: 'hw.png' }),
  });
  const body = await res.json();
  assert.equal(res.status, 201, JSON.stringify(body));
  return body.id;
}

// One /api/chat request. SSE by default; `json: true` takes the JSON path.
// `abortAfterDelta: true` drops the connection after the first text delta
// (a Stop / a dropped stream mid-reply).
async function chat(server, sessionId, messages, { imageId, capabilities, json = false, responseMode, abortAfterDelta = false } = {}) {
  const body = { sessionId, messages };
  if (imageId) body.imageId = imageId;
  if (capabilities) body.capabilities = capabilities;
  if (responseMode) body.responseMode = responseMode;
  const ctrl = new AbortController();
  const res = await fetch(`${server.base}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(json ? {} : { Accept: 'text/event-stream' }) },
    body: JSON.stringify(body),
    signal: ctrl.signal,
  });
  if (json) {
    const out = await res.json();
    return { status: res.status, reply: out.reply, usage: null };
  }
  if (abortAfterDelta) {
    const reader = res.body.getReader();
    let seen = '';
    while (!seen.includes('"type":"delta"')) {
      const { value, done } = await reader.read();
      if (done) break;
      seen += Buffer.from(value).toString('utf8');
    }
    ctrl.abort();
    return { status: res.status, aborted: true };
  }
  const text = await res.text();
  const frames = text.split('\n')
    .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
    .map((l) => JSON.parse(l.slice(6)));
  const complete = frames.find((f) => f.type === 'complete');
  assert.ok(complete, `no complete frame: ${text.slice(0, 300)}`);
  return { status: res.status, reply: complete.reply, usage: complete.usage || null };
}

// The model call whose params mention `marker` (exactly one expected).
function callFor(server, marker) {
  const calls = fs.readFileSync(server.captureFile, 'utf8')
    .split('\n')
    .filter((l) => l && l.includes(marker))
    .map((l) => JSON.parse(l));
  assert.equal(calls.length, 1, `one model call carries ${marker}`);
  return calls[0];
}

// [{ index, data, text }] for every message the model was shown with an image.
function imagesIn(call) {
  const out = [];
  call.messages.forEach((m, index) => {
    if (!Array.isArray(m.content)) return;
    for (const b of m.content) {
      if (b.type === 'image') {
        const textBlock = m.content.find((x) => x.type === 'text');
        out.push({ index, data: b.source.data, text: textBlock ? textBlock.text : null });
      }
    }
  });
  return out;
}

function sqlite(server) {
  return new Database(server.dbPath, { fileMustExist: true });
}

function imageRow(server, id) {
  const db = sqlite(server);
  try {
    return db.prepare('SELECT id, session_id, turn_key, turn_anchor, turn_reply, created_at FROM images WHERE id = ?').get(id);
  } finally {
    db.close();
  }
}

function setImageReply(server, id, key) {
  const db = sqlite(server);
  try {
    db.prepare('UPDATE images SET turn_reply = ? WHERE id = ?').run(key, id);
  } finally {
    db.close();
  }
}

function backdateImage(server, id, ageMs) {
  const db = sqlite(server);
  try {
    db.prepare('UPDATE images SET created_at = ? WHERE id = ?').run(Date.now() - ageMs, id);
  } finally {
    db.close();
  }
}

async function linked(server, id) {
  const row = await waitFor(() => imageRow(server, id), (r) => Boolean(r && r.turn_key && r.turn_anchor), { timeoutMs: 3000 });
  assert.ok(row && row.turn_key && row.turn_anchor, `image ${id} linked`);
}

// A client thread that behaves like iOS: visible turns plus the reply text.
function thread() {
  const visible = [];
  return {
    visible,
    user(content) { visible.push({ role: 'user', content }); return this; },
    assistant(content) { visible.push({ role: 'assistant', content }); return this; },
    wire() { return visible.map((m) => ({ ...m })); },
  };
}

// The iOS photo flow: upload, then the turn that carries the id; the reply
// joins the thread. Resolves once the server has linked the photo.
async function sendPhotoTurn(server, sessionId, t, content, opts = {}) {
  const bytes = photo();
  const id = await upload(server, sessionId, bytes);
  t.user(content);
  const r = await chat(server, sessionId, t.wire(), { ...opts, imageId: id });
  t.assistant(r.reply);
  await linked(server, id);
  return { id, b64: bytes.toString('base64'), reply: r };
}

async function followUp(server, sessionId, t, text, opts = {}) {
  const n = nonce();
  t.user(`${text} ${n}`);
  const r = await chat(server, sessionId, t.wire(), opts);
  t.assistant(r.reply);
  return { call: callFor(server, n), reply: r };
}

describe('the photo lands on the turn it came with (AUD-10)', () => {
  test('build 16 (blocks_v1): a photo-only turn is shown again on the next turn, nowhere else', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    t.user('hi');
    t.assistant((await chat(S, s, t.wire(), { capabilities: BLOCKS })).reply);
    const p = await sendPhotoTurn(S, s, t, SHARED, { capabilities: BLOCKS });
    const { call } = await followUp(S, s, t, 'ok and what does number 8 say again', { capabilities: BLOCKS });
    const imgs = imagesIn(call);
    assert.equal(imgs.length, 1, 'exactly one image');
    assert.equal(imgs[0].index, 2, 'on the photo turn (hi, reply, PHOTO, reply, new)');
    assert.equal(imgs[0].data, p.b64, 'the bytes the student uploaded');
    assert.equal(imgs[0].text, SHARED);
    assert.equal(imageRow(S, p.id).turn_reply, replyKey(p.reply.reply), 'the link records the reply iOS keeps');
    assert.equal(call.messages.length, 5);
    const last = call.messages[4];
    assert.equal(typeof last.content, 'string', 'the new turn carries no image');
  });

  test('iOS 2.0.0 (no capabilities): a text + photo turn, then "Explain more" (wire-only turn)', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const p = await sendPhotoTurn(S, s, t, 'i got x = 16 for number 7, is that right?');
    // Explain more: the injected instruction is the last wire message only.
    const n = nonce();
    const wire = [...t.wire(), { role: 'user', content: `${EXPLAIN_MORE} ${n}` }];
    const r = await chat(S, s, wire, { responseMode: 'deep' });
    t.assistant(r.reply); // the deeper reply replaces nothing; iOS appends it
    let imgs = imagesIn(callFor(S, n));
    assert.deepEqual(imgs.map((i) => [i.index, i.data, i.text]), [[0, p.b64, 'i got x = 16 for number 7, is that right?']]);
    // And the next typed turn still sees it.
    const { call } = await followUp(S, s, t, 'i plugged it in tho. 3(16-4)+5 = 41 and 2(16)+9 = 41');
    imgs = imagesIn(call);
    assert.deepEqual(imgs.map((i) => [i.index, i.data]), [[0, p.b64]]);
  });

  test('a lesson: the iOS re-tag on the photo turn does not stop the match', async () => {
    const S = servers.on;
    const s = sid();
    const opener = { role: 'user', content: OPENER };
    const visible = [];
    const lessonWire = (lastTagged) => {
      const w = [opener, ...visible.map((m) => ({ ...m }))];
      if (lastTagged) {
        const i = w.length - 1;
        w[i] = { role: 'user', content: `${TAG} ${w[i].content}` };
      }
      return w;
    };
    visible.push({ role: 'assistant', content: (await chat(S, s, [opener], { capabilities: BLOCKS })).reply });
    const bytes = photo();
    const id = await upload(S, s, bytes);
    visible.push({ role: 'user', content: SHARED });
    visible.push({ role: 'assistant', content: (await chat(S, s, lessonWire(true), { capabilities: BLOCKS, imageId: id })).reply });
    await linked(S, id);
    const n = nonce();
    visible.push({ role: 'user', content: `what does the worksheet ask? ${n}` });
    await chat(S, s, lessonWire(true), { capabilities: BLOCKS });
    const imgs = imagesIn(callFor(S, n));
    assert.deepEqual(imgs.map((i) => [i.index, i.data, i.text]), [[2, bytes.toString('base64'), SHARED]]);
  });

  test('two photo-only turns each keep their own photo; a Retry re-upload replaces the first try', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const A = await sendPhotoTurn(S, s, t, SHARED, { capabilities: BLOCKS });
    // Photo B's first try is cut off mid-reply (the model had started) …
    const b1 = photo();
    const b1Id = await upload(S, s, b1);
    t.user(SHARED);
    const cut = await chat(S, s, t.wire(), { capabilities: BLOCKS, imageId: b1Id, abortAfterDelta: true });
    assert.ok(cut.aborted);
    await linked(S, b1Id);
    // … and Retry re-uploads the same photo under a new id for the same turn.
    const b2 = photo();
    const b2Id = await upload(S, s, b2);
    t.assistant((await chat(S, s, t.wire(), { capabilities: BLOCKS, imageId: b2Id })).reply);
    await linked(S, b2Id);
    const { call } = await followUp(S, s, t, 'which one is harder?', { capabilities: BLOCKS });
    const imgs = imagesIn(call);
    assert.deepEqual(imgs.map((i) => [i.index, i.data]), [[0, A.b64], [2, b2.toString('base64')]]);
    assert.ok(!imgs.some((i) => i.data === b1.toString('base64')), 'the cut-off upload is never shown');
  });

  test('two chats that each open with a photo: going back to the older one shows its own photo', async () => {
    const S = servers.on;
    const s = sid();
    // Chat 1 opens with photo A, chat 2 (a New chat, same session) with B.
    const c1 = thread();
    const A = await sendPhotoTurn(S, s, c1, SHARED);
    const c2 = thread();
    const B = await sendPhotoTurn(S, s, c2, SHARED);
    // The mock answers both alike; a real model describes each photo. Give
    // chat 1 the reply a real model would have written for photo A.
    const replyA = 'That worksheet asks you to solve 3(x - 4) + 5 = 2x + 9. Where do you start?';
    c1.visible[1] = { role: 'assistant', content: replyA };
    setImageReply(S, A.id, replyKey(replyA));
    const back = await followUp(S, s, c1, 'ok what was number 7 again');
    assert.deepEqual(imagesIn(back.call).map((i) => [i.index, i.data]), [[0, A.b64]], 'chat 1 gets A, not the newer B');
    const on = await followUp(S, s, c2, 'and number 8?');
    assert.deepEqual(imagesIn(on.call).map((i) => [i.index, i.data]), [[0, B.b64]]);
  });

  test('the JSON path re-attaches too', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const bytes = photo();
    const id = await upload(S, s, bytes);
    t.user(SHARED);
    t.assistant((await chat(S, s, t.wire(), { imageId: id, json: true })).reply);
    await linked(S, id);
    const n = nonce();
    t.user(`and #8? ${n}`);
    await chat(S, s, t.wire(), { json: true });
    assert.deepEqual(imagesIn(callFor(S, n)).map((i) => [i.index, i.data]), [[0, bytes.toString('base64')]]);
  });
});

describe('never crosses sessions', () => {
  test("another session replaying the same thread gets no photo, and can't link the first one's", async () => {
    const S = servers.on;
    const owner = sid();
    const t = thread();
    t.user('hi');
    t.assistant((await chat(S, owner, t.wire())).reply);
    const p = await sendPhotoTurn(S, owner, t, SHARED);
    const before = imageRow(S, p.id);

    // The intruder replays the owner's exact thread (same texts, same anchors).
    const intruder = sid();
    const n1 = nonce();
    await chat(S, intruder, [...t.wire(), { role: 'user', content: `what is #8? ${n1}` }]);
    assert.deepEqual(imagesIn(callFor(S, n1)), [], 'no image for another session');

    // … and presenting the owner's imageId neither shows nor links it.
    const n2 = nonce();
    await chat(S, intruder, [{ role: 'user', content: `${SHARED} ${n2}` }], { imageId: p.id });
    assert.deepEqual(imagesIn(callFor(S, n2)), []);
    await new Promise((r) => setTimeout(r, 150));
    assert.deepEqual(imageRow(S, p.id), before, "the owner's link is untouched");

    // Control: the owner's own next turn does see it.
    const { call } = await followUp(S, owner, t, 'what is #8?');
    assert.equal(imagesIn(call).length, 1);
  });
});

describe('stops after the turn limit and after expiry', () => {
  test('follow-ups 1–6 see the photo, the 7th does not', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const p = await sendPhotoTurn(S, s, t, SHARED, { capabilities: BLOCKS });
    const seen = [];
    for (let k = 1; k <= 7; k++) {
      const { call } = await followUp(S, s, t, `follow-up ${k}`, { capabilities: BLOCKS });
      const imgs = imagesIn(call);
      seen.push(imgs.length);
      if (imgs.length) assert.equal(imgs[0].data, p.b64);
    }
    assert.deepEqual(seen, [1, 1, 1, 1, 1, 1, 0]);
  });

  test('shown while under 24 hours old, gone after', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const p = await sendPhotoTurn(S, s, t, SHARED);
    backdateImage(S, p.id, 24 * HOUR_MS - 60_000);
    let { call } = await followUp(S, s, t, 'still there?');
    assert.equal(imagesIn(call).length, 1, '23 h 59 m: still shown');
    backdateImage(S, p.id, 24 * HOUR_MS + 60_000);
    ({ call } = await followUp(S, s, t, 'and now?'));
    assert.deepEqual(imagesIn(call), [], '24 h 1 m: not shown');
  });

  test('PHOTO_REATTACH_TURNS=0 turns re-attaching off (the photo is still linked)', async () => {
    const S = servers.off;
    const s = sid();
    const t = thread();
    const p = await sendPhotoTurn(S, s, t, SHARED);
    assert.ok(imageRow(S, p.id).turn_key, 'linked');
    const { call } = await followUp(S, s, t, 'what is #8?');
    assert.deepEqual(imagesIn(call), []);
  });
});

describe('only an answered photo is linked', () => {
  test('a photo turn the model refused is never shown again', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const bytes = photo();
    const id = await upload(S, s, bytes);
    t.user('what is in this picture MOCK_REFUSAL');
    t.assistant((await chat(S, s, t.wire(), { imageId: id })).reply);
    // A partial reply that ends in a refusal is not an answer either.
    const partial = photo();
    const partialId = await upload(S, s, partial);
    t.user('and this one MOCK_REFUSAL_PARTIAL');
    t.assistant((await chat(S, s, t.wire(), { imageId: partialId })).reply);
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(imageRow(S, id).turn_key, null, 'not linked');
    assert.equal(imageRow(S, partialId).turn_key, null, 'not linked');
    const { call } = await followUp(S, s, t, 'hello?');
    assert.deepEqual(imagesIn(call), []);
  });
});

describe('a photo the model never answered is not linked', () => {
  test('an upstream error before any text (e.g. the API rejecting the image)', async () => {
    const S = servers.err;
    const s = sid();
    const id = await upload(S, s, photo());
    const res = await fetch(`${S.base}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
      body: JSON.stringify({ sessionId: s, messages: [{ role: 'user', content: SHARED }], imageId: id }),
    });
    const text = await res.text();
    assert.match(text, /"type":"error"/);
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(imageRow(S, id).turn_key, null);
  });
});

describe('the cached prefix', () => {
  test('the static system block is byte-identical with and without a re-attached photo', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    t.user('hi');
    t.assistant((await chat(S, s, t.wire(), { capabilities: BLOCKS })).reply);
    await sendPhotoTurn(S, s, t, SHARED, { capabilities: BLOCKS });
    const withPhoto = (await followUp(S, s, t, 'what is #8?', { capabilities: BLOCKS })).call;
    assert.equal(imagesIn(withPhoto).length, 1);

    // The same thread from a session with no photo.
    const other = sid();
    const n = nonce();
    await chat(S, other, [...t.wire().slice(0, -2), { role: 'user', content: `what is #8? ${n}` }], { capabilities: BLOCKS });
    const without = callFor(S, n);
    assert.deepEqual(imagesIn(without), []);
    assert.deepEqual(withPhoto.system, without.system, 'system blocks identical, byte for byte');
    assert.ok(withPhoto.system[0].cache_control, 'the static block keeps its breakpoint');
    const marks = (call) => call.system.filter((b) => b.cache_control).length
      + call.messages.reduce((k, m) => k + (Array.isArray(m.content) ? m.content.filter((b) => b.cache_control).length : 0), 0);
    assert.ok(marks(withPhoto) <= 4);
  });

  test('the photo sits before the history breakpoint: written once, then read from cache', async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    t.user('hi');
    t.assistant((await chat(S, s, t.wire())).reply);
    await sendPhotoTurn(S, s, t, SHARED);
    const f1 = await followUp(S, s, t, 'what is #8?');
    const f2 = await followUp(S, s, t, 'and #7?');
    // The breakpoint is on the reply after the photo turn (f1) / later (f2).
    const bp = (call) => call.messages.findIndex((m) => Array.isArray(m.content) && m.content.some((b) => b.cache_control));
    assert.equal(bp(f1.call), 3);
    assert.ok(imagesIn(f1.call)[0].index < bp(f1.call));
    // The mock bills an image block as 1200 tokens, like a ~1000 px photo.
    const u1 = f1.reply.usage;
    const u2 = f2.reply.usage;
    assert.ok(u1.cache_creation_input_tokens >= 1200, `f1 writes the photo into the cache (${JSON.stringify(u1)})`);
    assert.ok(u2.cache_read_input_tokens >= u1.cache_read_input_tokens + u1.cache_creation_input_tokens,
      `f2 reads it back (${JSON.stringify(u2)})`);
    assert.ok(u2.input_tokens < 1200, `the photo is not billed uncached on f2 (${u2.input_tokens})`);
  });
});

describe('erasure', () => {
  test("a deleted session's photos are gone and never come back", async () => {
    const S = servers.on;
    const s = sid();
    const t = thread();
    const p = await sendPhotoTurn(S, s, t, SHARED);
    assert.equal(imagesIn((await followUp(S, s, t, 'what is #7?')).call).length, 1, 'shown before the erasure');
    const del = await fetch(`${S.base}/api/session/${s}`, { method: 'DELETE' });
    assert.equal(del.status, 200);
    const receipt = await del.json();
    assert.equal(receipt.deleted.images, 1);
    assert.equal((await fetch(`${S.base}/api/images/${p.id}`)).status, 404);
    assert.equal(imageRow(S, p.id), undefined, 'the row is gone');
    // The same id and thread afterwards (a stale client): no photo.
    const { call } = await followUp(S, s, t, 'what is #8?');
    assert.deepEqual(imagesIn(call), []);
  });
});
