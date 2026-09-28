'use strict';

/**
 * The one place that shapes the `system` parameter of a model call.
 *
 * Every chat and lesson call this server makes sends its system prompt as TWO
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
 *   2. The static block always carries a breakpoint and is always first.
 *      Volatile text after the last breakpoint costs full input price but
 *      never disturbs the cache. Two more breakpoints are placed only where
 *      the bytes before them repeat: the dynamic block when it carries the
 *      widget's club material (the same bytes for every widget request in
 *      one mode on one day while the feeds are unchanged), and the last
 *      replayed message of the thread
 *      (withHistoryBreakpoint), so a conversation's own history is read back
 *      at 0.1× on the next turn instead of re-billed in full. Three at most,
 *      under the API's limit of four.
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
 *   - buildSystem({ staticText, dynamicText, cacheDynamic })
 *                          → the array for the SDK's `system` field:
 *                              [{ type:'text', text: staticText,
 *                                 cache_control: { type:'ephemeral' } },
 *                               { type:'text', text: dynamicText }]  // optional
 *                            The second block is present only when dynamicText
 *                            is a string that is non-empty after trim (it is
 *                            sent as given, untrimmed), and carries its own
 *                            cache_control only when cacheDynamic is true —
 *                            for dynamic text that repeats across requests
 *                            (the widget's club feeds). staticText must be a
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
 *   - withHistoryBreakpoint(messages, { clientMessages, window })
 *                          → a NEW messages array in which the second-to-last
 *                            message (the last one before the new user turn)
 *                            is sent as [{ type:'text', text,
 *                            cache_control:{ type:'ephemeral' } }]. Never the
 *                            last message: the latest user turn is trimmed,
 *                            may carry an image, and on iOS lessons carries a
 *                            wire-only re-tag that is gone on the next turn,
 *                            so a breakpoint there would be written every turn
 *                            and never read. Returned unchanged (a copy) when
 *                            the next turn could not read the write back
 *                            because the replayed thread will slide: fewer
 *                            than 2 messages, the target is not a non-empty
 *                            string, clientMessages.length + 2 > window (the
 *                            next turn adds a reply and a user turn and the
 *                            server or client window drops the oldest), or
 *                            the thread's content exceeds
 *                            HISTORY_CACHE_MAX_BYTES (iOS drops the oldest
 *                            turns past 24,000 bytes). Input never mutated.
 *   - HISTORY_CACHE_MAX_BYTES → 20,000.
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
  const { staticText, dynamicText, cacheDynamic } = opts;
  if (typeof staticText !== 'string' || staticText.trim() === '') {
    throw new TypeError('buildSystem: staticText must be a non-empty string');
  }
  const system = [
    { type: 'text', text: staticText, cache_control: { type: CACHE_CONTROL.type } },
  ];
  if (typeof dynamicText === 'string' && dynamicText.trim() !== '') {
    system.push(cacheDynamic === true
      ? { type: 'text', text: dynamicText, cache_control: { type: CACHE_CONTROL.type } }
      : { type: 'text', text: dynamicText });
  }
  return system;
}

// iOS cappedHistory drops the oldest turns once the thread passes 24,000
// content bytes; stay far enough under it that the next turn still fits.
const HISTORY_CACHE_MAX_BYTES = 20_000;

function threadBytes(messages) {
  let bytes = 0;
  for (const m of messages) {
    if (m && typeof m.content === 'string') bytes += Buffer.byteLength(m.content, 'utf8');
  }
  return bytes;
}

function withHistoryBreakpoint(messages, { clientMessages, window } = {}) {
  const out = Array.isArray(messages) ? messages.slice() : [];
  if (out.length < 2) return out;
  const thread = Array.isArray(clientMessages) ? clientMessages : out;
  if (!Number.isInteger(window) || thread.length + 2 > window) return out;
  if (threadBytes(thread) > HISTORY_CACHE_MAX_BYTES) return out;
  const i = out.length - 2;
  const m = out[i];
  if (!m || typeof m.content !== 'string' || m.content.trim() === '') return out;
  out[i] = {
    role: m.role,
    content: [{ type: 'text', text: m.content, cache_control: { type: CACHE_CONTROL.type } }],
  };
  return out;
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
  withHistoryBreakpoint,
  MIN_CACHEABLE_TOKENS,
  CHARS_PER_TOKEN,
  HISTORY_CACHE_MAX_BYTES,
};
