# Claude Sonnet 5.5 for the tutor (step 1: ready behind a variable)

Branch `feat/sonnet-5-5-ready`, from `main` at `873db75`.

The tutor can now run on `claude-sonnet-5-5` by setting one environment variable. Nothing changes until someone sets it: with `TUTOR_MODEL` unset, every request the server sends is byte-identical to `main`'s. Production stays on `claude-sonnet-4-6` until the A/B below passes.

## Environment variables

| Var | What it does | Default |
|---|---|---|
| `TUTOR_MODEL` | The tutor model: chat and lesson turns (both tracks), the unit-test grader, fact-check, analyze and the cache prewarm. A set value is also always on the `/api/chat` model allowlist. Only `claude-sonnet-4-6` and `claude-sonnet-5-5` are verified; any other id logs a boot warning (see "Any other model" below). | unset = `claude-sonnet-4-6` |
| `TUTOR_EFFORT` | `output_config.effort` for every tutor-model call except a homework problem turn, on a model that takes no temperature. On `claude-sonnet-5-5` those calls send `between_tools`. `low`, `medium` or `high` only: `between_tools` rejects `xhigh` and `max`. Anything else logs a boot warning and uses `low`. Ignored on `claude-sonnet-4-6`. | `low` |

These are unchanged: `HELPER_MODEL` (quiz, report card, concept map and briefing stay on `claude-haiku-4-5`, which still takes `temperature`), `HOMEWORK_THINKING`, `HOMEWORK_LEAK_GUARD`, `MODEL_ALLOWLIST` and `DAILY_BUDGET_USD`.

## What changes per route on Claude Sonnet 5.5

On Sonnet 5.5, `temperature`, `top_p` and `top_k` are rejected (non-default values return a 400). `thinking: {type: "disabled"}` is a 400. If `thinking` is left out, the model runs adaptive thinking at effort `high`. The lowest setting is `thinking: {type: "between_tools"}`. It does no extended thinking, takes no other field, and is accepted only at effort `high` or below.

| Call | Sonnet 4.6 (today, unchanged) | Sonnet 5.5 |
|---|---|---|
| Free-chat turn (SSE and JSON), debate, discussion | `temperature` from the response mode (0.3 / 0.4 / 0.6 / 0.7) | `thinking: {type: "between_tools"}`, `output_config: {effort: TUTOR_EFFORT}` |
| Homework problem turn (`looksLikeProblemWork`), and its answer-guard and writing-quote retries | `thinking: {type: "adaptive"}`, `output_config: {effort: "low"}`, no temperature, `max_tokens` = budget + 2048 (at least 3000) | `thinking: {type: "adaptive", display: "summarized"}`, effort `low`, same headroom |
| Deep-dive and Basics lesson turns | `temperature`, `max_tokens` 2048 | `between_tools` at `TUTOR_EFFORT`, `max_tokens` 2048 |
| Unit-test grader | `temperature: 0.2`, `max_tokens` 400 | `between_tools` at `TUTOR_EFFORT`, `max_tokens` 400 |
| Fact-check, analyze | no sampling or thinking field, `max_tokens` 700 | `between_tools` at `TUTOR_EFFORT` (otherwise the model would think adaptively at `high`) |
| Cache prewarm (`POST /api/admin/prewarm`, `PREWARM_ON_BOOT`) | no sampling or thinking field, `max_tokens` 1 | `between_tools` at `TUTOR_EFFORT`, to match what tutor turns send, because thinking and effort are part of the cached prompt |
| Quiz, report card, concept map, briefing | Haiku 4.5, unchanged | Haiku 4.5, unchanged |

The fields are chosen per call from the model that call actually uses. A client that names `claude-sonnet-4-6` or `claude-haiku-4-5` on a Sonnet 5.5 server gets those models' fields. No route builds these fields by hand any more. They come from `lib/modelParams.js` (`requestFields(model, intent)` and `maxTokensFor(model, intent, base)`). Each route spreads them between `max_tokens` and `system`, the same key order the requests have always had.

Thinking headroom: only problem turns think, so only they get the +2048. `between_tools` turns have no thinking to make room for. There are no tools in these requests, so there are no progress-update blocks either.

Why `display: "summarized"` on problem turns: Sonnet 4.6 summarizes thinking by default; Sonnet 5.5 defaults to `"omitted"`. Under `"omitted"` a think streams nothing until it ends: no `thinking_delta`, and the SDK drops the API's `ping` events. The stream idle watchdog (`STREAM_IDLE_MS`, 30 s) resets only on an upstream event, so a long silent think would end the turn with the `timeout` error frame where 4.6 finished it. Summarized thinking deltas keep the watchdog fed, as on 4.6. They never reach a student (the relay forwards `text` events only). `display` changes visibility only: thinking is billed the same either way. The Sonnet 4.6 request is unchanged (no `display` field). `between_tools` takes no `display` and does not need one.

## Any other model

`lib/modelParams.js` has verified request rules for `claude-sonnet-4-6` and `claude-sonnet-5-5` only. Setting `TUTOR_MODEL` to anything else logs `TUTOR_MODEL is not claude-sonnet-4-6 or claude-sonnet-5-5: its request fields are unverified` at boot. A client can also reach another model if `MODEL_ALLOWLIST` names it. What such a model gets:

- A model before 4.7 (for example `claude-haiku-4-5`): `temperature`, as today.
- Any other 4.7+/5.x model (for example `claude-sonnet-5`, `claude-opus-5-5`): no sampling fields, and `between_tools` is a 400 there. On Sonnet 5, Opus 5 and 5.5, and Haiku 5.5, leaving `thinking` out runs adaptive thinking, which would think inside reply budgets of 120 to 700 tokens and run out, so the reply would come back empty and turn into the refusal copy. Every call therefore sends `thinking: {type: "adaptive", display: "summarized"}` at `TUTOR_EFFORT` (a problem turn at `low`), with the problem-turn headroom: budget + 2048, at least 3000. The prewarm keeps `max_tokens` 1.

None of this has been evaluated. Run the A/B below on any such model before using it.

## What stays the same

- **Prompts and cache shape.** The static and dynamic system blocks, the history breakpoint and the thread trimming are unchanged. Prompt caching works the same way on Sonnet 5.5, but caches are per model: the first turns after a switch write the prefixes again, and the old model's entries are not reused. The minimum cacheable prompt is 512 tokens, and every static prefix is far above that.
- **Response handling.** Every reader takes the reply from `text` blocks by type: `firstTextOf` in `server.js`, `messageText` in `lib/claudeCall.js`, and the SSE relay, which forwards SDK `text` events only. An adaptive Sonnet 5.5 reply starts with a `thinking` block: a summary on problem turns, and empty text under the default display (`"omitted"`) wherever a request leaves `display` out. That block, its `thinking_delta` and `signature_delta` events, and Sonnet 4.6's summarized thinking never reach a student. The grader, fact-check, analyze, the briefing and the quiz/report-card/concept-map helper used to read `content[0].text`. They now use `firstTextOf` too.
- **Refusals.** `stop_reason: "refusal"` is handled as before (AUD-01, `REFUSAL_COPY`). The refusal log line now also carries `stop_details.category` (`cyber`, `bio`, `frontier_llm`, `reasoning_extraction`, `general_harms`). In the stream it is taken from `message_delta`, because SDK 0.39 does not copy it into the final message.
- **Accounting.** Every call still goes through `lib/claudeCall.js`. `lib/pricing.js` now has the Sonnet 5.5 rate card: $2 input, $10 output, $2.50 5-minute cache write and $0.20 cache read per million tokens. Sonnet 5 has the same card. The dollar budget, the per-session and per-IP quotas, Prometheus and the `usage` ledger therefore price Sonnet 5.5 calls at Sonnet 5.5 rates. The token estimate used when a stream ends early (`estimateTokens`) counts 1.3× for these models.
- **Requests with `TUTOR_MODEL` unset.** These were replayed against an export of `main` with the same mock, in both flag states, as 27 requests that cover every route, response mode and track. The captured params, including key order, were byte-identical.

## Measured later (the A/B decides)

1. **Cost per turn.** Sonnet 5.5 is $2/$10 against $3/$15, but its tokenizer counts about 30% more tokens for the same text. Per turn that is roughly 0.67 × 1.3 ≈ 0.87 of Sonnet 4.6's cost before thinking. Problem turns also pay for their adaptive thinking, and the first turns after a switch pay the cache writes again. Measure it from the eval servers' usage (`EVAL_EXPOSE_USAGE=1`) priced by `lib/pricing.js`, per route and per flag state.
2. **Reply length under the same token budgets.** `max_tokens` is unchanged: 120, 250, 600, 1400 and 2048. With 30% more tokens per word, the concise 250 now holds about 140 words instead of about 180. Watch the eval's cut-off criteria and the safety-topic budget floor, so the closing 988/741741 line still lands. If replies get cut, scale the budgets for this model. That is a follow-up, not part of this change.
3. **Eval thresholds that are counted in tokens.** The cache-evidence checks (≥5,000 cached tokens on lesson turns 2+, ≥1,000 on chat turns 2+, ≤1,000 uncached input tokens per turn) were set on Sonnet 4.6 counts. A breach that is only the tokenizer is not a regression.
4. **Latency.** Measure time to first text at p50 and p95 per route. With `between_tools` there should be no thinking pause. Problem turns think adaptively at `low` with `display: "summarized"`, so the stream stays alive while the model thinks, but the student still sees nothing until the first text. Count `timeout` error frames per model as well: summaries can arrive in bursts, and the longest gap between upstream events on a problem turn has to stay well under `STREAM_IDLE_MS` (30 s).
5. **Refusals, especially `general_harms`.** Sonnet 5.5's classifiers decline in five categories, and benign requests can trip `general_harms`. Count the `model refusal answered with the safe refusal copy` log lines by `category` on both models, and rerun the safety, crisis-history and refusal follow-up probes (`scripts/refusal-followup-probe.mjs`). Server-side fallback exists (beta header `server-side-fallback-2026-07-01` with `fallbacks: "default"`). It is not added here: it retries only `cyber` and `frontier_llm` declines, on Sonnet 5, and a client-side retry could not re-send `between_tools` to another model.
6. **Effort.** The levels are recalibrated on Sonnet 5.5, and `low` is the starting point for chat. If `low` loses quality on lessons or grading, rerun with `TUTOR_EFFORT=medium` (one variable, no code).

## A/B plan

Run four local eval servers, all from this branch, each with explicit env and a fresh SQLite file. Never contact production.

| Server | `TUTOR_MODEL` | `USE_UNIFIED_PROMPT` |
|---|---|---|
| A | unset (`claude-sonnet-4-6`) | 1 |
| B | unset | 0 |
| C | `claude-sonnet-5-5` | 1 |
| D | `claude-sonnet-5-5` | 0 |

Start each one with `EVAL_EXPOSE_USAGE=1 IP_DAILY_NEW_SESSIONS=1000`, written out as explicit variables rather than as a `$VARS` string. Leave `ANTHROPIC_BASE_URL` unset. Then run on each server:

```bash
BASE_URL=http://localhost:<port> node scripts/eval-pacing.mjs --runs 3 --label sonnet55-<model>-flag-<on|off>
```

Branch-vs-branch keeps the scoring code identical on both sides. With the variable unset, A and B send exactly `main`'s requests.

Also run the 48-chat homework test, the probe set behind PR #44's "34 of 48 without thinking, 46 of 48 with it", against A and C. `docs/evals/homework-2026-10-23` is not on this branch (`main` at `873db75`), so run it from wherever it lands.

**Pass:** C and D pass every criterion that A and B pass, by majority over the 3 runs, apart from token-count artifacts (items 2 and 3 above). C is at least 46/48 on homework. No new refusal categories show up on ordinary turns. Cost per turn and p95 latency are written down for the decision.

## Switching production, and back

1. Railway → the server service → Variables: set `TUTOR_MODEL=claude-sonnet-5-5`. Set `TUTOR_EFFORT` only if the A/B chose something other than `low`.
2. Redeploy. Per `railway.toml`, after changing variables use Redeploy in the dashboard.
3. Check:
   - `GET /api/health` returns `"model": "claude-sonnet-5-5"`.
   - The boot log line `Mercurius Ⅰ is running` shows `model` and `tutorEffort`.
   - `/metrics` `anthropic_tokens_total{model="claude-sonnet-5-5"}` grows.
   - The `usage` ledger `model` column shows the new model.
4. Optionally `POST /api/admin/prewarm` before a class session: the old model's cache entries do not carry over.

**Rollback:** delete `TUTOR_MODEL` (or set it to `claude-sonnet-4-6`), then Redeploy. There is no migration and no client change. iOS never sends `model`, and the widgets don't either.

## Not in this change

- Server-side or client-side refusal fallback (see item 5).
- Per-message effort, `display: "updates"`, task budgets. (`display: "summarized"` is sent on Sonnet 5.5 problem turns only; see above.)
- `HELPER_MODEL`, which stays on Haiku 4.5 with its requests unchanged.
- **Heads-up for a later SDK or API-version bump.** On `anthropic-version: 2026-10-21`, a request that sends `temperature`, `top_p` or `top_k` returns a 400 on every model. The pinned SDK (0.39) sends `2023-06-01`, so nothing breaks today. A future bump would have to drop the Sonnet 4.6 temperature path, or `lib/modelParams.js` would have to stop sending it.
- **Prompt audit.** The prompts were checked for "don't think" or "write out your reasoning" instructions, which make `between_tools` replies more likely to leak tags and invite `reasoning_extraction` declines. None were found.

## Tests

- `tests/modelParams.test.js`: the field table above, per model and intent, including the unverified 4.7+/5.x models.
- `tests/tutorModel.test.js`: boots the server with `TUTOR_MODEL=claude-sonnet-5-5` (both flag states, plus `TUTOR_EFFORT=medium`) and unset (both flag states). It drives free chat (SSE and JSON), problem turns with their guard retry, Deep-dive and Basics lessons, the grader, fact-check, analyze, the quiz and the prewarm. It asserts the captured params and key order, health, and the ledger's Sonnet 5.5 pricing. A sixth server runs with `MOCK_LEADING_THINKING=1`, where every reply starts with an empty thinking block, to prove every route reads its reply by type. A seventh runs Sonnet 5.5 with `STREAM_IDLE_MS=750` and `MOCK_THINKING_MS=2000`: a problem turn that thinks for longer than the idle window completes (with `display` omitted it ended in a `timeout` frame). An eighth runs `TUTOR_MODEL=claude-sonnet-5` and checks the boot warning and the explicit thinking and headroom on every route.
- `lib/anthropicMock.js` now rejects with a 400, like the API, every Sonnet 5.5 request with a sampling field, disabled/enabled/budget thinking, `between_tools` with another field or at `xhigh`/`max`, `between_tools` on any other model, and forced `tool_choice`. It returns thinking blocks first when a call thinks, and a request with no `thinking` field thinks on every 5.x model, as the API does. `MOCK_THINKING_MS` makes a streamed think take that long: silent under `"omitted"`, small `thinking_delta` pieces under `"summarized"`. `MOCK_CAPTURE_FILE` also records `top_p`, `top_k` and `paramKeys` (the request's key order).
- `tests/support/spawnServer.js` and the two suites that spawn the server themselves pin `TUTOR_MODEL` and `TUTOR_EFFORT` to empty, so a developer's own setting never changes what they assert.
