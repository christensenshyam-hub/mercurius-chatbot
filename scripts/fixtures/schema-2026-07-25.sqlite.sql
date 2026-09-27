-- scripts/fixtures/schema-2026-07-25.sqlite.sql
-- The SQLite schema exactly as the last successful production deploy
-- (8d62614, 2026-07-25) created it: the SQLite branch of that build's
-- db.initSchema, copied verbatim (`git show 8d62614:db.js`). It still has
-- student_memory, messages without `kind` and reports without
-- user_message / context / resolved_at, and none of the tables added since.
--
-- scripts/pg-smoke.mjs loads it into an EMPTY database, seeds a few July-era
-- rows, then runs today's db.initSchema() over it: the upgrade path the first
-- successful deploy takes against production. Do not edit to match db.js;
-- this file is a snapshot of what production already has.

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
