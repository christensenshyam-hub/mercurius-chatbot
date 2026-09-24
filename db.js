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
    // Bounded waits (ops safety rails): a wedged Postgres must surface as a
    // fast error, not a request that hangs until the client gives up.
    // statement_timeout is enforced server-side per connection; query_timeout
    // is the client-side backstop; connectionTimeoutMillis caps checkout from
    // the pool when every connection is busy or the host is unreachable.
    statement_timeout: 10000,
    query_timeout: 10000,
    connectionTimeoutMillis: 5000,
  });
  // pg-pool emits 'error' for a failure on an IDLE client (Postgres restart,
  // proxy reset). With no listener that is an uncaught exception that takes
  // the whole process — and every open lesson stream — down. The pool drops
  // the dead client itself; we only need to log it.
  pool.on('error', (err) => {
    logger.error({ err: err.message }, 'pg pool idle client error');
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
        timestamp BIGINT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'chat'
      );

      -- messages.kind ('chat' | 'lesson'): lets the free-chat history replay
      -- and the quiz/report-card/concept-map helpers read only the turns that
      -- belong to them. Existing rows predate the column and are all free
      -- chat, so the DEFAULT backfills them correctly. The ALTER is the
      -- migration for databases created before the column existed; it must
      -- run BEFORE the (session_id, kind, timestamp) index is created.
      ALTER TABLE messages ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'chat';

      CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp);
      CREATE INDEX IF NOT EXISTS idx_messages_session_kind ON messages(session_id, kind, timestamp);
      CREATE INDEX IF NOT EXISTS idx_sessions_leaderboard ON sessions(message_count, streak);

      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        updated_at BIGINT NOT NULL
      );

      -- student_memory (the LLM-extracted profile of each student) is gone:
      -- never created here again, dropped in prod by migrations/002.

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

      -- Runtime key/value settings (ops safety rails): admin-flipped switches
      -- that must survive a restart, unlike the in-memory lib/killSwitch flag.
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at BIGINT NOT NULL
      );

      -- Per-call usage/cost ledger: one row per Anthropic call (or refusal).
      -- Feeds the spend cap, per-session throttles and the admin stats view.
      -- session_id is a plain column (no FK) so a row can outlive its session
      -- for accounting — deleteSession still clears it (privacy cascade).
      CREATE TABLE IF NOT EXISTS usage (
        id SERIAL PRIMARY KEY,
        ts BIGINT NOT NULL,
        session_id TEXT,
        ip_hash TEXT,
        route TEXT NOT NULL,
        kind TEXT NOT NULL,
        model TEXT,
        input_tokens INTEGER DEFAULT 0,
        output_tokens INTEGER DEFAULT 0,
        cache_read_tokens INTEGER DEFAULT 0,
        cache_write_tokens INTEGER DEFAULT 0,
        cost_usd DOUBLE PRECISION DEFAULT 0,
        status TEXT NOT NULL,
        error_kind TEXT,
        duration_ms INTEGER,
        trace_id TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_usage_ts ON usage(ts);
      CREATE INDEX IF NOT EXISTS idx_usage_session ON usage(session_id, ts);

      -- Read-path indexes for the admin/ops queries (recent sessions, per-session
      -- report lookups, time-windowed message counts).
      CREATE INDEX IF NOT EXISTS idx_sessions_last_active ON sessions(last_active);
      CREATE INDEX IF NOT EXISTS idx_reports_session ON reports(session_id);
      CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
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
        kind TEXT NOT NULL DEFAULT 'chat',
        FOREIGN KEY (session_id) REFERENCES sessions(session_id)
      );
      CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp);
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
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
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        session_id TEXT,
        ip_hash TEXT,
        route TEXT NOT NULL,
        kind TEXT NOT NULL,
        model TEXT,
        input_tokens INTEGER DEFAULT 0,
        output_tokens INTEGER DEFAULT 0,
        cache_read_tokens INTEGER DEFAULT 0,
        cache_write_tokens INTEGER DEFAULT 0,
        cost_usd REAL DEFAULT 0,
        status TEXT NOT NULL,
        error_kind TEXT,
        duration_ms INTEGER,
        trace_id TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_usage_ts ON usage(ts);
      CREATE INDEX IF NOT EXISTS idx_usage_session ON usage(session_id, ts);
      CREATE INDEX IF NOT EXISTS idx_sessions_last_active ON sessions(last_active);
      CREATE INDEX IF NOT EXISTS idx_reports_session ON reports(session_id);
      CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
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
    // messages.kind ('chat' | 'lesson') — see the pg block above. SQLite
    // allows ADD COLUMN ... NOT NULL only with a non-null DEFAULT, which is
    // exactly what backfills every pre-existing row as free chat. The index
    // is created here (not in the exec block) so it never precedes the column.
    const msgCols = sqliteDb.prepare('PRAGMA table_info(messages)').all().map(c => c.name);
    if (!msgCols.includes('kind')) sqliteDb.exec("ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'chat'");
    sqliteDb.exec("CREATE INDEX IF NOT EXISTS idx_messages_session_kind ON messages(session_id, kind, timestamp)");
  }

  // Privacy: the name columns are dead (no reader or writer remains in the
  // server), so any value still sitting in them is retained personal data
  // with no purpose. Scrub on every boot until the columns are dropped. A
  // scrub failure is logged loudly but never blocks boot — an unavailable
  // app protects nobody.
  try {
    const scrubbed = await scrubLegacyNames();
    if (scrubbed > 0) logger.info({ scrubbed }, 'scrubLegacyNames: cleared legacy name columns');
  } catch (e) {
    logger.error({ err: e }, 'scrubLegacyNames failed');
  }
}

// ─── Legacy name scrub (privacy) ───
// NULLs sessions.display_name / sessions.student_name wherever either is set.
// Returns the number of rows touched (0 when already clean). Idempotent; runs
// at the end of initSchema and is exported for the tests and ops scripts.
async function scrubLegacyNames() {
  const sql = 'UPDATE sessions SET display_name = NULL, student_name = NULL WHERE display_name IS NOT NULL OR student_name IS NOT NULL';
  if (USE_PG) {
    const r = await pool.query(sql);
    return r.rowCount || 0;
  }
  return sqliteDb.prepare(sql).run().changes;
}

// ─── Raw access (scripts/migrate.mjs only) ───
// Two thin escape hatches so the migration runner can share this file's
// driver selection (DATABASE_URL → pg, else better-sqlite3 at SQLITE_PATH)
// instead of duplicating it. Application code must use the typed API below.
//
//   runRaw(sql)          → execute a possibly multi-statement SQL string with
//                          NO parameters, atomically: Postgres runs a
//                          multi-statement simple query in one implicit
//                          transaction; SQLite wraps exec() in an explicit one.
//                          The string must therefore not contain its own
//                          BEGIN/COMMIT. Resolves to undefined.
//   queryRaw(sql, params) → one statement with `?` placeholders; resolves to
//                          the result rows ([] for mutations on SQLite).
async function runRaw(sql) {
  if (USE_PG) {
    await pool.query(sql);
    return;
  }
  sqliteDb.transaction(() => { sqliteDb.exec(sql); })();
}

async function queryRaw(sql, params = []) {
  return await query(sql, params);
}

// Coerce a driver value (pg returns COUNT/SUM(bigint) as strings) to a number.
function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
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
  scrubLegacyNames,
  runRaw,
  queryRaw,

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

  async sessionExists(sessionId) {
    return Boolean(await queryOne('SELECT 1 AS one FROM sessions WHERE session_id = ?', [sessionId]));
  },

  // getOrCreateSession + "did this call create it": the per-IP new-session
  // quota keys off `created`, which the timestamp-equality heuristic it
  // replaces got wrong whenever a first turn errored before any write.
  async ensureSession(sessionId) {
    const existed = await this.sessionExists(sessionId);
    const row = await this.getOrCreateSession(sessionId);
    return { row, created: !existed };
  },

  // ─── Messages ───
  // Every persisted turn carries a `kind` so readers can pick the slice of
  // history that belongs to them instead of replaying a session's lifetime:
  //   'chat'   — free-chat turns (the default; every row that predates the
  //              column is free chat and was backfilled as such).
  //   'lesson' — curriculum turns, which the quiz / report-card / concept-map
  //              helpers must NOT ingest.
  // Contract:
  //   saveMessage(sessionId, role, content, kind = 'chat')
  //       → `kind` is coerced to 'chat' | 'lesson'; anything else (undefined,
  //         a typo, an old 3-arg caller) is stored as 'chat', never rejected.
  //   getMessages(sessionId, limit = 50, { kind } = {})
  //       → the most RECENT `limit` rows, in chronological order, as
  //         [{ role, content }] — exactly the shape the Anthropic messages
  //         array takes, so no extra columns are ever returned. With `kind`
  //         set, only rows of that kind are considered (the window is applied
  //         AFTER the filter, so 50 lesson turns never crowd out chat turns).
  async saveMessage(sessionId, role, content, kind = 'chat') {
    const now = Date.now();
    const k = kind === 'lesson' ? 'lesson' : 'chat';
    await query('INSERT INTO messages (session_id, role, content, timestamp, kind) VALUES (?, ?, ?, ?, ?)', [sessionId, role, content, now, k]);
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

  // ─── Settings (persistent runtime key/value) ───
  // Small string-valued switches an admin flips at runtime and that must
  // survive a restart (the in-memory lib/killSwitch flag does not). Values
  // are stored as TEXT; callers parse. Contract:
  //   getSetting(key)        → string | null (null when unset)
  //   setSetting(key, value) → upsert; `value` is coerced with String()
  async getSetting(key) {
    const r = await queryOne('SELECT value FROM settings WHERE key = ?', [key]);
    return r ? String(r.value) : null;
  },

  async setSetting(key, value) {
    await query(
      'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
      [key, String(value), Date.now()],
    );
  },

  // ─── Usage ledger (per-call cost accounting) ───
  // One row per Anthropic call (or per refusal, when the caller records one).
  // The spend cap, per-session throttles and admin stats all read from here,
  // so it is the single source of truth for "what did we spend and on whom".
  //
  //   recordUsage(row) → never throws: a failed ledger write is logged and
  //                      swallowed, because losing one accounting row must
  //                      never fail the student's request. Resolves true when
  //                      written, false when swallowed. Row keys are camelCase
  //                      (sessionId, ipHash, inputTokens, …); the snake_case
  //                      column names are accepted too. `ts` defaults to now;
  //                      route/kind/status default to 'unknown' rather than
  //                      violating NOT NULL. `status` is 'ok' for a completed
  //                      call; any other value counts as an error in
  //                      usageSummarySince, classified by `error_kind`.
  //   sumCostSince(tsMs)                → number: USD summed over rows with
  //                                       ts >= tsMs (0 when none).
  //   sessionUsageSince(sessionId, tsMs) → [{ kind, count, usd }] per kind,
  //                                       for per-session throttles.
  //   usageSummarySince(tsMs)           → { calls, usd, byRoute: [{ route,
  //                                       calls, usd }], errors: [{ route,
  //                                       error_kind, count }] } for the admin
  //                                       stats endpoint.
  async recordUsage(row = {}) {
    try {
      const pick = (camel, snake) => (row[camel] !== undefined ? row[camel] : row[snake]);
      const int = (v) => { const n = Number(v); return Number.isFinite(n) ? Math.round(n) : 0; };
      const optInt = (v) => { const n = Number(v); return v != null && Number.isFinite(n) ? Math.round(n) : null; };
      const str = (v, fallback = null) => (v == null || v === '' ? fallback : String(v));
      const tsRaw = Number(row.ts);
      const ts = Number.isFinite(tsRaw) && tsRaw > 0 ? Math.round(tsRaw) : Date.now();
      const cost = Number(pick('costUsd', 'cost_usd'));
      await query(
        `INSERT INTO usage (ts, session_id, ip_hash, route, kind, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_usd, status, error_kind, duration_ms, trace_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          ts,
          str(pick('sessionId', 'session_id')),
          str(pick('ipHash', 'ip_hash')),
          str(row.route, 'unknown'),
          str(row.kind, 'unknown'),
          str(row.model),
          int(pick('inputTokens', 'input_tokens')),
          int(pick('outputTokens', 'output_tokens')),
          int(pick('cacheReadTokens', 'cache_read_tokens')),
          int(pick('cacheWriteTokens', 'cache_write_tokens')),
          Number.isFinite(cost) ? cost : 0,
          str(row.status, 'unknown'),
          str(pick('errorKind', 'error_kind')),
          optInt(pick('durationMs', 'duration_ms')),
          str(pick('traceId', 'trace_id')),
        ],
      );
      return true;
    } catch (e) {
      logger.error({ err: e, route: row && row.route, kind: row && row.kind }, 'recordUsage failed (row dropped)');
      return false;
    }
  },

  async sumCostSince(tsMs) {
    const r = await queryOne('SELECT COALESCE(SUM(cost_usd), 0) AS usd FROM usage WHERE ts >= ?', [num(tsMs)]);
    return r ? num(r.usd) : 0;
  },

  async sessionUsageSince(sessionId, tsMs) {
    const rows = await query(
      'SELECT kind, COUNT(*) AS count, COALESCE(SUM(cost_usd), 0) AS usd FROM usage WHERE session_id = ? AND ts >= ? GROUP BY kind ORDER BY kind',
      [sessionId, num(tsMs)],
    );
    return rows.map((r) => ({ kind: r.kind, count: num(r.count), usd: num(r.usd) }));
  },

  async usageSummarySince(tsMs) {
    const since = num(tsMs);
    const total = await queryOne('SELECT COUNT(*) AS calls, COALESCE(SUM(cost_usd), 0) AS usd FROM usage WHERE ts >= ?', [since]);
    const byRoute = await query(
      'SELECT route, COUNT(*) AS calls, COALESCE(SUM(cost_usd), 0) AS usd FROM usage WHERE ts >= ? GROUP BY route ORDER BY calls DESC, route',
      [since],
    );
    const errors = await query(
      "SELECT route, error_kind, COUNT(*) AS count FROM usage WHERE ts >= ? AND status <> 'ok' GROUP BY route, error_kind ORDER BY count DESC, route, error_kind",
      [since],
    );
    return {
      calls: total ? num(total.calls) : 0,
      usd: total ? num(total.usd) : 0,
      byRoute: byRoute.map((r) => ({ route: r.route, calls: num(r.calls), usd: num(r.usd) })),
      errors: errors.map((r) => ({ route: r.route, error_kind: r.error_kind ?? null, count: num(r.count) })),
    };
  },

  // ─── Health ───
  // ping() → true when `SELECT 1` answers within 2 s, false otherwise (error
  // or timeout). Never throws — it exists for the health endpoint, which must
  // report a dead database rather than hang on it. A ping that times out is
  // left to finish in the background (its rejection is observed by the race,
  // so it can't become an unhandled rejection).
  async ping() {
    let timer;
    const timeout = new Promise((resolve) => { timer = setTimeout(() => resolve(false), 2000); });
    try {
      const ok = await Promise.race([
        (async () => { await query('SELECT 1'); return true; })(),
        timeout,
      ]);
      return ok === true;
    } catch (e) {
      logger.warn({ err: e }, 'db ping failed');
      return false;
    } finally {
      clearTimeout(timer);
    }
  },

  // ─── Right-to-erasure (audit P0-C) ───
  // Delete EVERYTHING keyed to one session, in a single transaction, so the
  // 30-day-deletion promise on marketing/privacy.html is honored by code
  // rather than by hand-run SQL. Children are removed before the sessions row
  // to satisfy the FK constraints. Gamification tables (progression, xp_ledger)
  // exist only when GAMIFICATION_ENABLED has run, and student_memory only
  // until migrations/002 drops it — probe for those first so a DELETE against
  // a missing table never aborts the transaction. The usage ledger is
  // session-keyed too (ip_hash + token counts), so it is part of the cascade.
  // Returns the per-table row counts for an auditable receipt.
  async deleteSession(sessionId) {
    // Child tables first (FK order), then the parent `sessions` row.
    const base = ['messages', 'images', 'reports', 'usage'];
    const optional = ['xp_ledger', 'progression', 'student_memory'];

    if (USE_PG) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const present = [];
        for (const t of optional) {
          const r = await client.query('SELECT to_regclass($1) AS reg', [t]);
          if (r.rows[0] && r.rows[0].reg) present.push(t);
        }
        const deleted = {};
        for (const t of [...present, ...base, 'sessions']) {
          const r = await client.query(`DELETE FROM ${t} WHERE session_id = $1`, [sessionId]);
          deleted[t] = r.rowCount;
        }
        await client.query('COMMIT');
        return { deleted, sessionExisted: (deleted.sessions || 0) > 0 };
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally {
        client.release();
      }
    }

    // SQLite: better-sqlite3 transactions are synchronous + atomic.
    const existing = sqliteDb
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('xp_ledger','progression')")
      .all()
      .map((r) => r.name);
    const order = [...existing, ...base, 'sessions'];
    const deleted = {};
    const txn = sqliteDb.transaction(() => {
      for (const t of order) {
        const info = sqliteDb.prepare(`DELETE FROM ${t} WHERE session_id = ?`).run(sessionId);
        deleted[t] = info.changes;
      }
    });
    txn();
    return { deleted, sessionExisted: (deleted.sessions || 0) > 0 };
  },

  async getMessages(sessionId, limit = 50, { kind } = {}) {
    // Most RECENT N messages, returned in chronological order. ORDER BY ASC
    // with LIMIT would pin the window to the FIRST N rows ever saved, freezing
    // the model's context once a session outgrows the limit. The `id DESC`
    // tie-break keeps same-millisecond user/assistant pairs ordered correctly.
    // The optional `kind` filter narrows the window to one class of turn
    // (see the Messages contract above saveMessage).
    let sql = 'SELECT role, content FROM messages WHERE session_id = ?';
    const params = [sessionId];
    if (kind != null) { sql += ' AND kind = ?'; params.push(String(kind)); }
    sql += ' ORDER BY timestamp DESC, id DESC LIMIT ?';
    params.push(limit);
    const rows = await query(sql, params);
    return rows.reverse();
  },

  // NOTE: there is deliberately no cross-session reader here. An old
  // getPastSessions() queried OTHER users' sessions as a "memory" fallback and
  // leaked one student's conversation into another's context.

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

  // display_name / student_name are never written any more (the widget stopped
  // asking, and scrubLegacyNames() nulls what was stored). The columns stay
  // only because dropping columns is awkward on SQLite.

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
