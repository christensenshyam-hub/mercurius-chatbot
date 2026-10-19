'use strict';

const crypto = require('node:crypto');
const { buildUserContent } = require('./visionContent');

/**
 * Photo re-attach (AUD-10): keep a student's homework photo in front of the
 * model for the follow-up turns that depend on it.
 *
 * Every shipped iOS build (2.0.0, 2.3.0 (16), main) sends a photo's `imageId`
 * on ONE request only: the turn that carries it. Later turns replay the
 * thread as text, where that turn reads "[Shared an image]" (photo only) or
 * the student's words. Before this module, only the request that carried the
 * id showed the model the image, so one turn later Merc asked the student to
 * retype the worksheet, blamed "handwriting", or invented a problem.
 *
 * The fix is server-side, so it reaches every build without a client change:
 *
 *   1. When a photo turn has been answered (the model streamed text for it),
 *      the server records on the image row which user turn it belongs to:
 *      `turnKey`, a hash of that turn's text, and `anchorKey`, a hash of the
 *      text together with the message just before it.
 *   2. On later requests from the same session, while the image is inside
 *      the store's retention (24 h) and its turn is at most `maxTurns` user
 *      turns back, the server finds that turn in the client's thread and
 *      sends it to the model as [image, text] again. Nothing else changes:
 *      the thread is still the client's own, never the database history.
 *
 * Why two keys. A photo-only turn is always the literal "[Shared an image]",
 * so the text alone cannot tell two photo turns apart. The anchor (the text
 * plus the message before it) can: it is what `plan()` matches first. It
 * also folds an iOS Retry into one turn, because Retry re-uploads the photo
 * under a new id for the SAME turn: the two images share an anchor, and only
 * the newest is used. The text-only key is a fallback for one case only: the
 * turn is now FIRST in the thread, because the client's byte cap dropped the
 * message before it.
 *
 * Text is hashed the way the server sees it on every turn (lesson re-tag
 * stripped by curriculumTag.normalizeReplayedHistory, the server's per-turn
 * cut applied), then canonicalised: leading whitespace dropped, cut to
 * CANON_CHARS UTF-16 units, trailing whitespace dropped. The cut makes the
 * key survive the one place the bytes differ between the photo turn and its
 * replays on iOS 2.0.0: a lesson's last turn carries the
 * "[CURRICULUM: …] " re-tag, so the server's 2,000-char cut leaves ~30 fewer
 * characters of a long message on the photo turn than on its replays.
 *
 * Contract (pure, no I/O):
 *   - canonicalText(s)          → the canonical form above ('' for non-strings).
 *   - keysForTurn(thread, i)    → { turnKey, anchorKey } for thread[i], a user
 *                                 message with non-empty canonical text;
 *                                 null otherwise. `thread` is the normalised,
 *                                 filtered list of { role, content } strings
 *                                 the server builds the request from.
 *   - plan({ thread, links, maxTurns, maxImages, maxBytes, excludeIds })
 *                               → [{ index, id }], newest turn first: which
 *                                 historical user turn (index into `thread`)
 *                                 gets which image. The LAST message of
 *                                 `thread` is the new turn and is never a
 *                                 target (its own image comes with its own
 *                                 imageId). `links` are the session's linked
 *                                 images, newest first:
 *                                 { id, turnKey, anchorKey, sizeBytes }.
 *                                 A turn is eligible while at most `maxTurns`
 *                                 user turns (the new one included) follow
 *                                 it. Each turn gets at most one image and
 *                                 each image one turn; at most `maxImages`
 *                                 images and `maxBytes` raw bytes in all.
 *                                 Ids in `excludeIds` are never used.
 *   - apply(messages, attachments)
 *                               → a NEW array in which each
 *                                 attachments[k] = { index, image } replaces
 *                                 messages[index] by a user turn whose
 *                                 content is buildUserContent(text, image):
 *                                 [image, text]. Input never mutated.
 *   - DEFAULT_MAX_TURNS (6), MAX_IMAGES (3), MAX_BYTES (10 MB), CANON_CHARS.
 */

const KEY_VERSION = 'photo-turn-v1';
const CANON_CHARS = 1500;
const DEFAULT_MAX_TURNS = 6;
// Three photos and 10 MB raw at most, so a request with the new turn's own
// photo (8 MB at most) stays far below the API's 32 MB request limit.
const MAX_IMAGES = 3;
const MAX_BYTES = 10 * 1024 * 1024;

function canonicalText(s) {
  if (typeof s !== 'string') return '';
  return s.trimStart().slice(0, CANON_CHARS).trimEnd();
}

function hash(...parts) {
  const h = crypto.createHash('sha256');
  h.update(KEY_VERSION);
  for (const p of parts) {
    h.update('\u0000');
    h.update(p);
  }
  return h.digest('hex').slice(0, 40);
}

function keysForTurn(thread, i) {
  if (!Array.isArray(thread) || !Number.isInteger(i) || i < 0 || i >= thread.length) return null;
  const m = thread[i];
  if (!m || m.role !== 'user' || typeof m.content !== 'string') return null;
  const text = canonicalText(m.content);
  if (!text) return null;
  const prev = i > 0 ? thread[i - 1] : null;
  const prevRole = prev && typeof prev.role === 'string' ? prev.role : '';
  const prevText = prev ? canonicalText(prev.content) : '';
  return {
    turnKey: hash('turn', text),
    anchorKey: hash('anchor', prevRole, prevText, text),
  };
}

function plan({ thread, links, maxTurns = DEFAULT_MAX_TURNS, maxImages = MAX_IMAGES, maxBytes = MAX_BYTES, excludeIds = [] } = {}) {
  if (!Array.isArray(thread) || thread.length < 2) return [];
  if (!Array.isArray(links) || links.length === 0) return [];
  if (!Number.isInteger(maxTurns) || maxTurns <= 0) return [];
  const excluded = new Set(excludeIds);
  const usable = links.filter((l) => l && typeof l.id === 'string' && l.turnKey && !excluded.has(l.id));
  const spent = new Set(); // anchor keys already placed (folds Retry duplicates)
  const used = new Set();  // image ids already placed
  const out = [];
  let bytes = 0;
  // User turns after index i, the new (last) turn included.
  let after = thread[thread.length - 1] && thread[thread.length - 1].role === 'user' ? 1 : 0;
  for (let i = thread.length - 2; i >= 0 && out.length < maxImages; i--) {
    if (!thread[i] || thread[i].role !== 'user') continue;
    if (after > maxTurns) break;
    after += 1;
    const keys = keysForTurn(thread, i);
    if (!keys) continue;
    const free = (l) => !used.has(l.id) && !spent.has(l.anchorKey);
    let pick = usable.find((l) => free(l) && l.anchorKey === keys.anchorKey);
    // The message before this turn was dropped by the client's byte cap:
    // the turn is first now, so only its text can be matched.
    if (!pick && i === 0) pick = usable.find((l) => free(l) && l.turnKey === keys.turnKey);
    if (!pick) continue;
    spent.add(pick.anchorKey);
    const size = Number(pick.sizeBytes) || 0;
    if (bytes + size > maxBytes) continue;
    bytes += size;
    used.add(pick.id);
    out.push({ index: i, id: pick.id });
  }
  return out;
}

function apply(messages, attachments) {
  const out = Array.isArray(messages) ? messages.slice() : [];
  if (!Array.isArray(attachments)) return out;
  for (const a of attachments) {
    if (!a || !Number.isInteger(a.index) || !out[a.index]) continue;
    const m = out[a.index];
    if (m.role !== 'user' || typeof m.content !== 'string') continue;
    const content = buildUserContent(m.content, a.image);
    if (!Array.isArray(content)) continue; // not a valid image: leave the text turn alone
    out[a.index] = { role: 'user', content };
  }
  return out;
}

module.exports = {
  canonicalText,
  keysForTurn,
  plan,
  apply,
  DEFAULT_MAX_TURNS,
  MAX_IMAGES,
  MAX_BYTES,
  CANON_CHARS,
};
