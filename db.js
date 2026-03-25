'use strict';

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
  console.log('  DB: PostgreSQL (persistent)');
} else {
  const Database = require('better-sqlite3');
  const path = require('path');
  sqliteDb = new Database(path.join(__dirname, 'mercurius.db'));
  sqliteDb.pragma('journal_mode = WAL');
  console.log('  DB: SQLite (ephemeral)');
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
    await query('INSERT INTO sessions (session_id, created_at, last_active) VALUES (?, ?, ?)', [sessionId, now, now]);
    return await queryOne('SELECT * FROM sessions WHERE session_id = ?', [sessionId]);
  },

  async saveMessage(sessionId, role, content) {
    const now = Date.now();
    await query('INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)', [sessionId, role, content, now]);
    await query('UPDATE sessions SET message_count = message_count + 1, last_active = ? WHERE session_id = ?', [now, sessionId]);
  },

  async getMessages(sessionId, limit = 50) {
    return await query('SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT ?', [sessionId, limit]);
  },

  async getPastSessions(sessionId, limit = 3) {
    if (USE_PG) {
      return await query(
        `SELECT m.session_id, STRING_AGG(m.content, ' ||| ') as messages, s.created_at
         FROM messages m
         JOIN sessions s ON m.session_id = s.session_id
         WHERE m.session_id != ? AND m.role = 'assistant'
         GROUP BY m.session_id, s.created_at, s.last_active
         ORDER BY s.last_active DESC
         LIMIT ?`, [sessionId, limit]);
    } else {
      return await query(
        `SELECT m.session_id, GROUP_CONCAT(m.content, ' ||| ') as messages, s.created_at
         FROM messages m
         JOIN sessions s ON m.session_id = s.session_id
         WHERE m.session_id != ? AND m.role = 'assistant'
         GROUP BY m.session_id
         ORDER BY s.last_active DESC
         LIMIT ?`, [sessionId, limit]);
    }
  },

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

  async setUnlocked(sessionId) {
    await query("UPDATE sessions SET unlocked = 1, mode = 'socratic' WHERE session_id = ?", [sessionId]);
  },

  async markUnlocked(sessionId) { await this.setUnlocked(sessionId); },

  async setTestState(sessionId, state) {
    await query('UPDATE sessions SET test_state = ? WHERE session_id = ?', [state, sessionId]);
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
    const today = new Date().toISOString().slice(0, 10);
    if (r.last_session_date === today) return r.streak || 1;
    let newStreak = 1;
    if (r.last_session_date) {
      const last = new Date(r.last_session_date);
      const now = new Date(today);
      const diffDays = Math.round((now - last) / 86400000);
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
      ORDER BY streak DESC, message_count DESC
      LIMIT 20
    `);
    return rows.map((r, i) => ({
      rank: i + 1,
      badge: r.session_id.slice(-4).toUpperCase(),
      streak: r.streak || 1,
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
};
