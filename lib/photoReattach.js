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
 * one is used. The text-only key is a fallback for one case only: the turn is
 * now FIRST in the thread, because the client's byte cap dropped the message
 * before it.
 *
 * And a third, `replyKey`: a hash of the start of the reply the photo turn
 * got, recorded when the photo is linked. When the client's thread has a
 * reply right after the turn, the photo must be the one that drew THAT reply
 * (the review of this branch): the key, not the anchor, is what proves the
 * turn is the photo's own. Two chats that open with the same words share an
 * anchor (no message before, same text), and a turn that is first in its
 * thread matches on text alone, so without this a photo from one chat showed
 * up on a different chat's turn that never had one (on a shared classroom
 * iPad, possibly another student's homework). Two chats that each open with
 * a photo-only turn are told apart the same way. With no reply after the
 * turn (older builds drop a failed reply bubble), a turn with a message
 * before it matches on its anchor alone and the newest photo wins, which is
 * also the Retry rule; a turn with nothing before it, which any chat's
 * opener could share, is never matched without its reply.
 *
 * A re-attached photo is the photo as the student sent it then, so its old
 * handwriting may be work the student has since fixed in chat. The turn
 * carries REATTACHED_PHOTO_NOTE between the image and the student's words,
 * so the model judges the newest message on its own instead of re-checking
 * the typed fix against the photo (the review saw "recheck your constant"
 * for a correct x = 5 in 6/6 replays with the legacy prompt).
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
 *   - replyKey(text)            → the hash of the reply's canonical first
 *                                 REPLY_CHARS units, or null when empty.
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
 *                                 { id, turnKey, anchorKey, replyKey?,
 *                                 sizeBytes }. When thread[i + 1] is a reply,
 *                                 only a link whose replyKey matches it is
 *                                 used; with no reply, only an anchor match
 *                                 on a turn with a message before it, newest
 *                                 first.
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
 *                                 content is [image, note, text]: the image
 *                                 and text of buildUserContent(text, image)
 *                                 with REATTACHED_PHOTO_NOTE between them.
 *                                 Input never mutated.
 *   - textView(messages)       → a NEW array in which each re-attached turn
 *                                 is back to the student's own words (a
 *                                 string), for checks that read the thread
 *                                 as text (homeworkGuard.looksLikeProblemWork).
 *                                 Every other turn is passed through as is.
 *   - DEFAULT_MAX_TURNS (6), MAX_IMAGES (3), MAX_BYTES (10 MB), CANON_CHARS,
 *     REPLY_CHARS.
 */

const KEY_VERSION = 'photo-turn-v1';
const CANON_CHARS = 1500;
// The start of a reply is enough to tell two replies apart, and the start is
// what survives a reply cut off mid-stream (iOS keeps what it received).
const REPLY_CHARS = 200;
const DEFAULT_MAX_TURNS = 6;
// Three photos and 10 MB raw at most, so a request with the new turn's own
// photo (8 MB at most) stays far below the API's 32 MB request limit.
const MAX_IMAGES = 3;
const MAX_BYTES = 10 * 1024 * 1024;
// Fixed text (no per-request bytes), so a re-attached turn reads the same on
// every later request and stays in the cached prefix.
const REATTACHED_PHOTO_NOTE = "[Photo the student sent earlier in this chat, shown again exactly as it was then. Its handwritten work is old: anything the student has typed since corrects or replaces it. Check their newest message by its own math, not against the work in this photo.]";

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

function replyKey(text) {
  const t = canonicalText(text).slice(0, REPLY_CHARS).trimEnd();
  return t ? hash('reply', t) : null;
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
    const next = thread[i + 1];
    let candidates;
    if (next && next.role === 'assistant') {
      // A reply follows: only the photo that drew this reply is this turn's.
      const nextReply = replyKey(next.content);
      const own = (l) => free(l) && nextReply !== null && l.replyKey === nextReply;
      candidates = usable.filter((l) => own(l) && l.anchorKey === keys.anchorKey);
      // The message before this turn was dropped by the client's byte cap:
      // the turn is first now, so its text and its reply are all there is.
      if (candidates.length === 0 && i === 0) candidates = usable.filter((l) => own(l) && l.turnKey === keys.turnKey);
    } else {
      // No reply in the thread (an older build dropped a failed bubble): the
      // anchor alone, and only when a message before the turn makes it this
      // chat's. Newest first, which is also the Retry rule.
      candidates = i > 0 ? usable.filter((l) => free(l) && l.anchorKey === keys.anchorKey) : [];
    }
    if (candidates.length === 0) continue;
    const pick = candidates[0];
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
    const [image, text] = content;
    out[a.index] = { role: 'user', content: [image, { type: 'text', text: REATTACHED_PHOTO_NOTE }, text] };
  }
  return out;
}

function textView(messages) {
  return (Array.isArray(messages) ? messages : []).map((m) => {
    const blocks = m && Array.isArray(m.content) ? m.content : null;
    if (!blocks || !blocks.some((b) => b && b.type === 'text' && b.text === REATTACHED_PHOTO_NOTE)) return m;
    const words = blocks.filter((b) => b && b.type === 'text' && b.text !== REATTACHED_PHOTO_NOTE).map((b) => b.text);
    return { ...m, content: words.join('\n') };
  });
}

module.exports = {
  canonicalText,
  replyKey,
  keysForTurn,
  plan,
  apply,
  textView,
  DEFAULT_MAX_TURNS,
  MAX_IMAGES,
  MAX_BYTES,
  CANON_CHARS,
  REPLY_CHARS,
  REATTACHED_PHOTO_NOTE,
};
