# Step 03: accessibility (AUD-12, AUD-21, AUD-22, AUD-23, AUD-46, AUD-47, AUD-48, AUD-49)

Branch `fix/ios-student-2026-10`, on top of step 02 (`e8ee6cf`). Nothing is pushed.

## Commits

| Commit | Subject |
|---|---|
| `282f2e7` | Give accent and success text their own readable tokens (AUD-21) |
| `484b64b` | Lay out the gate, path and chat for the largest text sizes (AUD-12, AUD-47, AUD-48) |
| `f1f34fd` | Make the unit test readable and tell VoiceOver what's picked and right (AUD-22) |
| `f17adf7` | Let VoiceOver walk a lesson reply and hear what happens (AUD-23, AUD-49, AUD-46) |
| `d450d89` | Give error text its own readable token too (AUD-21 follow-up) |
| `cb73b20` | Scroll the AX5 gate test with drags, so it passes on an iPhone SE too (AUD-12) |
| `6bd635c` | Set the unit test's grading feedback in body text too (AUD-22 follow-up) |

`d450d89` (errorText) wasn't in the brief; it is its own commit so it can be dropped. The first four were each built and tested as staged (the index exported to a separate checkout, full `swift test` there) before committing.

## What changed

### AUD-21: text tokens and contrast (`282f2e7`, `d450d89`)

- **Tokens** (DesignSystem `BrandColor`):
  - `accentText`: light `#4F46E5`, dark `#A5B4FC` (the audit's values).
  - `successText`: light `#166534`, dark `#22C55E`. Not the audit's `#15803D`: that falls to 3.9:1 on the green answer row over an elevated card.
  - `errorText`: light `#B91C1C`, dark `#F87171` (follow-up commit). The fill red as text was 3.6:1 on the light background.
  - `accent`, `success` and `error` stay as the fill and stroke hues.
- **One source of values:** the adaptive hex values moved into `BrandPalette`, which `BrandColor` builds from and the contrast test reads (a SwiftUI `Color` can't be resolved to dark mode on the macOS test host).
- **Where the text tokens are now used:** every text or state glyph that was drawn in a fill hue: the check question and [Q] stem, KEY IDEA, option letters, lesson and unit-test eyebrows, the Done buttons, "Nailed it!", UP NEXT, the coach card eyebrow, path status lines, Jump to latest, Retry, Explain more, Quiz me, numbered-list markers, the history mode chip, settings links, the ghost button, sheet Close buttons, failure reasons and wrong-answer marks. Decorative icons, fills, strokes and toggle tints keep the fill hues.
- **Locked path nodes:** they used `.disabled`, which dimmed "Locked" further. They now refuse taps (`allowsHitTesting(false)`), drop the button trait, and their tap handler ignores a locked node. The label keeps full `textSecondary`.
- **Test:** `BrandContrastTests`. Every text token (`text`, `textSecondary`, `accentText`, `successText`, `errorText`) is at least 4.5:1 on `background`, `surface` and `surfaceElevated`, and on the tinted cards text sits on, in light and dark. It also reproduces the audit's 3.95:1 and 2.28:1 and pins that the fill hues fail as text.

### AUD-12, AUD-47, AUD-48: the largest text sizes (`484b64b`, `cb73b20`)

- **AUD-12, the gate:**
  - Meet Merc and the resting screens (under 13, paused) scroll, centred while they fit, with the CTA pinned below.
  - `GateStepContainer` moves the title and subtitle into the scroll view at accessibility sizes.
  - The age wheel has a 150 pt minimum height.
  - `DuoButton` centres a title that wraps.
  - At AX5 every step's CTA is on screen without scrolling, on both phones.
- **AUD-47, the path:** at accessibility sizes it is a straight list. Each row has a 52 pt node, the full title wrapping freely, and the status underneath; rows grow with their text.
  - Stops, states, callbacks and the scroll to the frontier are unchanged.
  - The node and the row share `PathStopPresentation` (glyph, status line, tone, VoiceOver label).
  - The START callout is one line, capped at xxxLarge: no more "STAR/T".
- **AUD-48, the chat header:**
  - At accessibility sizes the pills become one "Mode: Socratic" menu (`chat.modeMenu`) holding an inline picker. Picking a mode runs the same first-tap description sheet.
  - The menu stops growing at AX3, where it fits one line on the SE (at AX5 it took two lines and 180 pt).
  - The "Try a prompt above" hint is hidden at accessibility sizes, where the prompts are off screen.
  - The streak chip stops growing at AX1 and has a 44 pt target.
- **UI-test harness:**
  - **A bug the existing AX test hid:** `launchApp(contentSize:)` set `UIPreferredContentSizeCategoryName` in `launchEnvironment`, which UIKit ignores. I checked on the simulator: the environment variable leaves the app at the simulator's size, and the launch argument applies. So `testHeaderRemainsVisibleAtAccessibilityTextSize` had been running at the default size. It is now a launch argument, and that test really runs at AX XXL.
  - **The "Debate" anchor:** `waitForBootComplete` accepts the mode menu as the chat signal at AX sizes. The header test opens the menu and finds "Debate" in it. At standard sizes the "Debate" pill is unchanged, so every other test and `AppStoreScreenshots` / `PerformanceTests` still find it.
  - **New: `testFirstRunGateCompletesAtLargestTextSize`.** It runs at AccessibilityXXXL, a fresh install, from Meet Merc to the Lesson 1 intro.
    - It asserts that each CTA is hittable without scrolling, that the wheel is at least 100 pt tall, and that the consent switch, scrolled to, turns on.
    - A frame-height canary fails the test if the text size didn't apply.
  - **New: `testModeMenuShowsDescriptionSheetAtAccessibilityTextSize`.**
  - **Scrolling on the SE (`cb73b20`):** `app.swipeUp()` didn't scroll the disclosure on the SE at AX5, though a finger drag from the same point did. The helper now uses explicit drags.

### AUD-22: the unit test (`f1f34fd`, `6bd635c`)

- **Answer rows** are ported from QuizView (`UnitTestOptionRow`):
  - Body text, a 44 pt minimum height, and the whole row tappable.
  - The letter is readable: secondary, indigo once picked, green or red once graded.
  - After submitting, rows lock with `allowsHitTesting(false)`, so the review keeps full colour. The right answer gets a check (filled if it was the pick); a wrong pick gets an x.
- **VoiceOver:**
  - Each row reads "Option B: …" with the `.isSelected` trait.
  - Once graded, its value is "Correct answer, your answer", "Correct answer" or "Your answer, incorrect", and reviewed rows drop the button trait.
  - The score is announced on submit, and the result when its screen opens (never on the crisis support screen).
  - The title is a heading.
- **Submit:** until every question has a pick it reads "Answer all 5 · 3/5", in readable text on a quiet card, instead of a half-faded button.
- **Text size:** instructions, explanations, grader feedback and result lines move from footnote to body.
- **The written answer:** the box is labelled "Your written answer" and shows a placeholder.
- **Done:** a 44 pt target.
- **"Unit mastered":** gets a celebrating Merc.
- **For screenshots only (DEBUG):** `-UnitTestPreview [-UnitTestStage partial|review|mastered|almost]` drives the real view model to each stage, with no network.

### AUD-23, AUD-49, AUD-46: VoiceOver and targets (`f17adf7`)

- **Lesson replies:** a settled lesson reply is an accessibility container ("Merc's reply"). Each run of paragraphs, KEY, EX and CHECK card is its own stop, and the [Q] options stay real buttons.
  - Free chat, the student's turns, a reply still streaming and a reply that never arrived still read as one element.
  - The report reasons are VoiceOver actions on each block. The long-press menu belongs to the bubble, which VoiceOver now walks into rather than lands on.
- **[Q] options:**
  - Each reads "Option B: …" with `.isSelected`, and a correct/incorrect value after grading.
  - The check question reads "Question: …".
  - A graded card keeps full colour and drops the button trait. An unanswered card on an older reply stays visibly inert.
- **Announcements** (`ChatAnnouncement`):
  - "Merc replied." plus the reply's question, if it asks one.
  - "Merc's reply didn't arrive. <reason>" when a reply fails.
  - "Correct." or "Not quite. The answer is B: …" after a [Q] pick.
  - "Lesson complete" is posted at high priority, so the reply's announcement can't cut it off.
- **Haptics:** success for a right pick, error for a wrong one. Before, both got the same impact.
- **AUD-49, headings:** unit banners and "Your learning path" are headings. The lesson header already was one (step 02), and the unit test's title is in `f1f34fd`.
- **AUD-46, 44 pt targets:** [Q] rows (about 37 pt before, now tappable edge to edge), the remove-photo button and the hint's dismiss button. The streak chip is in `484b64b`, and Done in lessons was already 44 pt (step 02).

## Tests

- **`swift test`** (full, `--scratch-path /private/tmp/merc-fixios-spm`) at HEAD: **812 tests in 120 suites passed**, ArchitectureTests included. Step 02 ended at 785, so this step added 27:
  - `BrandContrastTests`: 5
  - `GateLayoutTests`, `LearningPathLayoutTests` and `AccessibilityLayoutTests`: 10
  - `UnitTestReadabilityTests`: 6
  - `VoiceOverTests`: 6
- **Each commit on its own:** the four main commits were built and run as staged, from the index exported to a separate checkout. Results were 790, 800, 806 and 812 passing.
- **`xcodebuild test` with CI's flags** on Audit 16PM, at `cb73b20` (snapshots, perf and App Store screenshots skipped; retries on): **TEST SUCCEEDED**. All 21 `MercuriusUITests` passed: the 19 existing tests and the 2 new ones.
  - The "Debate" / "Settings" anchors and "Continue. Start the lesson." still work.
  - `testHeaderRemainsVisibleAtAccessibilityTextSize` now really runs at AX XXL and passes.
- **On Audit SE3:**
  - `testFirstRunGateCompletesAtLargestTextSize`: passed.
  - Earlier on the SE (before the drag fix): the header, mode-menu, first-run, mode-selector and curriculum-units tests passed.
- **`6bd635c`** (the last commit) only changes font sizes on the unit-test result screen. `swift test` passed after it and the app built for the simulator; I didn't rerun the UI tests after it.
- **Snapshots:** I ran comparison runs only, on Audit 16PM. Every snapshot test has a committed reference, so nothing was recorded, and `git status` shows the references untouched.
  - I compared HEAD against step 02's head (`e8ee6cf`, built from a `git archive` copy in /private/tmp).
  - **13 of 23 already fail at `e8ee6cf`, before this step:**
    - `testCurriculumListAtAccessibilityXXL`
    - `testEmptyChatView{Light,Dark,AccessibilityXXL}`
    - `testLessonCompleteOverlay{WithNext,LastLessonDark}`
    - `testMercAllStates`
    - `testMessageBubbleAssistant{Failed,Plain,Typing}`
    - `testModeSelector{Default,AtAccessibilityXXL}`
  - Those references predate the current designs. For example, the curriculum reference is the old list screen, and the overlay reference is the pre-Merc "Lesson complete" card. They need re-recording whatever this step does.
  - **HEAD fails the same 13 and no others.** Pixel-diffing the rendered images, HEAD against the baseline, shows what this step changed:
    - `testModeSelectorAtAccessibilityXXL`: 29% of pixels (now the "Mode: Socratic" menu).
    - `testLessonCompleteOverlayWithNext`: 0.69% ("Nailed it!", UP NEXT, Share and Back to lessons in the text tokens).
    - `testLessonCompleteOverlayLastLessonDark`: 0.10%.
    - `testMessageBubbleAssistantFailed`: 0.88% (the failure line in `errorText`).
    - `testCurriculumListAtAccessibilityXXL`: 0.06% (the path header title can now wrap; the path itself renders blank in this snapshot, before and after).
    - The other 8 render identically.
  - The `QuizView` snapshots still pass within their 98% tolerance, although "Q1." is now `accentText`.

## Screenshots (`docs/ios-batch/shots/`)

Audit SE3 is in dark mode and Audit 16PM in light, as before. Both are reset to text size `large`.

| Shot | What it shows |
|---|---|
| `03-gate-{meet,age,disclosure,limits,path}-{se3,16pm}-AX5.png` | Every gate step at AX5 with its CTA pinned on screen. Meet Merc and the disclosure scroll; "Start / Lesson 1" is centred. |
| `03-path-{se3,16pm}-AX5.png` | The path as a list at AX5: full titles, "Start now" and "Locked" under them. |
| `03-path-{se3,16pm}-L.png` | The winding path unchanged at standard size: "Start now" in `accentText`, "Locked" not dimmed. |
| `03-chat-{se3,16pm}-AX5.png` | The "Mode: Socratic" menu at AX5 (one line, capped at AX3), with no input hint. |
| `03-chat-{se3,16pm}-L.png` | The three pills and the input hint, unchanged at standard size. |
| `03-unittest-partial-se3-L.png` | Answer rows at body size, one picked. |
| `03-unittest-review-{se3,16pm}-L.png`, `03-unittest-review-se3-AX3.png` | After submitting, at full colour: the wrong pick in red with an x, the right answer in green with a check, the explanation in body text. |
| `03-unittest-mastered-se3-L.png` | "Unit mastered" with a celebrating Merc. |
| `03-unittest-almost-se3-L.png` | "Almost there", with the grade and feedback in body text. |

## Skipped or not verified

- **Out of scope, as instructed:** AUD-34, snapshot recording and `ConsentGate.currentVersion` (still 1).
- **No VoiceOver pass on a device or simulator.** The VoiceOver work is checked by unit tests of the labels, values and announcement copy, and by the UI tests that query the accessibility tree. I haven't heard "Merc's reply" containers, the announcements or the report actions spoken. In particular, I haven't confirmed that VoiceOver says the container label on entering a lesson reply.
- **No screenshot of a lesson [Q] card** after grading (the replay capture's first replies have no [Q]). The graded card's colours and labels are unit-tested, and its tokens are covered by the contrast test.
- **The [Q] undo window** before the auto-send (AUD-46 "consider") is not done; it's a product call.
- **Not changed:**
  - **White on the `accent` fill (4.47:1).** This is the active mode pill, `BrandButton` primary and the unit test's primary button. It is a fill, not a text token, so the contrast test doesn't cover it.
  - **The TabView's global `.tint(accent)`.** It also colours the selected tab label; changing it would recolour every toggle under it.
  - **QuizView's white letter on the green "correct" circle (2.3:1).** Same reason: a fill.

## Open risks / notes for the founder

- **Snapshots:** 13 references were already stale before this step; see Tests. The founder's re-record will also pick up the 5 drifts this step causes.
- **AX5 gate on the SE:**
  - **The consent switch.** On "Before you start", the switch sits at the foot of a ~660 pt label. A student scrolls to it; tapping the label doesn't toggle it, which is standard SwiftUI `Toggle` behaviour. The consent-row redesign is AUD-27, a later step.
  - **Your path.** The two pinned CTAs take most of the screen, leaving about 270 pt to scroll the lessons and reminders.
- **The UI-test content-size fix changes what an existing test does:** `testHeaderRemainsVisibleAtAccessibilityTextSize` used to run at the simulator's size. Anyone adding an AX-size UI test should use `launchApp(contentSize:)`, which now works.
- **`app.swipeUp()` didn't scroll the AX5 disclosure on the SE** under XCUITest, though a real drag does (checked with the simulator's input tool). The test uses explicit drags. If a CI simulator behaves differently, `scrollUntilHittable` is the place to look.
- **Stale module cache:** an incremental `xcodebuild` twice failed with "BrandColor has no member 'errorText'" right after the token was added, although `swift build` was clean. Deleting `/private/tmp/merc-fixios-dd` fixed it. CI builds clean, so this shouldn't affect it.
- **The mode menu reads its choices from a `Picker` inside a `Menu`.** XCUITest finds "Debate" as a button there on iOS 26. That isn't verified on iOS 17.
- **Announcements:**
  - "Merc replied" fires from any phase change that ends a request, including the free chat.
  - A Stop reads "Merc's reply didn't arrive. Cancelled."
- **The DEBUG `-UnitTestPreview` host** is compiled out of release builds, like the other preview arguments.
