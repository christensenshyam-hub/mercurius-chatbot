'use strict';

/**
 * Logger redaction tests.
 *
 * Strategy: instead of importing the global logger (which is forced
 * to `silent` level under NODE_ENV=test), build an isolated pino
 * instance that writes to a Writable stream we control. Apply the
 * exact same redact config the library exports. Then feed it the
 * shapes our server actually logs and assert that sensitive paths
 * are redacted.
 *
 * This verifies the redact config itself — not the rest of the
 * logger module — but that's the piece where a bug would ship
 * customer prompt content to Railway logs.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { Writable } = require('node:stream');
const pino = require('pino');

const logger = require('../lib/logger');

function makeCapturingLogger() {
  const chunks = [];
  const stream = new Writable({
    write(chunk, _encoding, callback) {
      chunks.push(chunk.toString('utf8'));
      callback();
    },
  });
  const testLogger = pino(
    {
      level: 'debug',
      redact: {
        paths: [...logger.redactPaths],
        censor: '[REDACTED]',
        remove: false,
      },
    },
    stream,
  );
  return { logger: testLogger, chunks };
}

function parseLines(chunks) {
  return chunks
    .join('')
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return { raw: line };
      }
    });
}

describe('logger redaction', () => {
  test('messages[].content is replaced with [REDACTED]', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.info({
      req: {
        body: {
          messages: [
            { role: 'user', content: 'This is a secret prompt about AI' },
            { role: 'assistant', content: 'And here is the secret reply' },
          ],
        },
      },
    }, 'incoming');

    const [entry] = parseLines(chunks);
    const serialized = JSON.stringify(entry);
    assert.ok(
      !serialized.includes('secret prompt'),
      'prompt text must not appear in log output',
    );
    assert.ok(
      !serialized.includes('secret reply'),
      'reply text must not appear in log output',
    );
    assert.ok(
      serialized.includes('[REDACTED]'),
      'redaction marker should appear for zeroed-out paths',
    );
  });

  test('top-level body.content is redacted', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.info({ body: { content: 'raw prompt' } }, 'incoming');
    const serialized = JSON.stringify(parseLines(chunks)[0]);
    assert.ok(!serialized.includes('raw prompt'));
    assert.ok(serialized.includes('[REDACTED]'));
  });

  test('assistant reply fields are redacted', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.info({ response: { reply: 'the full assistant answer' } }, 'response');
    const serialized = JSON.stringify(parseLines(chunks)[0]);
    assert.ok(!serialized.includes('full assistant answer'));
  });

  test('authorization header is redacted', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.info({
      req: {
        headers: {
          authorization: 'Bearer sk-ant-abcdef-supersecret',
          'x-admin-password': 'password123',
        },
      },
    }, 'headers seen');
    const serialized = JSON.stringify(parseLines(chunks)[0]);
    assert.ok(!serialized.includes('sk-ant-abcdef-supersecret'));
    assert.ok(!serialized.includes('password123'));
  });

  test('an env reflection of the Anthropic key is redacted', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.debug({ env: { ANTHROPIC_API_KEY: 'sk-ant-shouldnotleak' } }, 'env');
    const serialized = JSON.stringify(parseLines(chunks)[0]);
    assert.ok(!serialized.includes('sk-ant-shouldnotleak'));
  });

  test('non-sensitive fields pass through unchanged', () => {
    const { logger: log, chunks } = makeCapturingLogger();
    log.info({ traceId: 'abc-123', sessionId: 'sess_xyz', status: 200 }, 'ok');
    const entry = parseLines(chunks)[0];
    assert.equal(entry.traceId, 'abc-123');
    assert.equal(entry.sessionId, 'sess_xyz');
    assert.equal(entry.status, 200);
  });

  test('redactPaths is exposed for test consumers', () => {
    assert.ok(Array.isArray(logger.redactPaths));
    assert.ok(logger.redactPaths.length > 0);
    assert.ok(logger.redactPaths.includes('*.messages[*].content'));
  });
});
