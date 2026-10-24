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
| Free-chat turn (SSE and JSON), debate, discussion | `temperature` from the response mode (0.3 / 0.4 / 0.6 / 0.7); `max_tokens` 120 / 250 / 600 / 1400, debate at least 400, discussion and safety topics at least 600 | `thinking: {type: "between_tools"}`, `output_config: {effort: TUTOR_EFFORT}`; `max_tokens` 162 / 338 / 810 / 1890, debate at least 540, discussion and safety topics at least 810 (see "Tuning pass"); the model notes in the static block |
| Homework problem turn (`looksLikeProblemWork`), and its answer-guard and writing-quote retries | `thinking: {type: "adaptive"}`, `output_config: {effort: "low"}`, no temperature, `max_tokens` = budget + 2048 (at least 3000) | `thinking: {type: "adaptive", display: "summarized"}`, effort `low`, `max_tokens` = scaled budget + 2765 (at least 4050: the 2048 and the 3000, scaled too); also calculus, statistics, proofs and "i got N" turns (see "Tuning pass") |
| Deep-dive and Basics lesson turns | `temperature`, `max_tokens` 2048 | `between_tools` at `TUTOR_EFFORT`, `max_tokens` 2765 |
| Unit-test grader | `temperature: 0.2`, `max_tokens` 400 | `between_tools` at `TUTOR_EFFORT`, `max_tokens` 540 |
| Fact-check, analyze | no sampling or thinking field, `max_tokens` 700 | `between_tools` at `TUTOR_EFFORT` (otherwise the model would think adaptively at `high`), `max_tokens` 945 |
| Cache prewarm (`POST /api/admin/prewarm`, `PREWARM_ON_BOOT`) | no sampling or thinking field, `max_tokens` 1 | `between_tools` at `TUTOR_EFFORT`, to match what tutor turns send, because thinking and effort are part of the cached prompt |
| Quiz, report card, concept map, briefing | Haiku 4.5, unchanged | Haiku 4.5, unchanged |

The fields are chosen per call from the model that call actually uses. A client that names `claude-sonnet-4-6` or `claude-haiku-4-5` on a Sonnet 5.5 server gets those models' fields. No route builds these fields by hand any more. They come from `lib/modelParams.js` (`requestFields(model, intent)` and `maxTokensFor(model, intent, base)`). Each route spreads them between `max_tokens` and `system`, the same key order the requests have always had.

Thinking headroom: only problem turns think, so only they get the +2048 (+2765 on Sonnet 5.5, scaled for its tokenizer). `between_tools` turns have no thinking to make room for. There are no tools in these requests, so there are no progress-update blocks either.

## Tuning pass after the A/B (Oct 24)

The A/B (`ab-2026-10-24/`) had Sonnet 5.5 winning the blind homework comparison 34 to 9, but failing 10 eval checks against Sonnet 4.6's 5. The analysis traced most misses to two causes. Sonnet 5.5 reads the prompt literally, and its tokenizer needs more tokens for the same words. This pass changes Sonnet 5.5 requests only.

Every change is gated on `usesBetweenTools(model)` in `lib/modelParams.js`, the predicate that already picks the Sonnet 5.5 request fields (`claude-sonnet-5-5` and its dated ids). It is evaluated on the model each call actually uses, so a client that names `claude-sonnet-4-6` on a Sonnet 5.5 server still gets the 4.6 request. With `TUTOR_MODEL` unset, every request is byte-identical to `d238a02`. See "Proof" below.

| Change | Where | What it fixes (A/B evidence) |
|---|---|---|
| Every reply budget × 1.35, rounded up | `maxTokensFor` | The third Debate reply was cut off at its 400-token floor in 2 of 3 runs. A widget reply was cut at 250 tokens. A safety reply used exactly 250, the cap that protects the 988 / 741741 line. |
| Model notes in the cached free-chat prefix | `lib/modelNotes.js`; `v2Static` and `legacyStatic` in `server.js` | Median chat reply of 5 sentences. A hint after the opener's question. The missing "Yes" on a right step. A long Debate concession. A scoring block under its own lead-in. Give-ins to lazy students. Forced AI asides. Checks credited to the student. Settled answers quizzed again. The integral and n − 1 errors. |
| A wider problem detector, for the thinking decision only | `looksLikeProblemWork(…, { broad })` | calc-def, stats-sd and calc-int ran with no reasoning at all. |
| The AI tie-in is ordered only in a calm thread | `homeworkMoment(…, { calmTieIn })` | The server's own STEP CHECK note told the model to add the AI line, even for students on a timed test. |
| A calculus or statistics number is checked against the model's own working | `homeworkMoment(…, { calcCheck })` | The THEIR NUMBER note says "run it backwards; never work the formula out yourself", which can't be done for a definite integral or f'(2). That is the instruction behind calc-def's "12 would be right if …". |
| The eval's `RETRY_REFUSAL_RE` accepts a first-person "I'm not writing anything" | `scripts/eval-pacing.mjs` | roast-retry was marked failed even though Sonnet 5.5's declines were correct. |
| The eval's cut-off check reads each model's own caps | `notCutOff`, `tokenCaps` in `scripts/eval-pacing.mjs` | At 4.6's caps, a 5.5 reply cut at 338 tokens was missed and a finished 600–810-token one was flagged. |

### max_tokens

| Request | Sonnet 4.6 | Sonnet 5.5 |
|---|---|---|
| one_line / concise / balanced / deep | 120 / 250 / 600 / 1400 | 162 / 338 / 810 / 1890 |
| Debate floor; discussion and safety-topic floor | 400; 600 | 540; 810 |
| Deep-dive and Basics lesson turn | 2048 | 2765 |
| Unit-test grader; fact-check and analyze | 400; 700 | 540; 945 |
| Problem turn (concise; deep) | 3000; 3448 | 4050 (338 + 2765 is under the 4050 floor); 4655 |
| Prewarm | 1 | 1 |

Why 1.35: across every non-thinking reply in the A/B, Sonnet 5.5 used 1.28× the tokens per word that 4.6 did. By route the ratio was 1.28 for Basics, 1.31 for Deep dive, 1.34 for Debate, 1.16 for Discussion and 1.22 for Socratic. 1.35 covers Debate, the route that was cut off. The model never sees `max_tokens`, so a higher cap does not make replies longer: it only stops them from being cut off. Spend goes up only on replies that would otherwise have been cut off. The scale uses whole-percent arithmetic, so 700 becomes exactly 945.

A thinking problem turn's headroom and floor are scaled too (2048 → 2765, 3000 → 4050), because thinking is text in the same tokenizer. The wider detector also sends proofs and integrals to thinking now. This is margin, not a fix: the longest of Sonnet 5.5's 240 homework eval replies in the A/B used 862 output tokens, thinking included.

### The model notes (`lib/modelNotes.js`)

The notes are one byte-stable constant of about 740 words: one heading plus 13 one-line rules, each stated once, with the behaviour wanted and the cases it doesn't cover. Sonnet 5.5 applies a rule to every case it doesn't exclude, so the review of the first draft scoped each one (see "Review of the tuning pass"). They go in the cached static block of the free-chat prefixes only (app and widget, every mode, both flag states). They sit after the source library and before the app facts and the safety core, which stays LAST. The v2 prompt gets them as `<model_notes>`. The legacy prompt gets them under `## MODEL NOTES`.

Lessons (Deep dive and Basics), the grader and the helpers do not get them. Sonnet 5.5 passed the lesson length rows, and these rules are about chat and homework. Each variant is its own cache entry: 2 for v2 and 6 for legacy. When `TUTOR_MODEL` is Sonnet 5.5, the prewarm warms these variants, the ones its turns read.

The rules, each written against a measured miss:

- **SAFETY CORE replies keep their own shape.** A crisis, a safety topic, a refusal, a privacy warning or an age notice keeps the length, content and ending that block gives it. None of the other notes apply to it, so a sextortion or crisis reply is never squeezed to 4 sentences or given a closing question.
- **Length.** A reply is at most 4 sentences, its closing question included, and 3 is the usual shape. It is a ceiling, so a one-question opener and a one-line confirm fit. A reaction goes inside the sentence that carries the idea. A scenario goes inside the question. No sentence only announces or labels a point. The miss: 25 of 44 chat replies had 5 or more sentences, against 3 of 42 on 4.6. The prompt's "Six sentences is a hard ceiling" was read as an allowance.
- **The closing question is the last sentence and asks one thing.** When a bare new problem comes in (no work, no answer, and no request for a worked example or code), the first reply is that one question, and the opening message is not an ask. The first nudge is a smaller piece of the move the opener named. A request for a worked example or code gets it right away, on new numbers, as the hint ladder says (hw-example-first, which 5.5 passed 3 of 3). The miss: 25 of 105 first replies added a hint after the question (hw-algebra-persistent, hw-one-step, hw-moles).
- **"Yes" on a right step, in the same sentence as the next move.** Confirm and advance (and any STEP CHECK note) says what that move holds. The "Yes" is part of the move, not preamble. The miss: hw-step-both-sides, 0 of 3, because "No preamble" won over the STEP CHECK note.
- **Debate: a one-sentence concession with no source.** **Discussion: a scoring reply opens with "Here's how your reasoning scored:".**
- **A push for the answer is not being lost.** On anything but a one-variable linear equation, the student writes every line, setup and substitutions included. The escalation is spelled out: the first push names the technique and the exact piece it acts on; the second says how the technique works in general and asks about their piece; the third is a worked example on a different problem; after that, a narrower question on their latest line alternates with another worked example. A deadline or a teacher's permission gets a few calm words inside the move, never a bigger step and never an argument. A student who says they are lost keeps the ladder as written. The misses: proof-ind, calc-int, sys-1, energy-1, and take-home-test's bare one-liners. 5.5 won all 8 stuck-student chats, so that path is untouched.
- **Numbers that can't be checked by putting them back in** (a definite integral, a derivative at a point, a limit, a standard deviation) are checked silently against the tutor's own working. A match is shown against the matching line, then confirmed. A wrong one gets a failing check or the first false line of their work, never a case where it would be right (calc-def). An antiderivative is checked by differentiating it, the check 5.5 used well in calc-int.
- **A reason is checked before it is built on**, on schoolwork only, and only a wrong part is named (stats-sd). Debate and Discussion keep their own rules.
- **A confirmed answer is settled.** Asked again with nothing new, it gets a one-line confirm. New work, or a reason it might be wrong, gets checked, and a wrong confirmation is taken back plainly. After it, a harder problem is an offer, never a quiz, and none is offered during a test or a rush. A thanks closes the chat with no question, after any answer or reason in the same message is dealt with (molarity-1, take-home-test, growth-1, stats-sd).
- **The check in the reply is the tutor's**, and a slip of theirs is never an AI's (calc-rr, stoich-1, newton-fric).
- **The AI tie-in comes once, only in the reply that confirms a final answer they worked out themselves,** and never for a rushed or pushing student. A fact answer gets no AI line. The miss: AI lines in 27 of 48 chats against 4.6's 8, including hist-fact and second lines. hw-algebra-advance, the eval row that requires the tie-in, is a calm student who solves it, so the line is still due there.

No note quotes an opener a reply could copy word for word. The one exact line is the Discussion scoring lead-in, which is meant to be copied.

### The wider problem detector

With `broad`, `looksLikeProblemWork` also counts two more kinds of student message:

- calculus, statistics and proof words (integral, derivative, `lim`, prove, induction, standard deviation, variance) in a message with some math in it;
- a bare "i got / i said N".

It is used for the thinking decision only. The answer guard's holdback and the server's notes keep the current detector.

Over the 48 homework chats, it gives adaptive thinking to the early turns of 9 chats: calc-def, calc-deriv, calc-int, circuit-1, hw-eq, limit-1, ph-1, prob-bayes and stats-sd. It adds none of the 180 eval-pacing scenario turns. Those turns now pay for low-effort thinking, with the 4050 floor.

### The calm AI tie-in

A right final answer's STEP CHECK note keeps today's "add the one AI tie-in line" only when no turn of the thread pushed for the answer and none was rushed. A push is the push itself: "just tell me", "can you just …", "answer(s) only", "do it for me" and similar. Rushed is the clock itself: a due time, "N min left", "I have 5 minutes", "no time", a test in progress ("it's a test", "on a test right now", a take-home test) or "I'm gonna fail". Otherwise the note says "No AI line in this reply: they were rushed or pushing for the answer". An "idk" is being stuck, not pushing, so it doesn't count. Words that also turn up in calm work don't count either: "can you tell me if it's right", "a test catches 90%", "let me test x = 3", "60 km in 45 minutes", "I have a quiz Friday so I want to practice". Over the 48 homework chats, the patterns flag the 11 that pushed or were rushed and no longer flag gov-1 (a quiz tomorrow) or prob-bayes (a medical test).

### Calculus and statistics answers (`calcCheck`)

The THEIR NUMBER note tells the model to run the student's number backwards through the formula and never work it out itself. That can't be done for a definite integral, f'(2), a limit or a standard deviation, and it contradicts the notes' own-working rule. On Sonnet 5.5, when the thread has a calculus or statistics word (the `broad` detector's words) or calculus notation (f'(…), dy/dx, ∫), the note instead says: work it out silently; if their number matches, show the matching line of your working and confirm; if not, show a failing check or the first line of their work that breaks (or ask for it), never your own result; never describe a case where their number would be right. calc-def's exact wording never reached the note, but "evaluate the integral … i got 10" and "f(x) = …, find f'(2). i got 12" do. Any other formula or word problem (moles, acceleration, a mean, which can be run backwards) keeps today's note, and so does every model but Sonnet 5.5.

### Review of the tuning pass

A review of the first draft checked each change against the code and the A/B transcripts. What it found, and what changed:

| Finding | Outcome |
|---|---|
| The opener rule overruled "If they ask for a worked example, give it now" (hw-example-first), and "2–4 sentences" was a floor the one-question opener broke | Fixed: the opener rule excludes a request for a worked example or code; the length rule is "at most 4" |
| The server's THEIR NUMBER note ("run it backwards") contradicts the own-working rule on calculus answers | Fixed: `calcCheck` (above) |
| "Judge a reason … which part holds and which doesn't" invited invented flaws and reached Debate and Discussion | Fixed: schoolwork only, and only a wrong part is named |
| SAFETY CORE replies were not exempt from the length and closing-question rules | Fixed: a first rule exempts them |
| "Can't be run backwards" lumped antiderivatives in and dropped the visible check | Fixed: an antiderivative is differentiated back; a match is shown, then confirmed |
| A thanks that also carries a reason (stats-sd's last turn) had two rules and no order | Fixed: deal with the answer or reason, then close |
| The push rule had no rung for the 3rd and later pushes, and nothing for a deadline or a teacher's permission | Fixed: the escalation is spelled out, with a few calm words for either |
| "Settled" had no way back for new evidence | Fixed: new work or a reason gets checked, and a wrong confirmation is taken back |
| The push and rush patterns flagged calm students ("a test catches 90%", "can you tell me if it's right") | Fixed: they ask for the push or the clock itself |
| The thinking headroom wasn't scaled, and the eval judged 5.5 replies by 4.6's caps | Fixed: both (see "max_tokens" and the table above) |
| Quoted openers ("Right, and the word doing the work is …", "Yes — so what undoes …") could be copied | Fixed: the notes describe the shape and point at Confirm and advance |
| `RETRY_REFUSAL_RE`'s "anything" passed "Jake is not making anything of his life" | Fixed: first person only ("I'm (still) not writing anything") |
| The longform airy row, the teacher-permission claim, energy-1 and a delivered-roast check were not addressed | Documented under "Not done" |

### Proof that Sonnet 4.6 is unchanged

One script sent 42 requests through the mock, with `TUTOR_MODEL` unset, in both flag states. It ran once against an export of `d238a02` and once against this tree. The requests cover:

- free chat in every response mode, over SSE (iOS capabilities) and JSON;
- a widget (`club_v1`) turn;
- debate and discussion;
- problem turns with their guard retry;
- a right step on the way, a right final answer, and rushed right final answers ("due in 10 min", "15 min left");
- calm right final answers whose wording used to read as a push or a rush ("can you tell me if my answer is right", "let me test", "a quiz Friday");
- the calculus and statistics openers, and THEIR NUMBER on a definite integral, an f'(2) and a moles answer;
- an asked-for worked example;
- a writing turn and a safety-topic turn;
- Deep-dive and Basics lessons;
- client-named Haiku 4.5 and Sonnet 4.6;
- the grader, fact-check, analyze, quiz, report card and concept map;
- the prewarm.

All 50 captured calls with the flag on and all 54 with it off were byte-identical to the `d238a02` capture (`cmp`). That covers model, max_tokens, sampling and thinking fields, the system blocks, the messages and the key order. The same run with `TUTOR_MODEL=claude-sonnet-5-5`, against `d238a02` with the same variable, changed only these fields:

- `max_tokens` on 41 calls (every call but the prewarm, the Haiku ones and the one that names Sonnet 4.6);
- the static block of the free-chat calls (36 flag on, 40 flag off): removing the notes from it gives back the 4.6 prefix exactly, and in every one the notes come before the app facts and the safety core, which is LAST;
- `thinking` on the three calculus and statistics openers;
- the dynamic block of the two rushed right answers and the two calculus THEIR NUMBER turns.

`tests/tutorModel.test.js` asserts the same on every run.

### Not done in this pass, and why

- **The eval's airy-paragraph metric and `isScoringReply`.** The analysis found that the airy failures are mostly counting artifacts. The eval counts `?"` inside a sentence and `vs.` as sentence ends, and a scoring block left the pool when the model put its own lead-in before it. The proposed fix makes the metric count the way `lib/airyReflow.js` does, which lowers counts. That loosens a check, so it waits for an explicit decision. The notes' Discussion rule covers the scoring lead-in.
- **The two `[LESSON_COMPLETE] within 10 turns` rows.** Both models fail them because the scripted student never answers the exercise. Withholding the marker is correct.
- **Suppressing STEP CHECK verdicts on worksheet threads.** Sonnet 5.5 ignored the wrong notes there. The proposed heuristic (two or more equations in the problem turn) would also drop the verdict when an opener holds the problem and the student's first line. This is better done as a fix shared by both models.
- **Skipping the ask note once an answer is confirmed** (molarity-1's "so am i right tho"). The notes' "settled" rule covers it. If the rerun still shows it, add a deterministic version.
- **A server-side "Yes —" prefix for a right step.** This is the fallback if the rerun still misses hw-step-both-sides.
- **Grammar choices ("who or whom") as fact questions.** This conflicts with the worksheet integrity rule, so it is a founder decision.
- **The 4.6 wording "the check they just ran" in the AI tie-in rule.** 4.6 makes the same misattribution, but fixing it changes 4.6's bytes.
- **The longform airy row will likely still fail on Sonnet 5.5.** Its failures were deep-1 (an "Explain more" reply, which keeps its own length) and lesson replies, which get no notes, and they come from the same counting artifacts (`(what am I looking for?)`, `vs.`). Nothing in this pass reaches them. The row stays red until the founder decides on the metric.
- **Whether a teacher's permission to use AI changes anything.** 5.5 (and 4.6) never answered "my teacher allows AI" in take-home-test. The notes now have it acknowledged in a few calm words inside the move. Whether it should ever change what the tutor gives is a policy question for the founder.
- **energy-1's confirmed bare guess ("is it 19.8").** Both models' shared rules check a proposed value (CHECK BEFORE ANY VERDICT) and the last-step ladder even invites a guess. Whether a guess with no work should be confirmed is a shared-rule question, not 5.5 tuning.
- **A third roast-retry check for a delivered roast.** A reply such as "I'm not writing anything mean — here's a light one: …" passes the refusal check, as "I won't …" or "can't" already could. A check on body or skin words would fail every correct decline in the A/B (all six name his weight, skin or body), so none was added. Read roast-retry replies by eye on the rerun.

### Next

1. Rerun `scripts/eval-pacing.mjs --runs 3` on Sonnet 5.5 in both flag states (servers C and D above).
2. Rerun the 48-chat homework A/B on Sonnet 5.5. It should keep the 34 to 9 coaching win and improve the 9 lazy-student chats.
3. Watch these:
   - curt one-line replies that read as stonewalling (take-home-test), now that the push escalation is spelled out;
   - hw-example-first still getting the worked example in reply 1;
   - the safety rows (988, 741741, "not your fault", "don't pay", "trusted adult") with the notes in the prefix;
   - hw-algebra-advance still getting exactly one AI line;
   - the hw-chem and hw-accel openers;
   - Debate's line count;
   - latency and cost on the turns the wider detector now sends to thinking.

Why `display: "summarized"` on problem turns: Sonnet 4.6 summarizes thinking by default; Sonnet 5.5 defaults to `"omitted"`. Under `"omitted"` a think streams nothing until it ends: no `thinking_delta`, and the SDK drops the API's `ping` events. The stream idle watchdog (`STREAM_IDLE_MS`, 30 s) resets only on an upstream event, so a long silent think would end the turn with the `timeout` error frame where 4.6 finished it. Summarized thinking deltas keep the watchdog fed, as on 4.6. They never reach a student (the relay forwards `text` events only). `display` changes visibility only: thinking is billed the same either way. The Sonnet 4.6 request is unchanged (no `display` field). `between_tools` takes no `display` and does not need one.

## Any other model

`lib/modelParams.js` has verified request rules for `claude-sonnet-4-6` and `claude-sonnet-5-5` only. Setting `TUTOR_MODEL` to anything else logs `TUTOR_MODEL is not claude-sonnet-4-6 or claude-sonnet-5-5: its request fields are unverified` at boot. A client can also reach another model if `MODEL_ALLOWLIST` names it. What such a model gets:

- A model before 4.7 (for example `claude-haiku-4-5`): `temperature`, as today.
- Any other 4.7+/5.x model (for example `claude-sonnet-5`, `claude-opus-5-5`): no sampling fields, and `between_tools` is a 400 there. On Sonnet 5, Opus 5 and 5.5, and Haiku 5.5, leaving `thinking` out runs adaptive thinking, which would think inside reply budgets of 120 to 700 tokens and run out, so the reply would come back empty and turn into the refusal copy. Every call therefore sends `thinking: {type: "adaptive", display: "summarized"}` at `TUTOR_EFFORT` (a problem turn at `low`), with the problem-turn headroom: budget + 2048, at least 3000. The prewarm keeps `max_tokens` 1.

None of this has been evaluated. Run the A/B below on any such model before using it.

## What stays the same

- **Prompts and cache shape.** For Sonnet 4.6 the static and dynamic system blocks, the history breakpoint and the thread trimming are unchanged. Sonnet 5.5 free-chat prefixes also carry the model notes, and its homework notes differ in two cases (see "Tuning pass"). Prompt caching works the same way on Sonnet 5.5, but caches are per model: the first turns after a switch write the prefixes again, and the old model's entries are not reused. The minimum cacheable prompt is 512 tokens, and every static prefix is far above that.
- **Response handling.** Every reader takes the reply from `text` blocks by type: `firstTextOf` in `server.js`, `messageText` in `lib/claudeCall.js`, and the SSE relay, which forwards SDK `text` events only. An adaptive Sonnet 5.5 reply starts with a `thinking` block: a summary on problem turns, and empty text under the default display (`"omitted"`) wherever a request leaves `display` out. That block, its `thinking_delta` and `signature_delta` events, and Sonnet 4.6's summarized thinking never reach a student. The grader, fact-check, analyze, the briefing and the quiz/report-card/concept-map helper used to read `content[0].text`. They now use `firstTextOf` too.
- **Refusals.** `stop_reason: "refusal"` is handled as before (AUD-01, `REFUSAL_COPY`). The refusal log line now also carries `stop_details.category` (`cyber`, `bio`, `frontier_llm`, `reasoning_extraction`, `general_harms`). In the stream it is taken from `message_delta`, because SDK 0.39 does not copy it into the final message.
- **Accounting.** Every call still goes through `lib/claudeCall.js`. `lib/pricing.js` now has the Sonnet 5.5 rate card: $2 input, $10 output, $2.50 5-minute cache write and $0.20 cache read per million tokens. Sonnet 5 has the same card. The dollar budget, the per-session and per-IP quotas, Prometheus and the `usage` ledger therefore price Sonnet 5.5 calls at Sonnet 5.5 rates. The token estimate used when a stream ends early (`estimateTokens`) counts 1.3× for these models.
- **Requests with `TUTOR_MODEL` unset.** These were replayed against an export of `main` with the same mock, in both flag states, as 27 requests that cover every route, response mode and track. The captured params, including key order, were byte-identical.

## Measured later (the A/B decides)

1. **Cost per turn.** Sonnet 5.5 is $2/$10 against $3/$15, but its tokenizer counts about 30% more tokens for the same text. Per turn that is roughly 0.67 × 1.3 ≈ 0.87 of Sonnet 4.6's cost before thinking. Problem turns also pay for their adaptive thinking, and the first turns after a switch pay the cache writes again. Measure it from the eval servers' usage (`EVAL_EXPOSE_USAGE=1`) priced by `lib/pricing.js`, per route and per flag state.
2. **Reply length under the token budgets.** The A/B showed it: at 4.6's budgets, Sonnet 5.5 had one cut-off reply per run. Its budgets are now scaled by 1.35 (see "Tuning pass"). Keep watching the eval's cut-off criteria and the safety-topic floor, so the closing 988/741741 line still lands.
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
- `tests/modelNotes.test.js`: the notes go to `claude-sonnet-5-5` (and its dated ids) only. They are a byte-stable constant: frozen, the same bytes on a fresh load, no template braces or brackets, no model name, no example numbers and none of the eval's problems. They stay short, one rule per line. In the composed prefix they sit after the source library and before the app facts and the safety core (LAST), and without them the prefix is byte for byte today's.
- `tests/modelParams.test.js`: the scaled Sonnet 5.5 budget table, and today's budgets for 4.6, Haiku 4.5 and the unverified models.
- `tests/homeworkGuard.test.js`: `broad` (and that it is off by default), and `calmTieIn` (a push or a deadline drops the order, "idk" doesn't, and off it is today's note).
- `tests/evalPacing.test.js`: `RETRY_REFUSAL_RE` accepts Sonnet 5.5's declines, and the roast-retry row still fails an offer aimed at Jake.
- `tests/tutorModel.test.js`: boots the server with `TUTOR_MODEL=claude-sonnet-5-5` (both flag states, plus `TUTOR_EFFORT=medium`) and unset (both flag states). It drives free chat (SSE and JSON), problem turns with their guard retry, Deep-dive and Basics lessons, the grader, fact-check, analyze, the quiz and the prewarm. It asserts the captured params and key order, health, and the ledger's Sonnet 5.5 pricing. A sixth server runs with `MOCK_LEADING_THINKING=1`, where every reply starts with an empty thinking block, to prove every route reads its reply by type. A seventh runs Sonnet 5.5 with `STREAM_IDLE_MS=750` and `MOCK_THINKING_MS=2000`: a problem turn that thinks for longer than the idle window completes (with `display` omitted it ended in a `timeout` frame). An eighth runs `TUTOR_MODEL=claude-sonnet-5` and checks the boot warning and the explicit thinking and headroom on every route. For the tuning pass it also checks, in both flag states:
  - every Sonnet 5.5 free-chat prefix (app, widget, debate, discussion) is the 4.6 prefix plus the notes, in front of the app facts and the safety core, the same bytes every turn;
  - a client that names 4.6, a lesson, Basics, the grader and fact-check get no notes;
  - the prewarm writes the prefixes the turns read;
  - the scaled Debate, Discussion and safety floors;
  - the wider detector on 5.5 only, and the calm tie-in on 5.5 only;
  - no request on a `TUTOR_MODEL`-unset server ever carries the notes.
- `lib/anthropicMock.js` now rejects with a 400, like the API, every Sonnet 5.5 request with a sampling field, disabled/enabled/budget thinking, `between_tools` with another field or at `xhigh`/`max`, `between_tools` on any other model, and forced `tool_choice`. It returns thinking blocks first when a call thinks, and a request with no `thinking` field thinks on every 5.x model, as the API does. `MOCK_THINKING_MS` makes a streamed think take that long: silent under `"omitted"`, small `thinking_delta` pieces under `"summarized"`. `MOCK_CAPTURE_FILE` also records `top_p`, `top_k` and `paramKeys` (the request's key order).
- `tests/support/spawnServer.js` and the two suites that spawn the server themselves pin `TUTOR_MODEL` and `TUTOR_EFFORT` to empty, so a developer's own setting never changes what they assert.
