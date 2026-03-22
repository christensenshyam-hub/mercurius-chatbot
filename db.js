'use strict';

const Database = require('better-sqlite3');
const path = require('path');

const db = new Database(path.join(__dirname, 'mercurius.db'));

// Enable WAL mode for better performance
db.pragma('journal_mode = WAL');

// Create tables
db.exec(`
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
`);

// Migrate existing DB: add new columns if missing
(function migrate() {
  const cols = db.prepare('PRAGMA table_info(sessions)').all().map(c => c.name);
  if (!cols.includes('mode'))       db.exec("ALTER TABLE sessions ADD COLUMN mode TEXT DEFAULT 'socratic'");
  if (!cols.includes('unlocked'))   db.exec("ALTER TABLE sessions ADD COLUMN unlocked INTEGER DEFAULT 0");
  if (!cols.includes('test_state')) db.exec("ALTER TABLE sessions ADD COLUMN test_state TEXT DEFAULT NULL");
  if (!cols.includes('difficulty_level'))   db.exec("ALTER TABLE sessions ADD COLUMN difficulty_level INTEGER DEFAULT 1");
  if (!cols.includes('struggled_topics'))   db.exec("ALTER TABLE sessions ADD COLUMN struggled_topics TEXT DEFAULT '[]'");
  if (!cols.includes('streak'))             db.exec("ALTER TABLE sessions ADD COLUMN streak INTEGER DEFAULT 1");
  if (!cols.includes('last_session_date'))  db.exec("ALTER TABLE sessions ADD COLUMN last_session_date TEXT DEFAULT NULL");
  if (!cols.includes('total_session_count'))db.exec("ALTER TABLE sessions ADD COLUMN total_session_count INTEGER DEFAULT 1");
})();

module.exports = {
  // Get or create a session
  getOrCreateSession(sessionId) {
    const now = Date.now();
    const existing = db.prepare('SELECT * FROM sessions WHERE session_id = ?').get(sessionId);
    if (existing) {
      db.prepare('UPDATE sessions SET last_active = ? WHERE session_id = ?').run(now, sessionId);
      return existing;
    }
    db.prepare('INSERT INTO sessions (session_id, created_at, last_active) VALUES (?, ?, ?)').run(sessionId, now, now);
    return db.prepare('SELECT * FROM sessions WHERE session_id = ?').get(sessionId);
  },

  // Save a message
  saveMessage(sessionId, role, content) {
    const now = Date.now();
    db.prepare('INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)').run(sessionId, role, content, now);
    db.prepare('UPDATE sessions SET message_count = message_count + 1, last_active = ? WHERE session_id = ?').run(now, sessionId);
  },

  // Get recent messages for a session (last N)
  getMessages(sessionId, limit = 50) {
    return db.prepare(
      'SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT ?'
    ).all(sessionId, limit);
  },

  // Get all past sessions except current (for memory summary)
  getPastSessions(sessionId, limit = 3) {
    return db.prepare(
      `SELECT m.session_id, GROUP_CONCAT(m.content, ' ||| ') as messages, s.created_at
       FROM messages m
       JOIN sessions s ON m.session_id = s.session_id
       WHERE m.session_id != ? AND m.role = 'assistant'
       GROUP BY m.session_id
       ORDER BY s.last_active DESC
       LIMIT ?`
    ).all(sessionId, limit);
  },

  // Update topics for a session
  updateTopics(sessionId, topics) {
    db.prepare('UPDATE sessions SET topics = ? WHERE session_id = ?').run(JSON.stringify(topics), sessionId);
  },

  // Get session stats
  getSessionStats(sessionId) {
    const session = db.prepare('SELECT * FROM sessions WHERE session_id = ?').get(sessionId);
    const totalSessions = db.prepare('SELECT COUNT(DISTINCT session_id) as count FROM sessions').get();
    return { session, totalSessions: totalSessions.count };
  },

  // Get all session IDs (for memory lookup)
  getAllSessionIds() {
    return db.prepare('SELECT session_id FROM sessions ORDER BY last_active DESC').all().map(r => r.session_id);
  },

  // Get mode/unlock state for a session
  getSessionState(sessionId) {
    return db.prepare('SELECT mode, unlocked, test_state, message_count FROM sessions WHERE session_id = ?').get(sessionId);
  },

  // Set mode ('socratic' | 'direct') — only allowed if unlocked
  setMode(sessionId, mode) {
    db.prepare('UPDATE sessions SET mode = ? WHERE session_id = ?').run(mode, sessionId);
  },

  // Mark session as unlocked
  setUnlocked(sessionId) {
    db.prepare("UPDATE sessions SET unlocked = 1, mode = 'socratic' WHERE session_id = ?").run(sessionId);
  },

  // Alias for setUnlocked (used by server.js)
  markUnlocked(sessionId) { this.setUnlocked(sessionId); },

  // Update test state: null | 'pending' | 'in_progress' | 'passed' | 'failed'
  setTestState(sessionId, state) {
    db.prepare('UPDATE sessions SET test_state = ? WHERE session_id = ?').run(state, sessionId);
  },

  // Adaptive difficulty: get/set 1-3
  getDifficulty(sessionId) {
    const r = db.prepare('SELECT difficulty_level FROM sessions WHERE session_id = ?').get(sessionId);
    return r ? (r.difficulty_level || 1) : 1;
  },
  setDifficulty(sessionId, level) {
    const clamped = Math.max(1, Math.min(3, level));
    db.prepare('UPDATE sessions SET difficulty_level = ? WHERE session_id = ?').run(clamped, sessionId);
  },

  // Spaced repetition: struggled topics
  getStruggledTopics(sessionId) {
    const rows = db.prepare('SELECT struggled_topics FROM sessions WHERE struggled_topics IS NOT NULL AND struggled_topics != ?').all('[]');
    const all = [];
    rows.forEach(r => {
      try { const arr = JSON.parse(r.struggled_topics || '[]'); arr.forEach(t => { if (!all.includes(t)) all.push(t); }); } catch(e){}
    });
    return all.slice(0, 5);
  },
  addStruggledTopic(sessionId, topic) {
    const r = db.prepare('SELECT struggled_topics FROM sessions WHERE session_id = ?').get(sessionId);
    let arr = [];
    try { arr = JSON.parse(r?.struggled_topics || '[]'); } catch(e){}
    if (!arr.includes(topic)) arr.push(topic);
    if (arr.length > 10) arr = arr.slice(-10);
    db.prepare('UPDATE sessions SET struggled_topics = ? WHERE session_id = ?').run(JSON.stringify(arr), sessionId);
  },

  // Streak tracking
  updateStreak(sessionId) {
    const r = db.prepare('SELECT streak, last_session_date FROM sessions WHERE session_id = ?').get(sessionId);
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
    db.prepare('UPDATE sessions SET streak = ?, last_session_date = ? WHERE session_id = ?').run(newStreak, today, sessionId);
    return newStreak;
  },

  getStreakData(sessionId) {
    const r = db.prepare('SELECT streak, last_session_date, topics, message_count, unlocked FROM sessions WHERE session_id = ?').get(sessionId);
    const totalSessions = db.prepare('SELECT COUNT(*) as c FROM sessions WHERE session_id = ?').get(sessionId);
    return {
      streak: r?.streak || 1,
      lastDate: r?.last_session_date,
      topics: (() => { try { return JSON.parse(r?.topics || '[]'); } catch(e){ return []; } })(),
      messageCount: r?.message_count || 0,
      unlocked: !!(r?.unlocked),
    };
  },

  // Leaderboard: anonymous
  getLeaderboard() {
    return db.prepare(`
      SELECT session_id, streak, message_count, unlocked, last_session_date, topics
      FROM sessions
      WHERE message_count > 2
      ORDER BY streak DESC, message_count DESC
      LIMIT 20
    `).all().map((r, i) => ({
      rank: i + 1,
      badge: r.session_id.slice(-4).toUpperCase(),
      streak: r.streak || 1,
      messages: r.message_count || 0,
      unlocked: !!(r.unlocked),
      lastActive: r.last_session_date,
    }));
  },

  // Dashboard stats
  getDashboardStats() {
    const total = db.prepare('SELECT COUNT(*) as c FROM sessions').get().c;
    const unlocked = db.prepare('SELECT COUNT(*) as c FROM sessions WHERE unlocked = 1').get().c;
    const totalMessages = db.prepare('SELECT COUNT(*) as c FROM messages').get().c;
    const recentSessions = db.prepare('SELECT session_id, message_count, streak, topics, unlocked, last_session_date FROM sessions ORDER BY last_active DESC LIMIT 20').all();
    // Aggregate topics
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
};
