# Interactive lesson player pilot: handoff

Branch `pilot/interactive-lesson-player`, local only (not pushed). It is based on `origin/main` (b5d1603), not the old `feat/cost-cuts` checkout; PROGRESS.md D1 explains why. The decision log and all evidence are in `PROGRESS.md`; metric definitions are in `METRICS.md`; how to convert the next lesson is in `ADDING_LESSONS.md`.

## What changed

**New module: `ios/Packages/LessonPlayer`.** It depends on DesignSystem only and is registered as a content module in `ArchitectureTests/Tests/DependencyGraphTests.swift`.

| Path | What it is |
|---|---|
| `Sources/Model/LessonContent.swift`, `Activity.swift` | Typed lesson data: stable ids, content/schema versions, objective, prerequisites, scenario and evidence material (real or fictional), answer keys, rubrics, per-answer feedback, hints, optional depth |
| `Sources/Core/LessonValidator.swift` | Runtime validation. Errors keep a lesson legacy; editorial targets are warnings |
| `Sources/Core/Grading.swift` | Deterministic grading (single, multi, claim selection, claim vs evidence) and the evaluation-result validator |
| `Sources/Core/LessonMachine.swift` | The step state machine (select → submit → feedback → continue), with double-submit, double-advance and stale-result guards |
| `Sources/Core/LessonAttempt.swift` | The attempt as one Codable value, pinned to its content version, normalized after a relaunch |
| `Sources/Core/ExperienceResolver.swift` | Which experience a lesson opens in; the one-time reward ledger |
| `Sources/Core/LessonPlayerEvent.swift` | The measurement events (no text) |
| `Sources/Content/` | `Lesson_u1_l3.swift`, `Lesson_b1_l1.swift`, `LessonCatalog.swift` |
| `Sources/Player/` | `LessonPlayerModel`, `LessonPlayerView`, `ActivityViews`, `ActionBar`, `ShortResponseView` (and the practice step), `PlayerCopy` |
| `Tests/` | Core, Lesson 3, Basics 1.1, and the model's evaluation failures |

**App wiring: `ios/Packages/AppFeature`.**
- `Sources/LessonPlayer/LessonPlayerFlag.swift`: the switch.
- `LessonAttemptStore.swift`: saved attempts and the reward ledger.
- `LessonPlayerTelemetry.swift`: the event sink.
- `PlayerSupport.swift`: evaluation, practice and the Ask Merc sheet.
- `AppShellView.swift`: decides the experience on open (`makePlayerLaunch`) and shows `playerCover` or the unchanged `legacyLessonCover`.
- `AppEntryView.swift`: refreshes the flag and logs `first_open`.
- `SettingsSheet.swift` and `Mac/MacShellView.swift`: delete-my-data erases attempts.
- `AppEnvironment.swift`: owns the flag and the store.
- Tests are in `Tests/LessonPlayerHostTests.swift`.

**Networking: `ios/Packages/NetworkingKit/Sources/APIClient+LessonPlayer.swift`.** The config probe and the evaluation call.

**Server, additive only.**
- `lib/lessonPlayer.js` and `GET /api/lesson-player/config`: the flag.
- `lib/lessonPlayerRubrics.js` and `POST /api/lesson-player/evaluate`: the short-response check against a server-held rubric.
- `POST /api/lesson-player/activity`: start, resume and complete, ids only and no model call. A player lesson keeps the learner's **streak** and writes the same `lesson_events` start and complete rows as a chat lesson.
- `lib/schemas.js`: `LessonPlayerEvaluateRequest`.
- `lib/anthropicMock.js`: the mock answers the evaluator.
- Tests: `tests/lessonPlayerConfig.test.js`, `tests/lessonPlayerEvaluate.test.js`.

**Two flag-independent fixes, each in its own commit.**
- `3339ff6`: key-idea, example and check cards render inline Markdown. The literal `**` came from `Text(String)` in `ChatFeature/Sources/BlockCards.swift`, which draws a string verbatim. They now use `InlineMarkdown`. This affects legacy lessons and free chat's cards on iPhone and iPad; plain text is unchanged, and the Mac already did this.
- `6a30eca`: the Unit 1 Lesson 3 server guide gains a Grading note. An unlocated citation leaves a claim unverified, not proven fake, and a real paper still has to support the claim. No authored text said the opposite; the "treat it as made up" line in the founder's recording was the model's own wording, which nothing in the guide prevented.

**UI tests:** `ios/MercuriusUITests/LessonPlayerUITests.swift` (they can't run on this Mac; see Validation).

## Architecture and content migration

- **Lesson content is data, authored in Swift.** It is not generated, and it is validated when the app starts using it. Everything a learner taps on, and every piece of objective feedback, is ready before they tap, so objective steps work offline and with the model down.
- **The model is used in three places only:**
  - **Short-response evaluation:** the server holds the rubric and the client sends ids and the answer.
  - **Practice messages:** these go through the existing live tutor.
  - **Ask Merc:** this opens the existing chat.
- **`LessonMachine` is the only thing that changes an attempt.** The view model forwards taps and network results to it, saves after every change, and turns its effects into host calls (evaluate, practice, complete, exit, events).
- **The app decides the experience once, when a lesson opens:**
  1. An unfinished player attempt resumes, on its own content version.
  2. Otherwise, a lesson with a legacy chat thread stays legacy.
  3. Otherwise, with the flag on and valid content, a new player attempt starts.
  4. Otherwise, legacy.
- **Completion goes through the same `handleLessonComplete` as legacy lessons**, so progress, sync, unlocks, certificates, the review prompt and the Live Activity behave exactly as before. A per-lesson ledger stops a replay from granting one-time rewards twice.
- **Adding the next lesson:** see `ADDING_LESSONS.md`. In short:
  1. Write `Lesson_<id>.swift` from the lesson's real objective, guide and assessment.
  2. Add it to `LessonCatalog`, and its id to `PILOT_LESSONS`.
  3. If it has a short response, add a server rubric.
  4. Write its test suite.

## How to turn it on, and roll it back

- **On (server):** set `LESSON_PLAYER_ENABLED=1` in Railway and restart. Optionally narrow it with `LESSON_PLAYER_LESSONS=u1_l3` or `b1_l1`.
  - Clients pick it up at their next launch (`GET /api/lesson-player/config`, cached on the device).
  - **This only works for a build that contains this code.** The App Store build doesn't have it yet, so turning it on requires shipping this branch in a release first.
- **Off:** unset the variable, or set it to `0`, and restart. **No app release is needed.**
  - From the next launch, new attempts open the legacy lesson.
  - An attempt already started in the player stays in the player until it is finished. Nothing swaps mid-lesson; that was verified in the simulator after a kill and relaunch with the flag off.
- **Kill it in a build:** set `LessonPlayerFlag.clientAllowed = false` (compile time). That build never shows the player.
- **Local testing:** in DEBUG builds, `-LessonPlayer YES|NO` overrides the server. `-LessonPlayerStubGrade meets|not_yet|offline|timeout|invalid` answers evaluations and practice without the network.
- **Rolling back the code:** revert the branch. The server routes are additive, and the App Store client never calls them.

## Validation

Commands and full results are in PROGRESS.md.

**Automated tests**
- **Swift, player and app:** `cd ios/Packages && swift test --filter "LessonPlayerTests|AppFeatureTests|ArchitectureTests"`, all green.
  - Covers deterministic grading, step transitions and guards, validation, version pinning, legacy mapping, reward idempotency, resume after kill, the switch, and the deletion path.
  - Also covers evaluation failures: invalid output, timeout, offline, a cancel followed by a late result, crisis, and retry.
  - Also covers both lessons played through, and a check that no event field ever carries answer text.
- **Swift, full package suite:** `swift test --parallel` gives 1698 tests, all passing except 4 issues in `LoopbackNetworkTests` (SYN-drop timing). **Verified:** the same 4 fail on a clean `origin/main` worktree on this Mac. It's the macOS 27.2 loopback change that open PR #89 addresses, and it is unrelated to this work.
- **Server:** `npm test` gives 2048 / 2049 passing. The one failure is `widgetCore`'s sync check, which finds a widget copy inside an old, gitignored local desktop build (`desktop/dist/…`, March 2026). CI doesn't have that folder; it's not mine, so I left it in place.
  - The pilot's own server tests pass: 4 for the config probe, and 18 for evaluation and activity (registry, prompt shape, delimiter injection, validation, 422, 404, a free-form task refused, crisis, a hung call returning 504, an upstream error, the kill switch, and the streak plus `lesson_events` rows).
- **iOS app build:** `xcodegen generate && xcodebuild build … -destination 'platform=iOS Simulator,id=<iPhone 16>'` gives BUILD SUCCEEDED.

**Simulator (iPhone 16, iOS 26.4, flag on, stubbed grading and practice)**
- Lesson 3 and Basics 1.1 walked end to end. Both completed through the existing path: the curriculum path showed "Completed", Lesson 4 unlocked, and Basics showed "1 lesson of 18".
- Exercised:
  - wrong answers with specific feedback
  - hints
  - the Basics wrong pick, completing with the answer shown
  - Go deeper staging
  - claim selection
  - claim vs evidence
  - the short response states (Checking…, graded)
  - the practice reply
- **Flag off:** Lesson 3 opens the unchanged legacy lesson.
- **Pin:** started in the player, killed the app, relaunched with the flag off, and the attempt resumed at the same step in the player.
- **Largest accessibility text size:** the step scrolls and nothing is clipped. That required a fix: the header now compacts and the hint moved into the step.
- Several visual bugs were found and fixed during these runs (PROGRESS.md, M2 and M6 notes).

**Not verified here**
- **UI tests can't run on this Mac:** every XCUITest run, including the existing `testBootCompletes`, fails with "The test runner hung before establishing connection", even after a CoreSimulator reset. The three new UI tests compile; they need CI or another Mac.
- **The real model:** done on 2026-11-11 with the founder's $5 budget ($2.20 spent). Details in `EVALS.md`:
  - The Lesson 3 guide gate passes in both flag states, with no regression.
  - The guide now corrects "can't find it, so it's made up" (8/8) and confirms sound plans (4/4).
  - The live tutor answers "Are you a real person?" plainly in every mode (12/12).
  - The evaluator judges 15/15 labelled answers correctly, including an injection attempt.
- **VoiceOver end to end:** labels, values, focus moves and the hint and status words are in the code, but a full screen-reader pass was not run. It is in the manual checklist below.
- **iPad and other device sizes:** not run. Only one simulator is kept booted per the session's limits. The player caps its reading width at 640 pt and scrolls.
- **The Mac app:** it keeps legacy lessons (D4).

## Fresh-context review

A fresh-context review compared the full diff with SPEC.md. Three reviewers each took one lens (limits, grading and state, content and player), and a skeptic re-checked each finding. **Every finding is fixed.**

**Fixed (confirmed by the skeptics):**
1. **A player-only lesson day didn't count toward the streak**, because only `/api/chat` updated it. Fixed with `POST /api/lesson-player/activity`, which updates the server streak as a chat turn does; the client caches it and awards streak milestones.
2. **Learner text could close the `<student_answer>` block in the grading prompt.** Angle brackets in the answer are now neutralized (tested).
3. **`active_seconds` read 0 for a lesson done in one sitting.** Time is now flushed on every action, with idle gaps capped at 2 minutes (tested).
4. **`first_open` counted existing learners updating to this build, and fired after a network call.** It is now written at launch, for new learners only, with `experience: unknown` when the switch isn't known. A learner's arm comes from their first `lesson_start`.
5. **Feedback wasn't announced to VoiceOver, and the primary button lost focus when its label changed.** Feedback is now announced, and the button keeps its identity.
6. **Opening a lesson could overwrite a completed attempt, or a record from a newer build.** Completed attempts now move to a history key, and unreadable records are never replaced (the lesson opens legacy).
7. **Lesson 3 step 3's right claim was by far the longest.** Rebalanced, and the validator now checks claim lengths.
8. **METRICS.md defined finish-step drop-off and the transfer status wrongly.** Both corrected, and `not_graded` was added to the event table.

**Refuted by the skeptics, but changed anyway (cheap and safer):**
- **A revealed answer counted as "assisted".** It is now `notDemonstrated`.
- **A reverted server (404) left the cached flag on.** A 404 from the config route now turns it off.

## Manual checklist (UI that couldn't be run automatically here)

1. **Flag on, Deep dive, Unit 1 Lesson 3** (`-LessonPlayer YES`, real server):
   - Answer step 1 wrong, then right. Feedback should be specific; the hint appears after Try again.
   - Open Why?, Show an example, and Go deeper three times; the stages appear in order.
   - Open Ask Merc, chat, then go Back to the lesson: you should be on the same step.
2. **Short response, real model:**
   - Write a sound answer: Correct and the lesson completes.
   - Write "it's fake because I can't find it": the misconception correction appears.
   - Write nonsense: "Not quite" plus one hint.
   - Turn on Airplane mode and submit: "Not graded yet", the text is kept, and Retry works once you're back online.
3. **Leave mid-lesson** (X), relaunch the app, reopen: same step, same answer.
4. **Server flag off, then relaunch:** a fresh lesson opens legacy, and an unfinished player attempt still opens in the player.
4a. **Streak:** do a player lesson on a day with no chat. The streak chip counts the day.
5. **Basics, new install:** choose "I'm new to AI". `b1_l1` opens in the player. Send the practice message. **Check that Merc's reply to "Are you a real person?" is plain and honest.** Complete the lesson, and check the reply appears as a chat in History.
6. **VoiceOver:**
   - Each step's heading is read first.
   - Options read "Option A: …", plus "Selected" or "Your answer, correct/not correct".
   - Feedback is read with its title ("Correct" / "Not quite" / "Not graded yet").
   - Progress reads "n of m done".
7. **Text size AX5:** every step scrolls, and the primary button stays reachable above the keyboard on the short response.
8. **Reduce Motion:** step changes cross-fade with no slide.
9. **iPad:** the reading column is limited to about 640 pt, centred, and the action bar sits within the safe area.
10. **Settings → Delete my data:** reopening a pilot lesson starts fresh, and the old answer is gone.

## Plan for the rest of the curriculum

Convert in this order, one unit at a time. Each lesson gets a content review, a test suite, and a short student test before its id goes into `PILOT_LESSONS`.

1. **Basics Unit 1** (`b1_l2`, `b1_l3`): reuses the practice step; no new primitives.
2. **Deep dive Unit 1** (`u1_l1`, `u1_l2`):
   - `u1_l1` keeps its tokenizer interactive as an optional depth item, or as a later "interactive" step kind that wraps `LessonInteractives` cards. That is the first new primitive worth building.
   - `u1_l4` (review) needs a multi-part short response with a rubric per part.
3. **Basics Units 2–6:** the four safety lessons (`b2_l3`, `b2_l4`, `b5_l2`, `b5_l3`) put their checks in `mustBeCorrect`.
4. **Deep dive Units 2–3** (bias, AI in society): ethics scenarios need choices that credit defensible alternatives. The model is "explain the tradeoff" feedback plus a short response, not a single right answer.
5. **Deep dive Units 4–8**, then the unit reviews.
6. **Unit tests (mastery):** unchanged until the lessons above are proven. They could later reuse `Grader` and the evaluation endpoint.

## Student testing

- **Who:** about 5–8 students per lesson, through TestFlight builds with the server flag on.
- **What to observe:**
  - Time to the first answer, where they hesitate, whether they open Why? or Go deeper, and whether they read the feedback.
  - Collect the device log for the `lessonPlayer` category (METRICS.md).
- **Ask afterwards:**
  - "What does unverified mean?"
  - "What would you do if you couldn't find a source?"
  - "What was confusing?"
- **Delayed transfer:** 2–7 days later, without reopening the lesson, show each student a new fictional claim with a citation they can't find, for example "Chewing mint gum improves exam scores by 18%". Ask in one sentence what they'd do. Score it with the same rubric as Lesson 3's step 6 (hold off and seek checkable evidence; credit for checking support; flag "missing citation means false"). Record the score, the delay in days, and whether they used the player or the legacy lesson. Report counts, not significance (METRICS.md rules).
- **Compare:** run legacy and player students the same way on the same lessons.

## Decisions for the founder to review

1. **D1, base branch:** `origin/main`, not the stale `feat/cost-cuts` HEAD.
2. **D12, pending vs retry:** a lesson never completes with a short response that is pending or ungraded. The learner keeps the answer and can Retry, Edit, or Finish for now. Lesson 3 therefore can't complete in the player while grading is down. The legacy lesson needs the model for every turn anyway.
3. **D11, legacy threads stay legacy:** a learner who already opened a pilot lesson in the chat keeps it there.
4. **D13, the practice step:** Basics 1.1's objective (a real first message) is met through the existing live tutor. It saves a chat in History, in the chat's current mode. The D13a check passed: every mode answers "Are you a real person?" plainly (EVALS.md).
5. **D7, the Lesson 3 guide's Grading note:** a prompt change to `CURRICULUM_PROMPT`. Its eval gate passed in both flag states, run on the curriculum conversations for budget reasons (EVALS.md).
6. **D4, the Mac keeps legacy lessons** in the pilot.
7. **Measurement:** there is no telemetry pipeline, so events stay on the device. Collecting real numbers needs a pipeline and a privacy review.
8. **D5, feature mapping:**
   - "Deep Dive" (the spec's depth feature) maps to staged "Go deeper" optional depth. In code, "Deep dive" stays the track's name.
   - "Why?" and "Show an example" are authored depth.
   - "Ask Merc" opens the existing chat.
9. **Draft copy for review:**
   - Basics Lesson 1 (below).
   - Lesson 3 (`Lesson_u1_l3.swift`), adapted from the script with all invented material labelled.

### Draft copy: Basics Lesson 1, "What is an AI chatbot?"

1. **Decision.** "You type a question into a chatbot, and an answer appears a few seconds later. Who wrote that answer?"
   - A person at the company, typing fast. Feedback: "It feels like a person, because the words are friendly and quick. But no one is typing back. A computer program wrote it."
   - It was copied from one website. Feedback: "Good guess, but it doesn't copy a page. A computer program writes a new answer each time you ask."
   - **A computer program, word by word.** Feedback: "Yes. A computer program wrote it, one word after another. No one is typing back to you."
   - Why?: "An AI chatbot is a computer program you talk to by typing or speaking. It writes back in everyday words, so it can feel like a person. It isn't one."
2. **"You can't break anything here."** "An AI chatbot is a computer program you talk to by typing or speaking. There are no silly questions. Type in the box, or tap the microphone on your keyboard and talk. Then tap Send."
   - Key idea: "A chatbot is a computer program you talk to. No one is typing back."
3. **Practice (live tutor).** "Now send your first message to a chatbot. Ask Merc whether it's a real person, or ask in your own words."
   - Suggestion: "Are you a real person?"
   - After the reply: "That's it: you sent a message, and a computer program wrote back in everyday words. You just used a chatbot."
   - If it can't send: "Your message couldn't reach Merc right now, so it's saved here. Check that you're online, then tap Retry. You haven't done anything wrong."
4. **"How it writes."** "A chatbot learned from a huge amount of writing. It makes each answer by guessing, word by word, what fits best. It isn't a person, and it isn't a search engine. ChatGPT, Claude, Gemini and Copilot are chatbots. Merc is one too."
   - Key idea: "It writes by guessing what words fit best."
   - Example: "If you type 'The cat sat on the…', a chatbot is very likely to guess 'mat' or 'chair' next. It writes whole answers the same way, one guess at a time."
5. **Postcard rule.** "Here's a safety rule: if you wouldn't write it on a postcard, don't type it into a chatbot. Which message follows it?" Labelled up front: "The card number and password below are made up for practice."
   - **What's a good soup for a cold day?** Feedback: "Yes. A soup question is fine on a postcard. Card numbers and passwords never are, and you can get help without them."
   - My card number is 4000 1234 5678 9010. Feedback: "Never type a card number into a chatbot, even to ask about a charge. You can get good help without it."
   - My password is Rover2024. Is it good? Feedback: "Keep passwords to yourself, even to check them. You can ask 'What makes a strong password?' instead."
6. **Check.** "Last one, and there's no grade. Which is the best description of an AI chatbot?"
   - A person at the company typing answers to you. Feedback: "It can sound like one, but no person is typing. A computer program writes each answer."
   - **A program that writes by guessing what words fit.** Feedback: "That's it. A chatbot is a computer program that writes answers by guessing what words fit best."
   - A big library that looks up the right answer. Feedback: "It doesn't look answers up, and it can be wrong. It writes by guessing what words fit best."
7. **Finish: "You did it".**
   - "You sent your first message to a chatbot, saw that a computer program writes back, and learned the postcard rule."
   - "Try this today: ask a chatbot one thing you've wondered about this week. Next lesson: what chatbots are good at."

Completion: the practice message answered, plus every check answered. A wrong pick still completes (Basics' rule), and the right answer is shown kindly.

## Before and after

`captures/`:
- **Before (flag off):** `before-l3-legacy-intro-flag-off.png`, the unchanged legacy lesson intro.
- **The legacy lesson in use:** this session's recorded clip, `~/Desktop/Mercurius Unit 1 Lesson 3 Clip 2026-11-11/`. It shows the literal `**` key-idea cards and the long chat transcript.
- **After:**
  - Lesson 3: `after-l3-*`
  - Basics 1.1: `after-b1-*`
  - Validation: `validate-a11y-xxxl-*` (largest text size), `validate-flag-off-attempt-stays-pinned.png`
