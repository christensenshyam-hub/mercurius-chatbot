'use strict';

/**
 * Shared Zod schemas for request-body validation.
 *
 * Why centralize:
 *  - The previous handwritten validators scattered through server.js
 *    drifted over time — some endpoints checked length, others didn't;
 *    some enforced types, others implicitly coerced.
 *  - One source of truth means every endpoint's error output is shaped
 *    the same, and adding a new field (see Phase 5c's `model` allowlist)
 *    is a one-line schema change, not a search for every handler.
 *
 * Error-response compatibility:
 *  - The existing integration tests (and the iOS client) expect errors
 *    like `{ error: 'invalid_session' }` and `{ error: 'invalid_messages' }`.
 *    The `validate(schema, options)` helper in this file maps Zod's
 *    issue paths back to those legacy error codes so we don't break the
 *    wire contract. Clients see the same JSON shape they did before;
 *    the only difference is that validation is stricter and more
 *    consistent across endpoints.
 */

const { z } = require('zod');
const logger = require('./logger');

// ---------------------------------------------------------------------------
// Atomic types
// ---------------------------------------------------------------------------

/**
 * Session id: alphanumeric + `_` / `-`, 1 to 64 chars. Matches the
 * existing server-side `isValidSessionId` regex and the client-side
 * `SessionIdentity.isValid(_:)` rules so the two agree.
 */
const SessionId = z
  .string()
  .min(1, 'session_id_empty')
  .max(64, 'session_id_too_long')
  .regex(/^[a-zA-Z0-9_-]+$/, 'session_id_bad_chars');

/**
 * Chat message as it appears on the wire. Content is capped; the
 * existing pipeline truncates to 2000 chars silently at the boundary
 * for robustness, so we don't REJECT over-length content here — we
 * cap at a very permissive upper bound purely to guard against
 * obviously hostile payloads.
 */
const ChatMessage = z.object({
  role: z.enum(['user', 'assistant', 'system']),
  content: z.string().max(10_000, 'content_too_long'),
});

const ChatMode = z.enum(['socratic', 'direct', 'debate', 'discussion']);

// ---------------------------------------------------------------------------
// Request schemas
// ---------------------------------------------------------------------------

/**
 * `POST /api/chat`
 * `model` is an optional client-supplied override. Its presence is
 * only type-checked here; the allowlist enforcement lives in
 * `lib/modelAllowlist.js` because the allowlist is env-driven and
 * evaluates at request time, not at schema-build time.
 */
const ChatRequest = z.object({
  sessionId: SessionId,
  messages: z.array(ChatMessage).min(1, 'messages_empty').max(200, 'messages_too_many'),
  model: z.string().min(1).max(64).optional(),
});

const ModeRequest = z.object({
  sessionId: SessionId,
  mode: ChatMode,
  // Client is free to send `clientUnlocked`; server ignores it (the DB
  // is the source of truth). Accept it without failing validation.
  clientUnlocked: z.boolean().optional(),
  unlocked: z.boolean().optional(),
});

const QuizRequest = z.object({
  sessionId: SessionId,
  // The `messages` list on this endpoint is ignored server-side — the
  // server reads from its own DB — but the iOS client sends an empty
  // array. Accept either shape.
  messages: z.array(ChatMessage).optional(),
});

const ReportCardRequest = QuizRequest;
const ConceptMapRequest = QuizRequest;

// ---------------------------------------------------------------------------
// Validator middleware
// ---------------------------------------------------------------------------

/**
 * Map a Zod issue-path to the legacy error code the wire contract
 * (and iOS client) expects. Order matters — first match wins.
 */
function legacyErrorCode(issues) {
  for (const issue of issues) {
    const path = issue.path.join('.');
    if (path.startsWith('sessionId')) return 'invalid_session';
    if (path.startsWith('messages') || path === '' && issue.code === 'invalid_type') {
      return 'invalid_messages';
    }
    if (path.startsWith('mode')) return 'invalid_request';
  }
  return 'invalid_request';
}

/**
 * Build an Express middleware that parses `req.body` against the given
 * schema and populates `req.validated` with the parsed result on
 * success. On failure, responds 400 with an error envelope shaped to
 * match the existing client contract.
 */
function validate(schema, { endpoint = 'unknown' } = {}) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (result.success) {
      req.validated = result.data;
      return next();
    }
    const code = legacyErrorCode(result.error.issues);
    logger.forRequest(req).warn(
      {
        endpoint,
        code,
        issues: result.error.issues.map((i) => ({
          path: i.path.join('.'),
          code: i.code,
          message: i.message,
        })),
      },
      'request validation failed',
    );
    return res.status(400).json({
      error: code,
      reply: code === 'invalid_session'
        ? 'Session ID missing or invalid.'
        : code === 'invalid_messages'
          ? 'No messages provided.'
          : 'Bad request.',
    });
  };
}

module.exports = {
  SessionId,
  ChatMessage,
  ChatMode,
  ChatRequest,
  ModeRequest,
  QuizRequest,
  ReportCardRequest,
  ConceptMapRequest,
  validate,
  // Exposed for unit tests.
  _legacyErrorCode: legacyErrorCode,
};
