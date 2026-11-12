# Lesson player pilot — progress

Spec: `docs/lesson-player-pilot/SPEC.md` (saved verbatim from the founder's message, 2026-11-11).
After a compaction, re-read SPEC.md, this file and `git log --oneline origin/main..HEAD` before continuing.

## Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | Ground truth | done (12c90e2) |
| 1 | Lesson data and deterministic core | done (c14bb04) |
| 2 | Player and Lesson 3 (steps 1–5, 7) | done (39b5393) |
| 3 | State and progress | done (84eb442) |
| 4 | Short response and model evaluation | done (b676e59) |
| 5 | Measurement | done (c63bbe2) |
| 6 | Second lesson | done (3f7cb19) |
| 7 | Validation, review, handoff | done |

## Session start (2026-11-11)

- `git status`: clean. The checkout at `~/Desktop/mercurius-chatbot` was on `feat/cost-cuts` (e58b870, 2026-09-24).
- **Deviation from the spec ("create from the current HEAD"), for review:** `feat/cost-cuts` is an ancestor of `origin/main` and 461 commits behind it. Building there would miss everything since September (Basics track, interactives, certificates, all lesson fixes). The branch `pilot/interactive-lesson-player` was created from `origin/main` (b5d1603) instead. It contains HEAD, so nothing is lost.
- Local only: nothing is pushed.

## Ground truth (Milestone 0)

Surveyed by five read-only subagents. Paths are relative to the repo root; package code is under `ios/Packages/`.

**Platforms.** One Node 22 / Express server (`server.js`, `db.js`, `lib/`; SQLite locally, Postgres in production) serves a native SwiftUI iOS/iPadOS app (iOS 17+), a native SwiftUI Mac app (same packages; `AppFeature/Sources/Mac`), a web widget and the marketing site. iOS code is in local SPM packages with an enforced layering test (`ArchitectureTests/Tests/DependencyGraphTests.swift`). The Xcode project is generated from `ios/project.yml`. `mobile/` is a legacy Expo prototype that CLAUDE.md says not to touch.

**Curriculum.**
- Lessons are defined in `CurriculumFeature/Sources/Curriculum.swift` (Deep dive, 8 units; version 1 with an id migration table) and `BasicsCurriculum.swift` (Basics, 18 lessons).
- `Lesson` = id, number, title, objective, starter.
- **Prerequisites are not data.** They come from sequential gating: `ProgressStore.isLessonUnlocked` (ProgressStore.swift:188) says a unit's first lesson is always open and each later lesson needs the previous lesson in its unit completed.
- **The lessons are model-taught.** A lesson opens `CurriculumLessonView` (ChatFeature), which sends a hidden starter tag (`[CURRICULUM: Unit 1, Lesson 3]` or `[BASICS: …]`). The server switches to `CURRICULUM_PROMPT` (server.js:575–850, which holds every lesson's teaching guide) or `lib/basicsGuide.js`. The model teaches, asks checks, and ends with `[LESSON_COMPLETE]` when it judges proficiency.
- **Unit 1 Lesson 3:**
  - id `u1_l3`, "Why AI sounds confident but can be wrong", objective "Understand hallucination and the confidence-accuracy gap." (Curriculum.swift:115).
  - Guide at server.js:634–638: Mata v. Avianca ($5,000 fine), GPT-4 Technical Report calibration, and an exercise with an invented paragraph (identify 2 claims; what would you check; how would you verify; all three from the student).
  - It has no Grading note, so it relies on the generic STEP 4 and "PROFICIENCY SIGNAL — be strict" rules (server.js:603, 839).
  - Prerequisite: `u1_l2` completed.
  - The u1_l3 interactive `citationThatWasnt` exists but ships dark.
- **First lesson a new user enters.** The first-run flow ends on the "Your path" step (`AppFeature/Sources/YourPathStep.swift`). It offers "I'm new to AI: start with the Basics" first, then "Take the Deep dive", then "Just chat instead".
  - Basics opens **`b1_l1` "What is an AI chatbot?"** (objective "You'll send your first message to a chatbot."; guide at `lib/basicsGuide.js:131`; no prerequisites).
  - Completion rule (basicsGuide.js:114): at least one practice message answered, plus the check answered. A wrong pick still completes outside the safety lessons.
  - This is the pilot's second lesson. Deep dive's first lesson is `u1_l1`, which has the tokenizer interactive.
- **Citation wording.** No authored server, prompt or iOS text says an unlocated citation proves a source was made up. The phrase the founder saw ("If I can't find a real paper ... I'd treat it as made up", praised as "solid") is the model's own wording. Nothing in the Lesson 3 guide prevents it. The fix is a Lesson 3 grading note in the guide (Decision D7).

**Rendering and features.**
- Lesson replies use blocks_v1 markers (`lib/blockMarkup.js`). They are parsed on iOS by `ChatFeature/Sources/MessageBlocks.swift` and shown by `BlockCards.swift` (`KeyIdeaCard`, `ExampleCard`, `CheckQuizCard`), routed from `MessageBubbleView.blockView`.
- A quick-check tap sends "I picked B) …" as a user turn. The choice is graded locally for colour only; the model judges the lesson.
- **Literal `**`:** the cause is `Text(text)` with a `String` in `BlockCards.swift` (verbatim; no Markdown parsing). Prose goes through MarkdownUI, so it renders fine. The Mac's own cards already parse inline Markdown (`nightInlineMarkdown`, macOS-only).
- **Composer:** always shown in lessons (`CurriculumLessonView.swift:547`), including during objective checks.
- **Spec feature names mapped to code:**

  | Spec name | In code |
  |---|---|
  | Key-idea cards | `KeyIdeaCard` |
  | Choice cards | `CheckQuizCard` (the `[Q]` block) |
  | Explain more | `ChatViewModel.explainMore()`: a footer chip that sends a hidden "Explain more…" turn with `responseMode = .deep` |
  | **Deep Dive** | **the name of the Deep dive curriculum track (`CurriculumTrack.deepDive`), not a depth feature** |
  | Why? | none |
  | Show an example | none |
  | Ask Merc | none (Mac menu placeholder text only) |
  | Tutor modes | `ChatMode` socratic/debate/discussion, free chat only; lessons are separate (`ChatViewModel.makeLesson`) |

**Persistence and progress.**
- `CurriculumProgressStore` (`CurriculumFeature/Sources/ProgressStore.swift`) keeps everything in UserDefaults through `PreferenceStore`:
  - completed ids
  - `.inProgress` (lessonId → conversation UUID)
  - `.masteredUnits`
  - `.completedAt`
  - `.lastOpened`
  - `.version`
- `markCompleted` / `markUnitMastered` are idempotent.
- Sync: `CurriculumProgressSync` (AppFeature) and `GET`/`PUT /api/progress/:sessionId`. Forward-only, with statuses `completed < mastered` (`lib/schemas.js` `PROGRESS_STATUS_RANK`). In-progress state is never synced.
- Transcripts: SwiftData `ConversationRecord`/`MessageRecord`; lesson threads are tagged curriculum.
- **Completion side effects** (`AppShellView.handleLessonComplete` :665, Mac `MacShellView.handleLessonComplete` :402):
  - certificates (diffed before and after)
  - `progress.markCompleted`
  - last activity
  - review prompt (first completion only)
  - the `explorer` achievement (Deep dive)
  - Live Activity
  - gamification event (off)
- **Mastery** = a unit test passed (≥ 80% multiple choice on the device, plus a defence answer graded by the server model, `lib/unitTestGrader.js`). It is never granted by a lesson.
- Streaks are computed on the server per day with a chat; the client only caches them.
- Certificates: Deep dive = all 8 units mastered; Basics = all 18 lessons completed. Stored on the device only.
- **Deletion:**
  - Settings → `deleteServerDataAndStartOver` calls `DELETE /api/session/:id`, which in one transaction deletes messages, images, reports, usage, lesson_events, curriculum_progress and others.
  - The host `extraReset` (`AppFeature/Sources/SettingsSheet.swift:52`) clears the chat store, progress, certificates, streak, achievements and more.
  - New stored data must join both.
- **Identity:** an anonymous Keychain session id, per device (`NetworkingKit/Sources/SessionIdentity.swift`). No accounts.

**Backend, flags, analytics.**
- Every model call goes through `lib/claudeCall.js` after `gate()` (draining, kill switch, `DAILY_BUDGET_USD` spend cap, quotas; kinds `lesson|chat|helper|image`).
- The bounded-grading precedent is `POST /api/unit-test/grade` (server.js:3022, `lib/unitTestGrader.js`): rubric prompt, answer wrapped as data, JSON parse plus validation, `helper` kind, 400 tokens. It has no explicit timeout and no pending state.
- `ANTHROPIC_MOCK=1` lets tests inject replies (`MOCK_REPLY:` / `MOCK_SAY_B64:`) and failures (`MOCK_SCENARIO=error|slow|hang…`, `MOCK_TIMEOUT_MS`).
- **Flags:**
  - Client: compile-time only (`GamificationFlag.clientEnabled`, `InteractiveSpec.enabled`).
  - Server: env plus a probe endpoint (`GAMIFICATION_ENABLED` and `/api/progression/me`). The runtime kill switch reads env, then a `settings` row, then an admin endpoint.
  - There is no `/api/config`. Turning off any client flag today needs an app release.
- **Analytics:**
  - Server: `lesson_events` (start/turn/complete, written by the chat handler; CHECK-constrained event names), the `usage` ledger, Prometheus, and admin stats (D1/D7 = a user message on day D+N, UTC).
  - Client: none, apart from a local OSLog marker sink for onboarding (`AppFeature/Sources/OnboardingTelemetry.swift`).
  - A lesson that never posts to `/api/chat` is invisible to D1/D7 and to `lesson_events`.

**Build and test** (see "Commands that work here").
- Swift Testing in packages; XCTest in app-hosted tests and UI tests.
- `swift test` from `ios/Packages`. `ArchitectureTests` reads a `manifest.json` fixture that must be regenerated (`swift package dump-package`) whenever Package.swift changes.
- `npm test` (node:test; `tests/support/spawnServer.js` boots a mock server).
- Xcode 26.4. iPhone 16 simulator C65EB7CC… exists.
- Never record snapshots. Derived data goes outside iCloud.

## Implementation plan

1. **Core (M1).** A new leaf SPM target `LessonPlayer`, depending on DesignSystem only and registered as a content module in the architecture test. It holds:
   - the typed lesson schema plus `LessonValidator`
   - deterministic `Grader` (single, multi, claim selection, claim vs evidence)
   - `StepMachine` (explicit select → submit → feedback → continue states, with double-submit guards)
   - `LessonAttempt` (one Codable value)

   No IO in the module: storage, network and telemetry come in through protocols the composition root implements. Swift Testing covers all of it.
2. **Player + Lesson 3 (M2).** SwiftUI `LessonPlayerView` and activity views in the same module, using DesignSystem tokens. Lesson 3 is authored as typed data.
   - Flag (D3): server env `LESSON_PLAYER_ENABLED`, default off, read through an additive probe `GET /api/lesson-player/config`, cached on the device. There is also a DEBUG launch override. `AppShellView` routes `u1_l3` to the player only when the flag is on.
   - The Markdown fix and the citation grading-note correction each get their own commit.
3. **State (M3).** An attempt store (UserDefaults suite, cleared by Settings' delete).
   - Experience assignment is pinned per attempt (a legacy in-progress conversation stays legacy; a player attempt stays player whatever the flag).
   - Content-version pinning.
   - Completion goes through the existing `handleLessonComplete`, guarded by a reward ledger.
   - Separate fields for completion, independent success, assisted success and mastery.
4. **Short response (M4).** An additive `POST /api/lesson-player/evaluate`: `helper` gate, a server-side rubric registry (the endpoint can't be used as a general model proxy), answer passed as data, a strict JSON result `{status, feedback, hint?, flags[]}`, and an explicit timeout. The client has pending, ungraded and fallback states.
5. **Measurement (M5).** A `LessonPlayerEvents` protocol with an OSLog debug sink (no pipeline), plus METRICS.md.
6. **Second lesson (M6).** `b1_l1` in the player, with its copy drafted in HANDOFF.md.
7. **Validation (M7).** Tests, simulator end-to-end runs, a fresh-context review, and HANDOFF.md.

## Decisions

- **D1 (base branch):** `origin/main`, not the stale HEAD. Reason above.
- **D2 (second lesson):** `b1_l1`. The path step lists Basics first ("I'm new to AI"), and the spec asks for "the first beginner lesson a new user actually enters". A new user who picks Deep dive enters `u1_l1` instead; that lesson is outside the pilot.
- **D3 (flag):** there is no remote client flag, and compile-time flags need a release to turn off. Smallest switch that can be reversed without a release: a server env flag (default off) exposed by a read-only probe, AND-ed with a compile-time client allowance. DEBUG builds can force it with `-LessonPlayer YES|NO`. The flag decides only which experience a new attempt gets; an attempt already started keeps its experience.
- **D4 (Mac):** the player is integrated on iPhone and iPad (`AppShellView`). The Mac keeps the legacy lesson in the pilot (`MacShellView` is not routed), to keep the pilot small; listed as a known gap.
- **D5 (feature mapping):** "Why?" and "Show an example" become authored optional depth in the lesson data (expand in place). "Deep Dive" in the spec's sense becomes staged optional depth ("Go deeper", in stages) inside teaching steps; "Deep dive" in code stays the track name. "Ask Merc" opens the existing free chat (Socratic mode, unchanged) in a sheet above the player, so the learner keeps their place. No new mode and no prompt change.
- **D6 (where the rubric lives):** the server holds the authoritative grading rubric per (lesson, step, content version). Without that, a client could send any "task" and use the endpoint as a free model proxy.
- **D7 (citation correction):** add a Unit 1 Lesson 3 "Grading note" to the server guide (an unlocated citation is unverified, not proof of fabrication; a real paper still has to support the claim). This is a prompt change. CLAUDE.md's gate for prompt changes (`scripts/eval-pacing.mjs --runs 3`, both flag states) needs real API spend, which needs the founder's budget approval, so it is pending.

## Commands that work here

- Player core and architecture tests (macOS host, about 1 min cold): `cd ios/Packages && swift test --filter "LessonPlayerTests|ArchitectureTests"`.
  M1 result: `✔ Test run with 43 tests in 8 suites passed` (36 player tests plus 7 architecture tests).
- After any Package.swift change: `cd ios/Packages && swift package dump-package > ArchitectureTests/Tests/Fixtures/manifest.json` (ArchitectureTests reads it).

## Milestone 1 notes

- New SPM target `LessonPlayer` (DesignSystem only). It is registered in `DependencyGraphTests.contentModules`, which adds it to the allow-list; no existing rule was loosened. AppFeature depends on it.
- Files:
  - `LessonPlayer/Sources/Model/` (LessonContent, Activity)
  - `Core/Grading.swift` (Grader, EvaluationParser)
  - `Core/LessonAttempt.swift` (attempt record, codec, relaunch normalisation)
  - `Core/LessonMachine.swift` (state machine)
  - `Core/LessonValidator.swift`
  - `Core/ExperienceResolver.swift` (library, experience assignment, reward ledger)
- **D8 (double advance):** `advance` carries the id of the step it was tapped on. A second Continue tap from a screen the lesson has already left is ignored, so it can't skip the next teaching step.
- **D9 (misses):** after two wrong objective answers the right answer is shown with its explanation, and the learner may continue. That counts as assisted success, never independent. A short response has no such path: only a "meets" grade resolves it. After two "not yet" results the player shows an authored exemplar, and the learner still writes and submits their own answer.
- **D10 (success levels):** completion, independent success, assisted success and "not demonstrated" are separate values on the attempt. A lesson never grants unit mastery; that stays with the unit check.

## Separate fix commits (flag-independent, per the spec)

- 3339ff6: lesson cards render inline Markdown (the cause of the literal `**`).
  - `Text(String)` in `BlockCards.swift` was verbatim; it now goes through `InlineMarkdown`, with the same rules as the Mac's `nightInlineMarkdown`.
  - Shared by legacy lessons and free chat's [KEY]/[EX] cards on iPhone and iPad. Plain text is unchanged (tested); the Mac is untouched.
  - ChatFeatureTests: 464 passed.
- 6a30eca: Unit 1 Lesson 3 server guide, new Grading note (an unlocated citation is unverified, not proven fake; a real paper must still support the claim).
  - `CURRICULUM_PROMPT` only. Prompt tests: 139 passed.
  - **Pending:** the CLAUDE.md eval gate (`scripts/eval-pacing.mjs --runs 3`, both flag states) needs API spend, so it waits for the founder's budget OK (D7).

## Milestone 2 notes

- Lesson 3 content is in `LessonPlayer/Sources/Content/Lesson_u1_l3.swift`; the catalog is in `Content/LessonCatalog.swift`.
- Player:
  - `Player/LessonPlayerModel.swift` drives the attempt, saves after every change, and runs evaluations with a 25 s timeout.
  - `LessonPlayerView`, `ActivityViews`, `ActionBar`, `ShortResponseView` and `PlayerCopy` are the views and their words.
- Flag (D3):
  - Server: `lib/lessonPlayer.js` and `GET /api/lesson-player/config` (env `LESSON_PLAYER_ENABLED`, off by default; optional `LESSON_PLAYER_LESSONS`); tests in `tests/lessonPlayerConfig.test.js`.
  - Client: `NetworkingKit/APIClient+LessonPlayer.swift` and `AppFeature/Sources/LessonPlayer/LessonPlayerFlag.swift` (compile-time allowance AND the cached server answer; DEBUG `-LessonPlayer YES|NO`).
  - The flag is refreshed on shell appear, but never under UI tests.
- Host:
  - `AppShellView.makePlayerLaunch` decides the experience once, on open (`ExperienceResolver`).
  - `playerCover` shows the player; `legacyLessonCover` is the old cover, unchanged.
  - Completion goes through the existing `handleLessonComplete`, behind the reward ledger.
  - Ask Merc opens the existing chat (`ChatView`, same model) in a sheet above the lesson.
- Storage: `LessonAttemptStore` (same preferences suite as progress) is erased by Settings' reset on iPhone and Mac (`SettingsSheet.lessonAttempts`).
- Measurement stub: `LessonPlayerTelemetry`, an OSLog debug sink (M5 documents it).
- Short-response grading: a stub that returns "ungraded" until M4. DEBUG `-LessonPlayerStubGrade meets|not_yet|offline|timeout|invalid` drives the UI with no network.
- **Verified in the iPhone 16 simulator (iOS 26.4), flag on, stubbed grading.** Walked all 7 steps of Lesson 3, including:
  - a wrong answer: specific feedback, then a hint on Try again
  - Go deeper staging
  - the claim selection
  - the excerpt
  - typed transfer: Checking…, then graded
  - the finish, then the path shows Lesson 3 "Completed" and Lesson 4 unlocked

  With the flag off, the same link opens the legacy lesson.
  Captures are in `captures/`: before = `before-*`; after = `after-l3-*`.
- **Fixed during the walkthrough:**
  - The progress line counted the finish step.
  - Feedback didn't scroll into view on a second answer.
  - Answered rows were dimmed below readable contrast (`.disabled` replaced by `.allowsHitTesting`).
  - A new step opened part-way down.
  - The primary button's old and new labels cross-faded.
  - Content showed through the action bar.
- **UI tests:** `ios/MercuriusUITests/LessonPlayerUITests.swift` has three tests (full Lesson 3; ungraded response, leave, resume with text kept; flag off opens legacy). They compile, but **could not run here:** every UI test run, including the existing `MercuriusUITests/testBootCompletes`, fails with "The test runner hung before establishing connection", even after a CoreSimulator reset. That is an environment fault on this Mac (macOS 27.2, Xcode 26.4), not these tests. They should run on CI or a working host.

## Commands (M2)

- `cd ios/Packages && swift test --filter "AppFeatureTests|LessonPlayerTests|ArchitectureTests"`: ✔ 308 tests in 47 suites passed.
- `cd ios && xcodegen generate && xcodebuild build -project Mercurius.xcodeproj -scheme Mercurius -destination 'platform=iOS Simulator,id=C65EB7CC-2FE5-4AA3-90EE-DF4245B4444C' -derivedDataPath /private/tmp/merc-player-dd`: BUILD SUCCEEDED.
  - Don't pass `CODE_SIGNING_ALLOWED=NO` for a build you run: unsigned simulator builds can't use the Keychain, and the app shows "Couldn't start".
- `node --test tests/lessonPlayerConfig.test.js`: 4 passed.

## Milestone 3: state and progress

**What is persisted.** One `LessonAttempt` per lesson, saved after every learner action (`LessonAttemptStore`, the same UserDefaults suite as `CurriculumProgressStore`). It holds:
- attempt id
- content and schema versions
- experience (`player`)
- current step
- per step: draft, submissions (response, grading status, feedback, hint, flags, hints seen), hints shown, reveal, depth opened, phase
- active seconds, resume count
- a completion record with its success level

**Rules, and where each is enforced.**
- **Pinning.** `LessonMachine.init` refuses an attempt on a different content version. `ExperienceResolver` resumes an unfinished attempt on its own version whatever the flag says. The decision is made once, when the lesson opens (`AppShellView.makePlayerLaunch`), so a flag change while the lesson is open does nothing to it.
- **Legacy mapping** (tested):
  - A lesson with a legacy thread stays legacy, in progress or completed (D11).
  - Completed legacy progress is never touched.
  - Player completion uses the same `progress.markCompleted`, so sync, certificates and unlocks behave exactly as before.
- **One-time rewards:** `LessonAttemptStore.shouldRecordCompletion` (ledger key `lesson.complete.<id>`). The app's completion path is idempotent as well (review prompt counts first completions only; Explorer and certificates are idempotent).
- **Resume:**
  - After backgrounding: state is saved continuously, and active time stops on inactive.
  - After closing the app: an evaluation in flight becomes "ungraded (interrupted)" with the text kept, and the player offers Retry.
  - Finish for now: same state.
- **Distinct states:**
  - Completion = `completion != nil`.
  - Success level = `independent`, `assisted` or `notDemonstrated`.
  - Mastery stays the unit check's (`markUnitMastered`); the player never writes it.
- **Identity and sync:** unchanged. Completion is synced through the existing forward-only `completed` status. Attempts and success levels stay on the device, like in-progress legacy lessons. Settings' delete-my-data erases them (tested).
- **Decision D11:** a learner with a legacy thread for a pilot lesson keeps it, and the player never hides their transcript. The cost: learners who opened Lesson 3 before the flag went on won't see the player for that lesson.

Tests:
- `AppFeature/Tests/LessonPlayerHostTests.swift`: store round trip, resume after kill, unreadable records left alone, completion once, reset, flag cache/override, pilot lessons matching the curriculum, Settings reset.
- Plus the core tests from M1.
- Command: `swift test --filter "AppFeatureTests.LessonPlayer|AppFeatureTests.SettingsReset|LessonPlayerTests"`: ✔ 60 tests in 14 suites.

## Milestone 4: short response and model evaluation

**Server: `POST /api/lesson-player/evaluate`** (additive). Code in `server.js` and `lib/lessonPlayerRubrics.js`; schema `LessonPlayerEvaluateRequest` in `lib/schemas.js`.
- **What the client sends:** `{sessionId, lessonId, contentVersion, stepId, rubricId, answer ≤ 600}`, and nothing else (strict schema).
  - The task, the evidence and the rubric come from the server's registry, keyed by all four ids, so the endpoint can't be used as a general model relay.
- **Rails:** the same as the unit-test grader: crisis check, session rate limit, unseen-session refusal, `gate(kind: 'helper')` (kill switch, `DAILY_BUDGET_USD` cap, quotas), and `claudeCall.createMessage` (usage ledger, pricing, alerts). There is also a hard `AbortSignal.timeout` (15 s; `LESSON_PLAYER_EVALUATE_TIMEOUT_MS`).
- **Prompt:** `helperSystem(EVALUATOR_PROMPT)`, which carries the shared safety core. The answer is sent last, between `<student_answer>` markers, as data. The prompt says to accept equivalent reasoning, not repeat the answer, give no lecture after "meets", and return one hint at most.
- **Result:**
  - Strictly validated: `{status: meets|not_yet, feedback ≤ 400, hint (not_yet only) ≤ 240, flags ⊆ rubric}`. Anything off-shape or containing markup is rejected with a 422, never repaired.
  - Crisis → `{crisis: true, message}`, never graded.
  - Timeout → 504; upstream failure → 502; rails → the usual refusals.
  - **Nothing is stored or logged** (no answer text in logs; the usage ledger records only cost and status).
- **Mock:** `lib/anthropicMock.js` answers the evaluator's prompt, so local dev and tests run with no key.

**Client.**
- `APIClient.checkLessonResponse` calls the endpoint.
- `LessonPlayerEvaluation` (AppFeature) maps every error to an `UngradedReason`: offline, timeout, invalidResult, unavailable, interrupted, support.
- `LessonPlayerModel` re-validates any result with `EvaluationParser.check` (rubric flags only), adds a 25 s client timeout, and shows the crisis support sheet (`CrisisSupportView`) for a crisis reply.
- The answer is kept through every state. Retry re-checks the same submission; Edit lets the learner revise.
- Reviewed fallback guidance (authored in the lesson data) is shown whenever there is no grade.

**D12 (pending vs retry, for review): a lesson never completes with a response that is pending or ungraded.**
- **Behaviour:** the learner keeps their answer, can Retry, Edit, or Finish for now, and resumes on the same step with the answer still there. After a relaunch, a check that was in flight becomes "not graded yet (interrupted)", and Retry is offered.
- **Why:** the spec says an ungraded answer never counts as correct. Lesson 3's legacy assessment needs all three parts from the student and a strict proficiency judgement. Its completion unlocks Lesson 4, so completing on an ungraded answer would grant progress for understanding nobody checked.
- **The cost:** while grading is down, Lesson 3 can't complete in the player. The legacy lesson is in the same position, because it needs the model for every turn, so the player is no worse.
- **Escape hatch:** none needed beyond Retry later. The two lessons' objective steps are graded on the device and keep working offline.

Tests:
- `node --test tests/lessonPlayerEvaluate.test.js`: 15 passed. Covers registry lookup, iOS/server rubric ids staying in step, the message shape, validation, the schema refusing a free-form task, meets/not_yet, the captured prompt, flags, invalid output (422), unknown rubric (404), crisis, a hung call (504 in under 5 s), an upstream error (5xx) and the kill switch.
- `swift test --filter "LessonPlayerTests|AppFeatureTests.LessonPlayer"`: 65 passed. Adds model tests for meets, invalid output, an unknown flag, timeout, offline, leaving mid-check with a late result ignored, crisis, and retry then meets; plus the error→reason mapping.

## Milestone 5: measurement

- **No telemetry pipeline existed**, so the pilot adds a thin interface (`LessonEventSink`) with a local OSLog sink (`LessonPlayerTelemetry`, AppFeature). No SDK or network. Definitions are in `METRICS.md`.
- **Events:** `first_open`, `lesson_start`, `lesson_resumed`, `step_viewed`, `answer_submitted`, `feedback_shown`, `explanation_expanded`, `help_used`, `lesson_completed`, `lesson_error`.
- **Fields:** install id (random and local, replaced by delete-my-data), app version, attempt id, lesson id, content version, experience, step id, interaction, attempt index, grading status, help, active seconds.
- **Legacy lessons** log start, resume and complete with `experience=legacy` (logging only).
- **`first_open`** is logged once per install after the switch is fetched (`AppEntryView.task`, which now does the refresh), so it records the experience a new learner would get.
- **Tests:**
  - first_open once per install;
  - a full Lesson 3 run emits every spec event, and no field contains the answer text.
  - `swift test --filter "AppFeatureTests|LessonPlayerTests"`: ✔ 324 tests in 53 suites.
- **For the founder:** collecting these numbers from real users needs a pipeline and a privacy review (out of scope). For now, events are visible only on test devices.

## Milestone 6: second lesson (`b1_l1`)

- **Content:** `LessonPlayer/Sources/Content/Lesson_b1_l1.swift`, a DRAFT for the founder's review (copy listed in HANDOFF.md).
- **Objective:** "You'll send your first message to a chatbot."
- **Assessment preserved** (`lib/basicsGuide.js` COMPLETION): a practice message Merc answered, plus the check answered.
  - A wrong pick still completes. The right answer is shown kindly, and success is recorded as `notDemonstrated`.
  - The rule is `mustBeAnswered` for every activity, with no prerequisites.
- **D13 (new primitive, `.practice`):** the lesson's objective is a real message to a chatbot, which no authored activity can stand in for.
  - The step sends the learner's message through the **existing live tutor**: a fresh `ChatViewModel` on a new conversation, saved in History as their real first chat, in the chat's own mode. No new mode and no prompt change.
  - It is not graded. Its status is `notGraded`, which never counts as correct and never feeds the success level.
  - It resolves only once Merc has replied. Offline or failed sends keep the text and offer Retry, as for a short response.
- **For review (D13a):** the free-chat prompt has no explicit rule for answering "Are you a real person?" plainly. Before turning the flag on, check with the real model that each mode answers it honestly and simply for a beginner (`lib/basicsGuide.js` HONESTY has the wording the Basics lesson uses). This needs a small API budget, so it was not run here.
- **Verified in the simulator** (flag on, stubbed reply):
  - Opened from the Basics track.
  - A wrong first pick showed a kind correction and the right answer, then Continue.
  - Practice: the "Use this" suggestion, Send, the reply, a notice line.
  - The postcard step.
  - The check.
  - The finish showed no success line, correct after the miss.
  - The Basics path now shows "1 lesson of 18" and the lesson "Completed".
  - Captures: `after-b1-*`.
- **Fixed during the walkthrough:**
  - The reveal line repeated the right answer's own "Yes." feedback after a miss. It now reads "The right answer: …".
  - The postcard step's made-up card number and password weren't labelled until the feedback. They now carry a fictional-material label up front.
  - The practice notice no longer claims the reply said what it is (a live reply might not).
- **Attempt dates** now encode at full precision (`.deferredToDate`). Whole seconds made the round-trip test time-dependent.
- **Notes on adding lessons:** `ADDING_LESSONS.md`.
- **Tests:** `BasicsLesson1Tests` (validity, no statistics, practice resolution and retry, wrong pick completes, all-right first time is independent, practice can't be in `mustBeCorrect`) and `LessonPlayerPracticeTests` (reply clean-up, stub).
  - `swift test --filter "LessonPlayerTests|AppFeatureTests"`: ✔ 333 tests in 55 suites (three runs, all green).

## Milestone 7: validation, review, handoff

- **Simulator checks:**
  - At AX5 text size the header compacts and the hint moved into the step (fix committed in 5838291). Everything scrolls and nothing is clipped.
  - Flag switched off mid-attempt: verified after a kill and relaunch. The attempt resumed at the same step in the player.
  - Rebalanced claim step re-captured.
- **Full suites:**
  - `npm test`: 2048 / 2049. The one failure is the environmental, gitignored `desktop/dist` widget copy.
  - `swift test --parallel`: 1698 tests. The only failures are 4 `LoopbackNetworkTests` issues, **verified identical on a clean `origin/main` worktree** (macOS 27.2, PR #89).
- **Fresh-context review:** three lenses plus adversarial verification. Every finding is fixed; HANDOFF.md lists them. The fixes added `POST /api/lesson-player/activity` (streak and `lesson_events`), so the pilot keeps learners' streaks.
- **HANDOFF.md written.**
- **Temporary files:** none in the repo (scratch scripts and the main-branch worktree lived in the session scratchpad and were removed). The simulator is shut down, at default text size.

## Known gaps

- Home's primary button says "Start Lesson 3", not "Continue", for a lesson with an unfinished *player* attempt. `HomeState` reads the legacy in-progress map, and writing the attempt id there would make the resolver treat the lesson as legacy. Tapping it still resumes the attempt at its step.

- The Mac app keeps legacy lessons in the pilot (D4).
- Server admin D1/D7 count only `/api/chat` messages. Player lessons now feed the streak and `lesson_events` (`/api/lesson-player/activity`), but a player-only learner still doesn't appear in admin D1/D7 (METRICS.md).
- The XCUITest runner can't start on this Mac (it fails for existing tests too). The new UI tests compile but haven't run.
- The real model hasn't been called: evaluation quality, the live tutor's answer to "Are you a real person?" (D13a), and the D7 eval gate all need the founder's budget OK.
