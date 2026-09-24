'use strict';

/**
 * Discord alert for a user-submitted content report (App Store Review
 * Guideline 1.2: the developer must be able to see and act on reports).
 *
 * The report row lands in the `reports` table for the admin review queue;
 * this module is the pager. It turns one report into ONE Discord message and
 * hands it to lib/alerts, so the founder learns about a flagged reply within
 * seconds instead of at the next queue check. The message is METADATA ONLY —
 * never the student's turn or the model's reply. marketing/privacy.html
 * promises that messages go only to Anthropic and Railway, and Discord is
 * neither; the full row stays in the DB behind the admin password.
 *
 * Message shape (Discord markdown, one report per post):
 *
 *   🚩 Report #<id|?>: <reason|unspecified> · <surface|?>/<mode|?> · lesson <lessonId|?> · <appVersion|?> · session <first 8 chars>…
 *   student <N> chars · merc <M> chars
 *   Review: GET /api/admin/reports?unresolved=1
 *
 *   - The session id is NEVER posted in full: only its first 8 characters
 *     followed by '…'. The channel is a pager, not a data store, and the id
 *     is a per-device secret that can enumerate the student's history.
 *   - Every posted field is client-controlled text (validated, but free-form
 *     within its cap), so newlines are collapsed and `@everyone` / `@here` /
 *     `<@…>` are neutralized with a zero-width space.
 *
 * Contract:
 *   - notifyReport(report, { notify = require('./alerts').notify } = {})
 *       → Promise<boolean>
 *       Formats the report and posts it under the FIXED key 'report' with a
 *       60 s throttle (REPORT_THROTTLE_MS): lib/alerts keeps one clock per
 *       key, so a burst of reports — a flood, or one classroom flagging the
 *       same reply — becomes one post a minute instead of one per report.
 *       Anything collapsed is still in the queue, and the daily digest's
 *       open-report count covers it. Resolves to notify's boolean (true only
 *       when Discord took it). NEVER throws and never rejects: a formatting
 *       bug or a rejecting/throwing `notify` resolves false and is logged at
 *       warn (key only, never report content). Callers may fire-and-forget:
 *       `void notifyReport(report)`.
 *   - formatReport(report) → string
 *       The message text alone, for tests and the admin queue preview.
 *
 * Accepted report shape — tolerant of both the validated request body
 * (camelCase) and a `reports` row (snake_case), so the integrator can pass
 * whichever it has:
 *   { id?,
 *     sessionId? | session_id?,
 *     reason?, content?, userMessage? | user_message?,
 *     context?: { surface?, mode?, lessonId?, appVersion? } }
 *   Flat `surface` / `mode` / `lessonId` | `lesson_id` / `appVersion` |
 *   `app_version` are read as a fallback when `context` is absent. `content`
 *   and the user message contribute only their lengths.
 */

const logger = require('./logger');

const SESSION_PREFIX_CHARS = 8;
const ALERT_KEY = 'report';
const REPORT_THROTTLE_MS = 60_000;
const REVIEW_HINT = 'Review: GET /api/admin/reports?unresolved=1';

/** Coerce anything to a trimmed string; null/undefined/non-scalars → ''. */
function str(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') return '';
  return String(v).trim();
}

/**
 * Make a user-controlled string safe to embed in one Discord line: collapse
 * newlines and defuse mentions.
 */
function inline(text) {
  return String(text)
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/@(everyone|here)/gi, '@​$1')
    .replace(/<@/g, '<​@');
}

/** First 8 chars + '…', or '?' when there is no id. Never the full id. */
function sessionPrefix(sessionId) {
  const id = str(sessionId);
  if (!id) return '?';
  return `${id.slice(0, SESSION_PREFIX_CHARS)}…`;
}

function pick(...candidates) {
  for (const c of candidates) {
    const s = str(c);
    if (s) return s;
  }
  return '';
}

/** Character count of a text field; non-strings count as 0. */
function chars(v) {
  return typeof v === 'string' ? v.length : 0;
}

function formatReport(report) {
  const r = report && typeof report === 'object' ? report : {};
  const ctx = r.context && typeof r.context === 'object' ? r.context : {};

  const id = r.id !== null && r.id !== undefined && r.id !== '' ? inline(str(r.id)) : '?';
  const reason = pick(r.reason) || 'unspecified';
  const surface = pick(ctx.surface, r.surface) || '?';
  const mode = pick(ctx.mode, r.mode) || '?';
  const lessonId = pick(ctx.lessonId, r.lessonId, r.lesson_id) || '?';
  const appVersion = pick(ctx.appVersion, r.appVersion, r.app_version) || '?';

  const header =
    `🚩 Report #${id}: ${inline(reason)} · ${inline(surface)}/${inline(mode)}` +
    ` · lesson ${inline(lessonId)} · ${inline(appVersion)}` +
    ` · session ${sessionPrefix(r.sessionId ?? r.session_id)}`;
  const sizes = `student ${chars(r.userMessage ?? r.user_message)} chars · merc ${chars(r.content)} chars`;

  return [header, sizes, REVIEW_HINT].join('\n');
}

async function notifyReport(report, { notify } = {}) {
  try {
    const send = typeof notify === 'function' ? notify : require('./alerts').notify;
    const text = formatReport(report);
    const posted = await send(ALERT_KEY, text, { throttleMs: REPORT_THROTTLE_MS });
    return posted === true;
  } catch (err) {
    // Only the key is logged — never the report (it is student data).
    logger.warn({ key: ALERT_KEY, err }, 'reportWebhook: failed to post report alert');
    return false;
  }
}

module.exports = {
  notifyReport,
  formatReport,
  // Exposed for tests.
  ALERT_KEY,
  REPORT_THROTTLE_MS,
  REVIEW_HINT,
};
