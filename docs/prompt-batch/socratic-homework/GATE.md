# A/B gate: Socratic homework (2026-10-21) — NOT RUN, blocked on API credit

**Verdict: no verdict.** The gate could not run. The Anthropic account behind the repo `.env` still returns `400 "Your credit balance is too low to access the Anthropic API"`. It first returned this at 19:06 UTC, partway through the build step's confirmation run. It was checked with 1-token calls at 19:37, 19:38, 19:39, 20:02 and 20:26 UTC, and again at 21:04 UTC, before this note was written. Nothing in the table below was measured today, and no row can be called a pass or a regression.

A gate with every row "pending" is not a pass. **Don't merge the homework commits on this note.**

## What the gate compares

| | Code | Flag on | Flag off |
|---|---|---|---|
| base | `3f46b2d`, the #44 head before this task (worktree `.claude/worktrees/socratic-base`) | 3431 | 3432 |
| branch | `e58a7f8` = `3843ff5` rules + `8a1bcec` eval + docs | 3433 | 3434 |

Both sides use the branch's `scripts/eval-pacing.mjs`, which has 59 scenarios, with `--runs 3`. The labels are `socratic-hw-{base,branch}-flag-{on,off}`.

## What was done in this step

- **Base worktree.** It was made at `3f46b2d`, with `node_modules` symlinked from this worktree (the lockfiles are identical). It was removed again at the end with `git worktree remove --force`.
- **`npm test` on the branch:** 1090/1090.
- **API credit was checked** with 1-token `messages` calls; the key was never printed. No server was started for the gate, because each start would only produce error frames. Ports 3431–3434 were free at the start and are still free.
- **A static-prefix comparison was made offline, with no API calls.** It is below, and it decides which rows can move at all.

An earlier attempt at this step, 17:56–18:10 UTC, ran 12 single runs at once on 3431–3434. It never finished and wrote no result files. It ran on `ad5f2cb`'s text, where the flag-on prefix read was 14,101 tokens, not the committed r15 text at 14,152. It is superseded either way. Its logs are in the session scratchpad only.

## Which rows can change: the static prefixes, base vs branch

Only two runtime files differ between `3f46b2d` and the branch: `lib/responseQuality.js` and `prompts/mercurius-v2.md`. `server.js`, `lib/safetyCore.js`, `lib/systemBlocks.js` and `lib/appFacts.js` are byte-identical. Each piece `server.js` takes from the two changed files was hashed in both trees (sha256, first 12 characters):

| Piece | Used by | base | branch |
|---|---|---|---|
| `qualityPrefix('socratic')` | flag off, free chat (socratic) | `cbfd3c1aa8a1` (6,612 chars) | `df17f301ac7e` (11,575) |
| `qualityPrefix('debate')` | flag off, debate | `c09dc4ae9dce` (7,692) | `b9940e05b958` (12,554) |
| `qualityPrefix('discussion')` | flag off, discussion | `69c187a8bed5` (6,856) | `372b74f09b05` (11,718) |
| `UNIFIED_PROMPT` | flag on, all free chat | `486689384bb8` (37,647) | `a4d78bb3e744` (42,874) |
| `EXPAND_MODE_NOTE`, `RESPONSE_MODE_BUDGETS`, `needsSafetyBudget`, `resolveResponseMode`, `MODE_TOKENS`, `buildRuntimeContext(...)` | budgets and the dynamic block | identical | identical |

So:

- **Every free-chat static block changes**, in every mode, for the app and the widget, in both flag states. These scenarios can move: socratic, debate, discussion, deep, `widget-1`, every free-chat `safety-*`, `chat-*` and `hw-*`.
- **These are byte-identical in both flag states:**
  - the lesson prefixes (`curriculumStatic`, prose and blocks);
  - the unit-test grader prompt.

  So any base-vs-branch difference in these rows is sampling noise, not the change: `curriculum-*`, `lesson-*`, `safety-curriculum-crisis`, `safety-eating-disorder-lesson`, `safety-lesson-chatbot-news`, `safety-grade-*`, `helper-grade-normal`, and the curriculum cache row.
- **The safety core is still the last static block** on both paths, and its text is unchanged.

## Table

Each cell shows the majority verdict and how many of the 3 runs passed. Rows are grouped. Every cell is pending.

| Row group | Prompt changed? | Must hold | on: base | on: branch | off: base | off: branch |
|---|---|---|---|---|---|---|
| `hw-*` (8 scenarios) + the hw thread-wide rows (no other tool, AI tie-in at most once, plain words) | yes | branch PASS in both flags | pending | pending | pending | pending |
| Free-chat safety: crisis, sexual, harassment, medical, refusal ×2, injection, eating-disorder, ed-compensatory, ed-700, age-12, 6th/12th grade, pii, nudes-pressure, roast-retry, debate-deepfake, debate-meetup, chat-news, chat-news-method, sextortion | yes | PASS in both flags | pending | pending | pending | pending |
| Lesson and grader safety: curriculum-crisis, eating-disorder-lesson, lesson-chatbot-news, grade-crisis, grade-crisis-indirect, grade-risk-topic | no (noise only) | PASS in both flags | pending | pending | pending | pending |
| `chat-*` (photo right/wrong, save-chats, model-id, debate-your-move, scope, one-word, anthropic-train) | yes | no regression | pending | pending | pending | pending |
| Pacing: median/p90 sentences, socratic one question, previews, truncations, airy, deep ≥ 8, debate ≤ 7 lines, discussion scoring | yes | no regression (except the known flakes) | pending | pending | pending | pending |
| Lessons: beat 1, `[LESSON_COMPLETE]` ×2, blocks ×4, `lesson-*`, beat-1 length, micro-concept | no (noise only) | no regression (except the known flakes) | pending | pending | pending | pending |
| Cache: chat ≥ 1,000, curriculum ≥ 5,000, read-back, ≤ 1,000 uncached | chat yes, curriculum no | no regression | pending | pending | pending | pending |
| helper: grade-normal | no | no regression | pending | pending | pending | pending |

**Known flakes, not counted as regressions.** These are listed in the task, and two of them already fail on `3f46b2d` pending founder decisions (PR.md, notes A and C):

- legacy debate ≤ 7 lines;
- unified socratic one question;
- blocks and prose `[LESSON_COMPLETE]` within 10 turns;
- beat-1 length.

## The only branch evidence on the committed text so far

From the build step, `BUILD.md`. These are not gate runs: run 1 only, and only `socratic`, `chat-` and `hw` scenarios.

- **hw rows:**
  - every row passed in both flags except `hw-chem` with the flag on, 0/1 (two questions in reply 2);
  - the ladder row went 5/5 in each flag on its own run.
- **socratic and chat- rows:** all passed in both flags in run 1.
- **Not run on this text in either flag:** the free-chat safety rows, debate, discussion, deep, widget, the chat cache rows and the lesson rows.

The free-chat safety rows share the changed static block, so **the safety requirement is unverified, not just pending a repeat.**

## To run it once credit is back

1. **Check credit first.** A 1-token `messages` call must return 200. Then make sure the account has at least $20 on it. Today's spend on this account also includes another workflow's `basics-gate` servers (3461/3463, 19:03 UTC).
2. **Recreate the base worktree:**

   ```bash
   git -C /Users/shyamchristensen/Desktop/mercurius-chatbot worktree add /Users/shyamchristensen/Desktop/mercurius-chatbot/.claude/worktrees/socratic-base 3f46b2d
   ln -s /Users/shyamchristensen/Desktop/mercurius-chatbot/.claude/worktrees/fix-prompts-2026-10/node_modules /Users/shyamchristensen/Desktop/mercurius-chatbot/.claude/worktrees/socratic-base/node_modules
   ```

3. **For each port P,** with tree T and flag F as in the table at the top:
   - free the port: `lsof -ti :P | xargs kill -9`;
   - from T, run: `EVAL_EXPOSE_USAGE=1 IP_DAILY_NEW_SESSIONS=1000 IP_DAILY_USD=100 SESSION_PER_MIN=100 STREAM_IDLE_MS=90000 USE_UNIFIED_PROMPT=F PORT=P SQLITE_PATH=<scratchpad>/gate-P.db DATABASE_URL= NODE_ENV=development LOG_LEVEL=warn node --env-file=/Users/shyamchristensen/Desktop/mercurius-chatbot/.env server.js`
4. **Run the four evals at once,** from this worktree: `BASE_URL=http://localhost:P node scripts/eval-pacing.mjs --runs 3 --label socratic-hw-<base|branch>-flag-<on|off>`.
   - Expect about 60–70 minutes and roughly $12–15 in total. The Oct 18 gate was $8.91 for 39 scenarios; this one has 59, and the branch prefix is about 1,400 tokens larger.
   - **Keep the Mac on power with the lid open.** Today the 60-second credit poll logged at 23-minute gaps on battery, so a gate run in that state would stall.
5. **Re-run suspected flakes alone** with `--only <prefix> --runs 3` on all four servers.
6. **Finish up:**
   - `kill -9` all four servers and confirm the ports are free;
   - remove the base worktree with `git worktree remove --force`.

The eval writes its JSON only at the end of all three runs. If credit runs out again mid-gate, the servers' own SQLite `messages` and `usage` tables are the only record (see `BUILD.md`, "Results at the committed text").
