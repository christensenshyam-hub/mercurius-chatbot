# Step 03: daily limits, turn counting and lesson starts (AUD-30, AUD-31, AUD-29 follow-up)

Branch `fix/server-2026-10`, on top of steps 01 and 02. Nothing is pushed. No prompt text changed: `CURRICULUM_PROMPT`, the source library, `SAFETY_CORE` and the static system block are untouched. The `server.js` edits are in `sendRefusal`/`gate`, the quota hydrate, the lesson-event helpers, the two places the chat route records lesson events, the image and report refusals, and the boot-time spend hydrate. None of them is in PR #44's prompt constants.

## Commits

| Commit | What |
|---|---|
| `8e1d8a0` | **AUD-31.** Only a turn that got an answer uses a daily turn. Every call is still billed. |
| `37a0462` | **AUD-30, server half.** Quotas and `DAILY_BUDGET_USD` roll at midnight in `STREAK_TZ`. Refusals carry `retryable`; the SSE frame gains `scope`; `spend_cap` gains `retryAfterSec`. The network's copy says to switch to cellular data. |
| `6e7812c` | **Lesson analytics (PR #43 review).** A lesson's `start` is decided from `lesson_events`, not the wire thread. |
| (last) | These notes and `docs/evals/answered-turns-real-api.json`. |

`npm test`: 1076 → **1120**, all passing. `node scripts/pg-smoke.mjs` on SQLite: 39/39.

## AUD-30: when "tomorrow" is, and whether to retry

### The choice: roll on the product day, not UTC plus a reset time

I moved the quotas and the spend cap to the `STREAK_TZ` day instead of keeping UTC and sending a reset time.

- **It makes the existing copy true for every client.** 2.0.0, 2.3.0 and the widget print the server's copy verbatim, and it says "tomorrow". On the product day it is. With UTC, the copy would need a clock time. The server can only format one in one fixed zone, not the device's.
- **It fixes the morning lockout.** With UTC, a student who hit a limit after 7 PM Central stayed locked out until 7 PM the next day, through the morning meeting. A reset time in the copy only explains that; the local day removes it.
- **It stays compatible with PR #43.** PR #43 drops every sentence of a daily limit that says "tomorrow" and adds its own local clock time from `retryAfterSec`. A server-added clock sentence would have been shown next to PR #43's.
- **It is small.** One helper (`lib/productDay.js`) replaces the UTC-day code in `lib/quotas.js` and `lib/spendCap.js`. It also feeds the two hydrate queries, two alert keys and `db.streakDay`. It is the same zone and default the streaks already use.

### The fields, matched to PR #43

I read PR #43's `ServerRefusal`, `APIClient.validate`/`ErrorBody`, `SSEPayload`/`parseChatEvent` and `docs/ios-batch/04-network.md`. PR #43 decodes **`retryAfterSec`** (seconds, as a number or a numeric string) and **`scope`** (`"session"`, `"ip"` or `"global"`), from the JSON body and from the SSE `error` frame. It has no absolute reset field, so I added none. `retryAfterSec` is still the reset field; it now counts down to midnight in `STREAK_TZ`.

| Refusal | Status (JSON) | `scope` | `retryAfterSec` | `retryable` |
|---|---|---|---|---|
| `daily_limit`, the student's own | 429 | `session` | to midnight in `STREAK_TZ` | `false` |
| `daily_limit`, the network's (`new_sessions`, `ip_usd`, `ip_images`) | 429 | `ip` | to midnight in `STREAK_TZ` | `true` (cellular is another network) |
| `spend_cap` | 503 | `global` (new) | to midnight in `STREAK_TZ` (new), plus `Retry-After` | `false` |
| `service_disabled` | 503 | none | none | `false` |
| `busy` | 503 | `ip` or `global` | 60 | `true` |
| `restarting` | 503 | none | 5 | `true` |
| `rate_limited` (per minute) | 429 | none | none | `true` |

- **On the SSE frame:** `scope` is new there (PR #43's notes asked for it). `retryable` is new everywhere. Both are additive. 2.0.0's and 2.3.0's decoders ignore unknown keys. I checked `SSEPayload` and `ErrorBody` at `2e212dc` and `ios/v2.3.0-16`.
- **What `retryable` means:** whether a Retry button can help the student. It follows PR #43's `ServerRefusal.isRetryable`. No client reads it yet. The widget's `FINAL_CODES` agrees except that it offers no Retry for any daily limit, the network's included.
- **"Make `spend_cap` non-retryable on the wire":** on the wire, `spend_cap` now has `retryable: false`, a `retryAfterSec`, and a `Retry-After` header. 2.3.0 decides Retry from the code (`code != daily_limit`), so it still shows Retry next to "please try again tomorrow". No additive field can change that. PR #43 already hides it.

### The copy

The student's own limits are unchanged. The three network-scoped messages now read:

- `ip_usd`: "This network has reached today's usage limit. Switch to cellular data, or try again tomorrow."
- `ip_images`: "This network has reached today's image upload limit. Switch to cellular data, or try again tomorrow."
- `new_sessions`: "Too many new sign-ups from this network today. Switch to cellular data, or try again tomorrow." (It was "Too many new sessions from this network today." with no next step.)

**Wording.** The audit suggested "this Wi-Fi". I kept "network": a carrier's shared cellular address can trip the cap too, and PR #43 detects either word. The cellular advice is in the same sentence as "tomorrow" on purpose, because PR #43 drops that sentence and adds its own "Switch to cellular data and try again, or come back after 8:00 PM." So the advice never shows twice.

**What a student sees:**

| Client | Network's new-session cap (at 5:49 AM in Chicago, server in Chicago) |
|---|---|
| 2.0.0 / 2.3.0 | The server's copy verbatim. 2.3.0 shows no Retry (as before). |
| PR #43, phone in Chicago | "Too many new sign-ups from this network today. Switch to cellular data and try again, or come back tomorrow." With Retry. |
| PR #43, phone in New York | "…or come back tomorrow after 1:00 AM." |
| PR #43, the student's own chat limit | "You've used today's chat turns. Try again tomorrow." No Retry. |

The PR #43 rows come from the real frames: I captured them from this branch's server (mock upstream) and decoded them with PR #43's own `parseChatEvent`, `ErrorBody` and `ServerRefusal` (see Tests).

### Where the day boundary moved

| What | Before | Now |
|---|---|---|
| Per-session and per-IP daily quotas | UTC midnight | midnight in `STREAK_TZ` |
| `DAILY_BUDGET_USD` | UTC midnight | midnight in `STREAK_TZ` |
| Per-session hydrate after a restart (`sessionUsageSince`) | from UTC midnight | from the start of the `STREAK_TZ` day |
| Boot spend hydrate (`sumCostSince`) | from UTC midnight | from the start of the `STREAK_TZ` day |
| `ip_cap` / `report_cap` alert keys, the `budget_100` key | UTC date | product date |
| Budget page text | "refused until UTC midnight" | "refused until midnight America/Chicago" (the zone in use) |
| Streak day | `STREAK_TZ` | `STREAK_TZ` (same helper now; an unknown zone falls back to New York with a warning instead of throwing) |
| Discord digest, `/api/admin/stats` day buckets, `DIGEST_UTC_HOUR` | UTC | **UTC, unchanged.** A digest's "yesterday's cost" is a UTC day, so it no longer matches one budget day exactly. |

**Edge cases.** `lib/productDay.js` finds day edges by bisecting on the zone's date, so it doesn't assume a day is 24 h. A 23 h or 25 h DST day and a zone that skips midnight (America/Santiago) are handled and tested. `spendCap.state()` gains `timeZone`, and its `day` is the product date.

## AUD-31: only answered turns use the turn allowance

`lib/claudeCall.settle()` decides `answered` once per call. That value drives `quotas.record({ counted })` and the ledger's new `usage.answered` column.

| Call outcome | Uses a turn | Billed (budget, session and IP dollar caps) |
|---|---|---|
| Finished, with text, not a refusal | yes | yes |
| `stop_reason: "refusal"`, with or without partial text first | no | yes |
| Finished with no text | no | yes |
| Upstream error, at any point | no | yes (what was received) |
| The route's own watchdog (idle or hard cap), even after text | no | yes |
| Client Stop or disconnect before any text | no | yes (usually $0) |
| Client Stop after some text | yes | yes |

- **Why an error after partial text doesn't count:** the student sees an error with Retry, and a student can't cause an upstream error, so it isn't an abuse path. The audit's suggested formula (`status === 'ok' || output_tokens > 0`) would have counted it; I followed the brief ("errored … does not burn").
- **The bound on uncounted calls:** a client could Stop before the first token, or ask refused questions, without using turns. They still cost dollars, so `SESSION_DAILY_USD` ($0.75), `IP_DAILY_USD` and the per-minute `SESSION_PER_MIN` bound them.
- **Schema:** `usage.answered` is INTEGER: 1, 0, or NULL. NULL means a row from before the column, and it still counts. It is added at boot with `ALTER … IF NOT EXISTS` (Postgres) or a `PRAGMA` check (SQLite), like the step 02 columns. `sessionUsageSince` now returns, per kind, `count` = turns used and `usd` = every call's cost. So a restart's hydrate agrees with memory, and the audit's "still refused after a restart" is gone.
- Image uploads are unchanged: each upload is counted.

## Lesson analytics: `start` from `lesson_events`

**The problem.** Since AUD-29, PR #43 keeps a cut-off reply in the thread, so answering a cut-off opener sends `[opener, cut-off reply, answer]`. The old thread rule (`turnIndex === 1` or no assistant turn) logged that as a `turn`, and the cut-off opener wrote no row. So that attempt never got a `start`. On a retake, its `complete` was then dropped as a repeat of the last attempt's.

**The rule now** (`lessonTurnEvent` in `server.js`, `db.lastLessonMilestone`):

- No `start` or `complete` for this session and lesson → **`start`**.
- The latest of the two (by ts, then id) is a `start`, so an attempt is open → **`turn`**.
- The latest is a `complete` → **`start`** if this thread has fewer user turns than the one that passed, otherwise **`turn`**.

**Why the exception for a passed lesson.** The brief's rule alone ("no start newer than the latest complete") would make the next turn in a passed thread a new `start`. iOS keeps a passed lesson's thread open (the existing `adminTrust` test covers it), and the mock, like a real tutor, keeps judging it passed. That would add a second `start` and a second `complete` per kept-open thread. A retake is a fresh, shorter thread: its opener, or the answer to a cut-off opener. The comparison uses the `complete` row's `turn_index`.

**Fallbacks.** A loose `[CURRICULUM:` thread has no lesson id to look up, and a failed read must not lose the row. Both use the old thread rule.

**Write order.** The decision is made once the reply is in hand. Then the `start`/`turn` row and any `complete` are written in that order, because the `complete` dedupe reads the latest `start`.

**What changes in the numbers:**

- The review's case (a cut-off opener, then an answer under it) is now a `start`.
- A retake's pass is counted.
- An opener the server had already answered and that is sent again (a Retry after a lost tail) is one `start`, not two.
- **A behaviour change to know about:** restarting an *unfinished* lesson from its opener, in the same session, now continues the open attempt (a `turn` with `turn_index` 1) instead of adding a second `start`. iOS resumes lessons rather than restarting them, so this should be rare.

## Tests

44 new; `npm test` 1120/1120.

- **AUD-31** (`8e1d8a0`, +16):
  - `claudeCall`: create and stream, ok, a refusal (empty and partial), an upstream error, a Stop before and after text, the watchdog, and that the dollars count either way.
  - `quotas.record({ counted: false })` for each kind; unanswered calls still reach `SESSION_DAILY_USD`.
  - `sessionUsageSince` counting, and the SQLite boot migration of an old `usage` table.
  - `tests/answeredTurnsRoute.test.js`:
    - the audit's repro: `MOCK_SCENARIO=overloaded` with 2 lesson turns, 5 failures over SSE and JSON, then a restart on the same database with both turns still available and the 3rd refused;
    - a refused turn (`MOCK_REFUSAL` and `MOCK_REFUSAL_PARTIAL`) gets the 988 copy and uses no turn;
    - a Stop before the first token uses no turn.
- **AUD-30** (`37a0462`, +23):
  - `tests/productDay.test.js`: the audit capture (28143 s in Chicago instead of 10143), the default and blank zones, an unknown zone, UTC, DST 23/25 h days, Santiago's skipped midnight, edge consistency, a changed `STREAK_TZ`.
  - `quotas` and `spendCap` roll at midnight in Chicago, not at UTC midnight. The budget page fires once per product day and names the zone.
  - `tests/quotaCopyContract.test.js`: a JS mirror of PR #43's `ServerRefusalQuotaContractTests`, using its regexes. Every `ip` message names the network and mentions cellular, no `session` one does, and the cellular advice sits in the "tomorrow" sentence.
  - `tests/refusalWire.test.js`, on the mock:
    - both shapes for a student's limit, the network's new-session and dollar caps, and the kill switch (exact SSE frame keys, `Retry-After`);
    - the per-session hydrate counts from the Chicago day start: a row 1 s before it is ignored, one 1 s after counts. Whatever the hour, a UTC boundary would give 0 or 2;
    - the boot spend hydrate the same way.
  - `spendCap`: the `spend_cap` JSON and SSE frame carry `retryable: false`, `scope`, and `retryAfterSec`.
- **Lesson starts** (`6e7812c`, +5): `tests/lessonStartEvents.test.js`:
  - the review's case;
  - a retake after a pass whose own opener was cut off (its `start`, and its `complete` kept);
  - the kept-open passed thread;
  - an answered opener sent twice;
  - two lessons in one session;
  - `db.lastLessonMilestone`.
  The existing `adminTrust` lesson tests pass unchanged. `pg-smoke` C8 covers the new query (SQLite here; CI runs Postgres 16).
- **Each new route test fails on the old code.** I stashed the fix and reran: AUD-31 3/3, AUD-30 6/6 and the lesson file 3/5 fail. The other two are the per-lesson case and the db helper, which don't depend on the fix.
- **PR #43 compatibility, checked in a scratch copy** (deleted afterwards; nothing written to PR #43's worktree):
  - I copied PR #43's `NetworkingKit` sources and its `ServerRefusalTests.swift`/`TestClock.swift` next to this branch's `lib/quotas.js`.
  - `swift test --filter ServerRefusal` passed 17 tests in 4 suites. That includes the `contract with lib/quotas.js` suite, which reads the new copy.
  - The frames captured from this branch's server decoded through `parseChatEvent`/`ErrorBody` to the strings in the AUD-30 table above.

## Measurement (real API)

Port 3373, `USE_UNIFIED_PROMPT=1`, the required env, a throwaway SQLite file. Results are in `docs/evals/answered-turns-real-api.json`.

| Call | `stop_reason` / end | Ledger `answered` | Cost |
|---|---|---|---|
| Lesson opener, read to the end | `end_turn` | 1 | $0.0358 |
| The safety gate's weapon prompt | answered in text ("That's not something I can help with…") | 1 | $0.0347 |
| Stop after `: connected`, before any delta | client abort, 0 tokens | 0 | $0 |
| Stop after the first delta | client abort, 10 output tokens | 1 | $0.0030 |
| The safety gate's overdose prompt, SSE | `refusal`, 0 output tokens; the student got the 988 copy | 0 | $0.0029 |
| The same, JSON | `refusal`, 0 output tokens | 0 | $0.0029 |

- **Hydrate counts:** `sessionUsageSince` from the product-day start gives 2 chat + 1 lesson turns for the first session (four calls), and 0 turns but $0.0058 for the refusal session.
- **SDK check:** I also confirmed in the SDK source (0.39 `MessageStream`) that the `message` event, carrying `stop_reason`, fires before `end`.
- **Cleanup:** total spend $0.08. The server was killed and port 3373 is free. A mock server I used to capture frames (port 3374, no key) was killed too, and its database deleted.
- **eval-pacing:** not re-run, because no prompt changed.

## Open risks and founder decisions

1. **An evening deploy re-counts the afternoon.** The day key changes from the UTC date to the local date at deploy, and the hydrates read from local midnight.
   - Deployed after 7 PM Central, a student who got a fresh allowance at 7 PM is back to the afternoon's count until midnight.
   - The global budget hydrates the whole local day's spend, which can be over `DAILY_BUDGET_USD` after a heavy day.
   - Deploy before 7 PM Central, or in the morning, and it is seamless.
2. **Check `STREAK_TZ` on Railway.** It now sets when limits and the budget reset, not only streaks. The pilot playbook says `America/Chicago`; unset means New York, so the reset is at 11 PM Central. I updated `PILOT_PLAYBOOK.md`, `DEPLOY.md` and `.env.example` to say so.
3. **A phone in another zone than `STREAK_TZ`** sees the real reset under PR #43 ("tomorrow after 1:00 AM" in New York for a Chicago server). On 2.3.0 it reads "tomorrow".
4. **2.3.0 still offers Retry on `spend_cap`.** It decides from the code; PR #43 fixes it.
5. **Calls that use no turn still cost dollars.** Repeated refusals or Stops before the first token use no turns, bounded by the dollar caps. A Stop that early is recorded at $0 (no usage had arrived), as before this step, though Anthropic may bill the prompt.
6. **The digest is still UTC.** A digest's "yesterday's cost" and the budget day no longer line up. Moving the digest changes how the founder's numbers are defined, so I left it as a separate decision.
7. **Lesson-event race:** two answered turns of the same lesson finishing at the same moment can both see no open attempt and write two `start` rows. A double-send could do it; it is rare.
8. **PR #43 merge notes:**
   - Its DEBUG `NetworkScenarioPreview` still serves the old frames (no `scope`, old copy, the UTC wait). That is DEBUG only.
   - Its comments saying the SSE frame has no `scope` go stale.
   - Its contract test passes against this copy.
9. **PR #44 / PR #39 rebases:** `server.js` conflicts should be mechanical. Nothing in the prompt constants changed.
10. **A stray local boot (mine).** While checking syntax I once ran `node -e "require('./server.js')"` in the worktree.
    - It booted a server on port 3000 with no API key and no traffic, for about a minute, before I killed it (PID 92598). Port 3000 is free.
    - Its boot ran `initSchema` on the worktree's own gitignored `mercurius.db`, which now has the `usage.answered` column. Nothing else touched it.

## Skipped

- **The AUD-17 soft-break follow-up** in PR #43's server list: not in this step's brief.
- **Moving the digest or admin stats to the product day:** it changes the founder's metrics (see risk 6).
- **`currentDate` in the runtime context** (`server.js:1941`) is still the UTC date, so in a US evening the model is told tomorrow's date. That is prompt-adjacent (the dynamic block), so I left it for its own change.
- **Postgres:** not run; there is no local Postgres. CI's Postgres 16 `pg-smoke` covers `usage.answered`, `sessionUsageSince` and `lastLessonMilestone`.
- **Simulator:** not needed, since no iOS code changed. PR #43's decoding was checked in Swift against real frames instead.
