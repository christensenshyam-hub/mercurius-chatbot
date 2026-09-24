# Load rehearsal

`scripts/load-rehearsal.mjs` is the pre-kickoff drill for the server: it
boots `server.js` exactly as production runs it — every limit from
`.env.example` set explicitly, nothing loosened — but with the in-process
Anthropic mock (`ANTHROPIC_MOCK=1`, no key, no spend) on a throwaway SQLite
file, then throws the day-one traffic shapes at it and prints one verdict
table. Run it before a classroom kickoff and after any change to
`lib/quotas.js`, `lib/rateLimiter.js`, the `gate()` / `sendRefusal()` path
or the SIGTERM drain in `server.js`.

```
npm run load-rehearsal
```

Takes about 15 s. No new dependencies (global `fetch`, `node:net`,
`node:child_process`; Node 22).

## What it proves

| Scenario | Traffic | PASS means |
|---|---|---|
| **Classroom** | 30 sessions behind ONE forwarded-for address (a school NAT), each streaming a 5-turn `[CURRICULUM: Unit 1, Lesson 1]` lesson over SSE, all at once | zero refusals; every one of the 150 streams ends with a `complete` frame and `[DONE]` |
| **Hostile session** | one session fires 40 chat turns at once | the overflow beyond `SESSION_PER_MIN` (10) is refused `429 {error:"rate_limited"}` with a human message; `/api/health` stays 200; no crash |
| **Hostile rotation** | one address mints 80 fresh session ids, one turn each | fresh id #61 is the first refusal (`IP_DAILY_NEW_SESSIONS` 60) and every id after it gets `429 {error:"daily_limit", scope:"ip", retryAfterSec}` plus a `Retry-After` header |
| **Spike** | 200 first turns from 200 distinct addresses at once | every request is answered — `200`, or the SSE refusal frame `busy` once `MAX_INFLIGHT` (80) is reached; health stays 200 |
| **Drain** | 10 lesson streams are open when the process gets SIGTERM (what every Railway deploy sends) | all 10 finish with `complete` + `[DONE]`; `/api/health` answers `503 {status:"draining"}` during the drain; the process exits 0 inside `DRAIN_TIMEOUT_MS` |

The exit status is non-zero only when **Classroom** or **Drain** fails (or
the server crashes) — those two would wreck a real class. The hostile
scenarios print `FAIL` loudly but are informational, so a deliberate change
to a hostile-path envelope does not block a deploy by itself.

The table also reports, per scenario, the count of 200s, 429s and 503s by
`error` code, anything unexpected (500s, truncated streams, socket errors —
never expected, always shown), and p50 / p95 end-to-end latency. Below the
table each scenario prints the numbers behind its verdict, e.g. how many
lessons reached `[LESSON_COMPLETE]`, the exact refusal body seen, and the
drain's exit time.

Two details of the drain are worth knowing when reading its notes:

- `server.js` flips `draining = true` and calls `server.close()` in the same
  tick, so a health probe on a **new** TCP connection is refused
  (`ECONNREFUSED`) rather than answered 503. The script observes the real
  503 by opening a health request *before* SIGTERM and completing it during
  the drain (a request whose headers are partly sent is active, not idle, so
  `closeIdleConnections()` leaves it alone). Both outcomes are non-200,
  which is what the platform needs; the note lists both.
- The mock's stream delay (`--delay`, default 40 ms) makes a lesson turn
  stream for ~1.4 s. That is what lets the spike overlap 200 requests past
  the 80 in-flight cap and lets SIGTERM land mid-stream. Below ~20 ms the
  streams finish before either can happen.

## Reading a failure

- **Classroom refusals** mean a production default is too tight for one
  room. Note that 30 students × 5 turns = 150 is *exactly*
  `CHAT_IP_PER_MIN`; the scenario's headroom note sends request #151 from
  the same address inside the minute and reports what it got (expected:
  `429 rate_limited`). A real class streams each turn for 5–15 s, so it
  cannot reach 150 chat requests in a minute the way the mock does, but a
  retry storm or the widget's quiz/report-card helper calls share that
  bucket.
- **Drain losing streams** or exiting non-zero is a defect in the SIGTERM
  path (`shutdown()` in `server.js`, `inflightSse`, `claudeCall.inflight()`).
  Raise `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` only if the exit time in the
  note is genuinely close to `DRAIN_TIMEOUT_MS`.
- **`Other` non-zero anywhere** is the server answering something outside
  its documented envelopes; the server log path is printed and kept.

## Real-key smoke (spends money)

The mock proves the rails; it cannot prove the upstream. For a last check
before a kickoff, stream a handful of *real* first turns concurrently:

```
node scripts/load-rehearsal.mjs --real --concurrency 10
```

This spawns the server **without** the mock, with the production-default
limits and the `ANTHROPIC_API_KEY` from your environment or `./.env` (it
refuses to start if neither has one), and streams one real
`[CURRICULUM: Unit 1, Lesson 1]` opener from 10 concurrent sessions. It
runs only this smoke — never the hostile or drain scenarios — and prints
the same table with time-to-first-delta and a sample of the reply. Ten
Sonnet openers with the cached lesson prefix cost cents. Keep
`--concurrency` at or below `IP_MAX_INFLIGHT` (40): every session comes
from one address.

To smoke an already-running server (staging, or production right after a
deploy) instead of spawning one:

```
node scripts/load-rehearsal.mjs --real --concurrency 10 --base https://your-host
```

Nothing is spawned and nothing is sent SIGTERM; the target's own limits
apply. Ten fresh sessions count against that address's
`IP_DAILY_NEW_SESSIONS` (60) for the day.

## Flags

| Flag | Meaning |
|---|---|
| `--delay <ms>` | `MOCK_STREAM_DELAY_MS` for the spawned mock server (default 40; keep ≥ 20) |
| `--real` | real upstream smoke instead of the five mock scenarios |
| `--concurrency <n>` | sessions in the real smoke (default 10) |
| `--base <url>` | real smoke against an existing server (no spawn) |
| `LOAD_REHEARSAL_LOG_LEVEL=debug` | env: pino level for the spawned server's log file (default `warn`) |
