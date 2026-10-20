# Step 03: the rest of the app

**Branch:** `feat/mac-night-studio`, stacked on `feat/mac-app-2026-10` (PR #47). Not pushed.
**Built from:** `SPEC.md` §5.2 (path), §5.5 (unit check), §5.6 (lesson complete), §5.7 (gate), §5.8 (Settings), §5.9 (crisis), §5.10 (errors), §6 (copy), and the step's own asks where they differ (Decisions, below).
**Commits:**
- `8728f34`: the path, lesson complete, the unit check, the gate, Settings, the sheets, the error states, and their tests.
- `7c3c84e`: the snapshot harness's new states, and photographing sheets.
- `3f4cfd4`: the complete card's fade above its buttons in a short window.
- `docs` commit: this note and `shots/03/`.

Mac only. Every change is behind `#if os(macOS)` or in a Mac-only file. `ios-source-diff.py` reports **0 files with iOS-visible changes**.

## What changed

### 1. The learning path (`AppFeature/Sources/Mac/MacUnitPage.swift`, new)

`MacUnitPage` replaces the iPhone's winding path (`CurriculumView`) in the Mac's detail column, one unit per sidebar row.

- **The cover:** a lit card, not a gradient.
  - The eyebrow: "Unit 01 · Not started / In progress / All lessons done / Mastered".
  - The unit's title, its **summary**, and a meter: one capsule per lesson (lit when done, `lumen` for the current one), then a diamond for the check.
  - "2 of 4 lessons · then the unit check".
  - The big "01" numeral, as decoration, goes below a 560 pt column.
- **The thread:** one row per lesson, then the unit check, on a 2 pt thread that is lit (`progressLight`) where the student has been.
  - **Done:** a lit disc with a check, the title, "Done". A click opens the lesson to review it.
  - **Current:** the unit's first unlocked lesson that isn't done. Its node is lit with a breathing halo (still under Reduce Motion, none under Increase Contrast). It's a lit card under the lumen wash with "Lesson 1.3 · You're here" (or "· Next in this unit" when the student's frontier is in another unit), the title, the **objective**, and the page's one prominent button, "Start Lesson 1.3" or "Continue Lesson 1.3" (Return).
  - **Ahead:** a numbered node in place of a padlock, the title, the objective, and **"Opens after 1.2"**, straight from `isLessonUnlocked`.
  - **Open, out of order** (progress merged from another device): it opens, without the prominent button.
  - **The unit check:** a diamond node; "5 questions, then one written answer Merc grades."; "Opens after 1.4" until every lesson is done. Then it's the page's prominent button, "Take the check" (Return), with the halo. Once passed, "Mastered", and a click takes it again (as the iPhone's path allows).
- **Next unit:** its title and **summary**, one click away (it selects that unit in the sidebar). None on Unit 8.
- **The narrow window:** no top `safeAreaInset` (it blanked the path once the sidebar folded on macOS 26, PR #47 step 05). The fold rule, the toolbar title "Learning Path" / "Unit 1 of 8" and the Progress button are unchanged. At 700 pt a row's "Opens after" note moves under its title when the row is narrower than 420 pt.
- **VoiceOver:** each row is one element: "Lesson 1.1, done: …", "Lesson 1.3, you're here: …. {objective}", "Lesson 1.4, opens after lesson 1.3: …", "Unit 1 check, opens after lesson 1.4: …".

### 2. Lesson complete (`ChatFeature/Sources/Mac/NightLessonComplete.swift`, new)

`LessonCompleteOverlay` draws `NightLessonComplete` on the Mac.

- **The card:** 520 pt, over the lesson under a canvas-coloured scrim (70%, 92% under Reduce Transparency). It's a lit surface on **its own canvas** (both pools, stars in dark), radius 24, one shadow in light mode.
- **Top to bottom:**
  1. **Merc inside the card**, celebrating, with one bloom of the brand light behind him (none under Increase Contrast), then happy. 72 pt in a short window.
  2. The eyebrow "Unit 1 · Lesson 1 · Complete".
  3. **The credential headline**, derived from the objective in `Curriculum.swift`: "Understand X." becomes **"You can now explain X."** This happens for 15 of the 35 lessons. Any other objective ("Apply …", "Master …", "Learn …", "Analyze …") gets the plain headline **"Lesson complete"**, because "You can now master …" would claim more than a lesson shows.
  4. The lesson's title, then one quiet line: **"Merc marked this lesson complete from your answers."** That is what happened: the card shows only on the server's `[LESSON_COMPLETE]`, which the prompt allows only after the student shows proficiency (`lib/lessonOutcome.js`).
  5. **Key ideas from this lesson:** the `[KEY]` texts Merc gave in this thread (`NightKeyIdeas`, through `BlockParser`, each once), up to the last three, in New York 16, then "+N more in the lesson". There is no "saved" and no notebook.
  6. **The week:** a ring that lights this lesson's arc as the card arrives (only when the lesson counts this week), "1 of 2 this week", and the stopping cue "One more meets this week's goal. Or stop here for today." At the goal: "Weekly goal met. Anything more is a bonus." `MacShellView` passes the count (`NightLessonWeek`, from `WeeklyPlan`), because ChatFeature can't see the curriculum.
  7. **Up next:** "Up next · Lesson 2" and its title, or "Up next · Unit 1 check".
  8. **"Done for now"** (secondary; it closes the lesson, as "Back to lessons" did) and **"Start Lesson 2"** / "Take the Unit 1 Check" (primary, Return), **at equal width**. With nothing next, "Done for now" is the one button.
  9. **Share:** the existing `LessonShareCard` from a 30 pt chrome circle in the corner.
- **Timeline:** the card rises 12 pt and fades in; Merc and his bloom at +0.15 s; the key ideas from +0.25 s, 0.08 s apart; the ring at +0.5 s. Buttons work from the first frame. Reduce Motion gives one crossfade.
- **Keyboard:** Return takes the next step. Escape, or a click on the backdrop, goes back to the lesson. Tab reaches "Done for now" and Share.
- **700 × 600:** the content scrolls inside the card above the pinned buttons, with a 16 pt fade so no line is cut.
- **VoiceOver:** on arrival, "Up next: Lesson 2, …" follows the lesson's existing "Lesson complete". Key rows read "Key idea: …". The week row reads its sentence. Share reads "Share".

### 3. The unit check (`CurriculumFeature/Sources/Mac/NightUnitTest.swift`, new)

The same model, phases, grading, 4-of-5 rule and crisis branch, drawn in Night.

- **A header:** "Unit 1 check" and the unit's title. The instructions are in `ink2`, and the keyboard line is in `ink3`.
- **Each question:** a lit card, "Question 1", the stem in `title2`, and four **`NightAnswerRow`s**.
  - The row is new in DesignSystem and is now shared by the lesson's check (`NightCheckCard` was refactored onto it, with the same look and VoiceOver) and the Quiz me sheet.
  - After submit: green for the answer (filled when it was the pick, outlined when not), red for a wrong pick, and the explanation.
  - Focus: Night's own ring on the card. A–D / 1–4 answer and move on, ↑/↓ move, Tab walks the cards. The scroll to the focused question is instant under Reduce Motion.
- **Submit:** Night's prominent button, ⌘Return. While it can't be pressed, it's the existing "Answer all 5 · 3/5" on a quiet fill.
- **Written answer** (was "WRITTEN DEFENSE"):
  - The existing lead line.
  - Merc's question in New York 18, selectable, on a lit card under the wash.
  - The answer in a `surfaceRaised` well with the `fieldStroke` edge and an `ink3` placeholder.
  - An error is an `errorText` mark and the reason in reading text.
  - Grading shows "Grading your answer…" with a small spinner.
  - Submit for grading: ⌘Return.
- **The result:** no ceremony.
  - A seal (`successText`) or a retry mark, then "Unit mastered" / "Almost there" in `display`.
  - The existing sentence in `ink2`.
  - Quiz and Written answer rows with marks and words.
  - Merc's feedback under "Merc on your written answer".
  - Done (Return) when passed. Otherwise Retake test, then Done.
- **The crisis branch:** `CrisisSupportView` exactly as it is, on a **flat** canvas.
- **Unavailable:** `MacUnitTestUnavailable`, a lit card on a flat canvas: "This unit test isn't available right now.", "Go back to the path. Your lessons and progress are unchanged.", and Done (Return).

### 4. The gate (`OnboardingFlow`, `OnboardingSteps`, `YourPathStep`: Mac branches)

- **The shell** draws `NightCanvas(pools: .indigo, stars: false)` behind the gate's box. The flow's own fill is clear on the Mac, so the light isn't cut off at the box. It's drawn, not fetched: **nothing new reaches the network.**
- **Type:** titles in Lexend 30 (`display`); sublines and rows in reading text.
- **Buttons:** `DuoButton` and `BrandButton` now draw Night buttons on the Mac.
  - A first-run `DuoButton` is the large (44 pt) prominent or secondary capsule.
  - "Not now" is a Night text button.
  - "Read the privacy policy" is a Night link with the pointing hand.
- **Meet Merc:** Merc in his lamp at 120 pt, with the same entrance and a settled start under Reduce Motion.
- **Consent:** the rows' icons in `accentText`; the native checkbox on a lit row in Night's prominent tint. **The wording, the order, the checkbox rule, the identifiers and `ConsentGate.currentVersion` are untouched.**
- **Limits:** the rows on a lit card.
- **Under 13 and Paused:** a plain Merc (no lamp, no light), the title and the message. Calm.
- **Your path:** the lesson numbers on Night nodes (no gradient discs); the rows on a lit card. The reminders section is the shared one, palette only.
- **Motion:** step changes crossfade under Reduce Motion instead of sliding.

### 5. Settings (`MacSettingsWindowView`, `MacSettingsView`)

- Still the Mac's own settings window (SPEC D10): toolbar tabs, grouped `Form`, system type and controls.
- The panes sit on Night's **flat** canvas, with the grouped sections' own fills.
- Footers and the session ID are in `ink3`: ≥ 4.5:1 on the canvas, where the system's secondary label is about 4:1.
- The tint is Night's prominent indigo.
- The "finish setting up first" pane (before consent) is Merc in his lamp on the canvas.
- **Untouched:** Delete My Data & Start Over and its confirmation, its failure and device-only alerts, Privacy Choices and withdrawing consent, the session ID's Copy rules, and the erase lock on the main window.

### 6. The crisis view (palette only)

`CrisisSupportView` keeps its system type, its copy, its numbers (selectable), Copy, the FaceTime and Messages links, and the note. Its close button keeps the pre-Night look: `BrandButton` reads `\.brandButtonClassic`, which the crisis view sets, so the new Night button branch never reaches it. There's no Merc, no light, no glass and no motion. It sits on a flat canvas in the unit check and in the Quiz me sheet.

### 7. Sheets, errors, empty and loading states

- **The mode explainer** (`NightModeExplainer`):
  - the mode's name in `display`;
  - "What it's for" and "When to use it" in reading text;
  - the example to try in New York, on a lit card under the wash;
  - "Got it" (Return) and "Close" (Escape).
  - The copy is unchanged.
- **Quiz me** (`NightQuizSheet`): the same model.
  - Loading: a spinner and "Generating a quiz from our conversation…".
  - Failure: the existing reason after an `errorText` mark, and Try again.
  - The quiz: lit question cards with `NightAnswerRow`, and Submit quiz (⌘Return). The score is "3 / 4", the existing line, and New quiz.
  - The crisis branch: `CrisisSupportView` on a flat canvas.
- **Start-up failure** (`MacStartFailure`): "Couldn't start", the existing reason and Try again (Return), on a flat canvas.
- **The rule:** no sad Merc, no illustration and no colour wash on any error.
- **Chat's own errors, empty chat and typing indicator** were step 02's.

## Tests

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-mac-ns-spm` | **1128 tests in 168 suites passed** (step 02: 1100 in 163) |
| New: `MacUnitPageTests` | Fresh, midway, in progress, other unit (not "You're here"), check open, mastered, out-of-order merge, the next unit, VoiceOver sentences, the complete card's week (`MacShellView.lessonWeek`), and the credential across **every** objective in the curriculum (15 "Understand …" give one; none of the other 20 does). |
| New: `NightLessonCompleteTests` | The credential rule and its refusals, key-idea collection (Merc's only, in order, deduped), the last-three cut, the eyebrow, the week lines, the ring's start, the next stop's words, the honest-copy register (no notebook, saved, minutes, "nailed it", "call it a night", "mastered"…) with proof it catches the concept's and the old card's lines; `NightQuizSheetTests` (marks, stripped letters). |
| New: `NightUnitTestTests` | Each graded state's row, and the unit check's words (no "defense", no "saved", no minutes). |
| New: `NightRestContrastTests` | Every text token sampled across the complete card's own canvas at 520 × 640, 520 × 500 and 472 × 500 (≥ 4.5:1); the path's nodes (the done check on the brand light or, under Increase Contrast, on flat `accentText`; the mastered check; node numbers; the ahead ring); the written answer's well (edge ≥ 3:1, text and placeholder ≥ 4.5:1); the week well. **This caught a real fault:** under Increase Contrast in dark mode the done node's white check sat on pale `accentText` (#C7D2FE). It now draws in `surface`. |
| Extended: `NightCopyTests` | Every line the eight unit pages say, fresh, midway, check open and mastered (over 200 lines), against the banned register plus "padlock" and "locked". |
| Extended: `MacSnapshotOptionsTests` | The `sheet` target. |
| Pixel checks (PIL, on the shots) | Complete card's attribution (`ink3`) 5.51:1 light, 7.26 dark; its eyebrow 5.52; path "Opens after 1.1" 5.15 light (on the violet pool), 7.05 dark; the check's note 5.52; the written answer's placeholder 5.51 light, 6.07 dark; the cover's meter caption 6.09. |
| `ios/scripts/ios-source-diff.py feat/mac-app-2026-10` | **0 files with iOS-visible changes.** Every edited shared file (`BrandButton`, `DuoButton`, `CrisisSupportView`, `LessonCompleteOverlay`, `CurriculumLessonView`, `ModeDescriptionSheet`, `QuizView`, `ChatView`, `UnitTestView`, `OnboardingFlow`, `OnboardingSteps`, `YourPathStep`, `RootView`, `MacSettingsWindowView`) reports `same`. |
| `ios/scripts/ci-compat-lint.py` | 0 findings. |
| macOS Debug build (`/private/tmp/merc-mac-ns-dd`) | BUILD SUCCEEDED. |
| `ios/scripts/ios-unchanged-check.sh` (recording forced off, Audit 16PM) | **"iOS unchanged":** 11 pass, 12 stale, the same 23 results and the same pixel hashes for every stale render as the baseline; `__Snapshots__` untouched. |
| iOS `xcodebuild test`, CI's flags (`-retry-tests-on-failure -test-iterations 3`), Audit 16PM | **TEST SUCCEEDED** on the first attempt: 3 XCTest unit and 25 UI tests, 0 failures, plus the Swift Testing cases (3 tests in 2 suites). Snapshot, performance and App Store screenshot tests skipped, as CI does. |

## Screenshots (`shots/03/`, 101 JPEGs)

All are from a renamed, ad hoc signed copy (`com.mayoailiteracy.mercurius.native.macns3`), run with `ACTIVATE=NO` and off screen. They're full resolution (2×), saved as JPEG at quality 84. The PNGs are in `/private/tmp/merc-mac-ns-shots/03-final/`.

- **At 1280 × 800 and 700 × 600, light and dark** (`<state>`, `-dark`, `-min`, `-min-dark`):
  - **Path:** `path` (fresh), `path-week` (two done, 1.3 lit), `path-check` (check open), `path-mastered`.
  - **Complete:** `lesson-complete`.
  - **Unit check:** `unit-test-quiz` (three answered, the focus ring on question 1), `unit-test` (graded), `unit-test-written`, `unit-test-mastered`, `unit-test-unavailable`.
  - **Crisis and start-up:** `crisis`, `start-failure`.
  - **Gate:** `gate-meet`, `gate-consent`, `gate-limits`, `gate-path`.
- **Light and dark:**
  - `unit-test-almost`, `gate-age`, `gate-paused`, `gate-under13`;
  - the Settings window: `settings-general`, `settings-privacy`, `settings-about`, `settings-gated` (before consent);
  - the sheets themselves: `chat-quiz` (its failure state; no local server), `chat-mode-sheet`.
- **Accessibility:**
  - `lesson-complete` under Increase Contrast (`-hc`, `-dark-hc`), **Reduce Transparency** (`-rt`, `-dark-rt`: its glass "Done for now" and Share become opaque), the macOS 14–25 / CI fallback (`-noglass`, `-dark-noglass`) and Reduce Motion (`-rm`).
  - `path-week`, `unit-test` and `gate-consent` under Increase Contrast.
  - The Quiz me sheet and Settings ▸ Privacy under Reduce Transparency.

**Looked at, and fixed:**
- The complete card's ring carried a "1/2" label that crowded a 44 pt ring next to the same count in words; the label is gone.
- At 700 × 600 the card's week row was cut mid-line above the buttons; it now fades.
- The mastered result stacked two heavy lines ("Unit mastered" over a semibold sentence); the sentence is now reading text.
- The open unit check had no "you are here" mark; it takes the current lesson's halo.
- The unavailable-check state opened Today (the launch route ran after it); fixed.
- The harness photographed the window under a sheet and then hung on quit; `-MacSnapshotWindow sheet` and a forced exit fix both.

## Decisions and deviations, and why

1. **The credential headline (the step's ask) over SPEC §6's plain "Lesson complete".**
   - The judges asked for it, and the educator's objection was that it was asserted, not shown.
   - So it's derived only where the objective says "Understand X." (15 lessons), and every other lesson keeps "Lesson complete".
   - It's grounded twice: the card exists only after Merc judged proficiency, and it says so ("Merc marked this lesson complete from your answers."); the key ideas show what was covered.
   - The student's own words ("In your words") would be stronger evidence, but that's Field Notes' graft, which this step doesn't take (SPEC §7).
2. **Lesson codes ("1.3", "Opens after 1.2"), as the step asked**, over SPEC's "Opens after Lesson 3".
   - They're used throughout the page: the nodes, the eyebrow ("Lesson 1.3 · You're here") and the button ("Start Lesson 1.3").
   - VoiceOver says "lesson 1.3".
3. **`DuoButton` maps to the large (44 pt) Night capsule** and `BrandButton` to the regular (36 pt) one. `DuoButton` is the first-run and path button (SPEC §3.2 named no size for it).
4. **Settings sits on Night's flat canvas with `ink3` footers.** SPEC D10 kept system backgrounds, but the step asked for "Night style". The form, its controls and its type are still the Mac's own.
5. **The mastered result's sentence is reading text**, not `title2` (polish, above). Retake is not bound to Return (it resets a graded attempt); Done is, when passed.
6. **The mode explainer and Quiz me sheets were restyled too.** They were left over from step 02 and are part of "the rest of the app". Their copy and behaviour are unchanged. New lines: "Chat mode", "Quiz from this chat", "Merc on your written answer".
7. **VoiceOver's result announcement still says "Written defense"** (`UnitTestViewModel.resultAnnouncement` is the iPhone's string, which this branch can't change). The visible label is "Written answer".

## Skipped, and why

- **The Help window and the Progress sheet:** palette only. SPEC §3.1 keeps Help in system type, and Progress inherits the palette (never zeros). Neither was in this step's list.
- **The unit-mastery ceremony, the notebook, the share card, "In your words", "Sure / Not sure":** other directions' grafts (SPEC §7).
- **On screen only:**
  - The glass "Done for now", Share and Quiz chrome on macOS 26: the harness photographs glass dark. The opaque Reduce Transparency and the fallback versions are photographed.
  - The consent checkbox's and age pop-up's bezels: missing in the PNGs, as before. `-MacSnapshotDumpControls` lists them.
  - Focus rings and keys with Full Keyboard Access on: Tab through the path's rows, the complete card's buttons, the gate.
  - The unit check's card ring does show in `unit-test-quiz`.

## Founder's app

- PID 98503 ran before and after every run, and nothing was killed by name.
- `/private/tmp/merc-mac-dd` was never read or written.
- The frontmost-app watcher saw only Claude in front in every run; the copy never came forward.
- The copy's container `~/Library/Containers/com.mayoailiteracy.mercurius.native.macns3` holds test data only.
