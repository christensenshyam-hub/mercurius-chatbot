# Verification: Lesson 1.1's interactive on the iPhone

**Setup:** Xcode 26.4 (Swift 6.3) on this Mac. **Simulators:** "Audit 16PM" (iPhone 16 Pro Max, iOS 26.4) and "Audit SE3". **Build output:** iOS into `/private/tmp/merc-ios-tok-dd`, SwiftPM into `/private/tmp/merc-ios-tok-spm`, the Mac into `/private/tmp/merc-mac-tok2-dd`. Every build ran after `xcodegen generate`, and no snapshot was recorded.

## After the second review (round 3, 2026-10-21)

The second review returned four medium and three low findings. Six were fixed in `7ac6095` and `d3d76c8`. The seventh was the hand-off summary's pointers, which are corrected here and in the PR description. How each finding was checked first:

| Finding | Checked by | Fix |
|---|---|---|
| A pick slides the map 26 pt on an SE (medium) | the code: neither the finished sentence nor the map in words reserved its longest version | both are laid out for every state with one shown; the chips keep their size. `testAPickNeverMovesTheMapOrResizesTheCard`; on the SE, the `map` and `money` shots now differ only in the chip (rows 366–453 px), the sentence (601–679 px) and the map's inside (751–969 px). The panel's edge rows are identical |
| Nothing to tap on the card's first screen (medium) | the renders: the openings are about 990 pt into a 1,546 pt card at an SE's width | the compact line and "Try it ↓" (44 pt) on the first screen; `testTryItBringsTheOpeningsUp` on both phones |
| The check drawn over the "I" (low) | the code: the check was inserted inside the animated layout | an always-present ring that fills with the check; the SE clip's frames at 1/30 s show no movement of the words |
| "2 · It’s" looks like a token's dot (low) | the code | "Step 2: It’s cut into tokens" at the accessibility sizes (VoiceOver's own line) |
| The map's rules break under about 352 pt windows (medium) | `MeaningMapTests` at 240–296 pt: failures from 240 to 282 pt, passes from 284 pt | under 300 pt the 300 pt map is drawn and scaled down; 240/256/270/288 added to the map tests and 288 to the layout tests |
| A stray `---` rule after a part that ends in [EX] or [KEY] (low) | two new split tests, which failed on the old code | `LessonInteractiveSplit` drops a break that opens the prose after a card block |
| Wrong commit range and shot paths in the hand-off (low) | git log and the folders | the range is `4aa93cd..` HEAD; the key shots are in `key-shots/`, the full set outside the repo (see the README) |

Then the whole verification ran again on the final code, from the build step:

| Check | Result |
|---|---|
| `swift test`, full, from an empty scratch path (`/private/tmp/merc-ios-tok-spm` deleted first) | **1215 tests in 182 suites passed** (1209 before the fixes), 0 failures |
| `scripts/ci-compat-lint.py`, and again on `MercuriusTests` and `MercuriusUITests` | 0 findings |
| iOS build (Audit 16PM), installed on Audit 16PM and Audit SE3 | BUILD SUCCEEDED, no warnings in the changed files |
| iOS `xcodebuild test`, CI's flags, Audit 16PM | **TEST SUCCEEDED**: 7 XCTest unit (incl. the 4 `TokenizerCardLayoutTests`), 3 Swift Testing and 27 UI (incl. the 2 `LessonInteractiveUITests`): 34 test cases passed, 0 failed, so no retries |
| `LessonInteractiveUITests` on Audit SE3 | TEST SUCCEEDED (2 of 2), with the screens before and after "Try it" kept |
| `scripts/ios-unchanged-check.sh` (recording forced off) | "iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline": 11 pass, 12 stale. Nothing under `MercuriusTests/Snapshots` changed |
| Mac Debug build (`/private/tmp/merc-mac-tok2-dd`) | BUILD SUCCEEDED |
| Mac copied-app shots, `lesson-interactive-map`, `-money`, `-river` (copy `macns10`, off screen) | **Pixel-identical to the base build's (9504c58)**: PIL finds no differing pixel. The founder's running Mercurius was untouched |
| Shots | the SE and 16 Pro Max matrix taken again on the final build (60 shots), the slow-stream and cut-off checks, "Try it" from the UI test, three clips and the whole-card renders; see the README |

A comment in `LessonTokenizerCard.swift` was corrected after the test build. The final build, installed on both sims, includes it, and `swift test` and the lint ran again on it: 1215 tests in 182 suites passed, 0 findings. (One run of `swift test` made while the iOS build was compiling lost a loopback connection in NetworkingKit's `APIClient end-to-end` stream test; NetworkingKit is untouched on this branch, and the run with nothing else building passed.)

## After review (round 2, 2026-10-21)

The review returned no findings, so no code changed. The whole verification ran again on the final code (`f0d9e60` + the UI test `eaf03c2`), from the build step:

| Check | Result |
|---|---|
| `swift test`, full, from an empty scratch path (`/private/tmp/merc-ios-tok-spm` deleted first) | **1209 tests in 182 suites passed**, 0 failures |
| `scripts/ci-compat-lint.py` | 0 findings |
| iOS build (Audit 16PM), installed on Audit 16PM and Audit SE3 | BUILD SUCCEEDED |
| iOS `xcodebuild test`, CI's flags, Audit 16PM | **TEST SUCCEEDED**: 6 XCTest unit (incl. the 3 `TokenizerCardLayoutTests`), 3 Swift Testing and 26 UI (incl. `LessonInteractiveUITests`), 0 failed test cases, so no retries |
| `scripts/ios-unchanged-check.sh` (recording forced off) | "iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline": 11 pass, 12 stale. Nothing under `MercuriusTests/Snapshots` changed |
| Mac Debug build (`/private/tmp/merc-mac-tok2-dd`) | BUILD SUCCEEDED |
| Mac copied-app shots, `lesson-interactive-map`, `-money`, `-river` | **Pixel-identical to the base build's (9504c58)**: PIL finds no differing pixel. The founder's running Mercurius was untouched, and the copy never came to the front |
| Key shots, taken again on the final build | 13 frames (SE and 16 Pro Max, Large to AX5, light and dark) against the first set: mean difference 0.9 to 1.5 of 255, and no pixel more than 40 apart (JPEG noise) outside the system's own status bar and home indicator (the 16 Pro Max's home indicator had hidden itself in the first set) |

The sims were left at Large, light and Increase Contrast off, with the final build installed on both.

## First pass

| Check | Result |
|---|---|
| `swift test`, full, from an empty scratch path | **1209 tests in 182 suites passed** (1187 at the base). Includes the 7 shared `Lesson 1.1's interactive` suites, the Mac's `Night: the interactive …` suites, `NightReplyTextTests` and the sky contrast tests, and `The iPhone's night-sky card` |
| `scripts/ci-compat-lint.py` (trailing commas, unguarded new APIs) | 0 findings |
| iOS build (Audit 16PM) | BUILD SUCCEEDED |
| iOS `xcodebuild test`, CI's flags (skip ViewSnapshotTests, PerformanceTests, AppStoreScreenshots; retry on failure, 3 iterations, relaunch), Audit 16PM | **TEST SUCCEEDED** with every test passing first time: 6 XCTest unit (3 `ReplyTextScaleTests`, 3 `TokenizerCardLayoutTests`), 3 Swift Testing, and 26 UI (25 + `LessonInteractiveUITests`), 0 failures, no retries |
| `scripts/ios-unchanged-check.sh` (recording forced off, `DD=/private/tmp/merc-ios-tok-dd`) | **"iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline"**: 11 pass, 12 stale, the same hashes. No snapshot covers the lesson thread. Nothing under `MercuriusTests/Snapshots` changed |
| Mac Debug build (`MercuriusMac`) | BUILD SUCCEEDED |
| Mac copied-app shots (`scripts/mac-copy-snapshots.sh`, light) | `lesson-interactive-map`, `-money` and `-river` were taken from the base build (9504c58) and again after the change. **Before and after are pixel-identical** (PIL: no differing pixel), after the shared-logic commit and again on the final code. Against the earlier round's JPEGs (`explore-ui-shared/mac-tokenizer-shots/round2/`): mean difference 0.65 to 0.67 of 255, and no pixel more than 40 apart (JPEG noise). The founder's running Mercurius was untouched, and the copy never came to the front |

## What the shots show

The key shots are in `key-shots/`; the full set is outside the repo, in `.claude/worktrees/explore-ui-shared/ios-tokenizer-shots/`. See the README.

- **The card:** the SE and the 16 Pro Max at Large, xxxLarge, AX3 and AX5, in light and dark, before a pick and after each, plus Increase Contrast, Reduce Transparency and Reduce Motion.
- **Placement:**
  - `context`: the card follows the end of the example's part;
  - `after`: the check follows the card;
  - `slow-*`: while the reply streams and the card arrives, the reply stays held at its top with "Jump to latest" showing (AUD-09);
  - `se-cut-next`: a cut-off first reply never gets the card, and the next reply takes it (AUD-29).
- **Motion:**
  - `pick-money.mp4`: the pick;
  - `rm-crossfade.jpg`: the same pick with and without Reduce Motion.

## The polish pass

These came from looking at the shots and the test renders:
1. **The SE at AX3 and AX5:**
   - the bars over the numbers went (a picture of the signs), and the values now read as one line;
   - the fold button's icon went;
   - a picked opening's check moved above its words (beside them, AX5 split "paycheck,");
   - "1 · You type" replaces the disc at the accessibility sizes.
2. **The SE at Large:** five tokens make one line (six points apart, not eight).
3. **The map at the phone's widths:** the first version grew the labels to xxxLarge. The geometry tests failed (the river pill met the start caption and "water"), so the label size is now capped by the panel's width, and the card says the map in words from xxLarge up.
4. **Motion:** a pick changes the finished sentence at once, because animated, the old and the new sentence overlapped for 0.2 s. The start's caption no longer fades during the Reduce Motion crossfade.
5. **The map's height** comes from a Layout in one pass, so the first frame (and a render) has the map.

## Not checked here

- What only CI can prove: that Xcode 16.2 / Swift 6.0.3 compiles the branch.
- On a real device:
  - the selection haptic;
  - VoiceOver's walk through the card (its labels are tested, and the UI test reads them);
  - the system's own Reduce Motion and Reduce Transparency switches (the shots use the DEBUG overrides; Increase Contrast was the simulator's own setting).
