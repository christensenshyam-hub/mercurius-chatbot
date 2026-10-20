# Step 04: full verification

Branch `feat/mac-app-2026-10` (worktree `.claude/worktrees/mac-app`), on top of `fix/ios-student-2026-10` (PR #43). Not pushed, no PR. Run on 2026-10-20 with Xcode 26.4 (Swift 6.3) on macOS 26.3.

## Result

| Check | Result |
|---|---|
| Branch hygiene | Clean. No stray files (details below). |
| `swift test`, every package, empty scratch path | **994 / 994** in 147 suites, ArchitectureTests included. Run twice from an empty `/private/tmp/merc-mac-spm`, before and after this step's one commit. |
| iOS Simulator build | Succeeded. |
| iOS `xcodebuild test`, CI's flags, "Audit 16PM" | **31 / 31** (6 unit, 25 UI), no retries needed. Run twice, before and after this step's commit. |
| macOS Debug build | Succeeded, no compiler warnings. |
| macOS Release build, unsigned, universal | Succeeded, `x86_64 arm64`. The DEBUG harness and the DEBUG launch flags aren't in it. `-UITests` is (finding 1). |
| macOS tests | The `MercuriusMac` scheme has no test action. The Mac's tests are package tests and pass inside `swift test`. |
| `mac-bundle-check.sh` | Passes for both builds. |
| Screenshots | **Not taken.** The screen was locked for the whole run, so every capture came back black. `shots/verify/INDEX.md` lists the set and the commands. |
| No network before consent | **Holds.** Shown by reading the code and by five launches with fresh containers (below). |

This step changed one thing, in `efc17bd`: a DEBUG-only launch flag, `-ChatPreviewMode debate|discussion`, so the harness can show the chat in each mode. The harness had no way to switch modes, and it can't click. Nothing needed a build or test fix.

## 1. Branch hygiene

`git log fix/ios-student-2026-10..HEAD --stat`, after `efc17bd` and before this notes commit: 19 commits, 164 files, +7,302 / −368.

- **No iCloud duplicates.** No `* 2*` files anywhere in the worktree, tracked or untracked.
- **No build output.** No DerivedData, `.build`, `build/`, `.xcodeproj`, `xcuserdata`, `.xcresult` or `.DS_Store` in the diff. `git status --ignored` shows only the generated `ios/Mercurius.xcodeproj/` and `ios/Packages/Package.resolved`, both ignored.
- **Images.** Every image outside `docs/mac-app/shots/` is one of the ten Mac app icon PNGs (`ios/MercuriusMac/Resources/MacAssets.xcassets/MacAppIcon.appiconset/`). Those belong there. `shots/01` is 4.4 MB and `shots/02` is 15 MB.
- **Trailers.** All 19 commits end with the `Co-Authored-By: Claude Opus 5.5` trailer.
- **Tracked plists.** `ios/MercuriusMac/Info.plist` and `MercuriusMac.entitlements` are tracked, which is expected. xcodegen writes both from `project.yml`, the same way it writes the iOS app's.

## 2. `swift test`

`cd ios/Packages && swift test --scratch-path /private/tmp/merc-mac-spm`, run after `rm -rf` of that path:

- **994 tests in 147 suites pass.** That includes "Architecture — package dependency graph". The Mac work stays inside AppFeature and the feature packages, so the pinned graph is unchanged.
- **Mac test files.** About 69 tests are in Mac-specific files:
  - `MacShellModelTests` 13
  - `MacSidebarTests` 11
  - `MacSnapshotOptionsTests` 17 (includes the script-reading tests)
  - `MacChatSupportTests` 9
  - `ComposerSendRulesTests` 8
  - `MacReleaseConfigTests` 7
  - `SettingsResetTests` 4
- **Where they run.** The ones behind `#if os(macOS)` compile and run only on a Mac host, which is what CI's `spm` job uses.
- **Warnings.** None in package `Sources/`. The test build prints Swift 6 capture warnings in `NetworkingKit/Tests/APIClientEndToEndTests.swift`. That file is unchanged by this branch.

## 3. Xcode builds and tests

`xcodegen generate` first. All derived data goes to `/private/tmp/merc-mac-dd`, which I emptied first.

**iOS**
- **Build.** `xcodebuild build -scheme Mercurius -destination 'platform=iOS Simulator,id=04DB5F67-…'` succeeded.
- **Test command.** `xcodebuild test` with exactly CI's flags:
  - skips `ViewSnapshotTests`, `PerformanceTests` and `AppStoreScreenshots`;
  - `-retry-tests-on-failure -test-iterations 3 -test-repetition-relaunch-enabled YES`;
  - runs on "Audit 16PM" (iPhone 16 Pro Max, iOS 26.4).
- **Result: 31 / 31 passed, and none needed a retry.**
  - Unit (6): the three `ReplyTextScaleTests`, the launch smoke test and the two Live Activity state tests.
  - UI (25): every `MercuriusUITests` test, including:
    - all the gate flows (first run, at the largest text size, landing in the first lesson);
    - existing install, under-13, Not now, the interrupted first run;
    - the mode pills and their description sheets, the header Home and Settings buttons;
    - Settings, the curriculum, the tab bar, the starter prompts.
  - `testExistingInstallSeesGateOnceThenHome`, which step 01 saw fail once, passed both times.
- **Snapshots.** No snapshot record run, and no snapshot tests. CI skips them too.

**macOS**
- **Debug.** `MercuriusMac`, `-configuration Debug -destination 'platform=macOS'`, signed (Apple Development). Succeeded with no compiler warnings. The only log line is an `appintentsmetadataprocessor` note that there is no AppIntents dependency.
- **Release.** `-configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. Succeeded. `lipo -archs` gives `x86_64 arm64`, and the bundle id is `com.mayoailiteracy.mercurius.native`.
- **The DEBUG-only code is absent from Release.** Each row counts how many times the string occurs in the binary (`strings -a`):

  | String | Release | Debug |
  |---|---|---|
  | `MacSnapshot` (harness, options, logs) | 0 | 42 |
  | `CGWindowListCreateImage` | 0 | 1 |
  | `MacOpenWindow`, `MacSnapshotType`, `MacDebugWindows` | 0 | ≥1 |
  | `-EnterShell`, `-ChatPreview`, `-LessonReplay`, `-GateStep`, `-ForceCelebrate`, `-UnitTestCrisisPreview`, `-ResetConsent` | 0 | ≥1 |
  | `-UseLocalServer`, `-EphemeralSession`, `EphemeralKeychain` | 0 | ≥1 |
  | `-UITests`, `-SeedDemoChat` | **7, 0** | 1, 1 |

  `-UITests` is still in Release. That's older iOS code, and finding 1 below explains why it matters on a Mac. `http://localhost:3000` is in Release as the `.local` environment. Only the DEBUG `-UseLocalServer` flag selects it.
- **Bundle checks.** `mac-bundle-check.sh` passes for both builds:
  - both: version 2.3.0 (16), macOS 14.0 minimum, Education category, no non-exempt encryption, no arbitrary loads, the `mercurius` scheme, the icon, the privacy manifest;
  - Debug: the sandbox entitlement;
  - Release: both architectures.
- **macOS tests.** `xcodebuild test -scheme MercuriusMac` exits 66: "Scheme MercuriusMac is not currently configured for the test action". As designed in step 03, the Mac's tests are the package tests in section 2.

**Still unproven:** CI's Xcode 16.2 / Swift 6.0 / macOS 15 SDK compiling the app target. Only Xcode 26.4 is installed here, and the branch isn't pushed. The two `#available(iOS 18.0, macOS 15.0, *)` checks in `ChatView.swift` predate this branch, and the branch adds no availability checks.

## 4. Screenshots

**None taken.** The Mac's screen was locked from the first capture (00:47) to the end of the run (01:28). `ioreg` showed `CGSSessionScreenIsLocked` = true throughout.

- **What locking does.** While the screen is locked, the window server draws nothing for the window, as step 03 also found. A test capture of `today` came back all black, at 2306 × 1442 px instead of 2560 × 1600.
- **What I tried.** I sent one desktop notification asking for an unlock (the push to the phone didn't go out: Remote Control was off). A background watcher then waited 35 minutes to start the full set if the screen unlocked. It never did.
- **Nothing committed.** No blank pictures are committed. `shots/02/` is still the latest set of real pictures.

**Ready to run.** The set the brief asks for is scripted and listed in `shots/verify/INDEX.md`: every main state in light and dark at 1280 × 800 and at 860 × 600; Settings and Help in light and dark. Running it on an unlocked Mac takes about 12 minutes. That set includes:

- the gate;
- Today and the path;
- the lesson and lesson complete;
- the chat in each mode;
- crisis support;
- the three Settings tabs.

**New in `efc17bd`: the chat in each mode.**
- **The flag.** `-ChatPreviewMode debate|discussion` (DEBUG) switches modes through the real path: `MacShellModel.requestMode`, then the chat's mode request, then `ChatViewModel.switchMode`. The toolbar picker and ⌘2/⌘3 use the same path.
- **The shots.**
  - `chat-mode-intro`: the one-time Debate description sheet. It's in the default set.
  - `chat-debate` and `chat-discussion`: these switch through `POST /api/mode`, so they need a local server on `:3000` and stay out of the default set.
- **Checked in this run:**
  - `chat-debate` and `chat-discussion` sent `POST /api/mode` with `debate` and `discussion` to the local logging server;
  - `chat-mode-intro` sent none, because the description sheet comes first;
  - the script tests (every flag has a value) still pass.

## 5. No network call before consent

### Code reading

All traffic goes through `APIClient`: `urlSession.data(for:)` in `APIClient.swift`, and the SSE session in `APIClient+Chat.swift`. Nothing else in the packages or the Mac target opens a connection. The links to trymercurius.com open in the browser, and only when clicked. Every network method's caller on the Mac, and what holds it back until consent:

| Call | Caller on the Mac | Before consent |
|---|---|---|
| `fetchProgress` / `putProgress` | `MacShellView`: `.task(id: isGated)` → `progressSync.pullOnLaunch()`; `onChange(revision)` → `pushSoon()` | Both are guarded by `!isGated`, and `isGated` is `gate != nil`. |
| `sessionStreak` | `AppEntryView`: `.task(id: showsGate)` and `onChange(hasEnteredApp)` → `seedStreakIfNeeded()` | Both guarded by `!showsGate`. On iOS, `RootView.holdLaunchScreen` fetches too, but only when the gate won't show, and that path isn't compiled for the Mac (the Mac's `bootstrap()` only reads the session ID from the Keychain). |
| `streamChat`, `changeMode`, `uploadImage`, `reportResponse`, `generateQuiz` | `ChatViewModel`, `QuizViewModel` | Need the chat or a lesson on screen. While gated the detail column is the gate. The sidebar is hidden and disabled. Every menu command is `.disabled(shell.isGated)`, and `MacShellModel`'s entry points (`requestMode`, `newChat`, `show…`, `open…`) return early. `ChatViewModel.init` only reads the local chat store. |
| `gradeUnitDefense` | `MacShellView.unitTestView` | Only past the gate. |
| `progression` / `recordProgressionEvent` | `GamificationStore` | Configured in the past-the-gate task, and the client flag is off as well. |
| `deleteSession` | `SettingsViewModel` (Settings window) | `MacSettingsView` shows a placeholder until consent is on record. |
| A reminder or `mercurius://lesson/…` link | `NotificationRouter` → `pendingLessonId` → `presentPendingLesson()` | Guarded by `!isGated`. Reminders are also cancelled while consent isn't current. |
| The onboarding flow itself | `OnboardingFlow` / `OnboardingSteps` | No server calls. The privacy policy is a `Link`. |

### At run time

**Setup**
- **App copy.** The Debug app, copied and given a new bundle ID for each run (`com.mayoailiteracy.mercurius.native.macverify1` … `5`), signed ad hoc with the app's own entitlements, sandbox included. So each run started in a container that didn't exist before: no consent, no onboarding, no chats.
- **Session ID.** `-EphemeralSession YES` keeps it in memory, so no Keychain item was read or written. No `-UITests`, so the progress sync was live.
- **Watching for traffic.**
  - A local logging server on `:3000`, IPv4 and IPv6, that records every request. It answers `POST /api/mode` and returns 404 for everything else.
  - `log stream` on the app's `com.apple.network` and `com.apple.CFNetwork` logs. A URLSession request logs `Task <…> resuming` and `nw_connection_create`.
  - `lsof -i` sampled every 0.2 s. Too coarse for short requests: it also missed the control run's two.

| Run | Arguments | Requests to the server | URLSession tasks / connections |
|---|---|---|---|
| Fresh first run, local server, 20 s | `-UseLocalServer YES` | **0** | **0 / 0** |
| Fresh first run, **production URL**, 20 s | (none) | n/a | **0 / 0** |
| Existing install after withdrawal (gate only), 15 s | `-UseLocalServer YES -hasSeenOnboarding YES` | **0** | **0 / 0** |
| Settings window opened on the gate, 12 s | `-UseLocalServer YES -MacOpenWindow settings` | **0** | **0 / 0**. The window was 420 × 272 pt, the placeholder's size. |
| **Control:** past the gate, 12 s | `-UseLocalServer YES -consentVersion 1 -hasSeenOnboarding YES -EnterShell YES` | **2**, within a second of launch: `GET /api/session/<id>` (streak) and `GET /api/progress/<id>` | 2 tasks resumed, connections to `:3000` |

**What this shows**
- **The gate showed in the gated runs.** The screen was locked, so the pictures from these runs are blank. The control dump shows the gate anyway: the sidebar's list was hidden in every gated run and visible in the control.
- **Before consent the app only created its `URLSession` and started the network-path monitor.** Neither sends anything.
- **The setup does catch traffic.** The control run proves the watch would have seen requests.

**Leftovers.** The runs left five small containers, `~/Library/Containers/com.mayoailiteracy.mercurius.native.macverify1` … `5`. I didn't delete them, because macOS can ask for permission when another app's container is touched. Delete them in Finder or with `rm -rf` when convenient.

**How the app identifies itself (server question).** The control run's requests carried only `User-Agent: Mercurius/16 CFNetwork/3860.400.51 Darwin/25.3.0` and `x-trace-id`. An iPhone sends the same shape. The recommendation stands: an additive `X-Mercurius-Client: macos/2.3.0 (16)` header (and `ios/…`), not a body field. Some routes' `.strict()` zod schemas reject unknown fields with a 400. It isn't added here, and no server code was changed.

## Findings for the founder (not fixed here: this step fixes only build and test breakages)

> **Step 05 fixed findings 1 and 2** (`05-review-fixes.md`): `-UITests`, `-KeepAgeBlock` and `-SeedDemoChat` are DEBUG-only, and the harness and `mac-snapshots.sh` reject a blank, wrong-sized or (activated) inactive picture. It also found that a locked screen draws the window after all while the display is kept awake.

1. **On a Mac, launch arguments reach a Release build. Low severity.** On iOS, nobody can pass launch arguments to an App Store app. On a Mac anyone can, for example `open -a Mercurius --args …`, and the Release build honours two kinds:
   - **Argument values for any defaults key.** `-consentVersion 1 -hasSeenOnboarding YES` skips the whole consent and age gate. This is how the harness and the UI tests skip it, and it's Foundation behaviour, not DEBUG code.
   - **`-UITests YES`.** It isn't inside `#if DEBUG` (`AppEnvironment.makeDefaults`). It moves the under-13 block into a defaults suite that is wiped at every launch, so the 7-day cool-off ends on the next launch. It also makes chats in-memory and turns off progress sync.

   A student who does this could equally lie in the age picker, and a Mac user can edit the app's preferences file anyway. So this is defence in depth, not a hole the iPhone lacks. **Possible hardening:** put `-UITests` / `-SeedDemoChat` handling under `#if DEBUG`, and have Release builds read the consent, onboarding and age-block keys without the argument domain. I proved this by reading the code. I didn't run the Release build: unsigned, it isn't sandboxed and would use the real bundle ID's preferences and Keychain.

2. **`mac-snapshots.sh` accepts a blank picture. Low severity.** With the screen locked the harness wrote all-black 2306 × 1442 PNGs, and the script said `ok`. The store script rejects them, because their size is wrong. CI's `mac` smoke test uses `mac-snapshots.sh`, so it proves the app launches, makes a window and quits, but not that anything was drawn. **Possible fix:** fail a shot whose pixel size isn't the content size × the window's scale, or whose pixels are all one colour.

3. **Still open from earlier steps (unchanged):**
   - the `X-Mercurius-Client` header;
   - the Mac wording of the network errors ("try cellular data") and of the consent screen's Settings path;
   - the review prompt and window restoration on the Mac;
   - a text-size control;
   - no Mac UI-test target;
   - cross-device sync, a product gap by design;
   - the Debug-only `.macdev` bundle ID decision;
   - the iPad-on-Mac Keychain question in `PLAN.md`.

## Files

- `docs/mac-app/VERIFY.md` (this file), `docs/mac-app/shots/verify/INDEX.md`.
- `ios/Packages/AppFeature/Sources/Mac/MacShellView.swift`, `ios/scripts/mac-snapshots.sh` (`efc17bd`).
