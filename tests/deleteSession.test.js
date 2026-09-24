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
const { spawn } = require('node:child_process');

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

  test('deletes messages, memory, images, reports, and the session row', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.saveMessage(s, 'user', 'a minor typed this');
    await db.saveMessage(s, 'assistant', 'a reply');
    await db.saveMemory(s, 'interest', 'AI ethics');
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
    assert.ok(result.deleted.student_memory >= 1);
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
});

describe('DELETE /api/session/:sessionId', () => {
  const PORT = 9200 + Math.floor(Math.random() * 700);
  const BASE = `http://localhost:${PORT}`;
  const serverDb = path.join(os.tmpdir(), `merc-delete-http-${crypto.randomBytes(4).toString('hex')}.db`);
  let proc;

  before(async () => {
    await new Promise((resolve, reject) => {
      proc = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: {
          ...process.env,
          PORT: String(PORT),
          DATABASE_URL: '',
          SQLITE_PATH: serverDb,
          ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || 'sk-ant-test-placeholder',
          ALLOWED_ORIGIN: `http://localhost:${PORT}`,
          NODE_ENV: 'test',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let started = false;
      proc.stdout.on('data', (c) => {
        if (!started && c.toString().includes('Mercurius')) { started = true; setTimeout(resolve, 300); }
      });
      proc.stderr.on('data', (c) => {
        const t = c.toString();
        if (!started && (t.includes('Error') || t.includes('EADDRINUSE'))) reject(new Error(t));
      });
      proc.on('error', reject);
      proc.on('exit', (code) => { if (!started) reject(new Error(`server exited ${code}`)); });
      setTimeout(() => { if (!started) reject(new Error('server did not start within 10s')); }, 10000);
    });
  });

  after(() => {
    if (proc) proc.kill('SIGKILL');
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(serverDb + suffix, { force: true }); } catch { /* ignore */ }
    }
  });

  test('reports a report, then erases the whole session (200 ok)', async () => {
    const s = sid();
    // Seed a row through a real route so the session exists server-side.
    let res = await fetch(`${BASE}/api/report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: s, content: 'seed', reason: 'test' }),
    });
    assert.equal(res.status, 200);

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
});
