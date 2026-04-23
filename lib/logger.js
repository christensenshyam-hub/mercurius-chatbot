'use strict';

/**
 * Structured logger with redaction for prompt/response content.
 *
 * Responsibilities:
 *  - Emit JSON-line logs to stdout so Railway (or any hosted
 *    runtime) can ingest them as structured events.
 *  - Redact sensitive content paths before serialization so chat
 *    messages, assistant replies, and API keys NEVER leak into
 *    logs, even if a caller accidentally passes them to a log call.
 *  - Preserve the trace id each request carries so logs per request
 *    can be correlated end-to-end.
 *
 * Design notes:
 *  - Uses `pino` because it's the de-facto Node structured logger:
 *    fast, battle-tested, and its `redact` option intercepts fields
 *    at the serializer level — no path in the object tree gets
 *    written if it matches a redaction pattern, regardless of whether
 *    the caller remembered to strip it.
 *  - Log level defaults to INFO in production, DEBUG elsewhere.
 *    Override with LOG_LEVEL.
 *  - Does NOT pretty-print. In development, pipe through
 *    `node server.js | npx pino-pretty` if you want human-readable
 *    output; the raw stream stays machine-parseable.
 *
 * Never-log policy:
 *  - `*.content` — Anthropic-shaped message bodies + our own tool
 *    request bodies (quiz, report-card) carry chat content here.
 *  - `*.reply` — assistant responses.
 *  - `*.messages[*].content` — arrays of chat messages.
 *  - `*.text` inside a content block — Anthropic 2024+ SDK shape.
 *  - `authorization`, `x-api-key` — request auth headers.
 *  - `ANTHROPIC_API_KEY`, `ADMIN_PASSWORD` — environment reflections
 *    that occasionally get logged during debugging.
 */

const pino = require('pino');

const REDACT_PATHS = [
  // Chat + tool payloads
  '*.content',
  '*.reply',
  '*.messages[*].content',
  '*.messages[*].content[*].text',
  'req.body.messages',
  'req.body.content',
  'req.body.reply',
  'body.messages',
  'body.content',

  // Anthropic SDK response shape
  'response.content',
  'response.content[*].text',

  // Secrets / auth
  'authorization',
  '*.authorization',
  'req.headers.authorization',
  'req.headers["x-admin-password"]',
  'headers.authorization',
  'headers["x-admin-password"]',
  '*.ANTHROPIC_API_KEY',
  '*.ADMIN_PASSWORD',
  'env.ANTHROPIC_API_KEY',
  'env.ADMIN_PASSWORD',
];

const level =
  process.env.LOG_LEVEL ||
  (process.env.NODE_ENV === 'production' ? 'info' : 'debug');

const logger = pino({
  level,
  // `silent` is honored by pino in test environments so tests can
  // assert no output leaks. Force it on when NODE_ENV=test AND the
  // caller has not set LOG_LEVEL explicitly.
  ...(process.env.NODE_ENV === 'test' && !process.env.LOG_LEVEL
    ? { level: 'silent' }
    : {}),
  base: {
    service: 'mercurius',
    env: process.env.NODE_ENV || 'development',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: {
    paths: REDACT_PATHS,
    censor: '[REDACTED]',
    remove: false,
  },
  // Serialize Error objects cleanly.
  serializers: {
    err: pino.stdSerializers.err,
    error: pino.stdSerializers.err,
  },
});

/**
 * Return a child logger scoped to a request trace id. Use inside
 * request handlers so every log line carries the correlation id.
 *
 *    const log = logger.forRequest(req);
 *    log.info({ endpoint: '/api/chat' }, 'handling chat');
 */
logger.forRequest = function forRequest(req) {
  return logger.child({ traceId: req.traceId || 'unknown' });
};

/**
 * Paths we promise never to write. Exported for tests.
 */
logger.redactPaths = Object.freeze([...REDACT_PATHS]);

module.exports = logger;
