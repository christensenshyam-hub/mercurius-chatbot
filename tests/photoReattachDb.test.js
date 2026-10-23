'use strict';

// Photo re-attach (AUD-10), storage side: db.linkImageTurn / db.linkedImages,
// imageStore's age window, the erasure cascade, and the boot-time migration
// of an images table created before the turn_key / turn_anchor columns.
// Runs against a temp SQLite file (the local driver), like dbAdditions.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const dbPath = path.join(os.tmpdir(), `merc-photo-db-${crypto.randomBytes(4).toString('hex')}.db`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');
const imageStore = require('../lib/imageStore');

const HOUR_MS = 3_600_000;
const sid = () => 'test_' + crypto.randomBytes(8).toString('hex');
const imgId = () => crypto.randomBytes(18).toString('base64url');
const KEYS = { turnKey: 'a'.repeat(40), anchorKey: 'b'.repeat(40) };

async function seedImage(sessionId, { createdAt = Date.now(), size = 3 } = {}) {
  const id = imgId();
  await db.saveImage({
    id, sessionId, contentType: 'image/png', fileName: null,
    sizeBytes: size, data: Buffer.alloc(size, 1), createdAt,
  });
  return id;
}

before(async () => { await db.initSchema(); });
after(() => {
  delete process.env.IMAGE_RETENTION_HOURS;
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.rmSync(dbPath + suffix, { force: true }); } catch { /* ignore */ }
  }
});

describe('db.linkImageTurn', () => {
  test("links only the session's own image", async () => {
    const owner = sid();
    await db.getOrCreateSession(owner);
    const id = await seedImage(owner);
    assert.equal(await db.linkImageTurn(id, sid(), KEYS), false, 'another session cannot link it');
    assert.equal(await db.linkImageTurn('missing' + imgId(), owner, KEYS), false);
    assert.equal(await db.linkImageTurn(id, owner, { turnKey: 'x' }), false, 'both keys are required');
    assert.deepEqual(await db.linkedImages(owner, { sinceMs: 0 }), []);
    assert.equal(await db.linkImageTurn(id, owner, KEYS), true);
    const [row] = await db.linkedImages(owner, { sinceMs: 0 });
    assert.equal(row.id, id);
    assert.equal(row.turnKey, KEYS.turnKey);
    assert.equal(row.anchorKey, KEYS.anchorKey);
    assert.equal(row.replyKey, null);
    // A later link (the same id sent with another turn) replaces the keys.
    assert.equal(await db.linkImageTurn(id, owner, { turnKey: 'c'.repeat(40), anchorKey: 'd'.repeat(40), replyKey: 'e'.repeat(40) }), true);
    const [again] = await db.linkedImages(owner, { sinceMs: 0 });
    assert.equal(again.turnKey, 'c'.repeat(40));
    assert.equal(again.replyKey, 'e'.repeat(40));
  });
});

describe('db.linkedImages', () => {
  test('that session only, linked rows only, newest first, no bytes, numbers as numbers', async () => {
    const s = sid();
    const other = sid();
    const now = Date.now();
    const old = await seedImage(s, { createdAt: now - 3000, size: 10 });
    const mid = await seedImage(s, { createdAt: now - 2000, size: 20 });
    const unlinked = await seedImage(s, { createdAt: now - 1000 });
    const foreign = await seedImage(other, { createdAt: now });
    for (const id of [old, mid]) await db.linkImageTurn(id, s, KEYS);
    await db.linkImageTurn(foreign, other, KEYS);
    const rows = await db.linkedImages(s, { sinceMs: 0 });
    assert.deepEqual(rows.map((r) => r.id), [mid, old]);
    assert.ok(!rows.some((r) => r.id === unlinked));
    assert.deepEqual(Object.keys(rows[0]).sort(), ['anchorKey', 'createdAt', 'id', 'replyKey', 'sizeBytes', 'turnKey']);
    assert.equal(rows[0].replyKey, null, 'replyKey is optional');
    assert.equal(rows[0].sizeBytes, 20);
    assert.equal(typeof rows[0].createdAt, 'number');
    assert.deepEqual((await db.linkedImages(s, { sinceMs: now - 2500 })).map((r) => r.id), [mid], 'sinceMs bounds the age');
    assert.equal((await db.linkedImages(s, { sinceMs: 0, limit: 1 })).length, 1);
  });

  test('erasure takes the linked photos with it', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    const id = await seedImage(s);
    await db.linkImageTurn(id, s, KEYS);
    const r = await db.deleteSession(s);
    assert.equal(r.deleted.images, 1);
    assert.deepEqual(await db.linkedImages(s, { sinceMs: 0 }), []);
    assert.equal(await db.getImage(id), null);
    assert.equal(await db.linkImageTurn(id, s, KEYS), false, 'a late link writes nothing');
  });
});

describe('imageStore re-attach window', () => {
  test('the store retention, capped at 24 hours', () => {
    delete process.env.IMAGE_RETENTION_HOURS;
    assert.equal(imageStore.reattachMaxAgeMs(), 24 * HOUR_MS);
    process.env.IMAGE_RETENTION_HOURS = '1';
    assert.equal(imageStore.reattachMaxAgeMs(), HOUR_MS);
    process.env.IMAGE_RETENTION_HOURS = '72';
    assert.equal(imageStore.reattachMaxAgeMs(), 24 * HOUR_MS);
    process.env.IMAGE_RETENTION_HOURS = 'off';
    assert.equal(imageStore.reattachMaxAgeMs(), 24 * HOUR_MS);
    delete process.env.IMAGE_RETENTION_HOURS;
  });

  test('linkedForSession leaves out photos past the window', async () => {
    const s = sid();
    const fresh = await seedImage(s, { createdAt: Date.now() - (24 * HOUR_MS - 60_000) });
    const stale = await seedImage(s, { createdAt: Date.now() - (24 * HOUR_MS + 60_000) });
    for (const id of [fresh, stale]) await imageStore.link(id, s, KEYS);
    assert.deepEqual((await imageStore.linkedForSession(s)).map((r) => r.id), [fresh]);
    process.env.IMAGE_RETENTION_HOURS = '1';
    assert.deepEqual(await imageStore.linkedForSession(s), []);
    delete process.env.IMAGE_RETENTION_HOURS;
  });
});

describe('boot migration of an images table from before the columns', () => {
  test('initSchema adds turn_key / turn_anchor / turn_reply once; old rows read back unlinked', () => {
    const oldPath = path.join(os.tmpdir(), `merc-photo-old-${crypto.randomBytes(4).toString('hex')}.db`);
    const resultPath = `${oldPath}.json`;
    const Database = require('better-sqlite3');
    const old = new Database(oldPath);
    const s = sid();
    const id = imgId();
    old.exec(`
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, last_active INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0, topics TEXT DEFAULT '[]', student_name TEXT DEFAULT NULL,
        mode TEXT DEFAULT 'socratic', unlocked INTEGER DEFAULT 0, test_state TEXT DEFAULT NULL
      );
      CREATE TABLE images (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL, content_type TEXT NOT NULL,
        file_name TEXT DEFAULT NULL, size_bytes INTEGER NOT NULL, data BLOB NOT NULL, created_at INTEGER NOT NULL
      );
    `);
    old.prepare('INSERT INTO images (id, session_id, content_type, size_bytes, data, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .run(id, s, 'image/png', 3, Buffer.from([1, 2, 3]), Date.now());
    old.close();
    const script = `
      const fs = require('node:fs');
      const db = require(${JSON.stringify(path.join(__dirname, '..', 'db.js'))});
      (async () => {
        await db.initSchema();
        await db.initSchema();
        const cols = (await db.queryRaw('PRAGMA table_info(images)')).map((c) => c.name);
        const before = await db.linkedImages(${JSON.stringify(s)}, { sinceMs: 0 });
        const ok = await db.linkImageTurn(${JSON.stringify(id)}, ${JSON.stringify(s)}, ${JSON.stringify(KEYS)});
        const after = await db.linkedImages(${JSON.stringify(s)}, { sinceMs: 0 });
        fs.writeFileSync(${JSON.stringify(resultPath)}, JSON.stringify({ cols, before, ok, after }));
      })().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
    `;
    const env = { ...process.env, SQLITE_PATH: oldPath };
    delete env.DATABASE_URL;
    let r;
    try {
      execFileSync(process.execPath, ['-e', script], { env, cwd: path.join(__dirname, '..'), stdio: ['ignore', 'pipe', 'pipe'] });
      r = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    } catch (e) {
      assert.fail(`child initSchema failed:\n${String(e.stderr || e.message)}`);
    } finally {
      for (const f of [oldPath, `${oldPath}-wal`, `${oldPath}-shm`, resultPath]) {
        try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
      }
    }
    for (const c of ['turn_key', 'turn_anchor', 'turn_reply']) {
      assert.equal(r.cols.filter((n) => n === c).length, 1, `exactly one ${c} column`);
    }
    assert.deepEqual(r.before, [], 'a pre-upgrade photo is unlinked');
    assert.equal(r.ok, true);
    assert.deepEqual(r.after.map((x) => x.id), [id]);
  });
});
