# Night Studio on the Mac: verification

**Branch:** `feat/mac-night-studio`, stacked on `feat/mac-app-2026-10` (PR #47, `1466d51`), which is stacked on PR #43.
**Verified:** `b0214e0`, the end of step 03. Not pushed.
**Setup:** 2026-10-20, Xcode 26.4 (17E192), Swift 6.3, macOS 26.3, the "Audit 16PM" simulator (iPhone 16 Pro Max, iOS 26.4).

Nothing broke, so this step changed no code. Its commit adds only this note, `shots/verify/` and `compare/`.

## Results

| Check | Result |
|---|---|
| 1. Commits and files since the base | 14 commits. Every file is Night Studio code, its tests, its tools or its docs. No stray files, iCloud duplicates, build output, `.pbxproj` or `Info.plist`. Nothing outside `ios/` and `docs/mac-night-studio/` |
| 2. `swift test`, all packages, empty scratch path | **1128 tests in 168 suites passed**, 0 failed. The only warnings are in two older test files this branch doesn't touch |
| 3a. iOS snapshot comparison, recording forced off | **Identical to the base:** the same 11 pass and 12 already stale, and the same pixel hash for all 12 stale renders. `__Snapshots__` unchanged |
| 3b. iOS build and test suite with CI's flags, on Audit 16PM | `xcodegen`, then BUILD SUCCEEDED, then **TEST SUCCEEDED**: 3 XCTest unit tests, 3 Swift Testing tests, 25 UI tests, 0 failures, no retries. A clean rebuild of the iOS app also succeeded (§3.2) |
| 3c. The iOS view of every shared file | **0 changed lines that iOS compiles**, by two different methods. The only unguarded diff lines are comments, blank lines, `#if` lines and 3 closing braces that git aligned differently (§3.3) |
| 4. Mac Debug build | BUILD SUCCEEDED, incremental and again from clean (449 Swift compile steps). The only warning is the usual `appintentsmetadataprocessor` note |
| 4. Mac Release build, unsigned and universal (CI's command) | BUILD SUCCEEDED for `x86_64 arm64`. `mac-bundle-check.sh` passes for Release and Debug. No DEBUG harness code or demo text in the Release binary |
| CI compatibility | `ci-compat-lint.py`: 0 findings. `ci-probe/run.sh`: every check ok. All 5 macOS 26 `#available` checks sit inside `#if compiler(>=6.2)`. No Swift 6.1+ or 6.2-only syntax. The deployment target is macOS 14, so the local build already enforces macOS 15 availability |
| Safety: no network before consent (run-time) | **0 requests** to a logging server in each of three gated runs: a fresh first run, the consent step, and Settings opened on the gate. The control run, past the gate, made 2 (§5) |
| Safety: Delete my data, crisis view | Delete My Data & Start Over and its alerts are untouched; Settings only changed tint, footer colour and background. The crisis view is palette only (§5) |
| 5. Mac screenshots | **80 of 80 ok**, all checked against the harness's own size and blank-image checks: 16 main states × 4 variants, Settings ×4, and Increase Contrast and Reduce Transparency ×12. Contact sheets: `shots/verify/sheet-light.png` and `sheet-dark.png` |
| 6. Side by side | `compare/today.jpg`, `lesson.jpg`, `chat.jpg` (the same state, before and after), plus `today-week.jpg`, `lesson-check.jpg`, `chat-socratic.jpg` (the state closest to the concept) |
| Your running app | PID 98503 was running before and after every run. Nothing was killed by name. `/private/tmp/merc-mac-dd` was never read or written. Only Claude was ever in front, never the copy |

---

## 1. Commits and files

`git log feat/mac-app-2026-10..HEAD --stat` shows 14 commits, from `c7df5eb` (the spec) to `b0214e0` (the step 03 docs):

- **Swift, 63 files:**
  - 34 modified, all listed in §3.3;
  - 29 new: the Night components in `DesignSystem/Sources/Night/`, the Mac views in `*/Sources/Mac/`, and their tests. Every new file is wrapped in `#if os(macOS)` (`ios-source-diff.py` lists them as `new/mac`).
- **Scripts, 5:**
  - `ci-compat-lint.py`, `ios-source-diff.py`, `ios-unchanged-check.sh` and `mac-copy-snapshots.sh` are new;
  - `mac-snapshots.sh` is modified.
- **Docs:** `SPEC.md`, `ARCHITECTURE.md`, the three step notes, `ios-snapshot-baseline.txt`, `night_contrast.py`, the CI probe, and 170 JPEGs in `shots/01–03/`.
- **Not in the diff:**
  - `project.yml`, `Package.swift`, assets, fonts, `Info.plist`, the pbxproj;
  - anything under `ios/Mercurius/` (the iOS app shell) or `MercuriusTests/`;
  - any server or web code.

The worktree was clean. The only ignored file is `ios/Packages/Package.resolved`, and no `" 2"` files exist anywhere in it.

## 2. Package tests

```bash
rm -rf /private/tmp/merc-mac-ns-spm
cd ios/Packages && swift test --scratch-path /private/tmp/merc-mac-ns-spm
```

**Test run with 1128 tests in 168 suites passed**, 0 failed. XCTest ran 0 cases, as at base, because the packages use Swift Testing. The base had 1026 tests in 153 suites. The Night suites that ran include:

- **Contrast:**
  - "Night Studio contrast";
  - "… lesson and chat";
  - "… the path, lesson complete, the unit check".

  Every text pair in light, dark and both Increase Contrast versions, including over the glow pools.
- **The palette mapping:** "BrandColor on the Mac reads Night".
- **Honest copy:**
  - "Night copy is honest";
  - "Night: honest copy (lesson and chat)";
  - "Night lesson complete".
- **The lesson and chat:**
  - "Night: lesson parts";
  - "Night: sources";
  - "Night: the closing question";
  - "Night: the check from the keyboard";
  - "Night: the example's token line".
- **The rest:**
  - "Night unit check";
  - "Night quiz sheet";
  - the unit page tests;
  - "Crisis resources";
  - "Brand text contrast" (iOS's, unchanged).

The build has 100 warnings. All of them are in `ChatFeature/Tests/ChatViewModelIntegrationTests.swift` and `NetworkingKit/Tests/APIClientEndToEndTests.swift`, which this branch doesn't touch, and none is in a Night file.

## 3. iOS is unchanged

### 3.1 Snapshot comparison, recording forced off

`ios/scripts/ios-unchanged-check.sh /private/tmp/merc-mac-ns-logs/verify/ios-check` does four things:

1. It runs `xcodegen`.
2. It runs `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never xcodebuild test -only-testing:MercuriusTests/ViewSnapshotTests` on Audit 16PM.
3. It exports each stale test's render and hashes its RGBA pixels.
4. It compares the results with `ios-snapshot-baseline.txt`, which was recorded twice on the base branch at `1466d51` (= `feat/mac-app-2026-10`).

The output: "Executed 23 tests, with 12 failures". **"iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline"**. The 23 result lines match the baseline's byte for byte, hashes included.

| Test | Base (`1466d51`) | HEAD (`b0214e0`) |
|---|---|---|
| testBrandButtonPrimary | pass | pass |
| testBrandButtonSecondary | pass | pass |
| testBrandLogoFullDarkMode | pass | pass |
| testBrandLogoFullLightMode | pass | pass |
| testBrandLogoMark | pass | pass |
| testMessageBubbleUserLong | pass | pass |
| testMessageBubbleUserShort | pass | pass |
| testQuizViewFailedNonRetryable | pass | pass |
| testQuizViewFailedRetryable | pass | pass |
| testQuizViewLoaded | pass | pass |
| testQuizViewLoading | pass | pass |
| testCurriculumListAtAccessibilityXXL | stale `59d6e28e…` | stale `59d6e28e…` |
| testEmptyChatViewAccessibilityXXL | stale `dcfad3b6…` | stale `dcfad3b6…` |
| testEmptyChatViewDark | stale `c5d7f4c6…` | stale `c5d7f4c6…` |
| testEmptyChatViewLight | stale `fd9ddfed…` | stale `fd9ddfed…` |
| testLessonCompleteOverlayLastLessonDark | stale `efb7d78a…` | stale `efb7d78a…` |
| testLessonCompleteOverlayWithNext | stale `65d810d5…` | stale `65d810d5…` |
| testMercAllStates | stale `4c796bc3…` | stale `4c796bc3…` |
| testMessageBubbleAssistantFailed | stale `dc317efd…` | stale `dc317efd…` |
| testMessageBubbleAssistantPlain | stale `82a64000…` | stale `82a64000…` |
| testMessageBubbleAssistantTyping | stale `7139ec06…` | stale `7139ec06…` |
| testModeSelectorAtAccessibilityXXL | stale `95866dcd…` | stale `95866dcd…` |
| testModeSelectorDefault | stale `12d479db…` | stale `12d479db…` |

**Totals:** 11 pass and 12 stale on both. The 12 were already stale before this branch, and re-recording them is yours to do. `git status` stayed clean.

### 3.2 iOS build and test suite with CI's flags

These run from `ios/`, with derived data at `/private/tmp/merc-mac-ns-dd`:

```bash
xcodegen generate
xcodebuild build -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,id=04DB5F67-DB97-4DCB-B8BC-C050A26AD10A' -derivedDataPath /private/tmp/merc-mac-ns-dd
xcodebuild test  -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,id=04DB5F67-DB97-4DCB-B8BC-C050A26AD10A' -derivedDataPath /private/tmp/merc-mac-ns-dd \
  -skip-testing:MercuriusTests/ViewSnapshotTests -skip-testing:MercuriusUITests/PerformanceTests \
  -skip-testing:MercuriusUITests/AppStoreScreenshots \
  -retry-tests-on-failure -test-iterations 3 -test-repetition-relaunch-enabled YES
```

- **The build:** BUILD SUCCEEDED.
- **The tests:** **TEST SUCCEEDED** on the first attempt:
  - 3 XCTest unit tests (`ReplyTextScaleTests`);
  - 3 Swift Testing tests in 2 suites;
  - 25 UI tests in 294 s.
- 0 failures, and no test was retried. This is the same 31/31 as at base and in each step.
- No codesign xattr retry was needed.
- `xcodebuild clean build` of the iOS app then rebuilt it from scratch: see the build line in §4.

### 3.3 Every shared file, line by line

Two independent methods. Both say iOS compiles the same text.

**(a) `ios/scripts/ios-source-diff.py feat/mac-app-2026-10`**
- It reduces each whole file to what an iOS build compiles: `os(macOS)`, `os(iOS)` and `canImport` are resolved, `DEBUG` and `compiler(…)` keep every branch, and comments and whitespace are dropped.
- Then it compares base and head.
- Result: **"0 file(s) with iOS-visible changes"**:
  - 34 modified files report `same` (or `mac-app` for the Mac target's `MacSnapshot.swift`);
  - 29 new files report `new/mac`.

**(b) A per-line check written for this step**, not committed (`/private/tmp/merc-mac-ns-logs/verify/hunk-check.txt`):
- It takes `git diff -U0` and, for every added or removed line, works out the `#if` context in that line's own version of the file.
- It flags any line that iOS compiles.
- Unlike (a), it doesn't collapse whitespace, so a change inside a string literal would show.

| Shared file | Lines iOS never sees | `#if` / `#else` / `#endif` | Blank / comment | Lines iOS compiles |
|---|---|---|---|---|
| `DesignSystem/Color+Brand.swift` | 23 | 12 | 0 | 0 |
| `DesignSystem/BrandButton.swift` | 35 | 7 | 2 | 2 † |
| `DesignSystem/DuoButton.swift` | 10 | 3 | 0 | 0 |
| `DesignSystem/CrisisSupportView.swift` | 3 | 2 | 0 | 0 |
| `AppFeature/OnboardingFlow.swift` | 12 | 11 | 0 | 0 |
| `AppFeature/OnboardingSteps.swift` | 31 | 58 | 2 (comments) | 0 |
| `AppFeature/RootView.swift` | 15 | 7 | 0 | 0 |
| `AppFeature/YourPathStep.swift` | 10 | 9 | 0 | 0 |
| `ChatFeature/ChatView.swift` | 210 | 39 | 6 | 0 |
| `ChatFeature/ChatInputBar.swift` | 134 | 6 | 0 | 0 |
| `ChatFeature/CurriculumLessonView.swift` | 72 | 9 | 0 | 0 |
| `ChatFeature/EmptyChatView.swift` | 84 | 9 | 3 | 0 |
| `ChatFeature/LessonCompleteOverlay.swift` | 45 | 2 | 1 | 0 |
| `ChatFeature/MercCoachCard.swift` | 30 | 3 | 1 | 0 |
| `ChatFeature/MessageScrollPolicy.swift` | 9 | 2 | 1 | 0 |
| `ChatFeature/ModeDescriptionSheet.swift` | 5 | 7 | 0 | 0 |
| `ChatFeature/ReplyMarkdownTheme.swift` | 104 | 2 | 1 | 0 |
| `ChatFeature/Tools/QuizView.swift` | 2 | 3 | 0 | 0 |
| `CurriculumFeature/UnitTestView.swift` | 62 | 18 | 1 | 1 † |
| `SettingsFeature/MacSettingsWindowView.swift` | 32 | 0 | 0 | 0 |
| `AppFeature/Mac/*` (7 files: wholly `#if os(macOS)`) | 971 | 14 | 0 | 0 |
| `AppFeature/Tests/Mac*` (3 files: wholly `#if os(macOS)`) | 174 | 0 | 0 | 0 |
| `MercuriusMac/App/MacSnapshot.swift` (the Mac app target; iOS never builds it) | — | — | 7 (comments) | (7, Mac target) |

**† The three unguarded lines, explained.** Each is a closing `}` that git matched to a different `}` than the one that moved. The text iOS compiles is unchanged:

- **`BrandButton.swift`** (head lines 77–78, `    }` and `}`):
  - The Mac branch added `#endif`, the `body` and struct closings, then a new `#if os(macOS)` block (the `brandButtonClassic` environment key), whose last two lines reuse the base's original `    }` / `}`.
  - iOS still sees `… .opacity(isEnabled ? 1 : 0.5) } }`, exactly as before.
- **`UnitTestView.swift`** (base line 190, `        }`):
  - The base closed `.onChange(of: quizSubmitted)` on line 190, then had a Mac-only `.onAppear { … }` block.
  - That Mac block moved into `NightUnitTestContent`. Git kept its `}` as context and marked the `.onChange` closing as removed.
  - iOS still sees `.onChange(of: model.quizSubmitted) { … announce(line) } }`.

Method (a) agrees: all three files report `same`.

**Why "the same text" means "renders the same":**
- No resource, asset, font, `project.yml` or `Package.swift` changed.
- No iOS-compiled file gained a symbol. The new files are `#if os(macOS)` throughout, and the Night API is `Night`-prefixed, so nothing can capture an existing iOS call.
- The pixel check in §3.1 confirms it for the 23 snapshot views, and the UI suite in §3.2 confirms the flows.

## 4. Mac builds

All from `ios/` after `xcodegen generate`, with derived data at `/private/tmp/merc-mac-ns-dd`.

| Build | Command | Result |
|---|---|---|
| Debug (incremental) | `xcodebuild build -scheme MercuriusMac -configuration Debug -destination 'platform=macOS'` | BUILD SUCCEEDED. It was already up to date with step 03's build of the same sources |
| Debug (clean) | `xcodebuild clean build` (the same command) | **CLEAN SUCCEEDED, BUILD SUCCEEDED**, 449 Swift compile steps. Only the `appintentsmetadataprocessor` note |
| Release, unsigned, universal | `xcodebuild build -scheme MercuriusMac -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`, as CI runs it | **BUILD SUCCEEDED**, every module compiled for arm64 and x86_64. `lipo -archs`: `x86_64 arm64`. Only the `appintentsmetadataprocessor` note |
| iOS app (clean) | `xcodebuild clean build -scheme Mercurius` on Audit 16PM | **CLEAN SUCCEEDED, BUILD SUCCEEDED**: the app, `MercuriusWidgets` and every package, with 0 warnings |

**`scripts/mac-bundle-check.sh`:**
- **Release:**
  - arbitrary loads false;
  - URL scheme `mercurius`;
  - icon present;
  - privacy manifest present;
  - arm64 + x86_64.
  - (It reads no entitlements from an unsigned build, as on CI.)
- **Debug:** the same, plus non-exempt encryption false and the sandbox entitlement true.

**The Release binary has no DEBUG code**, checked with `strings -a`. Long literals were used, because a Swift string of 15 bytes or fewer is stored inline and `strings` can't see it.

| Literal | Release | Debug |
|---|---|---|
| `NightReduceTransparency`, `NightCompleteAfterReply`, `NightUnitTestUnavailable` | absent | present |
| `MacSnapshot: problem`, `CGSSessionScreenIsLocked` | absent | present |
| The seeded demo chat ("I think it predicts the next word …") | absent | present |
| `Cited by Merc` and `Merc marked this lesson complete` (real UI copy) | present | — |

## 5. Safety at run time

### No network before consent

**The setup:**
- The renamed copy (`macns4`), launched through the harness flags but **without `-UITests`**, so the progress sync is live.
- `-UseLocalServer YES` and `-EphemeralSession YES`.
- A logging stub on `localhost:3000` (IPv4 and IPv6) that records every request.
- Each run lasted 12 s, and each one's picture confirms the screen it was on.

| Run | Arguments | Requests |
|---|---|---|
| Fresh first run (Meet Merc) | `-consentVersion 0 -hasSeenOnboarding NO` | **0** |
| The consent step | the same, plus `-GateStep disclosure` | **0** |
| Settings opened on the gate | the same, plus `-MacOpenWindow settings` | **0** |
| Control: past the gate (Today) | `-consentVersion 1 -hasSeenOnboarding YES -EnterShell YES` | 2: `GET /api/progress/<id>` and `GET /api/session/<id>` (the same two as PR #47's VERIFY) |

**The consent step's controls**, from `shots/verify/gate-consent.controls.txt`:
- the consent checkbox is present and visible;
- the sidebar's list is hidden behind the gate.

The consent wording, its order and `ConsentGate.currentVersion` are untouched (§3.3: `OnboardingSteps` only has Mac styling branches).

### Delete my data

The diff to `MacSettingsWindowView` and `MacSettingsView` changes only:
- the tint (`Night.prominent`);
- the footer colour (`.secondary` → `Night.ink3`);
- the pane background (`NightCanvas(.flat)`);
- the pre-consent placeholder's Merc and font.

The Delete My Data & Start Over button, its confirmation and failure alerts, Privacy Choices, the erase hooks in `MacShellModel` and `SettingsViewModel` are not in the diff. `MacShellModel` gained only `newChat(draft:)` and `showProgress()`, both behind `guard !isGated`. `settings-privacy*.jpg` shows the button.

### Crisis view

**The code:** `CrisisSupportView` changed by one Mac-only modifier, `.environment(\.brandButtonClassic, true)` on its close button. That keeps the pre-Night button, so no Night capsule or glass reaches the screen. The file has no Night type, canvas, glow, Merc, gradient or animation. Its Mac hosts (`NightUnitTest.supportPhase`, `NightQuizSheet`) show it as it is.

**The screenshots:** `crisis*.jpg` show:
- system type;
- a flat background;
- the selectable 988 / 741741 / 911 cards with Copy;
- the plain "Back to your path".

**Gap:** ARCHITECTURE §2.5 rule 5 planned a test that pins the crisis view's body to no Night decoration. No such test exists (no test file mentions `CrisisSupportView`). The rule holds today by inspection and by the screenshots. See "For the founder" below.

## 6. Screenshots (`shots/verify/`, see its `INDEX.md`)

80 PNGs became 80 full-resolution JPEGs (19 MB in all, with the two contact sheets). They come from a renamed, ad hoc signed copy, run off screen with `ACTIVATE=NO`, so the windows are drawn inactive.

**At 1280 × 800 and 700 pt, light and dark:**
- the gate (meet, age, consent);
- Today (fresh and with a seeded week);
- the path;
- the lesson intro, reply and check;
- lesson complete;
- the chat in Socratic, Debate and Discussion, plus the seeded thread;
- the unit check;
- crisis.

**Light and dark:** Settings (General, Privacy).

**Increase Contrast and Reduce Transparency, light and dark:** Today, the lesson check and the Socratic chat.

**Run details:**
- **Debate and Discussion** were switched through the real `POST /api/mode`, answered by a local stub. The stub logged exactly 8 mode requests for the 8 shots.
- **The variants really differ from the default render.** By pixel diff:
  - Increase Contrast changes 6.5% (Today light) to 31% (Today dark: no stars, flat pools, solid edges).
  - Reduce Transparency changes almost nothing off screen (max channel difference 15–31 on the lesson and chat). The Night surfaces are already opaque, and the glass it replaces renders without a backdrop off screen anyway.

**What I looked at** (both sheets, and at half size: Today, Today dark, crisis, lesson complete at 700 pt dark, Debate, the lesson check under Increase Contrast dark, the unit check):
- no clipped or overlapping text;
- no blank states;
- the honest-copy rules hold on screen:
  - "Part 3 · Check", with no total;
  - "Cited by Merc · dl.acm.org", not "pinned source";
  - no "Saved to notebook";
  - no time estimate;
  - the streak line reads "4 days running. One lesson or chat a day keeps it going."

## 7. Side by side (`compare/`)

Each image is three panels: the current Mac app (PR #47's `docs/mac-app/key-shots/`), then the Night Studio Mac, then the DesignLab concept (`explore-ui-shared/dir-a/shots/*-light.png`, an iPhone).

| File | Current Mac | Night Studio Mac | Concept |
|---|---|---|---|
| `today.jpg` | `01-today` (fresh) | `today` (the same fresh state) | `home-light` (mid-week) |
| `lesson.jpg` | `03-lesson` (first reply) | `lesson` (the same recorded reply) | `lesson-light` (its check) |
| `chat.jpg` | `05-chat-thread` | `chat-thread` (the same seeded thread) | `chat-light` |
| `today-week.jpg` | `01-today` | `today-week` (a seeded week, like the concept's) | `home-light` |
| `lesson-check.jpg` | `03-lesson` | `lesson-check` (Part 3, B picked) | `lesson-light` |
| `chat-socratic.jpg` | `05-chat-thread` | `chat-socratic` (source chip, Your turn) | `chat-light` |

**The differences from the concept are the honesty fixes:**
- "Beat 2 of 6" became "Part 3 · Check";
- "Saved to notebook" was dropped;
- "pinned source" became "Cited by Merc";
- "about 6 min" was dropped;
- "Rest days never reset your progress" was dropped;
- the other directions' grafts ("Give me a hint", the notebook button) were not added.

## 8. Your running app

- **Before and after every batch:** `running before: 98503` and `running after: 98503`.
- **Never:** `pkill`/`killall` by name, or reading or writing `/private/tmp/merc-mac-dd`.
- **What came to the front:** the frontmost-app watcher saw only `com.anthropic.claudefordesktop` in every batch, never the copy.
- **Copies:**
  - Every copy quit by itself, and none was left running.
  - The network check's four launches were quit by their own PIDs, if needed (none was).
  - The copy's container `~/Library/Containers/com.mayoailiteracy.mercurius.native.macns4` holds test data only, as `macns1–3` do. Delete them when convenient.

## For the founder

**These need a look on screen.** Off-screen pictures can't show them:
- the macOS 26 Liquid Glass (the sidebar, the toolbar's Progress button, the composer, the complete card's "Done for now" and Share);
- the gate's checkbox and pop-up bezels;
- focus rings with Full Keyboard Access on. Check Tab through Today, the path rows, the composer and the check; A–D, Return and Escape with a pick; ⌘Return in the unit check.

**Not proven here:**
- that CI's Xcode 16.2 / Swift 6.0.3 compiles the branch. The lint and the probe cover the known traps; the `spm`, `xcode` and `mac` jobs are the proof once pushed;
- the 12 stale iOS snapshot references. They were stale before this branch, and re-recording them is yours.

**Gaps and open questions** (none blocks the branch; I fixed nothing because nothing broke):
1. **No automated crisis pin.** The planned test that `CrisisSupportView` carries no Night decoration was never written (§5). Worth adding before merge, as a source-scan test like `NightCopyTests`.
2. **Today's week dots versus the streak line.** The dots mark *lesson* days this week, but the line under them says "4 days running" (which counts chats too). In the seeded week, 2 dots sit under "4 days running". VoiceOver reads the card's own sentence, but a sighted student may read the dots as the streak. One option is a small label or a gap between the two.
3. Still open from the earlier steps:
   - Merc's coach row hides while the composer has focus, and on the Mac the composer takes focus when a lesson opens (step 02);
   - VoiceOver still says "Written defense" on the unit check's result (step 03; it's the iPhone's string);
   - Retake isn't bound to Return.
4. **Repo size.** This branch commits about 50 MB of JPEGs: 30 MB in steps 01–03 and 19 MB here. Squash or prune `shots/` before merge if that's too much.

## Logs (not committed)

`/private/tmp/merc-mac-ns-logs/verify/` holds:
- the build and test logs: `swift-test.log`, `mac-debug.log`, `mac-debug-clean.log`, `mac-release.log`, `ios-build.log`, `ios-build-clean.log`, `ios-test.log`;
- the result bundles: `ios-check/snapshots.xcresult` and `ios-suite.xcresult`;
- the source checks: `ios-source-diff.txt` and `hunk-check.txt`;
- the run-time checks: `net-check.txt` and `mode-stub.log`.

The PNGs are in `/private/tmp/merc-mac-ns-shots/verify/` and `verify-net/`.
