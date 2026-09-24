'use strict';

/**
 * Anthropic list prices and the arithmetic that turns an SDK `usage` object
 * into US dollars. This is the pricing half of the daily spend cap
 * (lib/spendCap) — that module accumulates what this one computes.
 *
 * Rates are USD per MILLION tokens, first-party API list price. The four
 * token classes the API reports are billed at different multiples of the
 * uncached input rate:
 *
 *   input_tokens                 1×      (uncached prompt)
 *   output_tokens                5×      (Sonnet: $15 vs $3)
 *   cache_creation_input_tokens  1.25×   (writing a prompt-cache prefix)
 *   cache_read_input_tokens      0.1×    (serving a prefix from cache)
 *
 * `input_tokens` in the SDK usage object EXCLUDES the cached classes, so the
 * four counts are disjoint and simply summed.
 *
 * Contract:
 *   - PRICES                 → frozen { modelId: { in, out, cacheWrite,
 *                              cacheRead } } for the models this server may
 *                              call (see lib/modelAllowlist).
 *   - priceFor(model)        → the rate card for a model id. Exact match
 *                              first, then prefix match so dated snapshots
 *                              ('claude-haiku-4-5-20251001') and '-latest'
 *                              aliases resolve to their family. Unknown ids
 *                              get SONNET rates — the most expensive card in
 *                              the table — so a mis-priced model can only
 *                              over-count, never under-count, spend.
 *   - costUsd(model, usage)  → dollars for one completed call. `usage` is the
 *                              SDK `message.usage` shape; missing/NaN fields
 *                              count as 0, so a bare `{}` or `undefined`
 *                              costs $0.
 *   - normalizeUsage(usage)  → { input, output, cacheRead, cacheWrite } with
 *                              the same missing/NaN → 0 rule (shared with
 *                              lib/spendCap's per-class token tally).
 *   - estimateTokens(text)   → rough token count for a string when no usage
 *                              object is available (~3.8 chars per token for
 *                              English prose). Used for the estimate
 *                              fallback, never for billing reconciliation.
 */

const PRICES = Object.freeze({
  'claude-sonnet-4-6': Object.freeze({ in: 3, out: 15, cacheWrite: 3.75, cacheRead: 0.30 }),
  'claude-haiku-4-5': Object.freeze({ in: 1, out: 5, cacheWrite: 1.25, cacheRead: 0.10 }),
});

// The conservative default: any id we can't place is priced as Sonnet.
const FALLBACK_MODEL = 'claude-sonnet-4-6';

// Average characters per token for English prose — a deliberate slight
// under-estimate of chars/token (i.e. over-estimate of tokens) so the
// fallback errs toward counting more spend, not less.
const CHARS_PER_TOKEN = 3.8;

function priceFor(model) {
  const id = String(model || '').trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(PRICES, id)) return PRICES[id];
  // Prefix match at a '-' boundary: 'claude-haiku-4-5-20251001' and
  // 'claude-haiku-4-5-latest' → 'claude-haiku-4-5'. Longest key wins so a
  // future 'claude-sonnet-4-6-x' entry would shadow 'claude-sonnet-4-6'.
  let best = null;
  for (const key of Object.keys(PRICES)) {
    if (id.startsWith(key + '-') && (best === null || key.length > best.length)) best = key;
  }
  return PRICES[best === null ? FALLBACK_MODEL : best];
}

// Non-finite or negative → 0. The API never reports negatives; guarding
// keeps a malformed usage object from subtracting spend.
function count(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function normalizeUsage(usage) {
  const u = usage && typeof usage === 'object' ? usage : {};
  return {
    input: count(u.input_tokens),
    output: count(u.output_tokens),
    cacheRead: count(u.cache_read_input_tokens),
    cacheWrite: count(u.cache_creation_input_tokens),
  };
}

function costUsd(model, usage) {
  const p = priceFor(model);
  const t = normalizeUsage(usage);
  return (
    t.input * p.in +
    t.output * p.out +
    t.cacheRead * p.cacheRead +
    t.cacheWrite * p.cacheWrite
  ) / 1_000_000;
}

function estimateTokens(text) {
  return Math.ceil(String(text || '').length / CHARS_PER_TOKEN);
}

module.exports = { PRICES, FALLBACK_MODEL, priceFor, costUsd, normalizeUsage, estimateTokens };
