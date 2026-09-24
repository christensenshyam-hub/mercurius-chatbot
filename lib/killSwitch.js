'use strict';

/**
 * Runtime Claude kill switch (audit finding P0-B).
 *
 * The failure mode this closes: abuse or a runaway bill starts, and the only
 * off-switch is editing a Railway env var — which forces a restart (minutes
 * of continued spend) and wipes in-memory rate-limiter state. This flag flips
 * in-process, via an admin endpoint, in seconds, with no redeploy.
 *
 * Same single-replica reasoning as lib/spendCap: one Railway instance, no
 * Redis, so the in-memory flag IS the deployment-wide state. The settings
 * row is NOT a second source of truth — it is a boot-time seed so a runtime
 * override survives a restart/redeploy (previously a redeploy silently reset
 * the switch to whatever CLAUDE_DISABLED said, so an operator who killed
 * Claude via the endpoint could find it live again after the next push).
 *
 *   - Boot default comes from the CLAUDE_DISABLED env var ('1'/'true'),
 *     so a deploy can also start dark.
 *   - init(db) reads the persisted override (settings key 'claude_disabled',
 *     value '1'/'0'). A row wins over the env default; no row → env.
 *   - set(true|false) overrides at runtime (POST /api/admin/kill-switch) and
 *     writes through to the db when one is attached.
 *   - isKilled() is checked before every Anthropic call, alongside the
 *     daily spend ceiling.
 *
 * Contract:
 *   - init(db)      → Promise<void>. Attaches the db (needs getSetting(key)
 *                     → Promise<string|null> and setSetting(key, value) →
 *                     Promise<void>) and loads the saved override. A read
 *                     failure is logged and falls through to the env default
 *                     — the kill switch must never block boot.
 *   - set(disabled) → Promise<void>. The in-memory change is applied
 *                     SYNCHRONOUSLY, before any await, so callers that don't
 *                     await still get an immediate flip; the db write happens
 *                     after. A write failure is logged, never thrown: memory
 *                     keeps the new value, it just won't survive a restart.
 *   - isKilled()    → boolean, synchronous. Hot path; never touches the db.
 *   - state()       → { disabled, source: 'env'|'runtime', persisted }.
 *                     `persisted` is true only when the current runtime
 *                     override is known to be on disk (loaded at init or
 *                     last write succeeded). Env-sourced state is never
 *                     "persisted" — there is nothing to persist.
 */

const logger = require('./logger');

const SETTING_KEY = 'claude_disabled';

function parseFlag(raw) {
  const s = String(raw == null ? '' : raw).toLowerCase();
  return s === '1' || s === 'true';
}

function envDefault() {
  return parseFlag(process.env.CLAUDE_DISABLED);
}

// null = no runtime override yet → fall through to the env default.
let runtimeOverride = null;
// Attached settings store (see init). null = memory-only (no persistence).
let db = null;
// True once the current runtimeOverride is known to be stored in the db.
let persisted = false;

async function init(database) {
  db = database || null;
  persisted = false;
  if (!db) return;
  try {
    const raw = await db.getSetting(SETTING_KEY);
    if (raw !== null && raw !== undefined) {
      runtimeOverride = parseFlag(raw);
      persisted = true;
    }
  } catch (err) {
    logger.warn(
      { err: err && err.message },
      'kill-switch: failed to read persisted override — falling back to CLAUDE_DISABLED env default',
    );
  }
}

function isKilled() {
  return runtimeOverride === null ? envDefault() : runtimeOverride;
}

async function set(disabled) {
  // Apply to memory first, synchronously: this is the part that actually
  // stops Anthropic calls, and it must not wait on (or be blocked by) the db.
  const value = Boolean(disabled);
  runtimeOverride = value;
  persisted = false;
  if (!db) return;
  try {
    await db.setSetting(SETTING_KEY, value ? '1' : '0');
    // Only mark durable if a newer set() hasn't raced past this write.
    if (runtimeOverride === value) persisted = true;
  } catch (err) {
    logger.warn(
      { err: err && err.message, disabled: value },
      'kill-switch: failed to persist override — in-memory state kept, will not survive a restart',
    );
  }
}

function state() {
  return {
    disabled: isKilled(),
    source: runtimeOverride === null ? 'env' : 'runtime',
    persisted,
  };
}

// Test-only: forget any runtime override and detach the db.
function __resetForTest() {
  runtimeOverride = null;
  db = null;
  persisted = false;
}

module.exports = { init, isKilled, set, state, __resetForTest };
