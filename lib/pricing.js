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
 *                              get SONNET 4.6 rates — the most expensive card
 *                              in the table — so a mis-priced model can only
 *                              over-count, never under-count, spend.
 *   - hasRateCard(model)     → whether the id resolves to a card of its own
 *                              (exact or by prefix) rather than the fallback.
 *   - costUsd(model, usage)  → dollars for one completed call. `usage` is the
 *                              SDK `message.usage` shape; missing/NaN fields
 *                              count as 0, so a bare `{}` or `undefined`
 *                              costs $0.
 *   - normalizeUsage(usage)  → { input, output, cacheRead, cacheWrite } with
 *                              the same missing/NaN → 0 rule (shared with
 *                              lib/spendCap's per-class token tally).
 *   - estimateTokens(text, model)
 *                            → rough token count for a string when no usage
 *                              object is available (~3.8 chars per token for
 *                              English prose on the Sonnet 4.6 / Haiku 4.5
 *                              tokenizer, scaled by TOKENIZER_RATIO for a
 *                              model whose tokenizer counts more). Used for
 *                              the estimate fallback, never for billing
 *                              reconciliation.
 */

// Claude Sonnet 5.5 (TUTOR_MODEL=claude-sonnet-5-5) and Claude Sonnet 5 share
// one rate card: $2 in / $10 out, 5-minute cache write $2.50, cache read
// $0.20. Their tokenizer counts about 30% more tokens than Sonnet 4.6's for
// the same text, so a turn costs less per token but not 1/3 less per turn.
const PRICES = Object.freeze({
  'claude-sonnet-4-6': Object.freeze({ in: 3, out: 15, cacheWrite: 3.75, cacheRead: 0.30 }),
  'claude-sonnet-5-5': Object.freeze({ in: 2, out: 10, cacheWrite: 2.50, cacheRead: 0.20 }),
  'claude-sonnet-5': Object.freeze({ in: 2, out: 10, cacheWrite: 2.50, cacheRead: 0.20 }),
  'claude-haiku-4-5': Object.freeze({ in: 1, out: 5, cacheWrite: 1.25, cacheRead: 0.10 }),
});

// The conservative default: any id we can't place is priced as Sonnet 4.6,
// still the most expensive card above.
const FALLBACK_MODEL = 'claude-sonnet-4-6';

// Average characters per token for English prose — a deliberate slight
// under-estimate of chars/token (i.e. over-estimate of tokens) so the
// fallback errs toward counting more spend, not less.
const CHARS_PER_TOKEN = 3.8;

// Tokens per character relative to the Sonnet 4.6 tokenizer, for the
// estimate fallback only (a stream that ended before its final usage).
// Matched like the rate cards; any other id is 1.
const TOKENIZER_RATIO = Object.freeze({
  'claude-sonnet-5-5': 1.3,
  'claude-sonnet-5': 1.3,
});

// The table key an id resolves to: exact match, then prefix match at a '-'
// boundary ('claude-haiku-4-5-20251001' and 'claude-haiku-4-5-latest' →
// 'claude-haiku-4-5'). Longest key wins, so 'claude-sonnet-5-5' shadows
// 'claude-sonnet-5' and a future 'claude-sonnet-4-6-x' entry would shadow
// 'claude-sonnet-4-6'. null when nothing matches.
function tableKey(table, model) {
  const id = String(model || '').trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(table, id)) return id;
  let best = null;
  for (const key of Object.keys(table)) {
    if (id.startsWith(key + '-') && (best === null || key.length > best.length)) best = key;
  }
  return best;
}

function priceFor(model) {
  const key = tableKey(PRICES, model);
  return PRICES[key === null ? FALLBACK_MODEL : key];
}

function hasRateCard(model) {
  return tableKey(PRICES, model) !== null;
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

function estimateTokens(text, model) {
  const base = String(text || '').length / CHARS_PER_TOKEN;
  const key = model === undefined ? null : tableKey(TOKENIZER_RATIO, model);
  if (key === null) return Math.ceil(base);
  // Rounded to 6 places first so float noise (10 × 1.3 = 13.000000000000002)
  // never adds a token.
  return Math.ceil(Number((base * TOKENIZER_RATIO[key]).toFixed(6)));
}

module.exports = { PRICES, FALLBACK_MODEL, TOKENIZER_RATIO, priceFor, hasRateCard, costUsd, normalizeUsage, estimateTokens };
