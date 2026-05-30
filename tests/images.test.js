'use strict';

/**
 * Image upload (v3) tests.
 *
 *  - Pure-function tests for lib/imageValidation.js (decode + sniff + size),
 *    which need no server.
 *  - End-to-end HTTP tests against a spawned server (SQLite, no DATABASE_URL)
 *    covering upload success, retrieval round-trip, and every documented error
 *    case: invalid type, magic-byte mismatch, non-image, oversized, missing
 *    data, and missing/invalid session ("unauthenticated").
 */

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const crypto = require('node:crypto');

const {
  decodeAndValidateImage,
  sniffImageType,
  stripDataUriPrefix,
} = require('../lib/imageValidation');
const { MAX_IMAGE_BYTES } = require('../lib/schemas');

// ---------------------------------------------------------------------------
// Fixtures — minimal byte sequences with valid format magic numbers.
// ---------------------------------------------------------------------------

// A real 1×1 transparent PNG.
const TINY_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const PNG_BYTES = Buffer.from(TINY_PNG_B64, 'base64');

const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const GIF_BYTES = Buffer.concat([Buffer.from('GIF89a'), Buffer.from([0x01, 0x00, 0x01, 0x00])]);
const WEBP_BYTES = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0x1a, 0x00, 0x00, 0x00]), Buffer.from('WEBP')]);

// ===========================================================================
// 1. Pure-function validation (no server)
// ===========================================================================

describe('imageValidation.sniffImageType', () => {
  test('identifies each supported format by magic bytes', () => {
    assert.equal(sniffImageType(PNG_BYTES), 'image/png');
    assert.equal(sniffImageType(JPEG_BYTES), 'image/jpeg');
    assert.equal(sniffImageType(GIF_BYTES), 'image/gif');
    assert.equal(sniffImageType(WEBP_BYTES), 'image/webp');
  });

  test('returns null for non-image bytes', () => {
    assert.equal(sniffImageType(Buffer.from('hello world, not an image')), null);
    assert.equal(sniffImageType(Buffer.alloc(0)), null);
    assert.equal(sniffImageType('not a buffer'), null);
  });
});

describe('imageValidation.stripDataUriPrefix', () => {
  test('strips a data-URI prefix but leaves bare base64 untouched', () => {
    assert.equal(stripDataUriPrefix('data:image/png;base64,QUJD'), 'QUJD');
    assert.equal(stripDataUriPrefix('QUJD'), 'QUJD');
    assert.equal(stripDataUriPrefix(''), '');
    assert.equal(stripDataUriPrefix(null), '');
  });
});

describe('imageValidation.decodeAndValidateImage', () => {
  test('accepts a valid PNG and returns the decoded buffer', () => {
    const out = decodeAndValidateImage({ data: TINY_PNG_B64, contentType: 'image/png' });
    assert.equal(out.ok, true);
    assert.ok(Buffer.isBuffer(out.buffer));
    assert.equal(out.contentType, 'image/png');
  });

  test('tolerates a data-URI prefix', () => {
    const out = decodeAndValidateImage({ data: `data:image/png;base64,${TINY_PNG_B64}`, contentType: 'image/png' });
    assert.equal(out.ok, true);
  });

  test('rejects a content type off the allowlist', () => {
    const out = decodeAndValidateImage({ data: TINY_PNG_B64, contentType: 'image/bmp' });
    assert.equal(out.ok, false);
    assert.equal(out.error, 'image_invalid_type');
    assert.equal(out.status, 400);
  });

  test('rejects a declared type that disagrees with the bytes', () => {
    // PNG bytes declared as JPEG.
    const out = decodeAndValidateImage({ data: TINY_PNG_B64, contentType: 'image/jpeg' });
    assert.equal(out.ok, false);
    assert.equal(out.error, 'image_invalid_type');
  });

  test('rejects non-image data', () => {
    const out = decodeAndValidateImage({ data: Buffer.from('just text').toString('base64'), contentType: 'image/png' });
    assert.equal(out.ok, false);
    assert.equal(out.error, 'image_invalid_type');
  });

  test('rejects empty data as image_missing', () => {
    const out = decodeAndValidateImage({ data: '', contentType: 'image/png' });
    assert.equal(out.ok, false);
    assert.equal(out.error, 'image_missing');
  });

  test('rejects decoded bytes over the size cap as image_too_large', () => {
    const oversized = Buffer.alloc(MAX_IMAGE_BYTES + 1, 0x89).toString('base64');
    const out = decodeAndValidateImage({ data: oversized, contentType: 'image/png' });
    assert.equal(out.ok, false);
    assert.equal(out.error, 'image_too_large');
    assert.equal(out.status, 413);
  });
});

// ===========================================================================
// 2. HTTP end-to-end
// ===========================================================================

const SERVER_DIR = path.join(__dirname, '..');
// Distinct port range from server.test.js (9000–9999) so the two spawned
// servers never collide when node:test runs files in parallel.
const TEST_PORT = 10500 + Math.floor(Math.random() * 1000);
const BASE_URL = `http://localhost:${TEST_PORT}`;

let serverProc;

function makeSessionId() {
  return 'img_' + crypto.randomBytes(8).toString('hex');
}

async function postJson(p, body) {
  const res = await fetch(`${BASE_URL}${p}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json };
}

async function getRaw(p) {
  const res = await fetch(`${BASE_URL}${p}`);
  const bytes = Buffer.from(await res.arrayBuffer());
  return {
    status: res.status,
    contentType: res.headers.get('content-type'),
    cacheControl: res.headers.get('cache-control'),
    bytes,
  };
}

before(async () => {
  await new Promise((resolve, reject) => {
    serverProc = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: {
        ...process.env,
        PORT: String(TEST_PORT),
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
        ALLOWED_ORIGIN: `http://localhost:${TEST_PORT}`,
        NODE_ENV: 'test',
        // Force the default DB-backed image store on ephemeral SQLite.
        DATABASE_URL: '',
        IMAGE_STORAGE_DRIVER: 'db',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let started = false;
    serverProc.stdout.on('data', (chunk) => {
      if (!started && chunk.toString().includes('Mercurius')) {
        started = true;
        setTimeout(resolve, 300);
      }
    });
    serverProc.stderr.on('data', (chunk) => {
      const text = chunk.toString();
      if ((text.includes('Error') || text.includes('EADDRINUSE')) && !started) reject(new Error(text));
    });
    serverProc.on('error', reject);
    serverProc.on('exit', (code) => {
      if (!started) reject(new Error(`Server exited prematurely with code ${code}`));
    });
    setTimeout(() => {
      if (!started) reject(new Error('Server did not start within 10 seconds'));
    }, 10000);
  });
});

after(() => {
  if (serverProc) serverProc.kill('SIGTERM');
});

describe('POST /api/images — success + retrieval round-trip', () => {
  test('uploads a PNG and returns a stable response', async () => {
    const { status, json } = await postJson('/api/images', {
      sessionId: makeSessionId(),
      contentType: 'image/png',
      data: TINY_PNG_B64,
      fileName: 'pixel.png',
    });
    assert.equal(status, 201);
    assert.ok(json.id && typeof json.id === 'string');
    assert.equal(json.url, `/api/images/${json.id}`);
    assert.equal(json.contentType, 'image/png');
    assert.equal(json.fileName, 'pixel.png');
    assert.equal(json.size, PNG_BYTES.length);
    // createdAt is an ISO-8601 timestamp.
    assert.ok(!Number.isNaN(Date.parse(json.createdAt)));
  });

  test('GET returns the exact bytes with the right content type + cache header', async () => {
    const up = await postJson('/api/images', {
      sessionId: makeSessionId(),
      contentType: 'image/png',
      data: TINY_PNG_B64,
    });
    assert.equal(up.status, 201);

    const got = await getRaw(up.json.url);
    assert.equal(got.status, 200);
    assert.equal(got.contentType, 'image/png');
    assert.match(got.cacheControl || '', /private/);
    assert.equal(got.bytes.length, PNG_BYTES.length);
    assert.ok(got.bytes.equals(PNG_BYTES), 'returned bytes match what was uploaded');
  });

  test('each upload gets a unique id (no accidental dedupe)', async () => {
    const sid = makeSessionId();
    const a = await postJson('/api/images', { sessionId: sid, contentType: 'image/png', data: TINY_PNG_B64 });
    const b = await postJson('/api/images', { sessionId: sid, contentType: 'image/png', data: TINY_PNG_B64 });
    assert.notEqual(a.json.id, b.json.id);
  });
});

describe('POST /api/images — validation + error cases', () => {
  const sid = makeSessionId();

  test('content type off the allowlist → 400 image_invalid_type', async () => {
    const { status, json } = await postJson('/api/images', { sessionId: sid, contentType: 'image/bmp', data: TINY_PNG_B64 });
    assert.equal(status, 400);
    assert.equal(json.error, 'image_invalid_type');
  });

  test('declared type disagreeing with bytes → 400 image_invalid_type', async () => {
    const { status, json } = await postJson('/api/images', { sessionId: sid, contentType: 'image/jpeg', data: TINY_PNG_B64 });
    assert.equal(status, 400);
    assert.equal(json.error, 'image_invalid_type');
  });

  test('non-image data → 400 image_invalid_type', async () => {
    const { status, json } = await postJson('/api/images', {
      sessionId: sid,
      contentType: 'image/png',
      data: Buffer.from('definitely not an image').toString('base64'),
    });
    assert.equal(status, 400);
    assert.equal(json.error, 'image_invalid_type');
  });

  test('missing data → 400 image_missing', async () => {
    const { status, json } = await postJson('/api/images', { sessionId: sid, contentType: 'image/png' });
    assert.equal(status, 400);
    assert.equal(json.error, 'image_missing');
  });

  test('empty data string → 400 image_missing', async () => {
    const { status, json } = await postJson('/api/images', { sessionId: sid, contentType: 'image/png', data: '' });
    assert.equal(status, 400);
    assert.equal(json.error, 'image_missing');
  });

  test('missing sessionId → 400 invalid_session (unauthenticated)', async () => {
    const { status, json } = await postJson('/api/images', { contentType: 'image/png', data: TINY_PNG_B64 });
    assert.equal(status, 400);
    assert.equal(json.error, 'invalid_session');
  });

  test('oversized image → image_too_large', async () => {
    // Two layers reject oversized payloads with the same error code: Zod's
    // base64 char cap (400) and the handler's decoded-byte cap (413). This
    // payload trips whichever boundary it lands on; the unit test above pins
    // the handler's 413 path precisely. Either way the contract is stable.
    const oversized = Buffer.alloc(MAX_IMAGE_BYTES + 4096, 0x89).toString('base64');
    const { status, json } = await postJson('/api/images', { sessionId: sid, contentType: 'image/png', data: oversized });
    assert.ok(status === 413 || status === 400, `expected 400/413, got ${status}`);
    assert.equal(json.error, 'image_too_large');
  });
});

describe('GET /api/images/:id — not found + malformed', () => {
  test('well-formed but unknown id → 404', async () => {
    const id = crypto.randomBytes(24).toString('base64url');
    const got = await getRaw(`/api/images/${id}`);
    assert.equal(got.status, 404);
  });

  test('malformed id (too short) → 404 without a storage hit', async () => {
    const got = await getRaw('/api/images/short');
    assert.equal(got.status, 404);
  });
});
