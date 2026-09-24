# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Mercurius — an AI-literacy tutor for high-school students (Claude-backed, Socratic-first). One Node/Express server serves three clients: an embeddable vanilla-JS web widget, a native SwiftUI iOS app (`ios/`, the primary surface — shipped on the App Store), and static marketing/club sites. `mobile/` is a legacy Expo prototype — do not touch it.

## Commands

### Server (repo root)
Standard npm scripts (see `package.json`). `npm run dev` needs a `.env` with `ANTHROPIC_API_KEY`.

### iOS — SPM packages (fast loop, runs on macOS host)
Standard SPM commands from `ios/Packages`. `swift test` includes the architecture rules.

### iOS — app build/tests (simulator)
```bash
cd ios
xcodegen generate                    # ALWAYS regenerate before xcodebuild — see below
xcodebuild build -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/dd
xcodebuild test -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MercuriusUITests/MercuriusUITests/testBootCompletes   # single UI test
```

### iOS — release tooling (`ios/scripts/`)
- `provision.sh` — bootstraps the Apple Distribution cert + BOTH App Store profiles (app + `MercuriusWidgets` appex) via the ASC API. Credentials in `~/.appstoreconnect/`; dedicated keychain `mercurius-codesign.keychain-db`.
- `release.sh` — bump build number → xcodegen → archive → export → altool upload. `--no-bump` / `--no-upload` flags.
- `screenshots.sh` — App Store screenshots via the `AppStoreScreenshots` UI test on iPhone 6.5" + iPad 13" sims.

CI (`.github/workflows/`): `server.yml` runs `npm test` on Node 20/22; `ios.yml` runs `swift test` on macOS plus `xcodebuild test` on a simulator. CI regenerates the Xcode project with xcodegen — anything not in `project.yml` does not exist on CI.

## Critical: the Xcode project is generated

`ios/Mercurius.xcodeproj` is **gitignored** and produced by `xcodegen generate` from `ios/project.yml`. The app target's Info.plist is also written by xcodegen from the `info.properties` block. Never hand-edit the pbxproj or the app Info.plist — the next generate silently reverts it. New targets need the repo's xattr-strip `postBuildScripts` phase (see below).

## Architecture

### Server (`server.js` + `db.js` + `lib/`)
A single Express app. `server.js` holds the routes and the Claude streaming logic (SSE); `db.js` is a guarded better-sqlite3/Postgres layer; `lib/` holds extracted pure modules (prompt assembly in `unifiedPrompt.js`, gamification, image validation/store, unit-test grader, rate limiter). System prompts live in `prompts/mercurius-v2.md` and per-mode instructions in `lib/unifiedPrompt.js`.

**Every model call goes through `lib/claudeCall.js`** (`createMessage` / `streamMessage`) — never the SDK directly. It is the one place that settles usage exactly once per call (including aborted streams), prices it (`lib/pricing.js`), feeds the dollar budget (`lib/spendCap.js`, `DAILY_BUDGET_USD`), the per-session/per-IP daily quotas (`lib/quotas.js`), Prometheus, the `usage` ledger, and Discord alerts (`lib/alerts.js`). Every model route runs `gate(req, res, { kind })` first (draining → kill switch → budget → quotas → in-flight caps). `ANTHROPIC_MOCK=1` swaps in `lib/anthropicMock.js` so the server can be integration-tested with no key (refused when `NODE_ENV=production`). There is no per-student memory profile any more — do not reintroduce one.

**Trust + ops rails.** Content reports (`POST /api/report`, reason + preceding user turn + context; `REPORT_IP_PER_MIN` per IP, 60 by default; silently dropped for a session the server has never seen) land in an admin review queue (`GET /api/admin/reports`, `POST /api/admin/reports/:id/resolve`) and page Discord via `lib/reportWebhook.js` with metadata only — never student or model text — under one throttled key. Lesson lifecycle rows (`lesson_events`: one row per answered turn, the opener being `start`; `complete` once per attempt) are written from the chat handler after the reply; `GET /api/admin/stats?days=7` is the founder's weekly numbers (DAU/WAU, lessons, cost, D1/D7) plus live rails state. `lib/scheduler.js` runs in-process (one replica, no cron): a daily Discord digest (one `getAdminStats({ days: 7 })` through `digestStatsFromAdminStats`, headlining the last complete UTC day) and the retention sweep (`*_RETENTION_*` env; reports are kept 180 days, open or resolved; `curriculum_progress` is never purged). Off under `NODE_ENV=test`.

**Prompt assembly is cache-shaped.** Every model call sends one byte-stable static system block (`cache_control: ephemeral`, composed once via `lib/systemBlocks.js`: mode prompt + source library + club knowledge for `club_v1` clients only + the shared `lib/safetyCore.js` block LAST) plus a small dynamic block (runtime context, widget meeting/blog material, the "explain more" nudge). Anything per-request goes in the dynamic block — one byte of drift in a static prefix is a full cache miss. The conversation is the client's own thread (lesson threads normalized by `lib/curriculumTag.js`), never a replay of the session's database history. Prompt changes must pass `scripts/eval-pacing.mjs --runs 3` in BOTH `USE_UNIFIED_PROMPT` states (start the eval server with `EVAL_EXPOSE_USAGE=1 IP_DAILY_NEW_SESSIONS=1000`).

**Server↔client contract markers** — the server embeds control tags in the streamed reply which every client must strip and act on: `[LESSON_COMPLETE]` (server judged proficiency; iOS flips lesson state, widget advances) and per-turn `[CURRICULUM]` tagging. If you touch these, update **all three**: `server.js`, iOS `ChatViewModel`/`NetworkingKit`, and the web widget(s).

**Progress sync** — `GET`/`PUT /api/progress/:sessionId` mirror the iOS `CurriculumProgressStore` in `curriculum_progress` (lesson `uN_lM` → `completed`, unit `unit_N` → `mastered`; in-progress lessons stay on-device) and merge **forward-only** (`PROGRESS_STATUS_RANK` in `lib/schemas.js`: `completed < mastered`, never a downgrade or delete), with the chat handler's own `[LESSON_COMPLETE]` judgement written server-side as belt and braces.

**Two near-duplicate web widgets**: `public/widget.js` and `mayo-site/widget.js` (plus matching CSS). Feature changes must be applied to both or they drift. The club site actually deploys from a separate repo (`mayo-ai-literacy-club`) — the copy here is the working source.

### iOS (`ios/Packages` — local SPM packages, thin app shell)
Almost all code lives in local packages; the app target (`ios/Mercurius/`) is a shell. Layering is **enforced by a test** (`ArchitectureTests/Tests/DependencyGraphTests.swift`):

- **Infra**: `DesignSystem` (tokens + the procedural Merc mascot: `Merc`/`MercState`/`MercMascot`), `NetworkingKit` (APIClient, SSE streaming, progress sync, SessionIdentity/Keychain), `PersistenceKit` (SwiftData chat store, UserDefaults stores: streak, reminders, last activity, review-prompt counter).
- **Features**: `ChatFeature`, `CurriculumFeature`, `SettingsFeature` — may depend on infra, NOT on each other (one reviewed exception: Curriculum → Settings). `EngagementFeature` (streaks/achievements/reminders UI, notification art, `NotificationRouter`) is likewise composed only at the root.
- **Composition root**: `AppFeature` (`AppShellView` wires everything — e.g. it injects `GamifiedTopBar` into the curriculum path's `topBar` slot and `StreakChip` into the chat header, because the features can't import EngagementFeature themselves). `AppEnvironment` owns the app-wide stores, including the one `CurriculumProgressStore`.
- **`MercuriusActivity`**: the Live Activity (attributes, Aurora theme, lock card, Dynamic Island) — shared by the app AND the `MercuriusWidgets` appex so both use the same types. All ActivityKit code is `#if os(iOS)` (NOT `canImport` — the types import on macOS but are unavailable, and the SPM test host compiles on macOS).
- **App target**: `MercuriusApp.swift` only builds `AppEnvironment` and installs `NotificationRouter.shared` as the notification-center delegate in its `@UIApplicationDelegateAdaptor` (it must be set before launch finishes, or a cold-launch reminder tap is lost). A tap on a reminder opens `mercurius://lesson/<id>`.

Identity is an anonymous session id in the Keychain (survives reinstalls); there are no user accounts.

**Gamification is double-gated**: `NetworkingKit/GamificationFlag.clientEnabled` (compile-time) AND a server flag. UI must degrade gracefully when disabled — never render zeros.

**DEBUG launch arguments** (see `RootView`/`AppEntryView`): `-EnterShell` / `-EnterShellCurriculum` skip the Home doorman; `-LiveActivityPreview` starts a demo Live Activity; `-LiveActivityGallery` (+`-LiveActivityGalleryBottom`) renders every activity phase in-app; `-NotifPreview` fires demo notification banners; `-ChatPreview`, `-LessonPreview` (+`-LessonSkipIntro`), `-MercPreview`; `-ForceCelebrate` shows the lesson-complete overlay (and its share card) inside a lesson without a real completion, so it never counts toward progress or the review prompt. First-run gate (2.3.0): `-consentVersion N` sets the consent flag through the UserDefaults argument domain (`0` shows the gate, `1` = `ConsentGate.currentVersion` bypasses it — the UI tests pass `1` by default; pair with `-hasSeenOnboarding NO` for the full first-run flow); `-ResetConsent` clears the persisted consent so the gate shows again; `-GateStep <step>` opens the flow directly at one screen (`meet`, `age`, `underThirteen`, `disclosure`, `paused`, `limits`, `path`). Use these for screenshot verification — there is no CLI way to tap through the UI. `-UITests` (passed by every XCUITest) gives lesson progress, last activity and the Home reminder card private UserDefaults suites that are wiped at each launch, so each test starts on Home at Lesson 1; `-SeedDemoChat` loads a 50-message chat for App Store screenshots.

## Known build traps (all recur)

- **iCloud " 2" duplicate files**: the repo lives on an iCloud-synced Desktop, which spawns byte-identical `Foo 2.swift` copies. Any inside a package `Sources/` breaks clean builds with redeclaration errors. Delete them on sight (they're always untracked; verify with `git status`).
- **Codesign xattr failures** ("resource fork, Finder information, or similar detritus not allowed"): every target carries a "Strip extended attributes" script phase in `project.yml`, but the race still intermittently fails builds. Remedy: retry the build (loop `for i in 1 2 3`); if persistent, `rm -rf` the built .app and rebuild.
- **Stale module cache**: "cannot find type X in scope" for types that clearly exist means a corrupted/stale DerivedData module cache. `rm -rf` the derived data in use (`ios/build/dd` or `~/Library/Developer/Xcode/DerivedData/Mercurius-*`).
- **xcodebuild hangs at invocation** (no output for minutes): CoreSimulator is wedged. `pkill -9 xcodebuild XCBBuildService`, `launchctl remove com.apple.CoreSimulator.CoreSimulatorService`, reboot the sim, retry.
- **Snapshot reference recording is user-owned**: never launch snapshot record runs; defer (re)recording to the user and verify UI via simulator screenshots instead.

## Verifying UI changes

Build → `xcrun simctl install/launch` with a DEBUG launch arg → `xcrun simctl io <udid> screenshot` → inspect the PNG (crop/zoom/pixel-measure with Python + PIL for precise claims). Live Activities survive app termination, so terminate the app to photograph the Dynamic Island. UI tests anchor on the Home "Chat with Merc" button, the "Debate" mode pill, the "Settings"/"Home" header buttons, the Chat/History/Curriculum tab labels, the lesson intro's "Continue. Start the lesson." button, and the `onboarding.*` / `settings.*` accessibility identifiers — keep those if the UI around them changes.
