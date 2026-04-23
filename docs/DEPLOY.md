# Deploy + runtime configuration

Reference for operators running `server.js` in production.
Maintained alongside the code — update this doc whenever a new
env var becomes part of the supported runtime surface.

## Environment variables

### Required

| Var | Purpose | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | Upstream key used by `@anthropic-ai/sdk` | Never log this. See `lib/logger.js` redact list. |
| `ALLOWED_ORIGIN` | Comma-separated CORS allowlist | E.g. `https://mayoailiteracy.com,https://www.mayoailiteracy.com`. Unset in development means "any origin." |

### Recommended

| Var | Purpose | Default |
|---|---|---|
| `PORT` | HTTP bind port | `3000` |
| `NODE_ENV` | `production` switches log level to INFO and disables dev niceties | `development` |
| `DATABASE_URL` | Postgres connection string | If unset, falls back to a local SQLite file (`mercurius.db`). Fine for dev; use Postgres for production. |
| `ADMIN_PASSWORD` | Gates `POST /api/admin/events` | Unset = admin endpoints always 401. |

### Observability + runtime tuning

| Var | Purpose | Default |
|---|---|---|
| `LOG_LEVEL` | `trace`, `debug`, `info`, `warn`, `error`, `silent` | `info` in prod, `debug` elsewhere, `silent` when `NODE_ENV=test` |
| `MODEL_ALLOWLIST` | Comma-separated Anthropic model ids the server will accept when a client supplies `model` on `/api/chat` | `claude-sonnet-4-6,claude-3-5-haiku-latest` |
| `MEMORY_MODEL` | Model used for the background memory-extraction job (not client-selectable) | `claude-3-5-haiku-latest` |

### Rate limiting — horizontal scaling

| Var | Purpose | When to set |
|---|---|---|
| `REDIS_URL` | If set, rate limits are stored in Redis; counters are shared across every replica. If unset, each process keeps an independent in-memory counter (correct for a single replica). | Set this the moment you run more than one Railway replica — otherwise your effective rate limit becomes `N × configured_limit`. See `lib/rateLimiter.js`. |

Accepted URL shapes:

```
redis://user:pass@host:6379/0
redis://host:6379
rediss://host:6380   # TLS
```

Passwords are redacted from logs automatically (`lib/rateLimiter.js:redactUrl`).

Failure mode: if `REDIS_URL` is set but the server can't reach Redis, the limiter *open-fails* — requests are allowed through rather than 500'd. This avoids a Redis outage cascading into an API outage. The fallback is logged at `warn` level (search for `session rate-limit check failed`).

## Railway-specific deployment

### Running one replica (current, default)

No additional config needed. Set the env vars in the service's
Variables tab:

```
ANTHROPIC_API_KEY=sk-ant-...
ALLOWED_ORIGIN=https://mayoailiteracy.com
DATABASE_URL=<Railway-provided>
ADMIN_PASSWORD=<random 32 chars>
NODE_ENV=production
```

### Scaling to N replicas

Before bumping the replica count:

1. Provision a Redis service in the same Railway project
   (Dashboard → "+ Create" → "Redis"). Railway assigns `REDIS_URL`
   automatically.
2. Reference the Redis service's URL in the server service's
   variables using Railway's variable reference syntax:
   `${{Redis.REDIS_URL}}`.
3. Deploy. Watch the startup log for:
   `{"level":30,"msg":"rate-limiter: Redis connected", ...}`
4. Scale the replica count via the service's "Scaling" section.

### Verifying Redis is active

Two ways:

- **Startup log**: look for `rate-limiter: Redis connected`.
  If you see `no REDIS_URL — using in-memory store (single-replica mode)`
  the service didn't read the var.
- **Metrics**: hit `/metrics` and search for the `service="mercurius"`
  label. A per-replica divergence in `http_requests_total` between
  replicas that should see similar traffic is a hint the limiter
  isn't deduping.

## Health checks

| Route | Notes |
|---|---|
| `GET /api/health` | Returns `{ status, uptime, db, memory }`. Railway should point its health check at this. Returns 503 (not 200) when DB connectivity fails. |
| `GET /metrics` | Prometheus text exposition format. No auth. Scrape from any Prometheus-compatible agent. |

## Failure modes to know about

| Symptom | Likely cause | Action |
|---|---|---|
| `/api/health` returns 503 with `db: "error: ..."` | Postgres connection down / connection pool exhausted | Check `DATABASE_URL` validity; check Railway Postgres service health |
| Client sees `{"error":"rate_limited"}` en masse | Shared IP (school network, NAT) plus burst of students. IP-based limiter is 60 req/min/IP. | Consider raising the global limiter max in `server.js`, OR rely more on per-session limiting + configure Redis so the session limit works across replicas |
| Client sees `{"error":"invalid_model"}` | Client is passing a `model` that isn't in `MODEL_ALLOWLIST` | Either remove the client's override or add the model to the env allowlist. |
| Startup crashes: `Failed to initialize database` | Postgres schema creation failed. Check logs for the underlying SQL error. | Re-run migrations / verify schema drift. |
| Prompt content appears in Railway logs | Regression in `lib/logger.js` redact list | Open a red-PR issue — this is a correctness bug in the redaction layer. Review `tests/logger.test.js` for which paths are covered. |

## Secrets hygiene

- All secrets flow through env vars, not files. Nothing in the repo.
- `ANTHROPIC_API_KEY`, `ADMIN_PASSWORD` are auto-redacted from logs
  at the pino serializer layer (see `lib/logger.js:REDACT_PATHS`).
- `REDIS_URL` passwords are stripped from startup logs via
  `rateLimiter._redactUrl`.
- When rotating the Anthropic key: deploy the new key to Railway
  first, wait for the new replica to come up, then revoke the old
  key at console.anthropic.com. Brief period where both work.
