'use strict';

/**
 * The one place that shapes the `system` parameter of a model call.
 *
 * Every Anthropic call this server makes sends its system prompt as TWO
 * blocks: a large STATIC block that is byte-identical from call to call and
 * carries `cache_control: { type: 'ephemeral' }`, followed by a small DYNAMIC
 * block (mode, date, per-request context) that is allowed to vary. Prompt
 * caching is a PREFIX match — everything up to and including the last
 * cache_control breakpoint is served from cache when the bytes are identical
 * to a recent call, and any byte that differs anywhere in that prefix
 * invalidates all of it. So the whole cost argument rests on two things this
 * module owns:
 *
 *   1. The static text is assembled deterministically (composeStatic), so the
 *      same logical parts always yield the same bytes. Anything that changes
 *      per request (the date, the mode, club context, an image) MUST go in the
 *      dynamic block, never in the static one.
 *   2. The static block is the only block that carries the breakpoint, and it
 *      is always first. Volatile text after the breakpoint costs full input
 *      price but never disturbs the cache.
 *
 * Why it matters: measured before this change, a lesson turn was ~12–13k
 * input tokens with ZERO cache reads. A cache read on Sonnet is billed at
 * 0.1× the input rate (lib/pricing), so moving the bulk of the prompt behind
 * a stable breakpoint is where most of the targeted ~60% cut comes from.
 *
 * The API silently declines to cache a prefix shorter than the model's
 * minimum (1024 tokens on Sonnet 4.6, the production model — no error, just
 * cache_creation_input_tokens: 0). isCacheable()/MIN_CACHEABLE_TOKENS let
 * callers and tests assert the static block is actually big enough.
 *
 * Contract:
 *   - buildSystem({ staticText, dynamicText })
 *                          → the array for the SDK's `system` field:
 *                              [{ type:'text', text: staticText,
 *                                 cache_control: { type:'ephemeral' } },
 *                               { type:'text', text: dynamicText }]  // optional
 *                            The second block is present only when dynamicText
 *                            is a string that is non-empty after trim (it is
 *                            sent as given, untrimmed). staticText must be a
 *                            string that is non-empty after trim, otherwise a
 *                            TypeError is thrown — an empty system prompt is a
 *                            bug, never something to ship. staticText is sent
 *                            byte-for-byte (NOT trimmed here; composeStatic is
 *                            where normalisation happens). Never mutates its
 *                            input; every call returns fresh objects.
 *   - composeStatic(parts) → joins an array of strings with '\n\n' after
 *                            trimming each part's outer whitespace and
 *                            skipping null/undefined/empty/whitespace-only
 *                            parts. Pure and deterministic: the same logical
 *                            parts always produce a byte-identical string.
 *                            Throws TypeError on a non-array, or on a part
 *                            that is neither a string nor null/undefined, so
 *                            an accidental object can never be baked into the
 *                            cached prefix as '[object Object]'.
 *   - staticSize(text)     → { chars, approxTokens } with
 *                            approxTokens = Math.ceil(chars / CHARS_PER_TOKEN).
 *                            Non-strings count as empty.
 *   - MIN_CACHEABLE_TOKENS → 1024, Sonnet's minimum cacheable prefix.
 *   - isCacheable(text)    → staticSize(text).approxTokens >= MIN_CACHEABLE_TOKENS.
 *   - describe(system)     → for logging/metrics:
 *                              { blocks, staticApproxTokens,
 *                                dynamicApproxTokens, cached }
 *                            Accepts the array form OR a legacy plain string.
 *                            `static` means "billed as a cache write/read":
 *                            every text block up to and including the LAST
 *                            block carrying cache_control (prefix semantics);
 *                            `dynamic` is everything after it, billed at full
 *                            input price. A plain string has no breakpoint,
 *                            so it is all dynamic. `cached` is true only when
 *                            a breakpoint exists AND the prefix meets
 *                            MIN_CACHEABLE_TOKENS — i.e. the API is actually
 *                            expected to cache it. Never throws: null,
 *                            undefined or an unknown shape describe as zeros.
 *   - CHARS_PER_TOKEN      → 3.8, the chars-per-token estimate shared with
 *                            lib/anthropicMock (which bills chars / 3.8).
 *
 * Token figures here are estimates for metrics and guardrails. The
 * authoritative numbers are the `usage` object on each response, which
 * lib/claudeCall settles and prices.
 */

const CHARS_PER_TOKEN = 3.8;

// Sonnet 4.6's minimum cacheable prefix. Shorter prefixes are silently not
// cached (no error — the breakpoint is just ignored).
const MIN_CACHEABLE_TOKENS = 1024;

const CACHE_CONTROL = Object.freeze({ type: 'ephemeral' });

function staticSize(text) {
  const chars = typeof text === 'string' ? text.length : 0;
  return { chars, approxTokens: Math.ceil(chars / CHARS_PER_TOKEN) };
}

function isCacheable(text) {
  return staticSize(text).approxTokens >= MIN_CACHEABLE_TOKENS;
}

function composeStatic(parts) {
  if (!Array.isArray(parts)) {
    throw new TypeError('composeStatic: parts must be an array of strings');
  }
  const kept = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part === null || part === undefined) continue;
    if (typeof part !== 'string') {
      throw new TypeError(`composeStatic: part ${i} is ${typeof part}, expected string`);
    }
    const trimmed = part.trim();
    if (trimmed === '') continue;
    kept.push(trimmed);
  }
  return kept.join('\n\n');
}

function buildSystem(opts) {
  if (!opts || typeof opts !== 'object') {
    throw new TypeError('buildSystem: expected { staticText, dynamicText }');
  }
  const { staticText, dynamicText } = opts;
  if (typeof staticText !== 'string' || staticText.trim() === '') {
    throw new TypeError('buildSystem: staticText must be a non-empty string');
  }
  const system = [
    { type: 'text', text: staticText, cache_control: { type: CACHE_CONTROL.type } },
  ];
  if (typeof dynamicText === 'string' && dynamicText.trim() !== '') {
    system.push({ type: 'text', text: dynamicText });
  }
  return system;
}

function textBlocks(system) {
  if (typeof system === 'string') return [{ type: 'text', text: system }];
  if (!Array.isArray(system)) return [];
  return system.filter((b) => b && b.type === 'text' && typeof b.text === 'string');
}

function describe(system) {
  const blocks = textBlocks(system);
  let lastBreakpoint = -1;
  for (let i = 0; i < blocks.length; i++) {
    if (blocks[i].cache_control) lastBreakpoint = i;
  }
  let staticApproxTokens = 0;
  let dynamicApproxTokens = 0;
  for (let i = 0; i < blocks.length; i++) {
    const t = staticSize(blocks[i].text).approxTokens;
    if (i <= lastBreakpoint) staticApproxTokens += t;
    else dynamicApproxTokens += t;
  }
  return {
    blocks: blocks.length,
    staticApproxTokens,
    dynamicApproxTokens,
    cached: lastBreakpoint >= 0 && staticApproxTokens >= MIN_CACHEABLE_TOKENS,
  };
}

module.exports = {
  buildSystem,
  composeStatic,
  staticSize,
  isCacheable,
  describe,
  MIN_CACHEABLE_TOKENS,
  CHARS_PER_TOKEN,
};
