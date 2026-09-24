'use strict';

/**
 * Discord alert for a user-submitted content report (App Store Review
 * Guideline 1.2: the developer must be able to see and act on reports).
 *
 * The report row lands in the `reports` table for the admin review queue;
 * this module is the pager. It turns one report into ONE Discord message and
 * hands it to lib/alerts, so the founder learns about a flagged reply within
 * seconds instead of at the next queue check. The message is a preview, not
 * the record — the full text stays in the DB.
 *
 * Message shape (Discord markdown, one report per post):
 *
 *   🚩 Report: <reason|unspecified> · session <first 8 chars>… · <surface|?>/<mode|?> · <appVersion|?>
 *   > **student:** <userMessage, truncated to 300 chars>     (line omitted when absent)
 *   > **merc:** <content, truncated to 600 chars>
 *
 *   - The session id is NEVER posted in full: only its first 8 characters
 *     followed by '…'. The channel is a pager, not a data store, and the id
 *     is a per-device secret that can enumerate the student's history.
 *   - Newlines inside the quoted text are collapsed to spaces so a multi-line
 *     reply cannot break out of the `> ` quote block.
 *   - `@everyone` / `@here` / `<@…>` in user-controlled text are neutralized
 *     with a zero-width space so a student cannot ping the channel through a
 *     report.
 *
 * Contract:
 *   - notifyReport(report, { notify = require('./alerts').notify } = {})
 *       → Promise<boolean>
 *       Formats the report and posts it under the key
 *       'report:<id>' (or 'report:<ts>' when the row has no id yet, ts being
 *       report.ts / createdAt / created_at / now) with NO throttle — every
 *       report is its own event and must reach the channel. Resolves to
 *       notify's boolean (true only when Discord took it). NEVER throws and
 *       never rejects: a formatting bug or a rejecting/throwing `notify`
 *       resolves false and is logged at warn (key only, never the text).
 *       Callers may fire-and-forget: `void notifyReport(report)`.
 *   - formatReport(report) → string
 *       The message text alone, for tests and the admin queue preview.
 *
 * Accepted report shape — tolerant of both the validated request body
 * (camelCase) and a `reports` row (snake_case), so the integrator can pass
 * whichever it has:
 *   { id?, ts? | createdAt? | created_at?,
 *     sessionId? | session_id?,
 *     reason?, content?, userMessage? | user_message?,
 *     context?: { surface?, mode?, lessonId?, appVersion? } }
 *   Flat `surface` / `mode` / `lessonId` | `lesson_id` / `appVersion` |
 *   `app_version` are read as a fallback when `context` is absent.
 *   `lessonId` is deliberately not in the alert (it is in the queue row).
 */

const logger = require('./logger');

const SESSION_PREFIX_CHARS = 8;
const STUDENT_MAX_CHARS = 300;
const MERC_MAX_CHARS = 600;

/** Coerce anything to a trimmed string; null/undefined/non-scalars → ''. */
function str(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') return '';
  return String(v).trim();
}

/**
 * Make a user-controlled string safe to embed in one quoted Discord line:
 * collapse newlines (so it cannot leave the `> ` block) and defuse mentions.
 */
function inline(text) {
  return String(text)
    .replace(/\r\n|\r|\n/g, ' ')
    .replace(/@(everyone|here)/gi, '@​$1')
    .replace(/<@/g, '<​@');
}

/** Truncate to `max` characters, appending '…' when anything was cut. */
function truncate(text, max) {
  const s = String(text);
  return s.length > max ? `${s.slice(0, max)}…` : s;
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

function formatReport(report) {
  const r = report && typeof report === 'object' ? report : {};
  const ctx = r.context && typeof r.context === 'object' ? r.context : {};

  const reason = pick(r.reason) || 'unspecified';
  const surface = pick(ctx.surface, r.surface) || '?';
  const mode = pick(ctx.mode, r.mode) || '?';
  const appVersion = pick(ctx.appVersion, r.appVersion, r.app_version) || '?';

  const header =
    `🚩 Report: ${inline(reason)} · session ${sessionPrefix(r.sessionId ?? r.session_id)}` +
    ` · ${inline(surface)}/${inline(mode)} · ${inline(appVersion)}`;

  const lines = [header];

  const student = str(r.userMessage ?? r.user_message);
  if (student) {
    lines.push(`> **student:** ${truncate(inline(student), STUDENT_MAX_CHARS)}`);
  }

  const merc = str(r.content);
  lines.push(`> **merc:** ${truncate(inline(merc), MERC_MAX_CHARS)}`);

  return lines.join('\n');
}

function alertKey(report) {
  const r = report && typeof report === 'object' ? report : {};
  if (r.id !== null && r.id !== undefined && r.id !== '') return `report:${r.id}`;
  const ts = r.ts ?? r.createdAt ?? r.created_at;
  return `report:${ts !== null && ts !== undefined && ts !== '' ? ts : Date.now()}`;
}

async function notifyReport(report, { notify } = {}) {
  let key = 'report:?';
  try {
    key = alertKey(report);
    const send = typeof notify === 'function' ? notify : require('./alerts').notify;
    const text = formatReport(report);
    // No throttle: every report is a distinct event and must reach the pager.
    const posted = await send(key, text);
    return posted === true;
  } catch (err) {
    // Only the key is logged — never the report text (it is student data).
    logger.warn({ key, err }, 'reportWebhook: failed to post report alert');
    return false;
  }
}

module.exports = {
  notifyReport,
  formatReport,
  // Exposed for tests.
  _alertKey: alertKey,
  STUDENT_MAX_CHARS,
  MERC_MAX_CHARS,
};
