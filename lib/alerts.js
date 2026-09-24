'use strict';

/**
 * Discord webhook alerts (ops/safety-rails).
 *
 * The operators' pager is a Discord channel. Every safety rail (spend cap,
 * kill switch, per-IP cap, boot, Anthropic error bursts, ...) reports through
 * this one module so the failure modes are handled in ONE place:
 *
 *   - It NEVER throws and never rejects. An alerting bug must not take down
 *     the request that tried to alert. Every path resolves to a boolean.
 *   - It never blocks on a dead webhook: posts carry a 5 s AbortSignal
 *     timeout. Callers should still fire-and-forget (`void notify(...)`) —
 *     the promise is for tests and the rare caller that wants to know.
 *   - It never spams: a per-key throttle drops repeats inside the window.
 *   - It never leaks the webhook URL (it embeds a secret token) or the alert
 *     text into logs — only the key, status and character count are logged.
 *
 * Contract:
 *   - notify(key, text, { throttleMs = 0 } = {}) → Promise<boolean>
 *       Posts { content: text.slice(0, 1900) } as JSON to the webhook
 *       (Discord's hard limit is 2000 chars; 1900 leaves headroom).
 *       Resolves true only when Discord answered 2xx. Resolves false when:
 *         · DISCORD_WEBHOOK_URL is unset → logs ONE warning per process the
 *           first time, then silently no-ops (dev/test boxes stay quiet);
 *         · `key` fired less than throttleMs ago (the throttle clock is
 *           stamped on the ATTEMPT, not on success, so a failing webhook is
 *           not hammered at request rate — the next window retries);
 *         · fetch rejected / threw, timed out, or returned non-2xx → logged
 *           at warn and swallowed.
 *   - configure({ fetch, webhookUrl, now })
 *       Test/ops seams. Any key left undefined keeps its current value.
 *       Defaults: fetch = globalThis.fetch (resolved at call time),
 *       webhookUrl = process.env.DISCORD_WEBHOOK_URL (read at call time),
 *       now = Date.now.
 *   - __resetForTest()  → clear overrides, throttle stamps and the
 *                          warned-once flag.
 *
 * Keys in use (a key is just the throttle bucket + a log field; nothing here
 * treats any of them specially — new keys need no changes in this file):
 *   'budget_80'            daily token ceiling reached 80 %      (lib/spendCap)
 *   'budget_100'           daily token ceiling hit → 503s        (lib/spendCap)
 *   'ip_cap:<hash>'        one hashed IP tripped its cap         (lib/rateLimiter)
 *   'kill_switch'          kill switch flipped at runtime        (lib/killSwitch)
 *   'boot'                 process (re)started
 *   'anthropic_errors'     burst of Anthropic API errors
 *   'unhandled_rejection'  process-level unhandledRejection
 *   'report'               user-submitted content report
 *   'digest'               periodic usage digest
 *
 * Env: DISCORD_WEBHOOK_URL — the channel's webhook URL (a secret; never log
 * it). Unset → alerts are a no-op, which is the correct behavior for local
 * dev and CI.
 */

const logger = require('./logger');

const MAX_CONTENT_CHARS = 1900; // Discord caps `content` at 2000
const TIMEOUT_MS = 5000;

// configure() seams. `undefined` means "not overridden → use the default".
let overrides = {};
// key → timestamp (ms, from now()) of the last attempted post.
let lastAttempt = new Map();
// The unset-URL warning is emitted once per process.
let warnedNoUrl = false;

function resolveFetch() {
  return overrides.fetch !== undefined ? overrides.fetch : globalThis.fetch;
}

function resolveWebhookUrl() {
  return overrides.webhookUrl !== undefined
    ? overrides.webhookUrl
    : process.env.DISCORD_WEBHOOK_URL;
}

function resolveNow() {
  return overrides.now !== undefined ? overrides.now : Date.now;
}

async function notify(key, text, { throttleMs = 0 } = {}) {
  const alertKey = String(key);
  try {
    const url = resolveWebhookUrl();
    if (!url) {
      if (!warnedNoUrl) {
        warnedNoUrl = true;
        logger.warn(
          { key: alertKey },
          'alerts: DISCORD_WEBHOOK_URL is unset — alerts are disabled for this process'
        );
      }
      return false;
    }

    const now = Number(resolveNow()());
    const window = Number(throttleMs) || 0;
    const last = lastAttempt.get(alertKey);
    if (window > 0 && last !== undefined && now - last < window) {
      return false;
    }
    lastAttempt.set(alertKey, now);

    const content = String(text ?? '').slice(0, MAX_CONTENT_CHARS);
    const res = await resolveFetch()(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!res || !res.ok) {
      logger.warn(
        { key: alertKey, status: res ? res.status : undefined, chars: content.length },
        'alerts: Discord webhook returned non-2xx'
      );
      return false;
    }
    return true;
  } catch (err) {
    // Network failure, timeout (AbortError), non-function fetch, anything.
    logger.warn({ key: alertKey, err }, 'alerts: Discord webhook post failed');
    return false;
  }
}

function configure({ fetch, webhookUrl, now } = {}) {
  if (fetch !== undefined) overrides.fetch = fetch;
  if (webhookUrl !== undefined) overrides.webhookUrl = webhookUrl;
  if (now !== undefined) overrides.now = now;
}

// Test-only: forget overrides, throttle stamps and the warned-once flag.
function __resetForTest() {
  overrides = {};
  lastAttempt = new Map();
  warnedNoUrl = false;
}

module.exports = { notify, configure, __resetForTest };
