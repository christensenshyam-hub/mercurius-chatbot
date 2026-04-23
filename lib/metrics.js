'use strict';

/**
 * Prometheus metrics registry + Express middleware.
 *
 * Exposes:
 *   - `http_requests_total` — Counter{method, route, status}
 *   - `http_request_duration_seconds` — Histogram{method, route}
 *   - `anthropic_errors_total` — Counter{endpoint, kind}
 *   - `rate_limit_rejections_total` — Counter{scope, endpoint}
 *   - `validation_errors_total` — Counter{endpoint, code}
 *   - Node process metrics (`process_*`, `nodejs_*`) via
 *     `collectDefaultMetrics` — memory, event-loop lag, GC duration.
 *
 * Design:
 *   - One shared `Registry`, exported via `getRegister()` so the
 *     `/metrics` handler can render it.
 *   - `observe(req, res)` middleware fires on `res.finish` so every
 *     response — regardless of origin — updates the counters.
 *   - Route labels are normalized via Express's matched route
 *     pattern (`req.route?.path`) rather than the raw URL, so
 *     `/api/session/abc_123` and `/api/session/xyz_999` both land
 *     in the same bucket (`/api/session/:sessionId`). Unrecognized
 *     paths collapse to `unmatched` to prevent label-cardinality
 *     blowup from scanners / random 404 traffic.
 *   - Status labels are the numeric code as a string. 2xx / 4xx /
 *     5xx granularity matters; prom-client doesn't bucket it for us.
 *
 * Operator notes:
 *   - Scrape at `GET /metrics`. No auth; Prometheus convention.
 *     If you expose the server publicly and don't want /metrics
 *     reachable, block it at the ingress layer.
 *   - Running multiple instances: prom-client's default registry is
 *     per-process. Prometheus handles aggregation via multiple
 *     scrapes, no Redis needed.
 */

const promClient = require('prom-client');

const register = new promClient.Registry();

// Add service-level labels so multi-service dashboards can filter.
register.setDefaultLabels({ service: 'mercurius' });

// Default process metrics (heap, event-loop lag, GC pauses).
promClient.collectDefaultMetrics({ register });

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Count of inbound HTTP requests by method, matched route, and status code',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

const httpRequestDurationSeconds = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Wall-clock duration of inbound HTTP requests',
  labelNames: ['method', 'route'],
  // Buckets tuned for an AI-proxying API: most requests are under
  // a second (quick validation rejects, health checks), streaming
  // chats run multi-second. Beyond 30s we just collapse to +Inf.
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30],
  registers: [register],
});

const anthropicErrorsTotal = new promClient.Counter({
  name: 'anthropic_errors_total',
  help: 'Errors returned by the upstream Anthropic API, by endpoint + kind',
  labelNames: ['endpoint', 'kind'],
  registers: [register],
});

const rateLimitRejectionsTotal = new promClient.Counter({
  name: 'rate_limit_rejections_total',
  help: '429 rejections, labeled by limit scope + endpoint',
  labelNames: ['scope', 'endpoint'],
  registers: [register],
});

const validationErrorsTotal = new promClient.Counter({
  name: 'validation_errors_total',
  help: 'Zod-layer validation rejections, labeled by endpoint + legacy error code',
  labelNames: ['endpoint', 'code'],
  registers: [register],
});

/**
 * Normalize an Express request to a stable route label. Falls back
 * to `unmatched` when no route was matched (unknown URL / 404s from
 * the fallthrough) — keeps label cardinality bounded.
 */
function routeLabel(req) {
  // `req.route` is only set for matched Express routes after the
  // router runs. Prefer `baseUrl + route.path`, fall back to the
  // literal path. Unmatched paths → single bucket.
  if (req.route && req.route.path) {
    return (req.baseUrl || '') + req.route.path;
  }
  if (req.originalUrl && req.originalUrl.startsWith('/api/')) {
    // Some 404 fallthroughs never acquire a matched route.
    return 'unmatched';
  }
  return 'unmatched';
}

/**
 * Express middleware that observes every response. Stashes a
 * high-resolution start time on the request, then on
 * `res.on('finish')` records the count + duration.
 */
function observe() {
  return (req, res, next) => {
    const start = process.hrtime.bigint();
    res.on('finish', () => {
      const route = routeLabel(req);
      const status = String(res.statusCode);
      const method = req.method;
      const durationSec = Number(process.hrtime.bigint() - start) / 1e9;

      httpRequestsTotal.inc({ method, route, status });
      httpRequestDurationSeconds.observe({ method, route }, durationSec);
    });
    next();
  };
}

/**
 * Mount GET /metrics on the given Express app.
 */
function mount(app, path = '/metrics') {
  app.get(path, async (_req, res) => {
    res.setHeader('Content-Type', register.contentType);
    res.send(await register.metrics());
  });
}

module.exports = {
  register,
  observe,
  mount,
  routeLabel,
  // Domain counters exposed for server.js to increment directly.
  anthropicErrorsTotal,
  rateLimitRejectionsTotal,
  validationErrorsTotal,
};
