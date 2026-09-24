'use strict';

// Tests for the messages.kind column ('chat' | 'lesson') and the db.js
// contract around it: saveMessage's 4th argument, getMessages' { kind }
// filter, and the add-column migration for databases that predate the column.
//
// Runs directly against a temp SQLite db (the local driver), like
// tests/dbAdditions.test.js, so it needs no live Postgres. The migration case
// builds a second temp db BY HAND with the old messages schema (no kind
// column) and runs initSchema against it in a child process — db.js binds to
// SQLITE_PATH once at require time, so a second database needs a second
// process. That keeps this file's main db on the fresh CREATE TABLE path and
// the child on the ALTER TABLE path, so both are covered.

const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const tag = crypto.randomBytes(4).toString('hex');
const dbPath = path.join(os.tmpdir(), `merc-kind-${tag}.db`);
const oldDbPath = path.join(os.tmpdir(), `merc-kind-old-${tag}.db`);
const resultPath = path.join(os.tmpdir(), `merc-kind-old-${tag}.json`);
process.env.SQLITE_PATH = dbPath;         // must be set BEFORE db.js is required
delete process.env.DATABASE_URL;          // force the SQLite driver
const db = require('../db');

function sid() { return 'test_' + crypto.randomBytes(8).toString('hex'); }

async function kindsOf(sessionId) {
  const rows = await db.queryRaw('SELECT role, content, kind FROM messages WHERE session_id = ? ORDER BY id', [sessionId]);
  return rows.map((r) => [r.role, r.content, r.kind]);
}

before(async () => { await db.initSchema(); });
after(() => {
  for (const base of [dbPath, oldDbPath]) {
    for (const suffix of ['', '-wal', '-shm']) {
      try { fs.rmSync(base + suffix, { force: true }); } catch { /* ignore */ }
    }
  }
  try { fs.rmSync(resultPath, { force: true }); } catch { /* ignore */ }
});

describe('messages.kind schema (fresh database)', () => {
  test('column exists, NOT NULL, defaults to chat; (session_id, kind, timestamp) index present', async () => {
    const cols = await db.queryRaw('PRAGMA table_info(messages)');
    const kind = cols.find((c) => c.name === 'kind');
    assert.ok(kind, 'kind column present');
    assert.equal(kind.notnull, 1, 'NOT NULL');
    assert.equal(kind.dflt_value, "'chat'", "DEFAULT 'chat'");
    const indexes = (await db.queryRaw('PRAGMA index_list(messages)')).map((i) => i.name);
    assert.ok(indexes.includes('idx_messages_session_kind'), `index present (have: ${indexes.join(', ')})`);
    assert.ok(indexes.includes('idx_messages_session'), 'existing index untouched');
  });

  test('initSchema is idempotent on a database that already has the column', async () => {
    await db.initSchema();
    const cols = (await db.queryRaw('PRAGMA table_info(messages)')).filter((c) => c.name === 'kind');
    assert.equal(cols.length, 1, 'exactly one kind column');
  });
});

describe('saveMessage kind', () => {
  test('3-arg call (existing callers) stores kind chat', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.saveMessage(s, 'user', 'hi');
    await db.saveMessage(s, 'assistant', 'hello');
    assert.deepEqual(await kindsOf(s), [['user', 'hi', 'chat'], ['assistant', 'hello', 'chat']]);
  });

  test("explicit 'chat' and 'lesson' are stored as given", async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.saveMessage(s, 'user', 'free chat', 'chat');
    await db.saveMessage(s, 'user', 'lesson turn', 'lesson');
    await db.saveMessage(s, 'assistant', 'lesson reply', 'lesson');
    assert.deepEqual(await kindsOf(s), [
      ['user', 'free chat', 'chat'],
      ['user', 'lesson turn', 'lesson'],
      ['assistant', 'lesson reply', 'lesson'],
    ]);
  });

  test('anything else is coerced to chat, never rejected', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    for (const bad of ['quiz', 'LESSON', '', null, undefined, 42, {}, ['lesson']]) {
      await db.saveMessage(s, 'user', `k=${String(bad)}`, bad);
    }
    const kinds = (await kindsOf(s)).map((r) => r[2]);
    assert.equal(kinds.length, 8);
    assert.ok(kinds.every((k) => k === 'chat'), `all chat, got ${kinds.join(',')}`);
  });

  test('message_count still increments for every kind', async () => {
    const s = sid();
    await db.getOrCreateSession(s);
    await db.saveMessage(s, 'user', 'a');
    await db.saveMessage(s, 'user', 'b', 'lesson');
    await db.saveMessage(s, 'assistant', 'c', 'lesson');
    const state = await db.getSessionState(s);
    assert.equal(state.message_count, 3);
  });
});

describe('getMessages kind filter', () => {
  // Interleaved chat + lesson turns, saved in this order. saveMessage stamps
  // Date.now(); same-millisecond rows are tie-broken by id, so insertion order
  // IS chronological order for the assertions below.
  const turns = [
    ['user', 'c1', 'chat'],
    ['assistant', 'c2', 'chat'],
    ['user', 'l1', 'lesson'],
    ['assistant', 'l2', 'lesson'],
    ['user', 'c3', 'chat'],
    ['user', 'l3', 'lesson'],
    ['assistant', 'l4', 'lesson'],
    ['assistant', 'c4', 'chat'],
  ];
  let s;
  before(async () => {
    s = sid();
    await db.getOrCreateSession(s);
    for (const [role, content, kind] of turns) await db.saveMessage(s, role, content, kind);
  });

  const contents = (rows) => rows.map((r) => r.content);

  test('no kind → every turn, chronological, { role, content } only', async () => {
    const rows = await db.getMessages(s, 50);
    assert.deepEqual(contents(rows), turns.map((t) => t[1]));
    assert.deepEqual(Object.keys(rows[0]).sort(), ['content', 'role'], 'no extra columns leak into the Anthropic messages shape');
  });

  test('{} (empty options) behaves like no kind', async () => {
    assert.deepEqual(contents(await db.getMessages(s, 50, {})), turns.map((t) => t[1]));
  });

  test("kind: 'chat' → only chat turns, chronological", async () => {
    assert.deepEqual(contents(await db.getMessages(s, 50, { kind: 'chat' })), ['c1', 'c2', 'c3', 'c4']);
  });

  test("kind: 'lesson' → only lesson turns, chronological", async () => {
    assert.deepEqual(contents(await db.getMessages(s, 50, { kind: 'lesson' })), ['l1', 'l2', 'l3', 'l4']);
  });

  test('limit bounds the MOST RECENT N of the filtered kind, still chronological', async () => {
    assert.deepEqual(contents(await db.getMessages(s, 2, { kind: 'chat' })), ['c3', 'c4']);
    assert.deepEqual(contents(await db.getMessages(s, 3, { kind: 'lesson' })), ['l2', 'l3', 'l4']);
    // The window is applied after the filter: a chat-only read of the last 3
    // must not be crowded out by the lesson turns that sit between them.
    assert.deepEqual(contents(await db.getMessages(s, 3, { kind: 'chat' })), ['c2', 'c3', 'c4']);
    // Unfiltered limit behaves as it always has (most recent N overall).
    assert.deepEqual(contents(await db.getMessages(s, 3)), ['l3', 'l4', 'c4']);
  });

  test('a kind nothing was saved under → empty, not an error', async () => {
    assert.deepEqual(await db.getMessages(s, 50, { kind: 'quiz' }), []);
  });

  test('unknown session → empty with and without kind', async () => {
    assert.deepEqual(await db.getMessages(sid(), 50), []);
    assert.deepEqual(await db.getMessages(sid(), 50, { kind: 'chat' }), []);
  });
});

describe('add-column migration (database created before messages.kind existed)', () => {
  test('initSchema adds the column; pre-existing rows read back as chat', () => {
    // 1. Build the OLD schema by hand — the exact CREATE TABLE statements
    //    db.js used before the column, so this is a real pre-upgrade file.
    const Database = require('better-sqlite3');
    const old = new Database(oldDbPath);
    const s = 'legacy_' + tag;
    const t0 = 1_700_000_000_000;
    old.exec(`
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        last_active INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0,
        topics TEXT DEFAULT '[]',
        student_name TEXT DEFAULT NULL,
        mode TEXT DEFAULT 'socratic',
        unlocked INTEGER DEFAULT 0,
        test_state TEXT DEFAULT NULL
      );
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id)
      );
      CREATE INDEX idx_messages_session ON messages(session_id, timestamp);
    `);
    old.prepare('INSERT INTO sessions (session_id, created_at, last_active, message_count) VALUES (?, ?, ?, 2)').run(s, t0, t0);
    old.prepare('INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)').run(s, 'user', 'old user turn', t0 + 1);
    old.prepare('INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)').run(s, 'assistant', 'old assistant turn', t0 + 2);
    const beforeCols = old.prepare('PRAGMA table_info(messages)').all().map((c) => c.name);
    old.close();
    assert.ok(!beforeCols.includes('kind'), 'sanity: hand-built schema has no kind column');

    // 2. Run initSchema against it in a child process (db.js binds SQLITE_PATH
    //    at require time). Twice, to prove the migration is idempotent. Then
    //    exercise the read/write API on the migrated file and dump the results.
    const script = `
      const fs = require('node:fs');
      const db = require(${JSON.stringify(path.join(__dirname, '..', 'db.js'))});
      (async () => {
        await db.initSchema();
        await db.initSchema();
        const s = ${JSON.stringify(s)};
        const cols = await db.queryRaw('PRAGMA table_info(messages)');
        const indexes = (await db.queryRaw('PRAGMA index_list(messages)')).map((i) => i.name);
        const rawBefore = await db.queryRaw('SELECT role, content, kind FROM messages WHERE session_id = ? ORDER BY id', [s]);
        const all = await db.getMessages(s, 50);
        const chat = await db.getMessages(s, 50, { kind: 'chat' });
        const lessonBefore = await db.getMessages(s, 50, { kind: 'lesson' });
        await db.saveMessage(s, 'user', 'new lesson turn', 'lesson');
        await db.saveMessage(s, 'assistant', 'new chat turn');
        const lessonAfter = await db.getMessages(s, 50, { kind: 'lesson' });
        const chatAfter = await db.getMessages(s, 50, { kind: 'chat' });
        const rawAfter = await db.queryRaw('SELECT role, content, kind FROM messages WHERE session_id = ? ORDER BY id', [s]);
        fs.writeFileSync(${JSON.stringify(resultPath)}, JSON.stringify({ cols, indexes, rawBefore, all, chat, lessonBefore, lessonAfter, chatAfter, rawAfter }));
      })().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
    `;
    const env = { ...process.env, SQLITE_PATH: oldDbPath };
    delete env.DATABASE_URL;
    let stderr = '';
    try {
      execFileSync(process.execPath, ['-e', script], { env, cwd: path.join(__dirname, '..'), stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      stderr = String(e.stderr || e.message);
      assert.fail(`child initSchema failed:\n${stderr}`);
    }
    const r = JSON.parse(fs.readFileSync(resultPath, 'utf8'));

    // 3. Column + index exist after the migration, once each.
    const kindCols = r.cols.filter((c) => c.name === 'kind');
    assert.equal(kindCols.length, 1, 'exactly one kind column after two initSchema runs');
    assert.equal(kindCols[0].notnull, 1, 'NOT NULL');
    assert.equal(kindCols[0].dflt_value, "'chat'", "DEFAULT 'chat'");
    assert.ok(r.indexes.includes('idx_messages_session_kind'), `index created after the column (have: ${r.indexes.join(', ')})`);

    // 4. Old rows were backfilled as chat and are visible through every read path.
    assert.deepEqual(r.rawBefore, [
      { role: 'user', content: 'old user turn', kind: 'chat' },
      { role: 'assistant', content: 'old assistant turn', kind: 'chat' },
    ]);
    assert.deepEqual(r.all, [{ role: 'user', content: 'old user turn' }, { role: 'assistant', content: 'old assistant turn' }]);
    assert.deepEqual(r.chat, r.all, "kind:'chat' sees every legacy row");
    assert.deepEqual(r.lessonBefore, [], "kind:'lesson' sees none of them");

    // 5. The migrated file accepts new rows of both kinds and filters them.
    assert.deepEqual(r.lessonAfter, [{ role: 'user', content: 'new lesson turn' }]);
    assert.deepEqual(r.chatAfter.map((m) => m.content), ['old user turn', 'old assistant turn', 'new chat turn']);
    assert.deepEqual(r.rawAfter.map((m) => m.kind), ['chat', 'chat', 'lesson', 'chat']);
  });
});
