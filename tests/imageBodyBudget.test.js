'use strict';

// POST /api/images body budget, end to end: the process-wide budget counts
// the bytes that have actually arrived, so connections that declare a big
// body and then stall cannot starve everyone else's uploads, and a body still
// unread after IMAGE_BODY_READ_MS is answered 408 and gives its bytes back.
// There is deliberately no per-IP share: a whole classroom uploads through
// one school IP.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');

const dbPath = path.join(os.tmpdir(), `merc-image-budget-${crypto.randomBytes(4).toString('hex')}.db`);
const TINY_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const BUDGET = 1024 * 1024;
const READ_MS = 1500;

let BASE;
let PORT;
let proc;
const sockets = [];
const sid = () => 'imgb_' + crypto.randomBytes(8).toString('hex');

before(async () => {
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    IMAGE_UPLOAD_INFLIGHT_BYTES: String(BUDGET),
    IMAGE_BODY_READ_MS: String(READ_MS),
  });
  proc = server.proc;
  ({ base: BASE, port: PORT } = await server.ready);
});

after(() => {
  for (const s of sockets) s.destroy();
  if (proc) proc.kill('SIGKILL');
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

// A raw upload that declares `declared` bytes, sends only the start of the
// JSON body, then stalls. Resolves with whatever the server answers.
function stalledUpload(declared) {
  const socket = net.connect(PORT, '127.0.0.1');
  sockets.push(socket);
  let raw = '';
  const answered = new Promise((resolve) => {
    socket.on('data', (d) => { raw += d; });
    socket.on('close', () => resolve(raw));
    socket.on('error', () => resolve(raw));
  });
  socket.write(
    'POST /api/images HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n' +
    `Content-Length: ${declared}\r\n\r\n{"sessionId":"${sid()}","contentType":"image/png","data":"`,
  );
  return { socket, answered };
}

async function upload() {
  const res = await fetch(`${BASE}/api/images`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: sid(), contentType: 'image/png', data: TINY_PNG_B64 }),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

describe('image upload body budget', () => {
  test('stalled uploads that declare the whole budget do not block another upload', async () => {
    // Five stalls declaring 90% of the budget each: under declared-size
    // accounting the second one alone would have filled the budget.
    const stalls = Array.from({ length: 5 }, () => stalledUpload(Math.floor(BUDGET * 0.9)));
    await new Promise((r) => setTimeout(r, 200));
    const res = await upload();
    assert.equal(res.status, 201, JSON.stringify(res.json));
    for (const s of stalls) s.socket.destroy();
  });

  test('a body still unread after the read deadline is answered 408', async () => {
    const t0 = Date.now();
    const stall = stalledUpload(Math.floor(BUDGET * 0.5));
    const raw = await stall.answered;
    assert.match(raw, /^HTTP\/1\.1 408 /, raw.slice(0, 200));
    assert.match(raw, /"error":"timeout"/);
    assert.ok(Date.now() - t0 >= READ_MS - 100, 'not answered before the deadline');
    const after408 = await upload();
    assert.equal(after408.status, 201, 'the budget is free again');
  });
});
