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
 * Redis, so an in-memory flag IS the deployment-wide state.
 *
 *   - Boot default comes from the CLAUDE_DISABLED env var ('1'/'true'),
 *     so a deploy can also start dark.
 *   - set(true|false) overrides at runtime (POST /api/admin/kill-switch).
 *   - isKilled() is checked before every Anthropic call, alongside the
 *     daily spend ceiling.
 */

function envDefault() {
  const raw = String(process.env.CLAUDE_DISABLED || '').toLowerCase();
  return raw === '1' || raw === 'true';
}

// null = no runtime override yet → fall through to the env default.
let runtimeOverride = null;

function isKilled() {
  return runtimeOverride === null ? envDefault() : runtimeOverride;
}

function set(disabled) {
  runtimeOverride = Boolean(disabled);
}

function state() {
  return {
    disabled: isKilled(),
    source: runtimeOverride === null ? 'env' : 'runtime',
  };
}

// Test-only: forget any runtime override.
function __resetForTest() {
  runtimeOverride = null;
}

module.exports = { isKilled, set, state, __resetForTest };
