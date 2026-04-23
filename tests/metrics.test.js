'use strict';

/**
 * Unit tests for lib/metrics.js — exercise the route-label
 * normalizer + confirm the registry produces Prometheus text
 * output. The end-to-end /metrics HTTP surface is covered by the
 * server integration tests.
 */

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const metrics = require('../lib/metrics');

describe('routeLabel normalization', () => {
  test('uses the matched Express route pattern when present', () => {
    const req = { route: { path: '/api/session/:sessionId' }, baseUrl: '' };
    assert.equal(metrics.routeLabel(req), '/api/session/:sessionId');
  });

  test('concatenates baseUrl + route.path', () => {
    const req = { route: { path: '/stats' }, baseUrl: '/api/admin' };
    assert.equal(metrics.routeLabel(req), '/api/admin/stats');
  });

  test('collapses unmatched /api/* paths to `unmatched`', () => {
    const req = { route: null, originalUrl: '/api/does-not-exist' };
    assert.equal(metrics.routeLabel(req), 'unmatched');
  });

  test('collapses unrelated paths to `unmatched`', () => {
    const req = { route: null, originalUrl: '/favicon.ico' };
    assert.equal(metrics.routeLabel(req), 'unmatched');
  });

  test('handles missing originalUrl gracefully', () => {
    const req = { route: null };
    assert.equal(metrics.routeLabel(req), 'unmatched');
  });
});

describe('registry', () => {
  test('exposes the expected core metric names', async () => {
    const body = await metrics.register.metrics();
    // Histogram series always emits _count + _sum + _bucket siblings;
    // the HELP/TYPE comments carry the base name.
    assert.ok(body.includes('http_requests_total'));
    assert.ok(body.includes('http_request_duration_seconds'));
    assert.ok(body.includes('anthropic_errors_total'));
    assert.ok(body.includes('rate_limit_rejections_total'));
    assert.ok(body.includes('validation_errors_total'));
  });

  test('includes default Node process metrics', async () => {
    const body = await metrics.register.metrics();
    // prom-client's `collectDefaultMetrics` always emits at minimum
    // process_cpu_seconds_total + nodejs_heap_size_total_bytes.
    assert.ok(body.includes('process_cpu_seconds_total'));
    assert.ok(body.includes('nodejs_heap_size_total_bytes'));
  });

  test('applies the service label globally', async () => {
    const body = await metrics.register.metrics();
    // Default label should appear on at least one metric line.
    assert.ok(body.includes('service="mercurius"'));
  });

  test('content-type is the Prometheus text exposition format', () => {
    assert.ok(/text\/plain/.test(metrics.register.contentType));
    assert.ok(/version=/.test(metrics.register.contentType));
  });
});

describe('domain counters are incrementable', () => {
  test('anthropicErrorsTotal accepts { endpoint, kind } labels', () => {
    assert.doesNotThrow(() => {
      metrics.anthropicErrorsTotal.inc({ endpoint: '/api/chat', kind: 'timeout' });
    });
  });

  test('rateLimitRejectionsTotal accepts { scope, endpoint } labels', () => {
    assert.doesNotThrow(() => {
      metrics.rateLimitRejectionsTotal.inc({ scope: 'per-session', endpoint: '/api/chat' });
    });
  });

  test('validationErrorsTotal accepts { endpoint, code } labels', () => {
    assert.doesNotThrow(() => {
      metrics.validationErrorsTotal.inc({ endpoint: '/api/chat', code: 'invalid_session' });
    });
  });
});
