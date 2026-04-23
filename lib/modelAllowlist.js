'use strict';

/**
 * Model allowlist — controls which upstream model identifiers a
 * request is allowed to name.
 *
 * Why: by default iOS never sends `model`, so every request uses our
 * configured default. But an HTTP client could send
 *   { "model": "claude-4-opus-extra-expensive" }
 * and — until this check existed — the server would pass that
 * straight through to Anthropic. Real risk if the server ever gets
 * exposed beyond our own client.
 *
 * The allowlist is env-configurable:
 *   MODEL_ALLOWLIST=claude-sonnet-4-6,claude-3-5-haiku-latest
 *
 * With no env var, the allowlist is the single model the server is
 * configured to use by default plus the memory-extraction model, so
 * existing clients that send `model` explicitly (matching the
 * server default) continue to work unchanged.
 */

const DEFAULT_ALLOWED = ['claude-sonnet-4-6', 'claude-3-5-haiku-latest'];

function parseEnvList(raw) {
  return (raw || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Returns a frozen Set of allowed model identifiers. Resolved lazily
 * so tests can mutate process.env before calling.
 */
function allowedSet() {
  const envList = parseEnvList(process.env.MODEL_ALLOWLIST);
  const list = envList.length > 0 ? envList : DEFAULT_ALLOWED;
  return new Set(list);
}

/**
 * Pick the model to use for a given request.
 *  - If the caller did not supply one, fall back to `defaultModel`.
 *  - If they did, verify it's on the allowlist. Return `null` + a
 *    diagnostic message if it isn't.
 *
 * Signature is `(requested, defaultModel) → { model, error }` so
 * callers get a sum type they can branch on without a thrown error.
 */
function pickModel(requested, defaultModel) {
  if (requested === undefined || requested === null || requested === '') {
    return { model: defaultModel, error: null };
  }
  const allowed = allowedSet();
  if (!allowed.has(requested)) {
    return {
      model: null,
      error: `model '${requested}' is not on the allowlist`,
    };
  }
  return { model: requested, error: null };
}

module.exports = {
  pickModel,
  allowedSet,
  _DEFAULT_ALLOWED: DEFAULT_ALLOWED,
};
