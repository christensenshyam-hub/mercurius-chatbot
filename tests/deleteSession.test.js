'use strict';

// Tests for the right-to-erasure path (audit finding P0-C):
// db.deleteSession + DELETE /api/session/:sessionId.
//
// Runs directly against a temp SQLite db (the local driver) so it can assert
// row-level deletion across every session-keyed table without a live Postgres.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');

const dbPath = path.join(os.tmpdir(), `merc-delete-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }

describe('db.deleteSession removes every session-keyed row', () => {
  before(async () => { await db.initSchema(); });
  after(() => {
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('deletes messages, images, reports, and the session row', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.saveMessage(s, 'user', 'a minor typed this');
    await db.saveMessage(s, 'assistant', 'a reply');
    await db.saveImage({
      id: crypto.randomBytes(12).toString('hex'), sessionId: s,
      contentType: 'image/png', fileName: 'x.png', sizeBytes: 3,
      data: Buffer.from([1, 2, 3]), createdAt: Date.now(),
    });
    await db.saveReport({ sessionId: s, content: 'bad', reason: 'test', createdAt: Date.now() });

    // Precondition: the data is really there.
    assert.ok((await db.getMessages(s, 50)).length >= 2, 'messages seeded');

    const result = await db.deleteSession(s);
    assert.equal(result.sessionExisted, true);
    assert.equal(result.deleted.messages, 2);
    assert.equal(result.deleted.sessions, 1);
    // student_memory is gone from the schema; the cascade must not depend on it.
    assert.ok(!('student_memory' in result.deleted), 'no student_memory table in a fresh schema');
    assert.equal(result.deleted.images, 1);
    assert.equal(result.deleted.reports, 1);

    // Postcondition: nothing keyed to the session survives.
    assert.equal((await db.getMessages(s, 50)).length, 0, 'messages gone');
    assert.equal((await db.getSessionState(s)), null, 'session row gone');
  });

  test('deleting an unknown session is a harmless no-op', async () => {
    const result = await db.deleteSession(sid());
    assert.equal(result.sessionExisted, false);
    assert.equal(result.deleted.messages, 0);
    assert.equal(result.deleted.sessions, 0);
  });

  test('one session deletion does not touch another session', async () => {
    const keep = sid(); const drop = sid();
    await db.getOrCreateSession(keep); await db.saveMessage(keep, 'user', 'keep me');
    await db.getOrCreateSession(drop); await db.saveMessage(drop, 'user', 'drop me');

    await db.deleteSession(drop);

    assert.equal((await db.getMessages(keep, 50)).length, 1, 'other session untouched');
    assert.equal((await db.getMessages(drop, 50)).length, 0, 'target session cleared');
  });

  test('a photo whose upload began before the erasure is not kept; one begun after it is', async () => {
    // The images table has no foreign key: a photo still being written when
    // its session is erased used to stay behind under the erased id.
    const image = (sessionId, createdAt) => ({
      id: crypto.randomBytes(12).toString('hex'), sessionId,
      contentType: 'image/png', fileName: null, sizeBytes: 3,
      data: Buffer.from([1, 2, 3]), createdAt,
    });
    const s = sid();
    await db.getOrCreateSession(s);
    const began = Date.now() - 50; // the upload's request came in, then the erasure
    await db.deleteSession(s);
    const raced = image(s, began);
    assert.equal(await db.saveImage(raced), false);
    assert.equal(await db.getImage(raced.id), null, 'no photo under the erased id');

    // The phone keeps its id after an emailed erasure: a later upload under
    // it starts the session again and is stored as usual.
    await new Promise((r) => setTimeout(r, 5));
    const later = image(s, Date.now());
    assert.equal(await db.saveImage(later), true);
    assert.ok(await db.getImage(later.id));

    // Other sessions are never affected.
    const other = sid();
    const theirs = image(other, began);
    assert.equal(await db.saveImage(theirs), true);
    assert.ok(await db.getImage(theirs.id));
  });

  test('a report whose request began before the erasure is not kept', async () => {
    // Reports have no foreign key either, and are kept 180 days.
    const s = sid();
    await db.getOrCreateSession(s);
    const began = Date.now() - 50;
    await db.deleteSession(s);
    assert.deepEqual(await db.saveReport({ sessionId: s, content: 'raced', createdAt: began }), { id: null });
    const left = await db.queryRaw('SELECT COUNT(*) AS n FROM reports WHERE session_id = ?', [s]);
    assert.equal(left[0].n, 0, 'no report under the erased id');
    const theirs = await db.saveReport({ sessionId: sid(), content: 'kept', createdAt: began });
    assert.ok(Number.isInteger(theirs.id), 'another session is never affected');
  });

  test('an erasure that never reached Postgres does not mark the session erased', () => {
    // Postgres driver, pointed at a port nobody listens on, so the erasure's
    // pool checkout fails as it does when every connection is busy. Nothing
    // was erased, so the session's next report and photo must go to the
    // database (and fail here) rather than be dropped as "erased" for 10
    // minutes (POST /api/report answers a dropped report with ok, so
    // nobody would notice).
    const resultPath = path.join(os.tmpdir(), `merc-erase-pgdown-${crypto.randomBytes(4).toString('hex')}.json`);
    const script = `
      const fs = require('node:fs');
      const db = require('./db');
      const outcome = (p) => p.then((v) => 'resolved ' + JSON.stringify(v), (e) => 'rejected ' + (e.code || e.message));
      (async () => {
        const s = 'pgdown_' + 'a'.repeat(25);
        const erase = await outcome(db.deleteSession(s));
        const report = await outcome(db.saveReport({ sessionId: s, content: 'x', createdAt: Date.now() }));
        const photo = await outcome(db.saveImage({ id: 'pgdown', sessionId: s, contentType: 'image/png', sizeBytes: 1, data: Buffer.from([1]), createdAt: Date.now() }));
        fs.writeFileSync(${JSON.stringify(resultPath)}, JSON.stringify({ erase, report, photo }));
        process.exit(0);
      })().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
    `;
    const env = { ...process.env, DATABASE_URL: 'postgres://merc:merc@localhost:1/merc', NODE_ENV: 'test' };
    let r;
    try {
      const { execFileSync } = require('node:child_process');
      execFileSync(process.execPath, ['-e', script], { env, cwd: path.join(__dirname, '..'), stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
      r = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    } catch (e) {
      assert.fail(`child failed:\n${String(e.stderr || e.message)}`);
    } finally {
      try { fs.rmSync(resultPath, { force: true }); } catch { /* ignore */ }
    }
    assert.match(r.erase, /^rejected /, 'the erasure fails (no database)');
    // Before: 'resolved {"id":null}' and 'resolved false', without a query.
    assert.match(r.report, /^rejected /, `the report went to the database: ${r.report}`);
    assert.match(r.photo, /^rejected /, `the photo went to the database: ${r.photo}`);
  });

  test('a usage row or lesson event settling after the erasure no longer carries the erased id', async () => {
    const s = sid();
    const other = sid();
    await db.getOrCreateSession(s);
    await db.deleteSession(s);
    // What an in-flight model call writes when it settles a moment later.
    assert.equal(await db.recordUsage({ ts: Date.now(), sessionId: s, route: '/api/chat', kind: 'chat', status: 'aborted', costUsd: 0.01, traceId: 'late-trace' }), true);
    assert.equal(await db.recordLessonEvent({ sessionId: s, lessonId: 'u1_l1', event: 'turn', turnIndex: 2 }), false);
    await db.recordUsage({ ts: Date.now(), sessionId: other, route: '/api/chat', kind: 'chat', status: 'ok', costUsd: 0.01 });
    const Database = require('better-sqlite3');
    const sqlite = new Database(dbPath, { readonly: true });
    try {
      assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM usage WHERE session_id = ?').get(s).n, 0, 'no usage row under the erased id');
      assert.equal(sqlite.prepare("SELECT COUNT(*) AS n FROM usage WHERE session_id IS NULL AND trace_id = 'late-trace'").get().n, 1, 'still billed');
      assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM lesson_events WHERE session_id = ?').get(s).n, 0);
      assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM usage WHERE session_id = ?').get(other).n, 1, 'other sessions unaffected');
    } finally {
      sqlite.close();
    }
  });
});

describe('DELETE /api/session/:sessionId', () => {
  let BASE;
  const serverDb = path.join(os.tmpdir(), `merc-delete-http-${crypto.randomBytes(4).toString('hex')}.db`);
  let proc;

  before(async () => {
    const server = spawnServer({ SQLITE_PATH: serverDb, SESSION_DELETE_IP_PER_MIN: '5' });
    proc = server.proc;
    ({ base: BASE } = await server.ready);
  });

  after(() => {
    if (proc) proc.kill('SIGKILL');
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(serverDb + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('reports a report, then erases the whole session (200 ok)', async () => {
    const s = sid();
    const headers = { 'Content-Type': 'application/json' };
    // Create the session through a real route first: /api/report acknowledges
    // and drops a report for a session the server has never seen.
    let res = await fetch(`${BASE}/api/mode`, { method: 'POST', headers, body: JSON.stringify({ sessionId: s, mode: 'socratic' }) });
    assert.equal(res.status, 200);
    res = await fetch(`${BASE}/api/report`, { method: 'POST', headers, body: JSON.stringify({ sessionId: s, content: 'seed', reason: 'other' }) });
    assert.equal(res.status, 200);
    assert.ok(Number.isInteger((await res.json()).id), 'the report was stored');

    res = await fetch(`${BASE}/api/session/${s}`, { method: 'DELETE' });
    const json = await res.json();
    assert.equal(res.status, 200);
    assert.equal(json.ok, true);
    assert.equal(json.deleted.reports, 1);
  });

  test('rejects a malformed session id with 400', async () => {
    const res = await fetch(`${BASE}/api/session/not%20a%20valid%20id!`, { method: 'DELETE' });
    assert.equal(res.status, 400);
  });

  test('rejects a short (guessable) id with 400 — the id is the bearer capability', async () => {
    const res = await fetch(`${BASE}/api/session/abc123`, { method: 'DELETE' });
    assert.equal(res.status, 400);
  });

  test('a scripted sweep trips the dedicated delete limiter (SESSION_DELETE_IP_PER_MIN, 5 here)', async () => {
    const statuses = [];
    for (let i = 0; i < 8; i++) {
      const res = await fetch(`${BASE}/api/session/${sid()}`, { method: 'DELETE' });
      statuses.push(res.status);
    }
    assert.ok(statuses.includes(429), `expected a 429 in ${JSON.stringify(statuses)}`);
    const tripped = await fetch(`${BASE}/api/session/${sid()}`, { method: 'DELETE' });
    assert.equal(tripped.status, 429);
    assert.equal((await tripped.json()).error, 'rate_limited');
  });
});
