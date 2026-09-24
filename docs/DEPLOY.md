# Deploy + runtime configuration

Reference for operators running `server.js` in production.
Maintained alongside the code — update this doc (and `.env.example`,
which is the canonical annotated list) whenever a new env var becomes
part of the supported runtime surface.

## Toolchain

| What | Value | Where it is pinned |
|---|---|---|
| Node | **22** (`>=22`) | `.nvmrc`, `package.json` → `engines.node`, CI matrix in `.github/workflows/server.yml`, Railway's nixpacks build (reads `engines`) |
| npm | the one bundled with Node 22 | `package-lock.json` is lockfile v3 — always `npm ci`, never `npm install`, in CI and on Railway |

Local setup:

```
nvm use               # picks up .nvmrc → 22
npm ci
cp .env.example .env  # then fill in ANTHROPIC_API_KEY
npm test              # full suite; the count is whatever `# tests N` prints
npm run dev
```

Node 20 is no longer a supported target: it left Maintenance LTS in
April 2026 and CI tests against 22 only.

## Environment variables

`.env.example` carries one comment per variable and the value the code
falls back to when a variable is unset. This section is the operator
view: what to set in production and why.

### Required

| Var | Purpose | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | Upstream key used by `@anthropic-ai/sdk` | Never log this. See `lib/logger.js` redact list. Not needed when `ANTHROPIC_MOCK=1`. |
| `ALLOWED_ORIGIN` | Comma-separated CORS allowlist | E.g. `https://mayoailiteracy.com,https://www.mayoailiteracy.com`. Unset means "any origin" — acceptable only in development. |
| `DATABASE_URL` | Postgres connection string | Railway-provided. If unset the server falls back to a local SQLite file, which is fine for dev and wrong for production (ephemeral filesystem). |

### Recommended

| Var | Purpose | Default |
|---|---|---|
| `PORT` | HTTP bind port | `3000` (Railway injects its own) |
| `NODE_ENV` | `production` switches log level to INFO and disables dev niceties | `development` |
| `ADMIN_PASSWORD` | Gates every `/api/admin/*` route via the `x-admin-password` header (events, kill switch) | Unset = admin endpoints always 401. Use a random 32+ char string. |
| `USE_UNIFIED_PROMPT` | `1`/`true` serves every mode from the single unified system prompt (`lib/unifiedPrompt.js`) | Off. **Railway prod runs with it ON** — verify prompt work under both states. |
| `STREAK_TZ` | IANA zone that decides when a streak "day" rolls over | `America/New_York` |

### Anthropic + stream lifecycle + mock

The millisecond vars here treat empty or `0` as unset (the default
applies) — unlike the quotas below, where `0` means refuse.

| Var | Purpose | Default |
|---|---|---|
| `MODEL_ALLOWLIST` | Comma-separated model ids the server accepts when a client supplies `model` on `/api/chat`; anything else is rejected with `invalid_model` | `claude-sonnet-4-6,claude-3-5-haiku-latest` |
| `STREAM_IDLE_MS` | Abort a Claude stream that has produced no delta for this long (wedged upstream) | `30000` |
| `STREAM_MAX_MS` | Hard cap on one stream's total wall time (runaway reply). A healthy long lesson turn trips neither watchdog. | `150000` |
| `STREAM_WATCHDOG_MS` | Legacy name for `STREAM_MAX_MS` (eval/CI overrides); when set it wins | unset |
| `SSE_KEEPALIVE_MS` | Interval between SSE `: ping` keepalive comments so school proxies and cellular NATs keep a quiet stream open | `15000` |
| `DRAIN_TIMEOUT_MS` | On SIGTERM stop accepting model work at once but let in-flight streams finish for up to this long before exiting | `30000` — set Railway's `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` to at least this many seconds |
| `ANTHROPIC_MOCK` | Exactly `1` swaps the SDK for the in-process mock (`lib/anthropicMock.js`) — no key, no network, no spend. Integration tests and offline UI work; the server logs a boot warning. | off |
| `MOCK_SCENARIO` | `ok`, `error`, `overloaded`, `slow`, `hang` or `credit` — forces 5xx, 529, a stalled stream or credit exhaustion on demand | `ok`; only read when `ANTHROPIC_MOCK=1` |
| `MOCK_STREAM_DELAY_MS` | Delay between streamed text deltas from the mock (`slow` multiplies it by 20) | `5`; only read when `ANTHROPIC_MOCK=1` |
| `MOCK_TIMEOUT_MS` | How long a `hang` scenario waits before failing like the SDK client timeout | `30000`; only read when `ANTHROPIC_MOCK=1` |

### Observability

| Var | Purpose | Default |
|---|---|---|
| `LOG_LEVEL` | `trace`, `debug`, `info`, `warn`, `error`, `silent` | `info` in prod, `debug` elsewhere, `silent` when `NODE_ENV=test` |
| `DISCORD_WEBHOOK_URL` | Channel webhook that receives operator alerts: spend cap at 80 %/100 %, kill-switch flips, per-IP cap trips, boot, Anthropic error bursts (`lib/alerts.js`) | Unset = alerts are a silent no-op. Treat as a secret — the URL embeds a token. |
| `IP_HASH_SALT` | Salt appended to the client IP before it is sha256-hashed for the `usage` ledger, per-IP alerts and logs (`lib/claudeCall.js` `hashIp`) | Empty = unsalted hash. Set a long random string in production and keep it stable across deploys — rotating it breaks continuity of every hashed id in the ledger. Read once at boot. |

### Storage

| Var | Purpose | Default |
|---|---|---|
| `SQLITE_PATH` | SQLite file used only when `DATABASE_URL` is unset | `./mercurius.db` beside `db.js` |
| `IMAGE_STORAGE_DRIVER` | Where uploaded images are persisted | `db` (bytes in the database). Object-storage drivers plug in via `lib/imageStore.js`. |
| `GAMIFICATION_ENABLED` | `1`/`true` activates the standby gamification tables and `/api/progression/*` | off; when off nothing gamification-related is created or served |

### Spend + safety rails

All of these are **in-memory, per process**. That is correct for the
single-replica deployment and adds no infrastructure; see "Scaling"
below before running more than one replica.

| Var | Purpose | Default |
|---|---|---|
| `DAILY_BUDGET_USD` | Global daily Anthropic spend ceiling in US dollars, priced per call from `lib/pricing.js`. Once reached, every Claude-backed route returns 503 until UTC midnight. Re-hydrated from the usage table on restart. `0` refuses every call. Replaces the retired `DAILY_TOKEN_CEILING`, which is no longer read. | `15` |
| `CLAUDE_DISABLED` | `1`/`true` boots with all Anthropic calls disabled (503). The runtime toggle `POST /api/admin/kill-switch {"disabled":true\|false}` overrides it in seconds, no redeploy. | off |

### Per-minute rate limits (`lib/rateLimiter.js`)

Sized for a whole classroom behind one school NAT address, so a burst
of students never looks like one abusive client.

| Var | Scope | Default |
|---|---|---|
| `API_IP_PER_MIN` | all `/api/*` requests, per client IP | `400` |
| `CHAT_IP_PER_MIN` | `/api/chat`, per client IP | `150` |
| `UPLOAD_IP_PER_MIN` | `/api/images` uploads, per client IP | `60` |
| `SESSION_PER_MIN` | `/api/chat` turns, per session id | `10` |

### Daily quotas + in-flight caps (`lib/quotas.js`)

Per-session and per-address backstops beneath `DAILY_BUDGET_USD`, so a
single runaway client cannot drain it for every other student. Counters
are per UTC day and in-memory. A tripped daily quota answers
`429 daily_limit` (with `retryAfterSec` = seconds to UTC midnight); a
tripped in-flight cap answers `503 busy` with a 60 s retry. Unset =
default; `0` refuses everything.

| Var | Scope | Default |
|---|---|---|
| `SESSION_DAILY_LESSON_TURNS` | curriculum (lesson) turns per session | `40` |
| `SESSION_DAILY_CHAT_TURNS` | free-chat turns (incl. helper calls) per session | `60` |
| `SESSION_DAILY_USD` | Anthropic spend per session | `0.75` |
| `SESSION_DAILY_IMAGES` | image uploads per session | `20` |
| `IP_DAILY_USD` | Anthropic spend per client IP, summed over its sessions | `10` |
| `IP_DAILY_NEW_SESSIONS` | new session ids per client IP (curbs id rotation) | `60` |
| `IP_MAX_INFLIGHT` | concurrent Claude calls per client IP | `40` |
| `MAX_INFLIGHT` | concurrent Claude calls for the whole process; beyond it requests get `503 busy`, not a queue | `80` |

### Removed variables

| Var | Status |
|---|---|
| `REDIS_URL` | Removed. Rate limits, quotas, the spend cap and the kill switch are all in-process; there is no Redis-backed store any more. Setting it does nothing. |
| `MEMORY_MODEL` | Removed with the background memory-extraction job. Setting it does nothing. |

Delete both from the Railway Variables tab so nobody reads them as
live configuration.

## Railway-specific deployment

`railway.toml` is the source of truth for the service definition:
nixpacks build, `node server.js` start command, health check on
`/api/health` with a 120 s first-response timeout, restart on failure
up to 10 times.

### Running one replica (current, default)

Set the env vars in the service's Variables tab:

```
ANTHROPIC_API_KEY=sk-ant-...
ALLOWED_ORIGIN=https://mayoailiteracy.com,https://www.mayoailiteracy.com
DATABASE_URL=<Railway-provided>
ADMIN_PASSWORD=<random 32 chars>
NODE_ENV=production
USE_UNIFIED_PROMPT=1
DAILY_BUDGET_USD=15
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
IP_HASH_SALT=<random 32 chars>
STREAK_TZ=America/New_York
RAILWAY_DEPLOYMENT_DRAINING_SECONDS=30
```

`RAILWAY_DEPLOYMENT_DRAINING_SECONDS` is read by Railway, not the
server: it is how long the old replica keeps running after SIGTERM.
Keep it at or above `DRAIN_TIMEOUT_MS / 1000`, otherwise Railway
hard-kills the old replica while lessons are still streaming.

The per-minute limits and daily quotas can stay unset unless you are
tuning them; the defaults above apply.

### Database migrations

The base schema is code-owned (`db.initSchema`, `CREATE IF NOT EXISTS`
at server boot). Deltas on top of it ship as `migrations/NNN_name.sql`
and are applied with the `migrate` npm script (`scripts/migrate.mjs`):

```
npm run migrate                 # local (SQLite, or DATABASE_URL from .env)
railway run npm run migrate     # production, with the service's Variables injected
```

What the script does: picks the driver exactly as `db.js` does
(`DATABASE_URL` → Postgres, else SQLite at `SQLITE_PATH`), bootstraps
the base schema on a fresh database, creates `schema_migrations` if
missing, then applies each not-yet-recorded file in filename order —
file and bookkeeping row in one atomic statement, so a failure is
neither half-applied nor recorded. Exit 0 when everything is applied or
already recorded, 1 on the first failure. It is safe to re-run.

Run it against production **before** deploying a build that depends on
the new schema (the `railway run` form injects the service's
Variables, so it hits the real Postgres). Migration files must not
contain their own `BEGIN`/`COMMIT`.

### Scaling to N replicas

**Not supported by the current build.** Every safety rail — per-IP and
per-session rate limits, daily quotas, the USD spend cap and the kill
switch — is process-local state. With N replicas each of them silently
becomes `N × configured_limit` and the kill switch only flips the
replica that received the admin call. Before raising the replica count,
move that state to a shared store (the former Redis integration was
removed rather than left half-wired); until then keep the count at 1
and scale vertically.

## Health checks

| Route | Notes |
|---|---|
| `GET /api/health` | Returns `{ status, uptime, db, memory }`. Railway's health check points here (`railway.toml`). Returns 503 (not 200) when DB connectivity fails, so a deploy with a bad `DATABASE_URL` never takes traffic. |
| `GET /metrics` | Prometheus text exposition format. No auth. Scrape from any Prometheus-compatible agent. |

## Failure modes to know about

| Symptom | Likely cause | Action |
|---|---|---|
| Deploy stalls, then Railway marks it failed after ~2 min | `/api/health` never returned 2xx inside `healthcheckTimeout` — usually DB connectivity or a startup crash | Read the deploy log; check `DATABASE_URL`; run `railway run npm run migrate` if the log shows a missing table |
| `/api/health` returns 503 with `db: "error: ..."` | Postgres connection down / connection pool exhausted | Check `DATABASE_URL` validity; check Railway Postgres service health |
| Every Claude-backed route returns 503 and Discord got a `budget_100` alert | `DAILY_BUDGET_USD` reached | Decide whether the spend is legitimate. Raise the var (restart) or wait for UTC midnight. Look at `/api/admin/events` for who spent it. |
| Claude-backed routes return `503 restarting` for a few seconds | A deploy is draining the old replica (`DRAIN_TIMEOUT_MS`) | Expected; clients retry. If it outlasts the drain window the new replica failed its health check — read the deploy log. |
| Every Claude-backed route returns `503 service_disabled`, no budget alert | Kill switch is on — either `CLAUDE_DISABLED` at boot or a runtime flip | `GET /api/admin/kill-switch` to confirm; `POST /api/admin/kill-switch {"disabled":false}` to re-enable |
| Client sees `{"error":"rate_limited"}` en masse | Shared IP (school network, NAT) plus a burst of students over `API_IP_PER_MIN` / `CHAT_IP_PER_MIN` | Raise the relevant `*_PER_MIN` var for the event, then restore it. Per-session limits are unaffected. |
| One student gets `429 daily_limit` for the rest of the day | A `SESSION_DAILY_*` or `IP_DAILY_*` quota tripped (`lib/quotas.js`) | Confirm in the Discord `ip_cap` alert / admin events; raise the specific var if the usage was legitimate (restart to apply) |
| Clients get `503 busy` during a class | `IP_MAX_INFLIGHT` (whole school behind one NAT) or `MAX_INFLIGHT` reached | Transient by design — it clears as streams finish. Raise the cap only if `/metrics` shows the process was not actually saturated. |
| Client sees `{"error":"invalid_model"}` | Client is passing a `model` that isn't in `MODEL_ALLOWLIST` | Either remove the client's override or add the model to the env allowlist. |
| Startup crashes: `Failed to initialize database` | Postgres schema creation failed. Check logs for the underlying SQL error. | `railway run npm run migrate`; verify schema drift. |
| Prompt content appears in Railway logs | Regression in `lib/logger.js` redact list | Open a red-PR issue — this is a correctness bug in the redaction layer. Review `tests/logger.test.js` for which paths are covered. |

## Secrets hygiene

- All secrets flow through env vars, not files. Nothing in the repo.
- `ANTHROPIC_API_KEY`, `ADMIN_PASSWORD` are auto-redacted from logs
  at the pino serializer layer (see `lib/logger.js:REDACT_PATHS`).
- `DISCORD_WEBHOOK_URL` embeds a bearer-like token; `lib/alerts.js`
  never writes the URL or the alert body to the log — only the alert
  key, HTTP status and character count.
- `IP_HASH_SALT` is what keeps hashed IPs unlinkable to raw addresses;
  treat it like a password and do not reuse it across environments.
- When rotating the Anthropic key: deploy the new key to Railway
  first, wait for the new replica to come up, then revoke the old
  key at console.anthropic.com. Brief period where both work.
