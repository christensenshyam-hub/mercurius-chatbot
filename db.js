'use strict';

const logger = require('./lib/logger');

// ─── Database abstraction: PostgreSQL (production) or SQLite (local dev) ───
const DATABASE_URL = process.env.DATABASE_URL;
const USE_PG = !!DATABASE_URL;

let pool, sqliteDb;

if (USE_PG) {
  const { Pool } = require('pg');
  pool = new Pool({
    connectionString: DATABASE_URL,
    ssl: DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false },
    max: 10,
    idleTimeoutMillis: 30000,
  });
  logger.info({ driver: 'pg' }, 'db driver: PostgreSQL (persistent)');
} else {
  const Database = require('better-sqlite3');
  const path = require('path');
  // SQLITE_PATH lets tests point at an isolated temp database. Unset in
  // production (which uses Postgres anyway) and in local-default dev → behavior
  // is identical (mercurius.db beside this file).
  const sqlitePath = process.env.SQLITE_PATH || path.join(__dirname, 'mercurius.db');
  sqliteDb = new Database(sqlitePath);
  sqliteDb.pragma('journal_mode = WAL');
  logger.info({ driver: 'sqlite', path: sqlitePath }, 'db driver: SQLite (ephemeral)');
}

// ─── Helper: run a query ───
async function query(sql, params = []) {
  if (USE_PG) {
    // Convert ? placeholders to $1, $2, ... for pg
    let idx = 0;
    const pgSql = sql.replace(/\?/g, () => `$${++idx}`);
    const res = await pool.query(pgSql, params);
    return res.rows;
  } else {
    // SQLite — detect SELECT vs mutation
    const trimmed = sql.trim().toUpperCase();
    if (trimmed.startsWith('SELECT') || trimmed.startsWith('PRAGMA') || trimmed.startsWith('WITH')) {
      return sqliteDb.prepare(sql).all(...params);
    } else {
      sqliteDb.prepare(sql).run(...params);
      return [];
    }
  }
}

async function queryOne(sql, params = []) {
  const rows = await query(sql, params);
  return rows[0] || null;
}

// ─── Schema initialization ───
async function initSchema() {
  if (USE_PG) {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY,
        created_at BIGINT NOT NULL,
        last_active BIGINT NOT NULL,
        message_count INTEGER DEFAULT 0,
        topics TEXT DEFAULT '[]',
        student_name TEXT DEFAULT NULL,
        mode TEXT DEFAULT 'socratic',
        unlocked INTEGER DEFAULT 0,
        test_state TEXT DEFAULT NULL,
        difficulty_level INTEGER DEFAULT 1,
        struggled_topics TEXT DEFAULT '[]',
        streak INTEGER DEFAULT 1,
        last_session_date TEXT DEFAULT NULL,
        total_session_count INTEGER DEFAULT 1,
        display_name TEXT DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS messages (
        id SERIAL PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(session_id),
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL,
        timestamp BIGINT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp);
      CREATE INDEX IF NOT EXISTS idx_sessions_leaderboard ON sessions(message_count, streak);

      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        updated_at BIGINT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS student_memory (
        id SERIAL PRIMARY KEY,
        session_id TEXT NOT NULL,
        memory_type TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at BIGINT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_memory_session ON student_memory(session_id, memory_type);

      -- v3 image uploads. The DB-backed image store (lib/imageStore.js)
      -- persists bytes here; swapping to object storage (S3/R2) later means
      -- a new imageStore driver, not a schema change. id is an opaque,
      -- unguessable token that doubles as the retrieval capability.
      CREATE TABLE IF NOT EXISTS images (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        content_type TEXT NOT NULL,
        file_name TEXT DEFAULT NULL,
        size_bytes BIGINT NOT NULL,
        data BYTEA NOT NULL,
        created_at BIGINT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_images_session ON images(session_id, created_at);

      -- User reports of objectionable AI responses (App Store Guideline 1.2).
      CREATE TABLE IF NOT EXISTS reports (
        id SERIAL PRIMARY KEY,
        session_id TEXT NOT NULL,
        content TEXT NOT NULL,
        reason TEXT DEFAULT NULL,
        created_at BIGINT NOT NULL
      );
    `);
  } else {
    sqliteDb.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
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
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id)
      );
      CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp);
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS student_memory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        memory_type TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_memory_session ON student_memory(session_id, memory_type);
      CREATE TABLE IF NOT EXISTS images (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        content_type TEXT NOT NULL,
        file_name TEXT DEFAULT NULL,
        size_bytes INTEGER NOT NULL,
        data BLOB NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_images_session ON images(session_id, created_at);
      CREATE TABLE IF NOT EXISTS reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        content TEXT NOT NULL,
        reason TEXT DEFAULT NULL,
        created_at INTEGER NOT NULL
      );
    `);
    // Migrate existing SQLite DB: add new columns if missing
    const cols = sqliteDb.prepare('PRAGMA table_info(sessions)').all().map(c => c.name);
    if (!cols.includes('mode'))       sqliteDb.exec("ALTER TABLE sessions ADD COLUMN mode TEXT DEFAULT 'socratic'");
    if (!cols.includes('unlocked'))   sqliteDb.exec("ALTER TABLE sessions ADD COLUMN unlocked INTEGER DEFAULT 0");
    if (!cols.includes('test_state')) sqliteDb.exec("ALTER TABLE sessions ADD COLUMN test_state TEXT DEFAULT NULL");
    if (!cols.includes('difficulty_level'))   sqliteDb.exec("ALTER TABLE sessions ADD COLUMN difficulty_level INTEGER DEFAULT 1");
    if (!cols.includes('struggled_topics'))   sqliteDb.exec("ALTER TABLE sessions ADD COLUMN struggled_topics TEXT DEFAULT '[]'");
    if (!cols.includes('streak'))             sqliteDb.exec("ALTER TABLE sessions ADD COLUMN streak INTEGER DEFAULT 1");
    if (!cols.includes('last_session_date'))  sqliteDb.exec("ALTER TABLE sessions ADD COLUMN last_session_date TEXT DEFAULT NULL");
    if (!cols.includes('total_session_count'))sqliteDb.exec("ALTER TABLE sessions ADD COLUMN total_session_count INTEGER DEFAULT 1");
    if (!cols.includes('display_name')) sqliteDb.exec("ALTER TABLE sessions ADD COLUMN display_name TEXT DEFAULT NULL");
    sqliteDb.exec("CREATE INDEX IF NOT EXISTS idx_sessions_leaderboard ON sessions(message_count, streak)");
  }
}

// ─── Streak day boundary ───
// The product is US-first, so the streak "day" is anchored to a fixed product
// timezone (default America/New_York, override with STREAK_TZ) instead of the
// server's UTC date — with UTC the day flips at 5-8pm local (prime
// after-school time), letting a streak tick twice in one evening while the
// next-morning session earns nothing. 'en-CA' formats as YYYY-MM-DD, the same
// string shape last_session_date has always stored.
function streakDay(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: process.env.STREAK_TZ || 'America/New_York' }).format(now);
}

// ─── Exported async API (same interface as before, but now async) ───
module.exports = {
  initSchema,

  async getOrCreateSession(sessionId) {
    const now = Date.now();
    const existing = await queryOne('SELECT * FROM sessions WHERE session_id = ?', [sessionId]);
    if (existing) {
      await query('UPDATE sessions SET last_active = ? WHERE session_id = ?', [now, sessionId]);
      return existing;
    }
    // ON CONFLICT DO NOTHING (both drivers support it) makes the
    // SELECT-then-INSERT race-safe: two near-simultaneous first-contact
    // requests with the same brand-new sessionId both reach the INSERT, and
    // without it the loser throws duplicate-key — an unhandled rejection.
    await query('INSERT INTO sessions (session_id, created_at, last_active) VALUES (?, ?, ?) ON CONFLICT (session_id) DO NOTHING', [sessionId, now, now]);
    return await queryOne('SELECT * FROM sessions WHERE session_id = ?', [sessionId]);
  },

  async saveMessage(sessionId, role, content) {
    const now = Date.now();
    await query('INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)', [sessionId, role, content, now]);
    await query('UPDATE sessions SET message_count = message_count + 1, last_active = ? WHERE session_id = ?', [now, sessionId]);
  },

  // ─── Images (v3 image upload) ───
  // Persist an uploaded image's bytes + metadata. `data` is a Node Buffer
  // (stored as BYTEA on Postgres, BLOB on SQLite). `id` is an opaque random
  // token generated by the caller; it doubles as the retrieval capability.
  async saveImage({ id, sessionId, contentType, fileName, sizeBytes, data, createdAt }) {
    await query(
      'INSERT INTO images (id, session_id, content_type, file_name, size_bytes, data, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, sessionId, contentType, fileName ?? null, sizeBytes, data, createdAt],
    );
  },

  // Fetch an image row by id. Returns null if absent. `data` comes back as a
  // Buffer on both drivers.
  async getImage(id) {
    return await queryOne(
      'SELECT id, session_id, content_type, file_name, size_bytes, data, created_at FROM images WHERE id = ?',
      [id],
    );
  },

  // ─── Content reports (App Store Guideline 1.2) ───
  async saveReport({ sessionId, content, reason, createdAt }) {
    await query(
      'INSERT INTO reports (session_id, content, reason, created_at) VALUES (?, ?, ?, ?)',
      [sessionId, content, reason ?? null, createdAt],
    );
  },

  async getMessages(sessionId, limit = 50) {
    // Most RECENT N messages, returned in chronological order. ORDER BY ASC
    // with LIMIT would pin the window to the FIRST N rows ever saved, freezing
    // the model's context once a session outgrows the limit. The `id DESC`
    // tie-break keeps same-millisecond user/assistant pairs ordered correctly.
    const rows = await query('SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp DESC, id DESC LIMIT ?', [sessionId, limit]);
    return rows.reverse();
  },

  // NOTE: getPastSessions() was removed. It queried `WHERE session_id != ?`
  // (i.e. OTHER users' sessions) and was used as a memory fallback, which
  // leaked one student's conversation into another's context. Per-user
  // memory lives in student_memory (see buildMemoryProfile), scoped by
  // session_id. Do not reintroduce a cross-session reader here.

  async updateTopics(sessionId, topics) {
    await query('UPDATE sessions SET topics = ? WHERE session_id = ?', [JSON.stringify(topics), sessionId]);
  },

  async getSessionStats(sessionId) {
    const session = await queryOne('SELECT * FROM sessions WHERE session_id = ?', [sessionId]);
    const totalSessions = await queryOne('SELECT COUNT(DISTINCT session_id) as count FROM sessions');
    return { session, totalSessions: totalSessions?.count || 0 };
  },

  async getAllSessionIds() {
    const rows = await query('SELECT session_id FROM sessions ORDER BY last_active DESC');
    return rows.map(r => r.session_id);
  },

  async getSessionState(sessionId) {
    return await queryOne('SELECT mode, unlocked, test_state, message_count FROM sessions WHERE session_id = ?', [sessionId]);
  },

  async setMode(sessionId, mode) {
    await query('UPDATE sessions SET mode = ? WHERE session_id = ?', [mode, sessionId]);
  },

  async getDifficulty(sessionId) {
    const r = await queryOne('SELECT difficulty_level FROM sessions WHERE session_id = ?', [sessionId]);
    return r ? (r.difficulty_level || 1) : 1;
  },

  async setDifficulty(sessionId, level) {
    const clamped = Math.max(1, Math.min(3, level));
    await query('UPDATE sessions SET difficulty_level = ? WHERE session_id = ?', [clamped, sessionId]);
  },

  async getStruggledTopics(sessionId) {
    const r = await queryOne('SELECT struggled_topics FROM sessions WHERE session_id = ? AND struggled_topics IS NOT NULL', [sessionId]);
    try {
      const arr = JSON.parse(r?.struggled_topics || '[]');
      return arr.length > 0 && JSON.stringify(arr) !== '[]' ? arr.slice(0, 5) : [];
    } catch(e) { return []; }
  },

  async addStruggledTopic(sessionId, topic) {
    const r = await queryOne('SELECT struggled_topics FROM sessions WHERE session_id = ?', [sessionId]);
    let arr = [];
    try { arr = JSON.parse(r?.struggled_topics || '[]'); } catch(e){}
    if (!arr.includes(topic)) arr.push(topic);
    if (arr.length > 10) arr = arr.slice(-10);
    await query('UPDATE sessions SET struggled_topics = ? WHERE session_id = ?', [JSON.stringify(arr), sessionId]);
  },

  async updateStreak(sessionId) {
    const r = await queryOne('SELECT streak, last_session_date FROM sessions WHERE session_id = ?', [sessionId]);
    if (!r) return 1;
    const today = streakDay();
    if (r.last_session_date === today) return r.streak || 1;
    let newStreak = 1;
    if (r.last_session_date) {
      // Both strings are YYYY-MM-DD, which Date.parse reads as UTC midnight —
      // so the diff is an exact day count and DST never skews it.
      const diffDays = Math.round((Date.parse(today) - Date.parse(r.last_session_date)) / 86400000);
      newStreak = diffDays <= 2 ? (r.streak || 1) + 1 : 1;
    }
    await query('UPDATE sessions SET streak = ?, last_session_date = ? WHERE session_id = ?', [newStreak, today, sessionId]);
    return newStreak;
  },

  async getStreakData(sessionId) {
    const r = await queryOne('SELECT streak, last_session_date, topics, message_count, unlocked FROM sessions WHERE session_id = ?', [sessionId]);
    return {
      streak: r?.streak || 1,
      lastDate: r?.last_session_date,
      topics: (() => { try { return JSON.parse(r?.topics || '[]'); } catch(e){ return []; } })(),
      messageCount: r?.message_count || 0,
      unlocked: !!(r?.unlocked),
    };
  },

  async getLeaderboard() {
    const rows = await query(`
      SELECT session_id, streak, message_count, unlocked, last_session_date, topics, display_name
      FROM sessions
      WHERE message_count > 2
    `);
    // Rank by the EFFECTIVE streak: the stored streak only counts while it is
    // still alive under updateStreak's own 2-day grace rule. The raw column is
    // never recomputed for sessions that stop chatting, so without this a
    // lapsed 30-day streak from months ago would top the board forever.
    const today = streakDay();
    const ranked = rows
      .map((r) => {
        const diffDays = r.last_session_date
          ? Math.round((Date.parse(today) - Date.parse(r.last_session_date)) / 86400000)
          : Infinity;
        return { ...r, effStreak: diffDays <= 2 ? (r.streak || 1) : 0 };
      })
      .sort((a, b) => (b.effStreak - a.effStreak) || ((b.message_count || 0) - (a.message_count || 0)))
      .slice(0, 20);
    return ranked.map((r, i) => ({
      rank: i + 1,
      badge: r.session_id.slice(-4).toUpperCase(),
      streak: r.effStreak,
      messages: r.message_count || 0,
      unlocked: !!(r.unlocked),
      lastActive: r.last_session_date,
      name: r.display_name || null,
    }));
  },

  async getDashboardStats() {
    const total = (await queryOne('SELECT COUNT(*) as c FROM sessions'))?.c || 0;
    const unlocked = (await queryOne('SELECT COUNT(*) as c FROM sessions WHERE unlocked = 1'))?.c || 0;
    const totalMessages = (await queryOne('SELECT COUNT(*) as c FROM messages'))?.c || 0;
    const recentSessions = await query('SELECT session_id, message_count, streak, topics, unlocked, last_session_date FROM sessions ORDER BY last_active DESC LIMIT 20');
    const topicCounts = {};
    recentSessions.forEach(s => {
      try {
        const arr = JSON.parse(s.topics || '[]');
        arr.forEach(t => { topicCounts[t] = (topicCounts[t] || 0) + 1; });
      } catch(e){}
    });
    const topTopics = Object.entries(topicCounts).sort((a,b) => b[1]-a[1]).slice(0, 8).map(([topic, count]) => ({ topic, count }));
    return {
      totalSessions: total,
      unlockedCount: unlocked,
      unlockRate: total > 0 ? Math.round((unlocked/total)*100) : 0,
      totalMessages,
      avgMessagesPerSession: total > 0 ? Math.round(totalMessages/total) : 0,
      topTopics,
      recentSessions: recentSessions.map(s => ({
        badge: s.session_id.slice(-4).toUpperCase(),
        messages: s.message_count,
        streak: s.streak || 1,
        unlocked: !!(s.unlocked),
        lastActive: s.last_session_date,
      })),
    };
  },

  async getDisplayName(sessionId) {
    const r = await queryOne('SELECT display_name FROM sessions WHERE session_id = ?', [sessionId]);
    return r ? r.display_name : null;
  },

  async setDisplayName(sessionId, name) {
    await query('UPDATE sessions SET display_name = ? WHERE session_id = ?', [name, sessionId]);
  },

  async getEventsFromDB() {
    const row = await queryOne('SELECT data FROM events WHERE id = 1');
    if (!row) return null;
    try { return JSON.parse(row.data); } catch(e) { return null; }
  },

  async setEventsInDB(data) {
    const json = JSON.stringify(data);
    const now = Date.now();
    if (USE_PG) {
      await pool.query(
        'INSERT INTO events (id, data, updated_at) VALUES (1, $1, $2) ON CONFLICT (id) DO UPDATE SET data = $1, updated_at = $2',
        [json, now]
      );
    } else {
      sqliteDb.prepare('INSERT INTO events (id, data, updated_at) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at').run(json, now);
    }
  },

  async getEventsUpdatedAt() {
    const row = await queryOne('SELECT updated_at FROM events WHERE id = 1');
    return row ? row.updated_at : null;
  },

  // ─── Student memory (persistent across sessions) ───

  async saveMemory(sessionId, type, content) {
    const now = Date.now();
    await query('INSERT INTO student_memory (session_id, memory_type, content, created_at) VALUES (?, ?, ?, ?)',
      [sessionId, type, content, now]);
  },

  async getMemories(sessionId, limit = 20) {
    return await query(
      'SELECT memory_type, content, created_at FROM student_memory WHERE session_id = ? ORDER BY created_at DESC LIMIT ?',
      [sessionId, limit]
    );
  },

  async getMemoriesByType(sessionId, type, limit = 10) {
    return await query(
      'SELECT content, created_at FROM student_memory WHERE session_id = ? AND memory_type = ? ORDER BY created_at DESC LIMIT ?',
      [sessionId, type, limit]
    );
  },

  async buildMemoryProfile(sessionId) {
    const memories = await this.getMemories(sessionId, 30);
    if (memories.length === 0) return '';

    const byType = {};
    memories.forEach(m => {
      if (!byType[m.memory_type]) byType[m.memory_type] = [];
      byType[m.memory_type].push(m.content);
    });

    let profile = '\n\n### STUDENT MEMORY PROFILE\n';
    profile += 'You remember the following about this student from past conversations. Use this naturally — reference it when relevant, build on it, never repeat information they already know.\n\n';

    if (byType.interest) {
      profile += '**Interests:** ' + byType.interest.join(', ') + '\n';
    }
    if (byType.strength) {
      profile += '**Strengths:** ' + byType.strength.join(', ') + '\n';
    }
    if (byType.struggle) {
      profile += '**Areas they struggled with:** ' + byType.struggle.join(', ') + '\n';
    }
    if (byType.insight) {
      profile += '**Key insights they had:** ' + byType.insight.slice(0, 5).join(' | ') + '\n';
    }
    if (byType.misconception) {
      profile += '**Misconceptions corrected:** ' + byType.misconception.join(', ') + '\n';
    }
    if (byType.topic) {
      profile += '**Topics explored:** ' + [...new Set(byType.topic)].join(', ') + '\n';
    }
    if (byType.position) {
      profile += '**Positions taken in debate:** ' + byType.position.slice(0, 3).join(' | ') + '\n';
    }

    profile += '\nDo NOT repeat things they already know. Build on their existing knowledge. If they struggled with something before, revisit it gently when the topic comes up again.';
    return profile;
  },

  // ─────────────────────────────────────────────────────────────────────────
  // Standby gamification (mascot: Mercury) — STANDBY / FLAG-GATED.
  //
  // These tables and helpers exist for the gamification feature flag
  // (GAMIFICATION_ENABLED). `ensureGamificationSchema()` is called from
  // server.js ONLY when that flag is on, so with the flag off — the default and
  // production — the tables are never created and the live schema is
  // byte-identical to before. The helpers below are likewise only reached from
  // the flag-gated /api/progression/* routes.
  //
  // LEVEL ≠ RANK: `progression.rank` is a PLACEHOLDER column. No code here (or
  // anywhere in Phase 1) derives it from xp/level/streak. It defaults to
  // 'copper' at row creation and is never recomputed until the separate
  // Phase-2 competency engine owns it. `updateProgression` deliberately omits
  // it. The canonical production migration is migrations/001_gamification.sql.
  // ─────────────────────────────────────────────────────────────────────────

  async ensureGamificationSchema() {
    if (USE_PG) {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS progression (
          session_id TEXT PRIMARY KEY REFERENCES sessions(session_id),
          xp INTEGER NOT NULL DEFAULT 0,
          level INTEGER NOT NULL DEFAULT 1,
          current_streak INTEGER NOT NULL DEFAULT 0,
          longest_streak INTEGER NOT NULL DEFAULT 0,
          last_active_date TEXT DEFAULT NULL,
          rank TEXT NOT NULL DEFAULT 'copper',
          created_at BIGINT NOT NULL,
          updated_at BIGINT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS xp_ledger (
          id SERIAL PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES sessions(session_id),
          amount INTEGER NOT NULL,
          reason TEXT NOT NULL,
          source_type TEXT NOT NULL,
          source_id TEXT DEFAULT NULL,
          session_ref TEXT DEFAULT NULL,
          metadata TEXT DEFAULT NULL,
          created_at BIGINT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_xp_ledger_idem ON xp_ledger(session_id, source_type, source_id);
        CREATE INDEX IF NOT EXISTS idx_xp_ledger_session ON xp_ledger(session_id, reason, created_at);
      `);
    } else {
      sqliteDb.exec(`
        CREATE TABLE IF NOT EXISTS progression (
          session_id TEXT PRIMARY KEY,
          xp INTEGER NOT NULL DEFAULT 0,
          level INTEGER NOT NULL DEFAULT 1,
          current_streak INTEGER NOT NULL DEFAULT 0,
          longest_streak INTEGER NOT NULL DEFAULT 0,
          last_active_date TEXT DEFAULT NULL,
          rank TEXT NOT NULL DEFAULT 'copper',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        );
        CREATE TABLE IF NOT EXISTS xp_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          amount INTEGER NOT NULL,
          reason TEXT NOT NULL,
          source_type TEXT NOT NULL,
          source_id TEXT DEFAULT NULL,
          session_ref TEXT DEFAULT NULL,
          metadata TEXT DEFAULT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_xp_ledger_idem ON xp_ledger(session_id, source_type, source_id);
        CREATE INDEX IF NOT EXISTS idx_xp_ledger_session ON xp_ledger(session_id, reason, created_at);
      `);
    }
  },

  // Create the progression row if absent. `rank` is seeded to its placeholder
  // 'copper' here and never touched again by Phase-1 code.
  async ensureProgression(sessionId, now = Date.now()) {
    if (USE_PG) {
      await pool.query(
        `INSERT INTO progression (session_id, xp, level, current_streak, longest_streak, last_active_date, rank, created_at, updated_at)
         VALUES ($1, 0, 1, 0, 0, NULL, 'copper', $2, $2)
         ON CONFLICT (session_id) DO NOTHING`,
        [sessionId, now],
      );
    } else {
      sqliteDb.prepare(
        `INSERT OR IGNORE INTO progression (session_id, xp, level, current_streak, longest_streak, last_active_date, rank, created_at, updated_at)
         VALUES (?, 0, 1, 0, 0, NULL, 'copper', ?, ?)`
      ).run(sessionId, now, now);
    }
  },

  async getProgression(sessionId) {
    return await queryOne(
      'SELECT session_id, xp, level, current_streak, longest_streak, last_active_date, rank, created_at, updated_at FROM progression WHERE session_id = ?',
      [sessionId],
    );
  },

  // Persist a recomputed XP total + Level. Intentionally does NOT write `rank`
  // — keeping the engagement track (xp/level) and the credential track (rank)
  // strictly separate.
  async updateProgression(sessionId, { xp, level, updatedAt = Date.now() }) {
    await query('UPDATE progression SET xp = ?, level = ?, updated_at = ? WHERE session_id = ?', [xp, level, updatedAt, sessionId]);
  },

  // Maintain the progression streak columns (current_streak / longest_streak /
  // last_active_date) — nothing else ever writes them, so without this the
  // /api/progression payload reports streak 0 forever. Day boundary is the UTC
  // calendar date, matching the XP service's startOfUtcDay convention
  // (lib/gamification/xp.js). Same day → no-op; yesterday → extend; any longer
  // gap → reset to 1. Called from /api/progression/event on every XP event.
  async touchProgressionStreak(sessionId, now = Date.now()) {
    const row = await queryOne('SELECT current_streak, longest_streak, last_active_date FROM progression WHERE session_id = ?', [sessionId]);
    if (!row) return;
    const today = new Date(now).toISOString().slice(0, 10);
    if (row.last_active_date === today) return;
    const diffDays = row.last_active_date
      ? Math.round((Date.parse(today) - Date.parse(row.last_active_date)) / 86400000)
      : Infinity;
    const current = diffDays === 1 ? (Number(row.current_streak) || 0) + 1 : 1;
    const longest = Math.max(Number(row.longest_streak) || 0, current);
    await query('UPDATE progression SET current_streak = ?, longest_streak = ?, last_active_date = ?, updated_at = ? WHERE session_id = ?', [current, longest, today, now, sessionId]);
  },

  // Append one awarded event to the ledger. Idempotency is enforced by the
  // unique index on (session_id, source_type, source_id): a replay of a
  // structural event is a no-op. Returns { inserted } so the caller can tell an
  // award from a deduped replay. Branches on the driver because each expresses
  // "insert-or-skip + did-it-insert" differently.
  async recordXpEvent({ sessionId, amount, reason, sourceType, sourceId, sessionRef, metadata, createdAt }) {
    if (USE_PG) {
      const res = await pool.query(
        `INSERT INTO xp_ledger (session_id, amount, reason, source_type, source_id, session_ref, metadata, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (session_id, source_type, source_id) DO NOTHING
         RETURNING id`,
        [sessionId, amount, reason, sourceType, sourceId ?? null, sessionRef ?? null, metadata ?? null, createdAt],
      );
      return { inserted: res.rows.length > 0, ledgerId: res.rows[0] ? res.rows[0].id : null };
    } else {
      const info = sqliteDb.prepare(
        `INSERT OR IGNORE INTO xp_ledger (session_id, amount, reason, source_type, source_id, session_ref, metadata, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(sessionId, amount, reason, sourceType, sourceId ?? null, sessionRef ?? null, metadata ?? null, createdAt);
      return { inserted: info.changes === 1, ledgerId: info.lastInsertRowid != null ? Number(info.lastInsertRowid) : null };
    }
  },

  // Count prior awards of a reason for caps / diminishing returns. Optional
  // filters: `sinceTs` (created_at >= ts, for per-day + rolling-window) and
  // `sessionRef` (per activity-session cap).
  async countXpEvents(sessionId, reason, { sinceTs = null, sessionRef = null } = {}) {
    let sql = 'SELECT COUNT(*) AS c FROM xp_ledger WHERE session_id = ? AND reason = ?';
    const params = [sessionId, reason];
    if (sinceTs != null) { sql += ' AND created_at >= ?'; params.push(sinceTs); }
    if (sessionRef != null) { sql += ' AND session_ref = ?'; params.push(sessionRef); }
    const r = await queryOne(sql, params);
    return r ? Number(r.c) : 0;
  },

  // The append-only ledger is the source of truth for total XP.
  async sumXp(sessionId) {
    const r = await queryOne('SELECT COALESCE(SUM(amount), 0) AS s FROM xp_ledger WHERE session_id = ?', [sessionId]);
    return r ? Number(r.s) : 0;
  },

  async getRecentXpEvents(sessionId, limit = 10) {
    return await query(
      'SELECT amount, reason, source_type, source_id, created_at FROM xp_ledger WHERE session_id = ? ORDER BY created_at DESC LIMIT ?',
      [sessionId, limit],
    );
  },
};
