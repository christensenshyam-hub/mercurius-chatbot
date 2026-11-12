# Lesson player pilot — progress

Spec: `docs/lesson-player-pilot/SPEC.md` (saved verbatim from the founder's message, 2026-11-11).
After a compaction, re-read SPEC.md, this file and `git log --oneline origin/main..HEAD` before continuing.

## Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | Ground truth | done (12c90e2) |
| 1 | Lesson data and deterministic core | done |
| 2 | Player and Lesson 3 (steps 1–5, 7) | not started |
| 3 | State and progress | not started |
| 4 | Short response and model evaluation | not started |
| 5 | Measurement | not started |
| 6 | Second lesson | not started |
| 7 | Validation, review, handoff | not started |

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

## Known gaps

- The Mac app keeps legacy lessons in the pilot (D4).
- Server D1/D7 and `lesson_events` only see `/api/chat` traffic, so player-only learners are invisible to them (addressed in M5 / METRICS.md).
