# Step 06: fixes from the code and screenshot review

Branch `fix/ios-student-2026-10`, on top of `4a669b0` (the verified step 05 state). Nothing is pushed. I fixed or answered the 12 review findings below. The server is unchanged.

## Commits

| Commit | What | Review finding |
|---|---|---|
| `aafd23c` | Scale Merc's reply text for Dynamic Type once, not twice | 1 (high) |
| `4080275` | "Jump to latest" gets its own strip; a tall failure opens at its start | 4, 3 |
| `5f7fc19` | DEBUG: the crisis preview constant is `nonisolated` (the Swift 6 warning VERIFY.md listed) | VERIFY note |
| `f5acd18` | Gate at large text: a visible line says what a dimmed button waits for, and a tap scrolls to the control; the retention copy; an edge fade | 2, 5 |
| `ffdbd78` | Lesson title on two lines (in the thread at AX sizes); a readable placeholder; the mode menu whenever the pills don't fit | 8, 9, 7 (pills) |
| `bb5873f` | The path is a list from xxxLarge; it opens with a unit's banner whole | 7 (path), 6 |
| `b1f1538` | Settings: errorText for Delete; an icon-only Copy at AX sizes; plainer reset warning | 10, 11 |
| `d2b58a3` | Adjustments from the simulator pass ("Answer…", a smaller thread title, the first stop opens at its banner) | 9, 8, 6 |

## The findings, one by one

### 1 (high): reply text scaled twice. Fixed (`aafd23c`)

**Verified.** MarkdownUI 2.4.1 wraps the theme's font size in its own `@ScaledMetric(relativeTo: .body)` (`Views/Markdown.swift`, `ScaledFontSizeModifier`). Both reply bubbles passed it `bodyFontSize`, which was already `@ScaledMetric`-scaled. The new test below measured the old code: from Large to AX3, a one-line reply grew 2.76x while the student's bubble grew 1.67x.

**Fix:**
- `ReplyMarkdownStyling` now takes two sizes. `baseSize` is the unscaled 17, which MarkdownUI scales once. `scaledSize` is used only for the list markers, which are drawn with fixed-size fonts.
- The key-idea and example cards, the check question and the [Q] card keep the scaled size. They draw with `Font.custom(_, fixedSize:)` or `.system(size:)`, so scaling once there is right.

**Result:** at AX5 the lesson reads "Here's a / wild fact to / kick us off:" instead of "Her / e's" (`compare-se3-lesson.png`). In free chat at AX1, Merc's reply is now the same size as the student's bubble (`compare-16pm-chat.png`).

**Test:** `MercuriusTests/ReplyTextScaleTests` (new, iOS, runs in CI's `xcodebuild test`). It renders the real `MessageBubbleView` and compares how much a one-line reply grows from Large to xxxL, AX1 and AX3 with how much the student's bubble grows, in free chat and in a lesson. It fails on the old code (all three tests; 2.76x vs 1.67x at AX3) and passes now. A snapshot can't catch this, because at Large the scale factor is 1.

### 2 (medium): the gate's required control off-screen behind a dimmed button. Fixed (`f5acd18`)

**Verified** in the shots: at AX1 to AX5 the consent switch opens out of sight on both phones, and on the SE at AX5 the age wheel does too.

**Fix**, at accessibility sizes only (below them the switch is pinned and the wheel is in view):
- A visible line under the dimmed button says what it waits for: "Turn on the switch above to continue" or "Pick your age on the wheel to continue". It stops growing at AX2 and goes once the switch is on or an age is picked.
- Tapping that line, or the dimmed button itself, scrolls the control into view and outlines it for 1.6 s. The scroll anchors the control's foot to the bottom of the scroll area, right above the button it enables, because at AX5 the consent row is taller than the screen and the switch is at its foot.
- The tap on the dimmed button is a clear overlay hidden from VoiceOver. VoiceOver still meets a disabled button with its hint, so `isEnabled` stays false for the UI tests.

**Tests:**
- `GateCopyTests`: `showsSwitchHint` and `showsWheelHint` per size.
- New UI test `testDimmedAgreeShowsTheSwitchAtLargestTextSize`. At AX5 the line is there and the switch starts out of view. Tapping the dimmed Agree brings the switch above Agree. Turning it on enables Agree and removes the line.

**Shots:** `compare-se3-gate.png`, plus `*-disclosure-revealed.png` and `*-age-revealed.png`.

### 3 (medium): a tall failure opened at its end on the SE at AX5. Fixed (`4080275`)

**Verified:** a retryable failure changed the footer to Retry, and `footerChanged()` scrolled to the bottom.

**Fix:**
- A reply that failed before any text arrived is now a "bare failure" (`MessageListView.isBareFailure`). When one appears, the list scrolls its top to the top of the reading area (`.showLatestMessageTop`), as AUD-09 does for replies.
- That scroll stops at the end of the thread. A failure that fits therefore lands exactly where the bottom would, with Retry in view (`se3-L-blockpage.png`).
- A failure taller than the reading area now opens on "This network may be blocking Mercurius." (`compare-se3-AX5-failures.png`). The pill shows the way to Retry.
- The trigger now watches the footer and the bare-failure state together, so a failure with no Retry also opens at its start.
- A cut-off reply that has text keeps the bottom anchor, so a student who followed it isn't pulled back up.

**Tests:** `footerChanged(latestIsBareFailure:)`, following and not following; `isBareFailure` for empty, whitespace, partial, streaming, settled, user and nil.

### 4 (medium): the pill covered the last visible line. Fixed (`4080275`)

**Verified.** I didn't take the suggested fix, because a bottom content margin only helps at the very end of the list. The pill hides near the end anyway; it covers text in the middle of a held reply.

**Fix:**
- The pill now sits in its own strip under the scroll view (a `VStack`), so it never overlaps text.
- Whether it fits is judged on the list and strip together (`readingAreaHeight`). The strip shrinking the list therefore can't make the pill hide itself, bring the room back, show again, and so on.
- The strip only moves the end further away, so it can't flicker at the `pillDistance` threshold either.
- The strip's appearance changes the list height. `geometryChanged` treats that like the keyboard: it never moves a student who isn't at the end.

**Tests:** the strip's hysteresis, a small area staying pill-free, and the strip resize leaving a reader where they are.

**Cost:** on the SE at AX5 with the keyboard up, the reading area shows 2 lines plus the pill (`se3-AX5-lesson-keyboard.png`); before, it showed 1–2 words. The `pillMinimumViewport` rule (180 pt) is unchanged.

### 5 (low): the retention row. Fixed (`f5acd18`)

- **Copy:** "…You can delete them sooner in Settings → Delete my data & start over. Deleting the app doesn't delete them." This is consent copy, so it joins the pending `ConsentGate.currentVersion` decision. I did **not** bump the version, which is still `1`.
- **Fade:** a 20 pt fade at the bottom edge of every gate step's scroll area, with matching bottom padding so the last line clears it at the end. A row running on under the pinned switch now fades out instead of being sliced mid-line (`compare-disclosure-copy.png`).
- **Tests:** `GateCopyTests` checks the new sentence and button name.

### 6 (low): the path opened with the unit banner cut under the streak bar. Fixed (`bb5873f`, `d2b58a3`)

**Fix:** `PathOpeningScroll`.
- When the frontier is a unit's first lesson, including the path's very first stop, the path opens with that unit's banner whole at the top, just under the streak bar, and the node below it.
- Otherwise the node is centred, as before. When the whole path is done, it opens at the top.
- The scroll isn't animated under Reduce Motion.

My first version opened the path's first stop at the very top. On the SE at AX5 that showed only "Your learning path" and the progress line, so `d2b58a3` changed it.

**Status bar:** on the 16 Pro Max at AX5 the time and signal are visible again (`16pm-AX5-path.png`). The dark banner no longer sits under the bar, which is what had made iOS draw light status-bar text. I didn't set a status-bar style explicitly.

**Trade-off:** on the SE at AX5 the banner alone fills the screen, so "Start now" is one short scroll below it (`se3-AX5-path.png`). Before, the node was centred and the banner was sliced.

**Tests:** `PathOpeningScroll.target` for the first stop, a later unit's first lesson, a mid-unit lesson, a unit test, a finished path and an unknown id.

### 7 (low): xxxLarge truncations. Fixed (`ffdbd78`, `bb5873f`)

**Mode pills:**
- The pills now lay out with `EqualWidthHStack`: equal columns, with an ideal width of three times the widest pill.
- They sit inside `ViewThatFits`, so below accessibility sizes the "Mode: Socratic" menu stands in whenever an equal share would wrap a label.
- The SE at xxxLarge now shows the menu instead of "Discus-sion". At Large on every phone the pills still fit, so the UI tests' "Debate" anchor is unchanged.

**Path:** `LearningPathLayout.listFrom = .xxxLarge`, so the list now starts at xxxLarge.
- At xxLarge on the SE the winding labels still fit (`se3-xxL-path.png`).
- At xxxLarge they truncated on both phones; the list now shows them whole (`compare-xxxL-pills-path.png`).

**Tests:** `EqualWidthHStack.neededWidth`, and `LearningPathLayout.forSize` per size.

### 8 (low): the lesson title truncated in the header. Fixed (`ffdbd78`, `d2b58a3`)

- **Below accessibility sizes:** the header title gets two lines. At Large it now reads "What happens when you type / a prompt" in full on both phones.
- **At accessibility sizes:** the header has no title, to keep AUD-08's room. The thread's first row shows the title instead, in title3 capped at AX2. It is hidden from VoiceOver, which hears the title in the header label.
- **Limit:** that row scrolls away when the first reply is held at its top, so at AX sizes the student sees it only before the reply fills the screen, or by scrolling up. Holding the first reply at the title instead would have cost an SE at AX5 about 40% of its reading area, so I didn't.
- **Tests:** `LessonHeaderBar.showsTitle` per size, and `titleLineLimit == 2`.

### 9 (low): a faint placeholder. Fixed (`ffdbd78`, `d2b58a3`)

- **Contrast:** the composer's prompt uses `BrandColor.textSecondary`. Measured from the shots: 4.74:1 in light mode (`#5D6A8A` on `#EEF0F7`) and 6.27:1 in dark mode, up from 1.70:1 and 2.42:1. This applies to free chat as well.
- **AX sizes:** the lesson's placeholder is "Answer…". "Type your answer…" read "Type yo…", and my first try, "Your answer…", still read "Your an…" on the SE at AX5.
- **Tests:** `ChatInputBar.placeholder(_:compact:at:)`.

### 10 (low): Settings. Fixed (`b1f1538`)

- **Delete:** "Delete my data & start over" uses `errorText`, measured at 6.47:1 on white. It keeps its destructive role.
- **Copy:** at AX sizes it shows the icon alone, with a 44 pt target. VoiceOver still reads "Copy session ID".
- **Tests:** `copyShowsIconOnly` per size.

### 11 (low): the reset sheet's wording. Fixed (`b1f1538`)

- **New copy:** "Our server still has your chats and progress under the ID below. After this reset, the app can't delete them for you. To delete them later, email privacy@trymercurius.com with this ID, so copy it first."
- **Unreadable-ID variant:** it now says "nothing on this device can delete them".
- **Tests:** both variants' copy. The existing UI test still finds `privacy@trymercurius.com`.

### 0 (medium, server analytics): a cut-off opener's answer is logged as a 'turn', not a 'start'. Not fixed here; open risk

**Verified** by reading `server.js`:
- `lessonStart` is `turnIndex === 1 || no assistant message` (around line 1710).
- An aborted or errored stream records no event (`if (stream.errored || stream.aborted) return;`, around line 2035).
- Since AUD-29, a student who answers a cut-off opener sends `[opener, cut-off reply, answer]`. The server logs that as a `turn`, so that attempt never gets a `start` row.

**Effects:**
- The lesson funnel undercounts starts.
- A `complete` can land with no `start` before it.
- On a retake, `db.recordLessonEvent` drops the new `complete` as a duplicate of the last attempt.

**Why it isn't fixed:** students see nothing different. Dropping the cut-off reply from the wire again would undo AUD-29, which is the tutoring fix, and this PR leaves the server unchanged.

**Server follow-up** (not done):
- Decide `lessonStart` from `lesson_events`: the turn is the start when the session has no `start` row for this `lesson_id` newer than its latest `complete`.
- Add a server test that sends `[opener, assistant, user]` after an aborted opener and expects a `start` row.

## Tests

All local, at `d2b58a3`. These are the results recorded in `PR.md`.

| Check | Result |
|---|---|
| `swift test --parallel` from an empty scratch path | **927 tests in 138 suites passed**. VERIFY had 915 in 137; the new suite is `ThreadEndTests`. |
| `xcodebuild test` with CI's flags, clean derived data, Audit 16PM | **TEST SUCCEEDED, 31/31**, none retried. That is 6 app unit tests (the new `ReplyTextScaleTests` ×3, `AppLaunchTests`, `LiveActivityStateTests` ×2) and 25 UI tests (the new `testDimmedAgreeShowsTheSwitchAtLargestTextSize`, plus the 24 VERIFY lists). |
| `AppStoreScreenshots` + `PerformanceTests` | 4/4. Cold launch 0.811 s; seeded scroll 10.57 s, 94.7 MB peak; footprint 77.9 MB. |
| Snapshot comparison, recording forced off | The same 11 pass and the same 12 fail as at `720dbac` and `4a669b0`. To check this step's own drift, I rebuilt `4a669b0` (a `git archive` copy, deleted afterwards) and rendered the snapshots there. **All 12 failing renders are pixel-identical at `4a669b0` and HEAD**, so this step causes no snapshot drift. `__Snapshots__` is untouched. |
| Simulator build | `xcodegen generate` + `xcodebuild build` from emptied derived data on Audit 16PM: **BUILD SUCCEEDED**, first attempt |

**Warnings:** only the 42 pre-existing ones in two test files remain. The `RootView.swift:448` warning is gone.

**`ReplyTextScaleTests` against the old code:** I stashed the fix and ran the test. All three tests fail there: at AX3 the reply grew 2.76x while the student's bubble grew 1.67x, and the lesson reply grew 2.26x. All three pass with the fix.

## Screenshots: `docs/ios-batch/shots/review-fixes/`

**How they were taken:** a temporary XCUITest driver, `ZZFixShots`, launched each screen with the DEBUG arguments VERIFY's index lists and saved `XCUIScreen.main.screenshot()`. It was never committed and is deleted. Text size was set system-wide with `simctl ui content_size`. The SE is in dark mode and the 16 Pro Max in light. Both sims are back at `large`.

**Files:**
- 66 single screens, named `<sim>-<size>-<screen>.png`:
  - **Lesson:** keyboard down and up.
  - **Free chat.**
  - **Gate:** `age` and `disclosure`, plus `*-revealed` after tapping the dimmed button.
  - **Path.**
  - **Settings.**
  - **The reset sheet:** `*-L-reset-sheet`, with nothing on port 3000 so the delete fails.
  - **Failures:** `blockpage` and `newsessions`, from `-LessonReplayNetwork`.
- 8 before/after sheets, `compare-*.png`. "Before" is VERIFY's shot of `4a669b0` (or step 04/05's for the failures and the reset sheet).

## Open risks and notes

- **Stale incremental Xcode builds crash Settings.** After `b1f1538`, which adds a stored property to the public `SettingsView`, an incremental `xcodebuild` reused an `AppFeature` built against the old layout. Opening Settings then crashed in `outlined destroy of SettingsView`. A clean derived-data build fixed it. The Settings shots come from that clean build plus one incremental rebuild of a CurriculumFeature-only change, and the test runs above come from clean builds. CI builds clean. Locally, delete the derived data after pulling this branch.
- **Gate content scrolls under the status bar at AX sizes.** After a scroll (including the new reveal), the gate's text passes under the status bar's time (`se3-AX5-age-revealed.png`). That is SwiftUI's default for a scroll view at the top edge, and it predates this branch: any scroll on these steps did it. I didn't change it.
- **The thread title at AX sizes** is mostly scrolled away by the AUD-09 hold (see finding 8).
- **The pill strip** costs about one line of reading area while it shows (finding 4).
- **iOS 17, VoiceOver, real devices:** not run. The sims are iOS 26.4. The reveal's VoiceOver path is the disabled button with its hint, plus the new hint line, which is a plain button. I haven't heard either spoken.
- **Not done (instructed):** AUD-34, snapshot recording, and the `ConsentGate.currentVersion` bump. Nothing was pushed, uploaded or released.

## State left behind

- **Final build:** `xcodegen generate` + `xcodebuild build` from emptied derived data (`/private/tmp/merc-fixios-dd`) on Audit 16PM: **BUILD SUCCEEDED** on the first attempt. No warnings come from the project's own sources.
- **Simulators:** both are back at text size `large`; Audit 16PM is in light mode and Audit SE3 in dark. Simulator.app is still open, as VERIFY left it.
- **Temporary files:** the screenshot driver and the base-commit copy are deleted. There are no " 2" duplicates.
- **Uncommitted:** `docs/ios-batch/`, as in the earlier steps.
- **Not done (instructed):** nothing was pushed, uploaded, recorded or released. `ConsentGate.currentVersion` is still `1`.
