'use strict';

// POST /api/chat hardening, end to end against the real server with the
// in-process mock (usage exposed on the complete frame, so the tests can see
// what reached the model):
//
//   - per-turn budgets: every user turn the model sees is cut to 2,000
//     characters (latest AND replayed), and an earlier turn over the wire
//     schema's 10,000 is truncated, never a 400 that bricks the thread;
//   - the per-session limiter answers a streaming client with an SSE error
//     frame, like every other refusal;
//   - an attached image is only used by the session that uploaded it, and an
//     image-only turn whose image is gone still gets an answer;
//   - replies that hand out the crisis resources are counted in /metrics;
//   - CORS: the server's own pages and foreign origins never get a 500;
//   - content reports: one session's daily allowance.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');

const ADMIN_PASSWORD = 'test-admin-' + crypto.randomBytes(4).toString('hex');
const dbPath = path.join(os.tmpdir(), `merc-chat-hardening-${crypto.randomBytes(4).toString('hex')}.db`);
const CLUB_ORIGIN = 'https://club.example';
const TINY_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

let BASE;
let proc;
const sid = () => 'hard_' + crypto.randomBytes(8).toString('hex');

before(async () => {
  const server = spawnServer({
    SQLITE_PATH: dbPath,
    ADMIN_PASSWORD,
    ALLOWED_ORIGIN: CLUB_ORIGIN,
    EVAL_EXPOSE_USAGE: '1',
    MOCK_STREAM_DELAY_MS: '1',
    SESSION_PER_MIN: '3',
    SESSION_DAILY_REPORTS: '2',
  });
  proc = server.proc;
  ({ base: BASE } = await server.ready);
});

after(() => {
  if (proc) proc.kill('SIGKILL');
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

async function stream(sessionId, messages, extra = {}) {
  const res = await fetch(`${BASE}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sessionId, messages, ...extra }),
  });
  const text = await res.text();
  const frames = text.split('\n')
    .filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]')
    .map((l) => JSON.parse(l.slice(6)));
  return {
    status: res.status,
    contentType: res.headers.get('content-type') || '',
    frames,
    complete: frames.find((f) => f.type === 'complete'),
    error: frames.find((f) => f.type === 'error'),
    done: text.includes('data: [DONE]'),
    text,
  };
}

// Uncached input tokens the mock billed: a pure function of the messages the
// model received (the cached system prefix is billed separately).
async function inputTokens(messages) {
  const out = await stream(sid(), messages);
  assert.equal(out.status, 200, out.text.slice(0, 300));
  assert.ok(out.complete, `complete frame (${out.text.slice(0, 300)})`);
  return out.complete.usage.input_tokens;
}

function storedUserTurns(sessionId) {
  const Database = require('better-sqlite3');
  const sqlite = new Database(dbPath, { readonly: true });
  try {
    return sqlite.prepare("SELECT content FROM messages WHERE session_id = ? AND role = 'user' ORDER BY id").all(sessionId).map((r) => r.content);
  } finally {
    sqlite.close();
  }
}

describe('per-turn budgets', () => {
  test('an earlier turn over the 10,000-char wire cap is truncated, not a 400 that bricks the thread', async () => {
    const essay = 'My essay. '.repeat(1200); // 12,000 chars
    const out = await stream(sid(), [
      { role: 'user', content: '[CURRICULUM: Unit 7, Lesson 3] Help me write honestly with AI.' },
      { role: 'assistant', content: 'Paste what you have.' },
      { role: 'user', content: essay },
      { role: 'assistant', content: 'a'.repeat(10_500) },
      { role: 'user', content: 'Can you help?' },
    ]);
    assert.equal(out.status, 200);
    assert.ok(out.complete, `answered (${out.text.slice(0, 300)})`);
  });

  test('a replayed user turn reaches the model cut to 2,000 chars, exactly as when it was first sent', async () => {
    const tail = [{ role: 'assistant', content: 'Go on.' }, { role: 'user', content: 'And then?' }];
    const long = await inputTokens([{ role: 'user', content: 'y'.repeat(9000) }, ...tail]);
    const cut = await inputTokens([{ role: 'user', content: 'y'.repeat(2000) }, ...tail]);
    const shorter = await inputTokens([{ role: 'user', content: 'y'.repeat(1000) }, ...tail]);
    assert.equal(long, cut, 'the 9,000-char turn was replayed as its first 2,000');
    assert.ok(shorter < cut, 'the measure is sensitive to turn length');
  });

  test('the latest turn is cut to 2,000 chars for the model and in the stored transcript', async () => {
    const s = sid();
    const long = await stream(s, [{ role: 'user', content: 'z'.repeat(5000) }]);
    assert.equal(long.status, 200);
    const cut = await inputTokens([{ role: 'user', content: 'z'.repeat(2000) }]);
    assert.equal(long.complete.usage.input_tokens, cut);
    assert.deepEqual(storedUserTurns(s).map((c) => c.length), [2000]);
  });

  test('an empty text turn with no image is a 400, and blank replayed turns are dropped', async () => {
    const res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sid(), messages: [{ role: 'user', content: '   ' }] }),
    });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, 'invalid_messages');
    const out = await stream(sid(), [
      { role: 'user', content: 'first' },
      { role: 'assistant', content: '  ' },
      { role: 'user', content: 'second' },
    ]);
    assert.ok(out.complete, `a blank replayed turn never reaches the model (${out.text.slice(0, 300)})`);
  });
});

describe('per-session limiter', () => {
  test('a streaming client gets its refusal as an SSE error frame; a JSON client still gets 429', async () => {
    const s = sid();
    for (let i = 0; i < 3; i++) assert.ok((await stream(s, [{ role: 'user', content: `turn ${i}` }])).complete);
    const refused = await stream(s, [{ role: 'user', content: 'one more' }]);
    assert.equal(refused.status, 200);
    assert.match(refused.contentType, /text\/event-stream/);
    assert.equal(refused.error.code, 'rate_limited');
    assert.match(refused.error.error, /moving fast/);
    assert.ok(refused.done, 'terminated with [DONE]');

    const res = await fetch(`${BASE}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: s, messages: [{ role: 'user', content: 'json' }] }),
    });
    assert.equal(res.status, 429);
    const json = await res.json();
    assert.equal(json.error, 'rate_limited');
    assert.match(json.reply, /moving fast/);
  });
});

describe('attached images', () => {
  async function upload(sessionId) {
    const res = await fetch(`${BASE}/api/images`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId, contentType: 'image/png', data: TINY_PNG_B64 }),
    });
    assert.equal(res.status, 201);
    return (await res.json()).id;
  }

  test("only the uploader's session can attach an image", async () => {
    const owner = sid();
    const imageId = await upload(owner);
    const messages = [{ role: 'user', content: 'What is in this picture?' }];
    const own = await stream(owner, messages, { imageId });
    const other = await stream(sid(), messages, { imageId });
    const textOnly = await stream(sid(), messages);
    assert.ok(own.complete && other.complete && textOnly.complete);
    assert.ok(own.complete.usage.input_tokens > textOnly.complete.usage.input_tokens, 'the owner sees the image');
    assert.equal(other.complete.usage.input_tokens, textOnly.complete.usage.input_tokens, 'another session gets a text-only turn');
  });

  test('an image-only turn whose image is gone still gets an answer (not an upstream 400)', async () => {
    const out = await stream(sid(), [{ role: 'user', content: '' }], { imageId: crypto.randomBytes(24).toString('base64url') });
    assert.equal(out.status, 200);
    assert.ok(out.complete, `answered (${out.text.slice(0, 300)})`);
  });
});

describe('crisis replies', () => {
  test('a reply carrying the crisis resources is counted (no text) in /metrics', async () => {
    const out = await stream(sid(), [{ role: 'user', content: 'sometimes I want to hurt myself' }]);
    assert.match(out.complete.reply, /988/);
    const metrics = await (await fetch(`${BASE}/metrics`, { headers: { 'x-admin-password': ADMIN_PASSWORD } })).text();
    assert.match(metrics, /crisis_resource_replies_total\{[^}]*kind="chat"[^}]*\} 1\b/);
    assert.doesNotMatch(metrics, /hurt myself/);
  });
});

describe('CORS', () => {
  const post = (origin) => fetch(`${BASE}/api/mode`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: origin },
    body: JSON.stringify({ sessionId: sid(), mode: 'socratic' }),
  });

  test('the allowed origin gets CORS headers', async () => {
    const res = await post(CLUB_ORIGIN);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('access-control-allow-origin'), CLUB_ORIGIN);
  });

  test("the server's own pages (same-origin POST with an Origin header) are not refused", async () => {
    const res = await post(BASE);
    assert.equal(res.status, 200, 'admin.html and the Railway-hosted widget POST with their own origin');
  });

  test('a foreign origin gets no CORS headers, and no 500', async () => {
    const res = await post('https://evil.example');
    assert.notEqual(res.status, 500);
    assert.equal(res.headers.get('access-control-allow-origin'), null, 'the browser withholds the response');
  });
});

describe('content reports', () => {
  const postJson = (p, body) => fetch(`${BASE}${p}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, json: await r.json() }));

  test("past SESSION_DAILY_REPORTS a session's reports are acknowledged and dropped", async () => {
    const s = sid();
    assert.equal((await postJson('/api/mode', { sessionId: s, mode: 'socratic' })).status, 200);
    const answers = [];
    for (let i = 0; i < 3; i++) answers.push(await postJson('/api/report', { sessionId: s, content: `reply ${i}`, reason: 'other' }));
    for (const a of answers) assert.deepEqual([a.status, a.json.ok], [200, true]);
    assert.ok(Number.isInteger(answers[0].json.id) && Number.isInteger(answers[1].json.id));
    assert.equal(answers[2].json.id, undefined, 'the third is not stored');
    const Database = require('better-sqlite3');
    const sqlite = new Database(dbPath, { readonly: true });
    try {
      assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM reports WHERE session_id = ?').get(s).n, 2);
    } finally {
      sqlite.close();
    }
    const s2 = sid();
    await postJson('/api/mode', { sessionId: s2, mode: 'socratic' });
    const other = await postJson('/api/report', { sessionId: s2, content: 'reply', reason: 'other' });
    assert.ok(Number.isInteger(other.json.id), 'another session is unaffected');
  });
});

describe('wrong admin passwords', () => {
  const http = require('node:http');
  const posts = [];
  let hook;
  let adminBase;
  let adminProc;
  before(async () => {
    hook = http.createServer((req, res) => {
      let body = '';
      req.on('data', (c) => { body += c; });
      req.on('end', () => { posts.push(JSON.parse(body).content); res.writeHead(204).end(); });
    });
    await new Promise((resolve) => hook.listen(0, '127.0.0.1', resolve));
    const server = spawnServer(
      { SQLITE_PATH: dbPath + '.admin', ADMIN_PASSWORD, ADMIN_AUTH_FAIL_ALERT_AT: '3' },
      { discordWebhookUrl: `http://127.0.0.1:${hook.address().port}/hook` },
    );
    adminProc = server.proc;
    ({ base: adminBase } = await server.ready);
  });
  after(() => {
    if (adminProc) adminProc.kill('SIGKILL');
    hook.close();
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + '.admin' + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('pile up process-wide into one page; a missing header is not a guess', async () => {
    const get = (p, headers) => fetch(`${adminBase}${p}`, { headers }).then((r) => r.status);
    for (let i = 0; i < 5; i++) assert.equal(await get('/api/admin/stats'), 401);
    assert.equal(posts.filter((p) => /wrong admin passwords/.test(p)).length, 0);
    const guesses = [
      ['/api/admin/stats', { 'x-admin-password': 'guess-1', 'x-forwarded-for': '198.51.100.1' }],
      ['/metrics', { 'x-admin-password': 'guess-2', 'x-forwarded-for': '198.51.100.2' }],
      ['/api/admin/reports', { 'x-admin-password': 'guess-3', 'x-forwarded-for': '198.51.100.3' }],
      ['/api/admin/stats', { 'x-admin-password': 'guess-4', 'x-forwarded-for': '198.51.100.4' }],
    ];
    for (const [p, h] of guesses) assert.equal(await get(p, h), 401);
    assert.equal(await get('/api/admin/stats', { 'x-admin-password': ADMIN_PASSWORD }), 200);
    const deadline = Date.now() + 2000;
    while (!posts.length && Date.now() < deadline) await new Promise((r) => setTimeout(r, 25));
    const pages = posts.filter((p) => /wrong admin passwords/.test(p));
    assert.equal(pages.length, 1, JSON.stringify(posts));
    assert.match(pages[0], /^⚠️ 3 wrong admin passwords/);
    assert.doesNotMatch(pages[0], /guess-/);
  });
});

describe('club feeds (widget turns) behind a hung club site', () => {
  const http = require('node:http');
  const hits = { events: 0, blog: 0 };
  let stub;
  let feedBase;
  let feedProc;
  before(async () => {
    // Accepts the connection, never answers: the worst case for a turn.
    stub = http.createServer((req) => {
      if (req.url.includes('events')) hits.events += 1;
      else hits.blog += 1;
    });
    await new Promise((resolve) => stub.listen(0, '127.0.0.1', resolve));
    const at = `http://127.0.0.1:${stub.address().port}`;
    const server = spawnServer({
      SQLITE_PATH: dbPath + '.feeds',
      CLUB_EVENTS_URL: `${at}/events-data.json`,
      CLUB_BLOG_URL: `${at}/blog-content.json`,
      CLUB_FEED_TIMEOUT_MS: '300',
      MOCK_STREAM_DELAY_MS: '1',
    });
    feedProc = server.proc;
    ({ base: feedBase } = await server.ready);
  });
  after(() => {
    if (feedProc) feedProc.kill('SIGKILL');
    stub.closeAllConnections?.();
    stub.close();
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + '.feeds' + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  const widgetTurn = () => fetch(`${feedBase}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId: sid(), capabilities: ['club_v1'], messages: [{ role: 'user', content: 'When is the next meeting?' }] }),
  }).then(async (r) => ({ status: r.status, json: await r.json() }));

  test('concurrent turns share one bounded fetch per feed; a failed fetch is not retried on every turn', async () => {
    const first = await Promise.all([widgetTurn(), widgetTurn(), widgetTurn()]);
    for (const r of first) assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.deepEqual(hits, { events: 1, blog: 1 }, 'one fetch per feed for three concurrent turns');

    const t0 = Date.now();
    const next = await widgetTurn();
    assert.equal(next.status, 200);
    assert.ok(Date.now() - t0 < 250, `the next turn does not wait on the dead site again (${Date.now() - t0} ms)`);
    assert.deepEqual(hits, { events: 1, blog: 1 }, 'the failure is cached');
  });
});
