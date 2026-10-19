'use strict';

/**
 * sourceTags — turn the model's "[SOURCE: label — domain/path]" citations
 * into plain text for clients that don't render the tag (AUD-38).
 *
 * The prompts ask for "[SOURCE: Title — domain.com/path]". The web widget
 * renders that as a source pill (public/widget.js renderEmphasis), but the
 * iOS app has no [SOURCE] renderer, so students saw the raw brackets, often
 * with a made-up URL path (two runs of the hallucination lesson cited two
 * different, invented CourtListener docket numbers). For blocks_v1 clients
 * the server rewrites each tag, keeping the label and the domain and
 * dropping any path:
 *
 *   on its own line, or after a sentence → "Source: label (domain)"
 *   mid-sentence                          → "(Source: label, domain)"
 *   right after "("                       → "Source: label, domain"
 *
 * A tag with no recognisable domain keeps its label ("Source: label"); an
 * empty tag is dropped. Something that only looks like the start of a tag
 * (a newline or "[" before its "]", or no "]" within MAX_TAG_CHARS) passes
 * through as written.
 *
 * The streaming transformer holds text from "[SOURCE:" to its "]" (the
 * longest real tag in the audit corpus is 204 chars) and is
 * CHUNK-BOUNDARY INDEPENDENT: every decision depends on the text alone,
 * including the context it reads back from its own output.
 */

const OPEN = '[SOURCE:';
/// Longest tag the stream will hold, from "[" through "]".
const MAX_TAG_CHARS = 400;

const HOST = '(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,24}';
// scheme? www.? host (port)? (path|query|fragment)?
const URL_SRC = `(?:https?:\\/\\/)?(?:www\\.)?(${HOST})(?::\\d{2,5})?(?:[/?#]\\S*)?`;
// "label — url", "label – url", "label - url", "label: url", "label, url", "label | url"
const LABEL_SEP_URL_RE = new RegExp(`^(.*?)(?:\\s*[—–]\\s*|\\s+-\\s+|:\\s+|,\\s+|\\s+\\|\\s+)${URL_SRC}$`);
// "label (url)"
const LABEL_PAREN_URL_RE = new RegExp(`^(.*?)\\s*\\(\\s*${URL_SRC}\\s*\\)$`);
// "label url/with/path" or "label https://url" — a trailing token that is
// unmistakably an address even without a separator
const LABEL_SPACE_ADDRESS_RE = new RegExp(`^(.*\\S)\\s+((?:https?:\\/\\/)?(?:www\\.)?(${HOST})(?::\\d{2,5})?[/?#]\\S*|https?:\\/\\/(?:www\\.)?(${HOST})\\S*)$`);
const URL_ONLY_RE = new RegExp(`^${URL_SRC}$`);

const BLOCK_TOKEN_END_RE = /\[\/?(?:KEY|EX|CHECK|Q)\]$/;
const TRAILING_DECORATION_RE = /["'”’»)*_`\]]+$/;

/** Split a tag's inside into { label, domain } (either may be ''). */
function parseSourceTag(inner) {
  const text = String(inner ?? '').replace(/\s+/g, ' ').trim();
  if (!text) return { label: '', domain: '' };
  let m = URL_ONLY_RE.exec(text);
  if (m) return { label: '', domain: m[1] };
  m = LABEL_SEP_URL_RE.exec(text) || LABEL_PAREN_URL_RE.exec(text);
  if (m) return { label: cleanLabel(m[1]), domain: m[2] };
  m = LABEL_SPACE_ADDRESS_RE.exec(text);
  if (m) return { label: cleanLabel(m[1]), domain: m[3] || m[4] };
  return { label: cleanLabel(text), domain: '' };
}

function cleanLabel(label) {
  return String(label).replace(/[\s—–:,|-]+$/, '').trim();
}

/**
 * Where a tag sits, from the text already written before it:
 * 'line' (start of a line, after a sentence, a colon or a block marker),
 * 'paren' (right after "("), or 'inline' (mid-sentence).
 */
function contextOf(before) {
  const t = String(before ?? '').replace(/[ \t]+$/, '');
  if (t === '' || t.endsWith('\n')) return 'line';
  if (t.endsWith('(')) return 'paren';
  if (BLOCK_TOKEN_END_RE.test(t)) return 'line';
  const core = t.replace(TRAILING_DECORATION_RE, '');
  const last = core[core.length - 1];
  if (last && '.!?…:'.includes(last)) return 'line';
  return 'inline';
}

/** The plain text for one tag's inside, in its context. */
function formatSource(inner, context = 'line') {
  const { label, domain } = parseSourceTag(inner);
  if (!label && !domain) return '';
  if (context === 'inline') {
    return `(Source: ${[label, domain].filter(Boolean).join(', ')})`;
  }
  if (context === 'paren') {
    return `Source: ${[label, domain].filter(Boolean).join(', ')}`;
  }
  if (label && domain) return `Source: ${label} (${domain})`;
  return `Source: ${label || domain}`;
}

/** Length of the longest proper prefix of `token` that `text` ends with. */
function partialTailLength(text, token) {
  for (let k = Math.min(token.length - 1, text.length); k > 0; k -= 1) {
    if (text.endsWith(token.slice(0, k))) return k;
  }
  return 0;
}

/** Streaming transformer: `push(chunk) -> string`, `flush() -> string`. */
function createSourceRewriter() {
  let buf = '';
  // The last characters this transformer wrote: the context of the next tag.
  let written = '';

  function push(chunk) {
    buf += String(chunk ?? '');
    let out = '';
    const emit = (s) => {
      if (!s) return;
      out += s;
      written = (written + s).slice(-16);
    };
    for (;;) {
      const open = buf.indexOf(OPEN);
      if (open === -1) {
        const keep = partialTailLength(buf, OPEN);
        emit(buf.slice(0, buf.length - keep));
        buf = buf.slice(buf.length - keep);
        return out;
      }
      emit(buf.slice(0, open));
      buf = buf.slice(open);
      // buf starts with "[SOURCE:". Its "]" must come before any newline or
      // "[" and within MAX_TAG_CHARS — a rule about the text, not chunking.
      let end = -1;
      let notATag = false;
      for (let k = OPEN.length; k < buf.length && k < MAX_TAG_CHARS; k += 1) {
        const c = buf[k];
        if (c === ']') { end = k; break; }
        if (c === '\n' || c === '[') { notATag = true; break; }
      }
      if (end !== -1) {
        emit(formatSource(buf.slice(OPEN.length, end), contextOf(written)));
        buf = buf.slice(end + 1);
        continue;
      }
      if (notATag || buf.length >= MAX_TAG_CHARS) {
        emit(buf[0]); // release the "[" as written, rescan after it
        buf = buf.slice(1);
        continue;
      }
      return out; // wait for the rest of the tag
    }
  }

  function flush() {
    const rest = buf;
    buf = '';
    written = (written + rest).slice(-16);
    return rest;
  }

  return { push, flush };
}

/** One-shot form of the streaming transformer (same bytes, by construction). */
function rewriteSources(text) {
  const r = createSourceRewriter();
  return r.push(String(text ?? '')) + r.flush();
}

/**
 * Every form the rewrite writes, for tools that measure prose the way they
 * strip a raw [SOURCE: …] tag (scripts/eval-pacing.mjs). The standalone
 * form is matched through its "(domain)"; a domain-less "Source: label" is
 * not matched (its end can't be told from prose).
 */
const REWRITTEN_SOURCE_RE = new RegExp(
  `\\(Source: (?:[^()\\n]|\\([^()\\n]*\\))*\\)|Source: [^\\n]*?\\(${HOST}\\)`,
  'g',
);
/** A reply that ends with a rewritten source ended on purpose (not cut off). */
const ENDS_WITH_REWRITTEN_SOURCE_RE = new RegExp(
  `(?:\\(Source: (?:[^()\\n]|\\([^()\\n]*\\))*\\)|(?:^|[.!?…:]["'”’)*_]*[ \\t]+|\\n)Source: [^\\n]*)\\s*$`,
);

module.exports = {
  createSourceRewriter,
  rewriteSources,
  parseSourceTag,
  formatSource,
  contextOf,
  REWRITTEN_SOURCE_RE,
  ENDS_WITH_REWRITTEN_SOURCE_RE,
  MAX_TAG_CHARS,
};
