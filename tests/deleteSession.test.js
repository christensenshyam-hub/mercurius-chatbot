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
