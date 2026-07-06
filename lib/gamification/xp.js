'use strict';

/**
 * Server-authoritative XP service for the standby gamification system.
 *
 * The CLIENT MAY REQUEST an evaluation; the SERVER DECIDES. Every guard lives
 * here: idempotency, per-session caps, per-day caps, and diminishing returns.
 * Nothing the client sends can mint XP that these rules don't allow.
 *
 * LEVEL ≠ RANK. This service computes XP and Level only. It NEVER reads or
 * writes `rank` — rank advancement is a separate Phase-2 competency engine.
 * The `progression.rank` column is a placeholder this curve must ignore.
 *
 * XP rewards reasoning/engagement moves (see reasons.js), never correctness.
 *
 * `db` is dependency-injected (the db.js module) so the service is unit-
 * testable against a fake. All SQL lives in db.js (Postgres+SQLite parallel).
 */

const reasons = require('./reasons');
const level = require('./level');

/** UTC start-of-day in ms, matching the streak system's date convention. */
function startOfUtcDay(now) {
  const day = new Date(now).toISOString().slice(0, 10);
  return Date.parse(day + 'T00:00:00.000Z');
}

/**
 * Award XP for a reasoning/engagement event. Returns a result envelope; a
 * *business* rejection (capped / duplicate / diminished-to-zero) is a normal
 * outcome reported in `status`, not a thrown error.
 *
 * @param {object} db   the db module
 * @param {object} args { sessionId, reason, sourceType, sourceId, sessionRef, metadata, now }
 */
async function awardXp(db, {
  sessionId,
  reason,
  sourceType = null,
  sourceId = null,
  sessionRef = null,
  metadata = null,
  now = Date.now(),
}) {
  if (!reasons.isValidReason(reason)) {
    return { ok: false, status: 'invalid_reason', awarded: 0 };
  }
  const cfg = reasons.configFor(reason);

  // Structural (idempotent) events need a stable sourceId so the unique index
  // can dedupe replays. Without one we'd mint duplicates, so reject.
  if (cfg.idempotent && !sourceId) {
    return { ok: false, status: 'missing_source_id', awarded: 0 };
  }

  // A progression row must exist before we count/ledger against it.
  await db.ensureProgression(sessionId, now);

  // ── Per-day cap (always enforced) ──
  if (cfg.perDayCap != null) {
    const todayCount = await db.countXpEvents(sessionId, reason, { sinceTs: startOfUtcDay(now) });
    if (todayCount >= cfg.perDayCap) {
      return { ok: true, status: 'capped_day', awarded: 0, ...(await snapshot(db, sessionId)) };
    }
  }

  // ── Per-session cap (only when the client supplies a session_ref) ──
  if (cfg.perSessionCap != null && sessionRef) {
    const sessionCount = await db.countXpEvents(sessionId, reason, { sessionRef });
    if (sessionCount >= cfg.perSessionCap) {
      return { ok: true, status: 'capped_session', awarded: 0, ...(await snapshot(db, sessionId)) };
    }
  }

  // ── Diminishing returns (anti-grind) for repeated low-effort moves ──
  let amount = cfg.baseXp;
  if (cfg.diminishing) {
    const recent = await db.countXpEvents(sessionId, reason, { sinceTs: now - reasons.DIMINISHING.windowMs });
    amount = Math.round(cfg.baseXp * reasons.diminishingMultiplier(recent));
  }
  if (amount <= 0) {
    return { ok: true, status: 'diminished_to_zero', awarded: 0, ...(await snapshot(db, sessionId)) };
  }

  // ── Append to the ledger (idempotency enforced by the unique index) ──
  const insert = await db.recordXpEvent({
    sessionId,
    amount,
    reason,
    sourceType: sourceType || reason,
    sourceId: sourceId || null,
    sessionRef: sessionRef || null,
    metadata: metadata ? JSON.stringify(metadata) : null,
    createdAt: now,
  });
  if (!insert.inserted) {
    // Replay of an idempotent event — no double award.
    return { ok: true, status: 'idempotent', awarded: 0, ...(await snapshot(db, sessionId)) };
  }

  // ── Recompute the XP total + Level from the append-only ledger (source of
  //    truth) and persist. `rank` is deliberately left untouched. ──
  const totalXp = await db.sumXp(sessionId);
  const lvl = level.levelForXp(totalXp);
  await db.updateProgression(sessionId, { xp: totalXp, level: lvl, updatedAt: now });

  const before = Math.max(0, totalXp - amount);
  const leveledUp = level.levelForXp(before) < lvl;

  return {
    ok: true,
    status: 'awarded',
    awarded: amount,
    leveledUp,
    ...(await snapshot(db, sessionId)),
  };
}

/** The derived public view of a session's progression (Level only; no rank). */
async function snapshot(db, sessionId) {
  const row = await db.getProgression(sessionId);
  const xp = row ? Number(row.xp) : 0;
  const ls = level.levelState(xp);
  return {
    xp: ls.xp,
    level: ls.level,
    levelProgress: ls.progress,
    xpToNext: ls.xpToNext,
    currentStreak: row ? Number(row.current_streak) : 0,
    longestStreak: row ? Number(row.longest_streak) : 0,
  };
}

module.exports = { awardXp, snapshot, startOfUtcDay };
