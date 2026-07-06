-- migrations/001_gamification.sql
-- Standby gamification (mascot: Mercury) — Phase 1 data model.
--
-- ⚠️ NOT AUTO-APPLIED. This is the canonical, operator-run migration for
-- PRODUCTION (PostgreSQL). The server only creates these tables at boot when
-- GAMIFICATION_ENABLED is set (see db.ensureGamificationSchema), which is OFF
-- by default — so the production schema is untouched until someone deliberately
-- runs this file. SQLite (local dev) gets the parallel DDL from db.js.
--
-- ARCHITECTURE RULE — LEVEL ≠ RANK:
--   • xp / level  = engagement track (XP-driven; what Mercury celebrates).
--   • rank        = credentialed AI-literacy competency ladder, advanced ONLY
--                   by a separate Phase-2 competency engine. The `rank` column
--                   below is a PLACEHOLDER ('copper'); NOTHING in Phase 1
--                   computes it from xp / level / streak / usage.

CREATE TABLE IF NOT EXISTS progression (
  session_id       TEXT PRIMARY KEY REFERENCES sessions(session_id),
  xp               INTEGER NOT NULL DEFAULT 0,
  level            INTEGER NOT NULL DEFAULT 1,
  current_streak   INTEGER NOT NULL DEFAULT 0,
  longest_streak   INTEGER NOT NULL DEFAULT 0,
  last_active_date TEXT    DEFAULT NULL,
  rank             TEXT    NOT NULL DEFAULT 'copper',  -- PLACEHOLDER; never set from XP in Phase 1
  created_at       BIGINT  NOT NULL,
  updated_at       BIGINT  NOT NULL
);

-- Append-only XP audit log. One row per *awarded* event (capped / duplicate /
-- diminished-to-zero events are not written). `metadata` is JSON-as-text.
CREATE TABLE IF NOT EXISTS xp_ledger (
  id          SERIAL  PRIMARY KEY,
  session_id  TEXT    NOT NULL REFERENCES sessions(session_id),
  amount      INTEGER NOT NULL,
  reason      TEXT    NOT NULL,
  source_type TEXT    NOT NULL,
  source_id   TEXT    DEFAULT NULL,
  session_ref TEXT    DEFAULT NULL,
  metadata    TEXT    DEFAULT NULL,
  created_at  BIGINT  NOT NULL
);

-- Idempotency: a structural event (module / reflection / daily-return) carries
-- a stable (source_type, source_id); this unique index makes a replay a no-op.
-- Non-idempotent reasoning moves use a NULL source_id (NULLs are distinct in
-- both Postgres and SQLite unique indexes), so they are never deduped.
CREATE UNIQUE INDEX IF NOT EXISTS idx_xp_ledger_idem ON xp_ledger(session_id, source_type, source_id);

-- Read path for caps / diminishing-returns counting and the recent-events feed.
CREATE INDEX IF NOT EXISTS idx_xp_ledger_session ON xp_ledger(session_id, reason, created_at);
