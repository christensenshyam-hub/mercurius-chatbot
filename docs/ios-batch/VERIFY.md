# Verifying `fix/ios-student-2026-10`

I verified branch `fix/ios-student-2026-10` at `4a669b0` on 2026-10-19, from 00:55 to 01:45 CDT. It has 26 commits on `origin/main` `720dbac`.

**The result:** everything passes, and nothing in this step needed a fix or a commit.

| Check | Result |
|---|---|
| Stray files | None |
| Package tests (`swift test`) | All pass |
| Simulator build | Builds |
| App tests with CI's flags | 27 of 27 pass |
| Performance and App Store screenshot tests | 4 of 4 pass |
| Snapshot tests | 12 fail. All 12 also fail at the base commit, `720dbac`, and none newly fails. |
| Screenshots | 88 taken, on both simulators at L, xxxL, AX1 and AX5 |

Not done, as instructed:

- AUD-34;
- snapshot recording (the reference images are untouched);
- `ConsentGate.currentVersion`, which is still `1`;
- any push, PR, TestFlight upload or `release.sh` run.

## 1. Branch contents (`git log 720dbac..HEAD --stat`)

**Size:** 26 commits, from `c84abf0` (AUD-02) to `4a669b0` (AUD-54 follow-up). They change 107 files: +8074 / −929.

**What they touch:**

- `ios/`;
- `docs/APP_STORE_LISTING.md` (the AUD-57 App Privacy label).

`server.js` and `lib/` are unchanged, so the wire contract with production is unchanged.

**Using the right base:**

- The local `main` ref is stale at `8ce52ce`, so `git log main..HEAD` also lists 5 commits already on `origin/main`: PR #40, PR #41 and their merges.
- The branch's real base is `720dbac`, which is `origin/main` and was confirmed with `merge-base`. I used `720dbac..HEAD` throughout.

**Stray files:** none.

- No tracked file in the diff matches ` 2`, DerivedData, `.build`, `build/`, `.xcresult`, `xcuserdata`, `.DS_Store` or `*.png`.
- I searched the whole worktree for iCloud ` 2` duplicates and found none.
- **Untracked:** only `docs/ios-batch/`, which holds the step notes and `shots/`.
- **Ignored:** only the generated `ios/Mercurius.xcodeproj/` and `ios/Packages/Package.resolved`.
- No screenshot sits outside `docs/ios-batch/shots/`. The other PNGs in the repo are tracked marketing and site icons from `main`.
- All build products went to `/private/tmp/merc-fixios-dd` and `/private/tmp/merc-fixios-spm`.

## 2. `swift test`

```
cd ios/Packages && rm -rf /private/tmp/merc-fixios-spm
swift test --parallel --scratch-path /private/tmp/merc-fixios-spm      # as CI runs it
```

- **Result:** `Test run with 915 tests in 137 suites passed`. The run was clean, from an empty scratch path.
- **ArchitectureTests:** the suite "Architecture — package dependency graph" passed, including "Every feature module lists only allowed dependencies".
- **Warnings:**
  - One warning comes from this branch. `AppFeature/Sources/RootView.swift:448`, added in `ccadc0c`, reads a main-actor `static let` (`UnitTestCrisisPreviewHost.helper503`) from the nonisolated `CrisisPreviewTools`. Swift 6 would make this an error. It is DEBUG-only preview code and doesn't break the build. Marking the constant `nonisolated` would fix it. I left it alone, because this step fixes only breakages.
  - The other 42 warnings are in `APIClientEndToEndTests.swift` and `ChatViewModelIntegrationTests.swift`. They are captured-var mutations, and `git blame` shows every one predates the branch.
- **Snapshots:** the package tests contain no snapshot tests. The snapshot suite is `MercuriusTests/ViewSnapshotTests` in the app target, covered in section 3.

## 3. Xcode: `xcodegen generate`, `xcodebuild build`, `xcodebuild test` on Audit 16PM

**Simulator:** Audit 16PM is an iPhone 16 Pro Max on iOS 26.4 (23E244).

**Build:** `xcodegen generate`, then `xcodebuild build` from an emptied `/private/tmp/merc-fixios-dd`.

- **BUILD SUCCEEDED** on the first attempt, with no codesign retry.
- The only warning outside third-party packages is the `RootView.swift:448` one above.
- After I removed the temporary screenshot driver, I ran `xcodegen generate` again and rebuilt: **BUILD SUCCEEDED**.

### A. CI's exact flags

The run skipped `ViewSnapshotTests`, `PerformanceTests` and `AppStoreScreenshots`, and used `-retry-tests-on-failure -test-iterations 3`. The result was **TEST SUCCEEDED**, with 27 of 27 passing and 0 skipped. Every test passed on its first try, so none needed a retry.

**MercuriusTests (3):**

- `AppLaunchTests`;
- `LiveActivityStateTests` (2).

**MercuriusUITests (24):**

- **Launch and tabs:** `testBootCompletes`, `testTabBarHasChatAndCurriculum`.
- **Curriculum:** `testCurriculumListsAllUnits`, `testSwitchingToCurriculumTabShowsProgressSection`.
- **Chat header:** `testChatHeaderExposesHomeButton`, `testHeaderRemainsVisibleAtAccessibilityTextSize`.
- **Modes:** `testModeSelectorExposesAllModes`, `testFirstModeTapShowsDescriptionSheet`, `testAlreadySeenModeTapDoesNotShowSheet`, `testModeMenuShowsDescriptionSheetAtAccessibilityTextSize`.
- **Empty chat:** `testStarterPromptsPresentInEmptyChat`, `testEmptyChatHintVisibleOnFirstLaunch`, `testEmptyChatHintHiddenWhenAlreadySeen`.
- **Settings:** `testTappingSettingsOpensSheetWithAppearanceSection`, `testSettingsHasFeedbackAndHowItTeaches`, `testDeleteFailureShowsTheOldIdBeforeADeviceOnlyReset`. The delete-failure test really ran: port 3000 was closed, so it wasn't skipped.
- **Home:** `testHomeShowsNextStop`.
- **First-run gate:** `testFirstRunGateLandsInFirstLesson`, `testFirstRunGateCompletesAtLargestTextSize`, `testInterruptedFirstRunResumesOnYourPath`, `testConsentSentenceTogglesTheSwitch`, `testUnderThirteenIsBlocked`, `testNotNowPausesAndReviewReturns`, `testExistingInstallSeesGateOnceThenHome`.

The UI anchors (the "Debate" pill, or the AX "Mode" menu, and "Settings") still work.

### B. Snapshot comparison

The run was `-only-testing:MercuriusTests/ViewSnapshotTests` with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never`. That setting means a missing reference fails instead of being recorded. Afterwards `git status` under `__Snapshots__` was clean.

**Result:** 11 of 23 pass and 12 fail.

**What the failures mean:** I built the base commit `720dbac` (a `git archive` copy in `/private/tmp`, deleted afterwards) and ran the same comparison there. **The same 12 fail at the base.** Their reference images were already stale before this branch, so none of the 12 is a new failure. I then compared each HEAD render with the base render, pixel by pixel.

| Snapshot test | Ref vs base | Base vs HEAD | What this branch changed (intended) |
|---|---|---|---|
| `testModeSelectorAtAccessibilityXXL` | 18.1% | **29.2%** | AUD-48 (`484b64b`): the truncated "Socr… / Deb… / Disc…" pills became one "Mode: Socratic" menu. |
| `testMessageBubbleAssistantFailed` | 17.3% | **0.88%** | AUD-21 follow-up (`d450d89`): "Network error. Try again." and its icon use the darker `errorText` red. The bubble is otherwise unchanged. |
| `testLessonCompleteOverlayWithNext` | 45.4% | **0.86%** | AUD-21 (`282f2e7`): "Nailed it!" uses `successText` and the links use `accentText`. AUD-52 (`d5e587f`): Merc's arm is attached at the shoulder. |
| `testLessonCompleteOverlayLastLessonDark` | 24.8% | **0.28%** | Same as `WithNext`, in dark mode. |
| `testMercAllStates` | 8.1% | **0.23%** | AUD-52 (`d5e587f`): only the `.celebrate` arm. It now comes from under the toga. The other five poses are pixel-identical. |
| `testCurriculumListAtAccessibilityXXL` | 8.0% | **0.06%** | AUD-47 (`484b64b`): the path header can wrap. The path body renders blank in this snapshot both before and after, a problem in the test harness that predates the branch. |
| `testEmptyChatViewLight` | 9.9% | 0 px | Unchanged by this branch. The `GeometryReader` wrap in `3e543c6` renders pixel-identically. |
| `testEmptyChatViewDark` | 9.2% | 0 px | Unchanged by this branch. |
| `testEmptyChatViewAccessibilityXXL` | 16.8% | 0 px | Unchanged by this branch. |
| `testMessageBubbleAssistantPlain` | 20.1% | 0 px | Unchanged by this branch. |
| `testMessageBubbleAssistantTyping` | 33.0% | 0 px | Unchanged by this branch. |
| `testModeSelectorDefault` | 12.9% | 0 px | Unchanged by this branch: the standard-size pills are the same. |

- **How the percentages are measured:** they count pixels whose channel difference is above 8/255. "0 px" means the base and HEAD renders are byte-for-byte identical in every pixel.
- **For the re-record:** all 12 need re-recording. The 6 that are identical show designs from before this branch.
- **Earlier step notes:** steps 03 and 05 said "13" stale snapshot tests, but the list they give names these same 12. The correct count is 12.
- **Orphaned references:** `testReportCardView{Failed,Loaded,Loading}.1.png` have no test. They were orphaned before this branch.

### C. The UI tests CI skips

The run used `-only-testing:` `PerformanceTests` and `AppStoreScreenshots`, with no retries. Result: **TEST EXECUTE SUCCEEDED**, 4 of 4.

- **`testCaptureAppStoreScreenshots`:** passed in 26 s. The release screenshot flow still works with this branch's UI.
- **`testColdLaunchTime`:** 0.819 s on average (RSD 0.7%).
- **`testSeededChatScrollPerformance`:** 10.63 s, peak 90.7 MB.
- **`testSeededChatMemoryFootprint`:** 80.9 MB absolute.

No performance baselines are committed, so these numbers are for reference only.

## 4. Screenshots

**Index:** `docs/ios-batch/shots/verify/INDEX.md`. It has 88 PNGs.

- **Screens (11):**
  - the gate: age and disclosure;
  - Home;
  - the path;
  - the lesson intro;
  - the lesson, with the keyboard down and up;
  - free chat, with the keyboard down and up;
  - the unit-test crisis support view;
  - Settings.
- **Phones:** both, at L, xxxL, AX1 and AX5.
- **Text size:** set system-wide with `simctl ui content_size`.
- **How they were taken:** a temporary XCUITest driver launched each screen with the DEBUG launch arguments listed in the index, then saved `XCUIScreen.main.screenshot()`. The driver was never committed and has been deleted. Every anchor was found.
- **The keyboard:** the first SE pass showed a focused composer with no keyboard, because Simulator had a hardware keyboard connected. I turned off "Connect Hardware Keyboard" (`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`, with Simulator.app open), deleted that pass and reshot everything. All 16 keyboard-up shots show the real software keyboard.

### What the screenshots show (design notes for review; nothing changed here)

These are design observations, not breakages. Most predate the branch or sit outside what the audit asked for at that size.

1. **The lesson and free chat at AX5:** reply text is so large that words break mid-word ("Her / e's a / wild" on both phones). On the SE with the keyboard up, only one or two words of the reply are visible. This branch didn't change the reply font sizes. Before it, the AX5 lesson had no reading area at all (the audit's AUD-08 budget was −525 pt). The reply font needs an AX cap; that's an accessibility-layout follow-up.
2. **The path at AX sizes:** it opens scrolled, so the top of the unit banner and, at AX5, the "Your learning path" title sit under the pinned streak bar. On the 16 Pro Max at AX5 the status bar's time and signal are also invisible: light text on the white bar. Step 03's `03-path-16pm-AX5.png` already shows both, so neither is new in step 04 or 05.
3. **The age step at AX5:** at first view the wheel is one "Select your age" row on the 16 Pro Max and isn't visible on the SE; it's reached by scrolling, with Continue pinned. This matches step 03's `03-gate-age-*-AX5.png`. The AX5 gate UI test passes on both phones.
4. **The SE at AX5:** Home's "Start Lesson 1" and "Chat with Merc" are below the fold. Home scrolls at AX sizes, so they can be reached. The disclosure shows only its heading and the pinned "Agree and continue" / "Not now"; the consent row needs a scroll (step 03's open risk).
5. **Mode pills at xxxL on the SE:** "Discussion" hyphenates to "Discus-sion". The AUD-48 menu only replaces the pills at accessibility sizes.
6. **Path titles at xxxL:** the winding path truncates them on both phones ("What happens when you type a p…"). AUD-47's list layout only applies at accessibility sizes.
7. **The "Jump to latest" pill:** it floats over a line of reply text when the reading area is short (the SE, keyboard up, AX sizes).
8. **Settings at AX5:** the Session ID "Copy" button wraps mid-word ("C / opy").
9. **The lesson header:** the one-line title truncates at L ("What happens when you typ…"). The header was made one compact row for AUD-08.
10. **Merc's "Nailed it!" arm with Reduce Motion:** the arm rests at its swing's low end, −40°, out and down. Under Reduce Motion, and in the snapshot, the still pose doesn't read as a cheer (see `testMercAllStates`). Making the raised angle the rest pose for the still case would fix it.

## 5. State left behind

- **Commits:** none from this step. Nothing broke, so there was nothing to fix. The step notes `01`–`05`, this file and `shots/` are uncommitted, like the earlier steps'.
- **Simulators:** both are at text size `large`. Audit 16PM is in light mode and Audit SE3 in dark, as before. Both are booted and have this branch's DEBUG build installed.
- **Simulator.app:**
  - It was not running at the start. It is open now, and I left it open, because quitting it shut both simulators down in step 02.
  - Its `ConnectHardwareKeyboard` default is deleted again, back to the state before this step. The running Simulator keeps the hardware keyboard disconnected until it's toggled or relaunched.
- **Background processes:** I started a `caffeinate -i -t 18000` to keep the Mac awake during the long runs. It ends on its own.
- **Not touched:** the three `node … server.js` processes on ports 3301–3303 that step 04 mentioned.
- **Temporary files:** the base-commit copy (`/private/tmp/merc-verify-base`) and its derived data are deleted.

## 6. Still open (carried from steps 01–05; founder decisions)

- **`ConsentGate.currentVersion`** is still `1`, although the consent copy changed in `0f2b3c8` (AUD-27). Whether to re-ask every install is the founder's call.
- **Snapshot re-record:** the 12 tests above.
- **AUD-34:** routing to the frontier lesson waits for approval.
- **AUD-17 follow-up:** waits on the server fix.
- **App Store Connect:** in App Privacy, set "Linked to the user" to Yes for the four collected types (AUD-57). This needs no build.
- **Product calls flagged in the step notes:**
  - no Retry on pause and spend cap;
  - the strict event-stream check;
  - saved free-chat threads opening at the top;
  - "Not now" closing the lesson like Done.
