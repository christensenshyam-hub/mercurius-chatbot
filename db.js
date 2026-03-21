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
    student_name TEXT DEFAULT NULL
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
  }
};
