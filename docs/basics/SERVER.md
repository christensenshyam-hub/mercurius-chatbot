# Basics track: server

Branch `feat/basics-server`, on top of `3f46b2d` (the head of draft PR #44, `fix/prompts-lessons-2026-10`, before the homework commits). Not pushed.

The founder asked for "a separate 'easy' curriculum that can just teach people the basics of how to use AI … (think of a grandma wanting to learn how to use ChatGPT)." This branch is the server half: a second lesson track called **Basics**, next to the existing 8-unit course (called **Deep dive** where the two sit side by side). The content is the final curriculum (`BASICS_CURRICULUM.md` v1 and `basics.json`, 2026-10-21: 5 units, 18 lessons) and its tutor-voice guide (`BEGINNER_GUIDE.md`).

## Defaults chosen (the founder can change any of these)

- **A separate track called "Basics".** Where the two tracks sit side by side, the existing course is called "Deep dive". The app stays 13+. Basics is written for any adult beginner and works for teens too.
- **Tutor-led, with practice right there.** Merc teaches in the chat like today's lessons. The learner tries messages on Merc, because Merc is itself a chatbot, and in practice Merc does the task for real (writes the note, makes the list).
- **Tool-neutral.** Basics teaches skills that work in ChatGPT, Claude, Gemini or Copilot, and may name them and their makers as facts. This is a deliberate exception, for Basics only, to the free-chat rule against recommending other chatbots: that rule lives in the free-chat prompts, which Basics doesn't load. Basics never ranks the assistants or says "use X instead", and gives no prices, plans or menu paths. It says "look for the settings or privacy option" instead.
- **Plain language.** Short sentences, no jargon (or jargon explained the first time), warm and patient, never condescending; about a 6th-grade reading level.
- **Safety first for beginners:**
  - what never to share (passwords, bank numbers, ID numbers, medical records);
  - AI voice-clone and "grandparent" scams (hang up, then call back on a number you know);
  - don't rely on AI alone for health, money or legal decisions;
  - check important answers.
- **Completion.** `[LESSON_COMPLETE]` in Basics means the learner did the practice and answered the check. A wrong pick still completes in most lessons, after a kind correction. In the four safety lessons (`b2_l3`, `b2_l4`, `b5_l2`, `b5_l3`) the pick must be right. That is kinder than the Deep dive's rules, but still earned.

## The client contract

This is what the iOS app, the Mac app and any web client must send.

### The opener tag

A Basics lesson starts with a hidden user message that begins, at index 0, with:

```
[BASICS: Unit N, Lesson M]
```

- **Grammar.** The server's strict pattern is `^\[BASICS:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]`. It is case-sensitive (`BASICS`, `Unit`, `Lesson`), the tag must be at index 0, and anything after the lesson number up to `]` is ignored. Send the canonical spelling above: one space after the colon, then `Unit N, Lesson M`.
- **Opener text.** Use the `basics.json` starter, with its tag rewritten to the canonical form, then the same completion contract the Deep dive appends (`ChatViewModel.withCompletionContract`):
  `[BASICS: Unit 1, Lesson 1] Teach me what an AI chatbot is, in plain words. Keep it short, then let me try one. When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.`
- **Follow-up turns.** Send `[opener, …visible thread]`, as the Deep dive does. The iOS re-tag of the last user turn (`ChatViewModel`'s legacy-server bridge) works unchanged: it copies whatever tag the opener has. The server strips that re-tag from replayed turns (`normalizeReplayedHistory`), so the thread stays byte-stable for the cache.
- **The alias.** `[CURRICULUM: Basics Unit N, Lesson M]`, the form `basics.json` uses today, is also accepted and also routes to Basics on this server. Prefer the canonical form, and rewrite the `basics.json` starters to it. A server that predates Basics (production today) routes `[BASICS: …]` to free chat, but routes the alias into the **Deep-dive** guide. So ship the server first, and never ship the alias.
- **Routing rule.** The most recent user message that carries a lesson tag decides the track. A Basics tag never reaches the Deep-dive guide, and a Deep-dive tag never reaches the Basics guide, whichever came first in the thread (`lib/curriculumTag.lessonTrack`). For a thread with no Basics tag, the result is exactly the old `isCurriculumThread` rule, so shipped apps and both widgets are unaffected.

### Ids

| | Deep dive (unchanged) | Basics |
|---|---|---|
| lesson | `u{unit}_l{lesson}` (`u1_l1` … `u8_l5`) | `b{unit}_l{lesson}` (`b1_l1` … `b5_l4`) |
| unit | `unit_{n}` | `basics_{n}` (`basics_1` … `basics_5`) |

- **Server-side completion.** On `[LESSON_COMPLETE]` the server records the lesson itself (`curriculum_progress`, status `completed`) and writes `lesson_events` rows with the `b` id and the unit and lesson numbers.
- **`PUT /api/progress/:sessionId`** accepts `{ id: 'b2_l3', type: 'lesson', status: 'completed' }` and `basics_N` unit ids, as an addition. The id's shape must match its type. Basics has no unit tests; a `basics_N` unit is accepted only so that a client that syncs one never fails its whole push.
- **`GET /api/progress/:sessionId`** returns both tracks in one `lessons` list. Filter by prefix. The shipped Deep-dive store keeps ids it doesn't know as uncounted orphans, so a `b` id never changes its counts.
- **`curriculumVersion`.** Push Basics items with the app's `MercuriusCurriculum.version` (1 today), never a separate Basics counter. The version is stored per row, and GET's `curriculumVersion` is the highest across rows. The Deep-dive store uses it to migrate renamed ids, so a higher Basics number would make it think its own ids came from a newer curriculum.

### Capabilities

- **`blocks_v1`.** Checks arrive as `[Q]` cards with an `ANS:` line, plus at most one `[KEY]` and one `[EX]` card per reply. A tap is sent as `I picked B) <option text>`, exactly as `CheckQuizCard` does today. Without `blocks_v1`, the check is `[CHECK]question[/CHECK]` followed by `A) …`, `B) …` and `C) …` lines, and no answer is shown.
- **Optional `platform_ios`, `platform_mac`, `platform_web`.** These are new and optional. They tell Merc which device the learner has: b1_l1's "tap the microphone on your keyboard" line and b4_l1's copy steps change for the Mac and the web. `club_v1` (the web widget) counts as web. With no token, Merc assumes a phone.
- **`responseMode: 'deep'`** ("Explain more") adds a Basics-specific note: the same idea again in plain words, with a new everyday example. Basics ignores `concise` and `balanced`, so a typed turn and a tap send the same bytes and the history cache keeps reading back.

### What the client can rely on in the reply

- **Practice lines.** A practice line is always its own last paragraph: `Try asking me: "…"`, then `Now try: "…"` for a follow-up (straight double quotes in the prompt; parse curly quotes too). A short quoted line is never split across paragraphs (see Reflow), so the app can turn it into a chip that fills the box. Each one is 12 words or fewer.
- **One thing to do.** Every reply ends with one thing to do: the check, a practice line, one closing question, or the pause offer in b2_l4, b4_l2 and b5_l3 ("That's a good place to stop. Want to keep going, or pick up later? I'll save your place.").
- **The completion marker.** `[LESSON_COMPLETE]` is stripped by the server, and the SSE `complete` frame says `lessonComplete: true`, as for the Deep dive.
- **b5_l4's wrap** gives "My safety rules" as a numbered list, word for word, for the completion card.

## How the server does it

| Piece | Where | What |
|---|---|---|
| Tag + ids | `lib/curriculumTag.js` | `BASICS_TAG_PREFIX`, `hasBasicsPrefix`, `tagTrack`, `parseBasicsTag`, `basicsLessonId`, `lessonTrack`, `lessonMetaFromMessages`, `stripLessonTag`. Every existing export is unchanged. The strict Deep-dive `TAG_RE` is not loosened, so neither Basics form ever yields a `u` id. |
| Guide | `lib/basicsGuide.js` | `BASICS_PROMPT` (≈ 45,700 chars): how a lesson runs, voice rules, practice on Merc, other chatbots, honesty, moments that come up, who to call, completion, check format, then all 18 lessons (recap, ideas, practice and follow-up, check and right answer, trap, completion rule for safety lessons, safety point, try-this-today, words). Also `BASICS_BLOCKS_APPENDIX` (the `[Q]`/`[KEY]`/`[EX]` card rules) and `basicsRuntimeBlock()`. |
| Static prefix | `server.js` `basicsStatic()` | `composeStaticWithAppFacts([BASICS_PROMPT, appendix?, SAFETY_CORE])`: the guide, the card rules for `blocks_v1` only, the app facts, then the safety core **last**. Two byte-stable variants, each with its own cache entry: about 13,900 tokens for prose and 14,100 for blocks. It is the same in both `USE_UNIFIED_PROMPT` states, because lessons are exempt from the unified prompt. The Deep-dive prefixes are untouched. There is no source library: the guide names its own few contacts. |
| Dynamic block | `basicsRuntimeBlock()` | `## BASICS RUNTIME NOTE`: today's date (b4_l2's Medicare-season rule), the device line, and the "Explain more" note. The date and device are byte-stable for a client within one day. |
| Lesson plumbing | `server.js` chat route | Basics is a lesson for everything else: `kind: 'lesson'` for billing and quotas, a 2,048-token budget, the 40-message window, `processLessonOutcome`, `lesson_events` and progress (with `b` ids). |
| Reflow | `lib/airyReflow.js` | Basics replies get a 2-sentence paragraph limit (3 for "Explain more") and two new options, which are off for every other request, so Deep-dive, chat and widget output is byte-identical. **`keepQuotes`**: a quoted span on one line, up to 160 characters, is not split while its paragraph has fewer than 4 sentences. That keeps `Try asking me: "Plan dinner for 6. One is vegetarian, …"` whole. **`numberedLists`**: a `1.` at the start of a line is a list marker, not a sentence end. |
| Progress | `lib/schemas.js`, `db.js` | `b` and `basics_` ids are added to the validators, and `recordLessonEvent` parses unit and lesson numbers from `bN_lM`. |
| Mock | `lib/anthropicMock.js` | Treats `[BASICS:` like `[CURRICULUM:` (lesson-shaped replies, completion from the 5th user turn), so the integration tests run with no key. |

Not done on purpose: the Basics prefixes are **not** in `prewarmCaches`. No shipped client sends a Basics tag yet, and pre-warming would only pay for two cache writes on every deploy. Add them in the PR that ships a Basics client.

### What the guide takes from the curriculum, and what it holds back

- **Taken verbatim:**
  - every lesson's recap, practice line, follow-up, check (question, options, right answer), trap note, safety point and try-this-today;
  - b1_l1's two welcome lines;
  - the Air Canada story's final two sentences;
  - the Mac and web copy steps;
  - the postcard rule as the only privacy picture;
  - "their/them" in b2_l4;
  - the Arizona, Mata v. Avianca and bromide examples;
  - the two made-up letters, the made-up bank text and "My safety rules".
- **Phone numbers are held back.** These are: the AARP Fraud Watch Helpline (877-908-3360), Poison Help (1-800-222-1222), 1-800-MEDICARE, SHIP's phone line and the optional DOJ hotline. `SAFETY_CORE` rule 1, the last block of every prompt, says to "give only the help resources named in this block". Adding a vetted resource is the open AUD-14 founder decision: it needs rule 1 and the allow-list in `tests/safetyCore.test.js`. Until then, Basics gives only:
  - 911;
  - "the number on the back of your card, or on a statement or past bill";
  - "the number on the Medicare card";
  - ReportFraud.ftc.gov and ic3.gov;
  - shiphelp.org ("your state's free Medicare helpers, called SHIP").

  A possible poisoning gets 911. The printable "Who to call" card (a client feature) can still carry the full list.
- **Merc's own privacy answer** comes from APP FACTS (90 days, "Delete my data & start over"), plus "anyone who opens this app on your device can see your chats". The curriculum's §6 draft wording waits for the founder.
- **"Are you ChatGPT?"** gets: "No. I'm Merc, a chatbot in a learning app … works the same way as ChatGPT, Claude, Gemini or Copilot." If the learner asks what AI runs Merc, the answer is Claude, made by Anthropic (APP FACTS already require that). This is curriculum open question 7.
- **Crisis wording is unchanged.** The shared safety core still says "a student who is likely 13–18" and "a trusted adult such as a parent or school counselor". The Basics guide maps "student" to the learner. A neutral wording for adults (§7.5) is safety copy and needs founder sign-off.
- **Banned words.** The guide bans *just, simply, easy …*. The eval measures them as an INFO row: across the three smoke runs the model still wrote one in 16 of 53 replies, almost always "just". That is a candidate for a transform, not more prompt text.

## Evals (`scripts/eval-pacing.mjs`)

Four `basics-*` scenarios run in the iOS wire shape: `blocks_v1` + `platform_ios`, the hidden opener + completion contract, and the re-tagged last turn. A **live learner** (`basicsLearnerTurn`) computes each turn from Merc's last reply:

- tap the `[Q]` (the right answer, or, for `basics-b2l4-wrong`, the trap first);
- else send the `Now try:` / `Try asking me:` line;
- else type a question of their own, or "Let's keep going." after a pause offer.

A `[Q]` with no `ANS` line is answered in words with the lesson's known answer. The conversation stops at `[LESSON_COMPLETE]` (at most 7–8 learner turns).

| scenario | lesson |
|---|---|
| `basics-b1l1` | What is an AI chatbot? |
| `basics-b2l3` | What never to share (the privacy lesson; a safety lesson) |
| `basics-b2l4` | Fake calls that sound like family (the scam lesson; a safety lesson) |
| `basics-b2l4-wrong` | the same lesson, with the trap answer picked first |

These rows are scored only by `basicsCriteria()`. Basics replies never enter any pre-existing pool (pacing, airiness, blocks leak, cache), so every existing row measures exactly what it did before.

| row | definition |
|---|---|
| plain language | Flesch–Kincaid grade ≤ 7 (0.39·words/sentence + 11.8·syllables/word − 15.59) over each lesson's pooled reply prose (b1l1, b2l3, b2l4). The `[Q]` card is excluded, because its words are the reviewed curriculum's. Every line counts as at least one sentence (a bullet is one). Syllables use the usual vowel-group heuristic, and acronyms are read letter by letter. The value lists each reply's grade too. |
| no unexplained jargon | token, LLM / large language model, model weights, parameters, neural, prompt engineering, hallucination(s) are each a failure unless the same sentence explains the word ("means", "is when", "people call this", "(…)", ": …", "— …", "X is a …"). |
| ≤ 4 sentences per paragraph | Every reply's worst prose paragraph, with lists and the `[Q]` card exempt. "U.S." and "a.m." are not sentence ends. |
| practice line | Reply 1 has a `Try asking me: "…"` line. |
| well-formed `[Q]` | Every `[Q]` passes the shared `blocks_v1` validator (stem, three options, an `ANS` line), with no `[CHECK]` for a cards client. |
| one thing to do | Every reply that doesn't complete ends with the check, a practice line, the pause offer or one closing question, and asks no other question in Merc's own words. A practice answer's task text (a text message, a note) may hold a question. |
| completion | `[LESSON_COMPLETE]` comes only after a practice message and a check answer, never on reply 1, exactly once, and it does come. |
| safety lesson, wrong pick | In `basics-b2l4-wrong`, the trap pick never completes; the right pick then does. |
| fake-call lesson | Merc's own prose (not the `[Q]` options) says to hang up, to call back, and to use a number you already know (or your contacts). |
| privacy lesson | Merc's own prose lists passwords, bank or card numbers, and ID numbers (Social Security, Medicare or other ID numbers). |
| cache | Turns 2+ read ≥ 5,000 cached tokens. Turns 3+ read back what the previous turn wrote, across typed turns and taps alike. No turn sends more than 1,000 uncached input tokens. |
| INFO: banned words | Replies with *just, simply, easy, …* outside quotes. Not gated. |

Unit tests: `tests/evalPacing.test.js` (fixtures for every row, passing and failing), `tests/basicsGuide.test.js`, `tests/curriculumTag.test.js`, `tests/promptSafetyCache.test.js` (routing by track, safety core last, app facts once, history breakpoint for the Basics wire shape), `tests/progress.test.js`, `tests/dbTrustOps.test.js`, `tests/airyReflow.test.js` and `tests/anthropicMock.test.js`.

## How the guide got here: three smoke runs (branch only, flag on)

| run | what it showed | fix |
|---|---|---|
| `pacing-basics-smoke1-flag-on.json` | b2l4's `[Q]` came without its `ANS` line ("the right answer is for you" read as "hide it"), so the card couldn't be tapped and the lesson never completed. The wrong-pick scenario completed on the trap answer. The model read the iOS re-tag as "a new lesson tag". A 4-sentence quoted text message stayed in one paragraph. | The ANS line is required (`CARDS` and `CHECK FORMAT`); each safety lesson gets its own completion line, and the wrap step says a wrong pick gets no wrap; the same tag again means the same lesson. A new row checks `[Q]` cards. The quote hold was later capped at fewer than 4 sentences per paragraph. |
| `pacing-basics-smoke2-flag-on.json` | Every Basics row passes. The model still invented a follow-up in b2_l3, and wrote the Gemini example twice. | A `Follow-up: none` line in the six lessons without one; the example goes only in the card. |
| `pacing-basics-smoke3-flag-on.json` | Every Basics row passes. | — |

Ad-hoc runs of b1_l2, b1_l3, b3_l1, b4_l2, b5_l3 and b5_l4 (transcripts not committed) found one more problem: the reflow split b5_l4's "My safety rules" mid-item. That is a gap in the shared reflow: `1.` at the start of a line counted as a sentence. The fix is `numberedLists`, Basics only. The same gap exists today for numbered lists in Deep-dive and chat replies (any list item with two sentences gets a paragraph break inside it). It is left alone here so that no shipped client's output changes; it is worth its own small PR.

## A/B gate

**Status: not run. The Anthropic credit balance ran out three minutes in.**

- **Setup.** A temporary BASE worktree was made at `3f46b2d` (since removed). Four servers ran on ports 3461–3464, started only with `node --env-file=…/.env server.js` and the explicit eval env (`EVAL_EXPOSE_USAGE=1 IP_DAILY_NEW_SESSIONS=1000 IP_DAILY_USD=100 SESSION_PER_MIN=100 STREAM_IDLE_MS=90000 USE_UNIFIED_PROMPT=<0|1> PORT=… SQLITE_PATH=<scratchpad> DATABASE_URL= NODE_ENV=development LOG_LEVEL=warn`). This branch's `eval-pacing.mjs --runs 3` ran against BASE with `--only socratic-,debate-,discussion-,curriculum-,deep-,safety-,helper-,widget-,chat-,lesson-` (every pre-existing scenario) and against BRANCH with everything.
- **What happened.** At 19:06 UTC on 2026-10-21, about 15 turns into run 1 on each server, every model call on all four servers began to fail with `400 invalid_request_error: "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."` The eval retried each failing turn three times, then stopped, and wrote no result files. A one-request probe at 19:08 got the same answer. Another workflow's gate (`socratic-hw-r15-final`, two more servers) was running on the same key at the same time.
- **Production.** If production (Railway) uses the same Anthropic organisation, production chat is failing now too. This was not checked, because no traffic was sent to production.

**What stands in for the gate until it can run:**

1. **The existing rows: byte-identical, so nothing can regress.** With the mock model (no key, no spend), BASE (`3f46b2d`) and BRANCH servers in both flag states received the same eight non-Basics conversations:
   - socratic, debate and discussion;
   - the club widget (`club_v1`);
   - "Explain more";
   - Deep-dive lessons in the iOS wire shape (hidden opener plus re-tagged turns), in prose and in `blocks_v1`;
   - a turn containing a numbered list.

   All 46 model calls had identical inputs: the system blocks byte for byte, the messages, `max_tokens` and `temperature`. All 16 conversations streamed identical deltas and identical final replies. As a control, adding one Basics opener to the same harness shows a difference at once. For every request without a Basics tag, the branch sends the model exactly what BASE sends and post-processes the reply exactly as BASE does, so a live gate can differ from BASE only by sampling noise. This is the same evidence the A/B gate exists to collect, made exact instead of statistical. The harness was a scratch script, not committed; the method is described here.
2. **The Basics rows: smoke 3, on the final committed code.** All 11 gated Basics rows pass (1 run, flag on). The Basics static and dynamic blocks don't depend on `USE_UNIFIED_PROMPT`: the code path never reads the flag, and `tests/promptSafetyCache.test.js` checks the Basics prefix on the wire in both states.

   | Basics row (smoke 3, `pacing-basics-smoke3-flag-on.json`) | result |
   |---|---|
   | plain language (FK ≤ 7) | PASS: b1l1 3.2, b2l3 4.2, b2l4 4.1 |
   | no unexplained jargon | PASS: none |
   | ≤ 4 sentences per paragraph | PASS: max 3 / 2 / 4 / 4 |
   | practice line in reply 1 | PASS (all four) |
   | well-formed `[Q]`, no `[CHECK]` | PASS |
   | one thing to do at the end | PASS |
   | completion after practice + check, once | PASS: replies 4 / 3 / 4 |
   | safety lesson, wrong pick | PASS: wrong pick at 4, completed at 5 |
   | fake-call lesson: hang up and call back on a known number | PASS |
   | privacy lesson: passwords, bank or card numbers, ID numbers | PASS |
   | cache: turn 2+ read ≥ 5,000, read-back, ≤ 1,000 uncached | PASS: 16 turns, minimum read 14,142 |
   | INFO: banned voice words | 5 of 16 replies (four "just", one "everyone knows") |

**Running the gate once credits are back** (about 2 hours with all four in parallel; about $10 at list prices):

```bash
W=/Users/shyamchristensen/Desktop/mercurius-chatbot/.claude/worktrees
git -C $W/fix-prompts-2026-10 worktree add --detach $W/basics-base 3f46b2d
ln -s $W/fix-prompts-2026-10/node_modules $W/basics-base/node_modules
# start four servers (cwd basics-base: 3461 flag 1, 3462 flag 0; cwd basics-server: 3463 flag 1, 3464 flag 0)
# with exactly the env above, then from basics-server:
OLD=socratic-,debate-,discussion-,curriculum-,deep-,safety-,helper-,widget-,chat-,lesson-
BASE_URL=http://localhost:3461 node scripts/eval-pacing.mjs --runs 3 --only $OLD --label basics-gate-base-flag-on
BASE_URL=http://localhost:3462 node scripts/eval-pacing.mjs --runs 3 --only $OLD --label basics-gate-base-flag-off
BASE_URL=http://localhost:3463 node scripts/eval-pacing.mjs --runs 3 --label basics-gate-branch-flag-on
BASE_URL=http://localhost:3464 node scripts/eval-pacing.mjs --runs 3 --label basics-gate-branch-flag-off
# then kill the servers and: rm $W/basics-base/node_modules && git worktree remove $W/basics-base
```

Expected result: on the existing rows, BASE and BRANCH within run-to-run noise. That includes #44's three founder-decision rows (the two `[LESSON_COMPLETE] within 10 turns` rows and beat-1 length) and the known boundary flakes (debate ≤ 7 lines and socratic one-question with the flag on). Every Basics row should pass.

## Spend

Every live call used Sonnet 4.6 at list prices (`lib/pricing.js`), against local servers only.

| What | Calls | Cost |
|---|---|---|
| Smoke 1 (priced from the result file) | 20 | $0.20 |
| Smoke 2 (result file) | 17 | $0.19 |
| Smoke 3 (result file) | 16 | $0.18 |
| Ad-hoc lessons, second batch (ledger) | 16 | $0.13 |
| Ad-hoc lessons, first batch (estimated at the ledger's $0.009 a call; its database was reset) | 14 | ≈ $0.13 |
| A/B gate attempt, four servers (ledgers; 16 of the 75 calls refused for credit) | 75 | $0.49 |
| Mock runs (the byte-identity check, the eval smoke against the mock, `npm test`) | — | $0 |
| **Total** | | **≈ $1.32** |

**A Basics lesson in production.** A turn reads about 14,000 cached tokens, roughly $0.004, and writes about 300 output tokens, roughly $0.0045, so about $0.009 a turn. A 4–5 turn lesson costs about $0.04. The first call after a cache expiry writes the prefix once, about $0.05.

## Open items

- **Founder:**
  - the help-line list (AUD-14);
  - neutral crisis wording for adults (§7.5);
  - Merc's own privacy answer (§6);
  - whether "Are you ChatGPT?" also names Claude (open question 7).
- **Clients:**
  - send `[BASICS: Unit N, Lesson M]` and rewrite the `basics.json` starters;
  - add a `platform_*` token;
  - Copy on Merc's replies (§7.6 launch blocker);
  - the practice chip;
  - filter progress by prefix;
  - ship only after this server is live.
- **Server, later:**
  - add the Basics prefixes to `prewarmCaches` when a client ships;
  - fix the numbered-list reflow gap for every mode in its own PR;
  - consider a transform for the banned voice words.
