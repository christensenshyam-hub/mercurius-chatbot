'use strict';

/**
 * clubContext — who gets the Mayo AI Literacy Club material, and how it is
 * assembled (cost-cuts PR).
 *
 * The club knowledge, the live meeting schedule and the blog library are
 * several thousand tokens that only matter to students arriving through the
 * club's web widgets. The iOS app (the primary, App-Store surface) has no
 * club affiliation, yet today every one of its turns pays to send all of it.
 * Gating on a client-declared capability — exactly how blocks_v1 works in
 * lib/blockMarkup.js — lets the two web widgets keep the material and drops
 * it from every iOS request without a server-side allowlist of clients:
 *
 *   request.capabilities includes "club_v1"  → club material injected
 *   anything else (iOS never sends it)        → nothing club-related in the
 *                                               prompt
 *
 * The material is split by VOLATILITY so the cached prefix stays cacheable:
 *
 *   staticClubBlock()  — club knowledge. A build-time constant, so its block
 *                        is BYTE-STABLE across requests and belongs in the
 *                        cache_control:ephemeral system block. Its presence
 *                        (or absence) forks the cache into two prefixes —
 *                        widget and non-widget — each of which hits on its
 *                        own traffic; that is the whole point.
 *   dynamicClubBlock() — meeting schedule + blog library. Both change
 *                        whenever the club edits its site/events, so they go
 *                        in the small UNCACHED dynamic block after the
 *                        prefix, wrapped in the same <meeting_context> /
 *                        <blog_context> tags lib/unifiedPrompt.js already
 *                        emits (only when non-empty — empty tags are noise).
 *
 * Contract:
 *   - CLUB_V1                              → 'club_v1', the capability token.
 *   - wantsClub(capabilities)              → true only when `capabilities` is
 *                                            an ARRAY containing 'club_v1'.
 *                                            Strings, objects, null → false.
 *   - staticClubBlock({ capabilities, clubKnowledge })
 *                                          → '' unless wantsClub; else
 *                                            '\n\n<club_knowledge>\n' +
 *                                            clubKnowledge.trim() +
 *                                            '\n</club_knowledge>'.
 *                                            Same inputs → identical bytes.
 *   - dynamicClubBlock({ capabilities, meetingContext, blogContext })
 *                                          → '' unless wantsClub; else the
 *                                            non-empty contexts, each wrapped
 *                                            in its tag, joined by '\n'
 *                                            (meeting first). Both empty → ''.
 *   - makeTtlCache(ttlMs, loader, { now }) → async getter `get()` that calls
 *                                            loader() at most once per ttlMs.
 *                                            Concurrent callers share the one
 *                                            in-flight promise. A loader error
 *                                            (thrown or rejected) is NOT
 *                                            cached: every waiting caller gets
 *                                            the rejection and the next call
 *                                            loads again. Falsy values
 *                                            (null, '', 0) ARE cached.
 *                                            `get.invalidate()` drops the
 *                                            cached value (and discards the
 *                                            result of any load in flight, so
 *                                            a value read before the
 *                                            invalidation is never stored).
 *                                            `get.peek()` returns the cached
 *                                            value synchronously while fresh,
 *                                            else undefined. `now` (default
 *                                            Date.now) is injectable for
 *                                            tests. ttlMs = 0 → dedupe only.
 *
 * The TTL cache exists for the events-table read that today happens on every
 * chat turn: the schedule changes weekly at most, so one DB read per minute
 * per replica is plenty. The deployment is a single replica with no Redis, so
 * (as with lib/spendCap.js) a module-level in-memory cache IS the mechanism.
 */

const CLUB_V1 = 'club_v1';

/** Whether a request's capabilities opt into the club material. */
function wantsClub(capabilities) {
  return Array.isArray(capabilities) && capabilities.includes(CLUB_V1);
}

function asText(value) {
  return value == null ? '' : String(value);
}

/**
 * The club-knowledge block for the CACHED system prefix. Byte-stable for a
 * given (capabilities, clubKnowledge) pair — do not add anything volatile.
 */
function staticClubBlock({ capabilities, clubKnowledge } = {}) {
  if (!wantsClub(capabilities)) return '';
  return '\n\n<club_knowledge>\n' + asText(clubKnowledge).trim() + '\n</club_knowledge>';
}

/**
 * The meeting + blog block for the UNCACHED dynamic system block. Emits only
 * the non-empty sections, in the same tag shape as buildRuntimeContext.
 */
function dynamicClubBlock({ capabilities, meetingContext, blogContext } = {}) {
  if (!wantsClub(capabilities)) return '';
  const parts = [];
  const tag = (name, value) => {
    const v = asText(value).trim();
    if (v) parts.push(`<${name}>\n${v}\n</${name}>`);
  };
  tag('meeting_context', meetingContext);
  tag('blog_context', blogContext);
  return parts.join('\n');
}

/**
 * Tiny TTL cache around an async loader. See the header for the contract.
 */
function makeTtlCache(ttlMs, loader, { now = Date.now } = {}) {
  const ttl = Number(ttlMs);
  if (!Number.isFinite(ttl) || ttl < 0) {
    throw new TypeError(`makeTtlCache: ttlMs must be a finite number >= 0, got ${ttlMs}`);
  }
  if (typeof loader !== 'function') {
    throw new TypeError('makeTtlCache: loader must be a function');
  }
  if (typeof now !== 'function') {
    throw new TypeError('makeTtlCache: now must be a function');
  }

  let value;
  let hasValue = false;
  let expiresAt = -Infinity;
  let inFlight = null;
  // Bumped by invalidate(); a load only stores its result if the generation
  // it started under is still current.
  let generation = 0;

  function isFresh() {
    return hasValue && now() < expiresAt;
  }

  function get() {
    if (isFresh()) return Promise.resolve(value);
    if (inFlight) return inFlight;

    const gen = generation;
    // The loader is invoked SYNCHRONOUSLY (the I/O starts now, not a
    // microtask later) inside a Promise executor, so a synchronous throw in
    // it becomes a rejection of this chain rather than a throw out of get().
    // Its result can only be observed via .then callbacks, which run after
    // `inFlight` below has been assigned.
    const p = new Promise((resolve) => resolve(loader()))
      .then((v) => {
        if (gen === generation) {
          value = v;
          hasValue = true;
          expiresAt = now() + ttl;
        }
        return v;
      })
      .finally(() => {
        if (inFlight === p) inFlight = null;
      });
    inFlight = p;
    return p;
  }

  get.invalidate = () => {
    generation += 1;
    value = undefined;
    hasValue = false;
    expiresAt = -Infinity;
  };

  get.peek = () => (isFresh() ? value : undefined);

  return get;
}

module.exports = {
  CLUB_V1,
  wantsClub,
  staticClubBlock,
  dynamicClubBlock,
  makeTtlCache,
};
