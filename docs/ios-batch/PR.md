# iOS: fixes from the October 2026 student-experience audit (AUD-02 first)

Branch `fix/ios-student-2026-10`, 35 commits on `main` `720dbac` (the last adds these notes). It touches `ios/` and `docs/APP_STORE_LISTING.md` only. `server.js`, `db.js` and `lib/` are unchanged, and the app keeps working against production as it is today:
- every new field it decodes is optional or defaults off (`crisis`, the SSE `scope`, the Live Activity's new fields);
- I checked each shape against `server.js` on this branch.

**Not in this PR:**
- **AUD-34** (routing to the frontier lesson): waits for your approval.
- **AUD-17 follow-up:** waits on the server fix.

The audit is `docs/audits/2026-10/REPORT.md` ("Batch 4: iOS PR"), with evidence in `findings.json`.

## Summary by AUD id

| AUD | What the student gets | Commits |
|---|---|---|
| **02** | A unit-test or chat-quiz answer the server flags as a crisis now shows a warm support screen: "I'm really glad you told me", with tappable Call 988, Text 988, Text HOME to 741741 and Call 911. It no longer shows a failed grade or Retake. Both crisis shapes are handled: a 200 `crisis:true` grade and a non-2xx crisis body. | `c84abf0`, `ccadc0c` |
| **08** | The lesson gets the screen. The header is one compact row with Done always visible. The title gets two lines (at accessibility sizes it is the thread's first row instead). Merc's coach card scrolls away and steps aside while the student types. **Merc's reply text is scaled for Dynamic Type once, not twice:** it was ~1.65x too big at AX1 and ~3x at AX5, breaking words ("Her / e's"). | `e8ee6cf`, `aafd23c`, `ffdbd78`, `d2b58a3` |
| **09** | A reply opens at its first line. The stream is followed only while the student is at the bottom. A "Jump to latest" pill, in its own strip so it never covers text, leads to the end. A failure taller than the screen opens at its first sentence. | `e8ee6cf`, `4080275` |
| **12** | At the largest text sizes, every gate step scrolls with its button pinned. A dimmed button now says what it is waiting for, and tapping it scrolls to the switch or the age wheel. | `484b64b`, `cb73b20`, `f5acd18` |
| **21** | Readable text tokens (`accentText`, `successText`, `errorText`, all ≥ 4.5:1), including Settings' "Delete my data & start over" (it was 3.57:1). | `282f2e7`, `d450d89`, `b1f1538` |
| **22** | The unit test uses body-size rows with visible A–D letters. VoiceOver says what is picked and what is right. | `f1f34fd`, `6bd635c` |
| **23, 46, 49** | VoiceOver walks a lesson reply block by block and hears replies land or fail. Headings are marked. Targets are 44 pt. | `f17adf7` |
| **27** | The consent screens say how long chats are kept ("90 days… photos for 24 hours… Settings → Delete my data & start over. Deleting the app doesn't delete them.") and warn against sharing private details. | `0f2b3c8`, `f5acd18` |
| **28** | The age wheel opens on "Select your age", then "18 or older" down to 13, with "12 or younger" last. | `c8d284d` |
| **29** | A reply cut off mid-stream stays in the thread, and on the wire, when the student answers it. A reply that failed before any text shows only the error line, with no empty Merc bubble. | `f5a4e23` |
| **30** (iOS half) | A daily limit shows its reset as a local clock time. Retry is offered only where it helps. A paused or capped server no longer locks the unit-test answer. | `fe29077`, `ebec681`, `07ebc1c` (DEBUG) |
| **32** | When a school network blocks Mercurius, the app names the network and suggests cellular data, not "the server". | `c1781b3` |
| **33** | The lesson intro has "Not now", which leaves without starting the lesson. | `e8ee6cf` |
| **35** | A first run interrupted after consent resumes at Your path. | `c8d284d` |
| **36** | The weekly nudges are skipped once the week's goal is met, and no longer call Sunday a new week. | `f565a0b` |
| **37** | The Live Activity shows the week. It shows a countdown only when a streak ends tonight. | `8513073` |
| **44** | The lesson placeholder reads "Type your answer…" in a readable colour ("Answer…" at accessibility sizes). The late-night pep talk and the scrolling line are gone. | `e8ee6cf`, `1f1e305`, `ffdbd78`, `d2b58a3` |
| **47** | From xxxLarge up, the path is a list whose titles wrap. It opens with the frontier's unit banner whole, not cut under the streak bar. | `484b64b`, `bb5873f`, `d2b58a3` |
| **48** | The mode pills become one "Mode: Socratic" menu at accessibility sizes, and whenever the pills wouldn't fit (an SE at xxxLarge read "Discus-sion"). | `484b64b`, `ffdbd78` |
| **50** | iPhone SE layouts: Home's two buttons, the empty chat's four starters, the consent switch pinned above "Agree", and the sentence as part of its tap target. | `3e543c6`, `0f2b3c8`, `f403674` |
| **51** | The lesson header says "UNIT 01 · LESSON 1 OF 4" instead of an unlabelled "0/4". | `e8ee6cf` |
| **52** | Merc's cheering arm is attached at the shoulder. | `d5e587f` |
| **54** | When "Delete my data" can't reach the server, the app shows the old ID and a Copy button before a device-only reset, and says in plain words that only an email to privacy@trymercurius.com can delete the server copy afterwards. | `c7dbb52`, `4a669b0`, `b1f1538` |
| **57** | `PrivacyInfo.xcprivacy` marks the four collected types as linked. The App Store listing doc matches. | `a4232eb` |

`5f7fc19` is DEBUG-only: it removes the one Swift 6 isolation warning this branch had added.

The per-step notes are `docs/ios-batch/01-crisis.md` … `05-firstrun-engagement-polish.md`, `VERIFY.md` (the full verification of `4a669b0`) and `06-review-fixes.md` (the review fixes on top).

## Screenshots

All are from the iOS 26.4 simulators: the iPhone SE (3rd generation) in dark mode and the iPhone 16 Pro Max in light mode, at text sizes L, xxxL, AX1 and AX5. A compressed key set (2 MB) is committed in `docs/ios-batch/key-shots/`. The full set (248 shots, 98 MB, including the 88-shot verification grid) stays local in the worktree's `docs/ios-batch/shots/` and is not committed.

**AUD-02, the crisis support view** (unit test on the SE at L; the chat quiz):

<img src="https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/01-crisis-se3-L.jpg?raw=true" width="260"> <img src="https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/01-crisis-16pm-AX5.jpg?raw=true" width="260"> <img src="https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/01-quiz-crisis-se3-L.jpg?raw=true" width="260">

**Before and after** (each sheet labels its panels):

| Sheet | Shows |
|---|---|
| `compare-se3-lesson.jpg` | The lesson at AX5 (keyboard down and up) and at L: readable reply text, the pill in its own strip, the two-line title. |
| `compare-16pm-chat.jpg` | Free chat at AX1 and AX5: Merc's reply is the same size as the student's text. |
| `compare-se3-gate.jpg` | The gate at AX1 and AX5, with the hint line and the reveal. |
| `compare-se3-AX5-failures.jpg` | The block page and the new-sessions limit open at their first sentence. |
| `compare-disclosure-copy.jpg` | The retention copy and the edge fade. |
| `compare-xxxL-pills-path.jpg` | The mode menu at xxxL, the path list, the banner whole. |
| `compare-lesson-header-placeholder.jpg` | The two-line title and the readable placeholder. |
| `compare-settings.jpg` | The Delete colour, the icon-only Copy, the reset-sheet copy. |

![lesson](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/compare-se3-lesson.jpg?raw=true)
![chat](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/compare-16pm-chat.jpg?raw=true)
![gate](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/fix/ios-student-2026-10/docs/ios-batch/key-shots/compare-se3-gate.jpg?raw=true)

**Also committed:** `02-cutoff-answered-se3-L.jpg` and `02-failempty-se3-L.jpg` (AUD-29), and `04-blockpage-se3-L.jpg` and `04-dailylimit-se3-L-newyork.jpg` (AUD-30/32).

## Tests

All local, on 2026-10-19, at `d2b58a3`.

| Check | Result |
|---|---|
| `swift test --parallel` (`ios/Packages`, from an empty scratch path, as CI runs it), including ArchitectureTests | **927 tests in 138 suites passed** |
| `xcodegen generate` + `xcodebuild test` with CI's exact flags (skips snapshots, perf and App Store screenshots; retries on), clean derived data, iPhone 16 Pro Max sim | **TEST SUCCEEDED, 31/31**, none retried: 6 app unit tests (including the new `ReplyTextScaleTests` ×3) and 25 UI tests (including the new `testDimmedAgreeShowsTheSwitchAtLargestTextSize`) |
| `AppStoreScreenshots` + `PerformanceTests` (CI skips these) | **4/4 passed**. Cold launch 0.811 s; seeded scroll 10.57 s, 94.7 MB peak. No baselines are committed. |
| Snapshot comparison (`ViewSnapshotTests`, recording forced off) | 11/23 pass, 12 fail; the same 12 fail at `720dbac`, and at `4a669b0` they render pixel-identically to HEAD. See below. |
| `xcodegen generate` + `xcodebuild build` for the simulator, emptied derived data | **BUILD SUCCEEDED**, first attempt; no warnings from the project's own sources |

**Warnings:** the only remaining ones are 42 pre-existing ones in two test files (`APIClientEndToEndTests`, `ChatViewModelIntegrationTests`).

**The wire:** I checked it against this branch's `server.js` (mock mode, no key) in step 04; see `04-network.md`.

## Snapshot references to re-record (founder)

Recording is yours. Nothing was recorded, and `__Snapshots__` is untouched.

All 12 failing references were already stale at `720dbac`. **Re-record all 12:**

1. `testCurriculumListAtAccessibilityXXL`
2. `testEmptyChatViewLight`
3. `testEmptyChatViewDark`
4. `testEmptyChatViewAccessibilityXXL`
5. `testLessonCompleteOverlayWithNext`
6. `testLessonCompleteOverlayLastLessonDark`
7. `testMercAllStates`
8. `testMessageBubbleAssistantFailed`
9. `testMessageBubbleAssistantPlain`
10. `testMessageBubbleAssistantTyping`
11. `testModeSelectorAtAccessibilityXXL`
12. `testModeSelectorDefault`

**What changed which reference:**
- **This PR's review fixes (`aafd23c`…`d2b58a3`):** none. All 12 failing renders at HEAD are pixel-identical to those at `4a669b0`. Some fixes touch code under snapshotted views: the mode pills' layout and the reply's font size. At the snapshotted sizes, though, the result is the same.
- **Earlier commits (from `VERIFY.md`):** 6 renders change, each intentionally.

  | Snapshot | Change |
  |---|---|
  | `testModeSelectorAtAccessibilityXXL` | The pills become one "Mode: Socratic" menu (AUD-48). |
  | `testMessageBubbleAssistantFailed` | The darker `errorText` red (AUD-21). |
  | `testLessonCompleteOverlayWithNext` | Text tokens (AUD-21) and Merc's arm (AUD-52). |
  | `testLessonCompleteOverlayLastLessonDark` | The same, in dark mode. |
  | `testMercAllStates` | The celebrate arm only (AUD-52). |
  | `testCurriculumListAtAccessibilityXXL` | The path header can wrap (AUD-47). |

- **The other 6** render the same as at `720dbac`; their references predate this branch.

**Orphans:** `testReportCardView{Failed,Loaded,Loading}.1.png` have no test. They were orphaned before this branch, and you can delete them.

## Founder decisions

1. **`ConsentGate.currentVersion` is still `1`.** The consent copy changed: AUD-27 added a retention row and a privacy row in the limits, and this PR's last pass changed the retention row's wording. The agreement sentence on the switch is unchanged.
   - **Bump to 2:** every existing install sees the agreement again on its next launch.
   - **Keep 1:** existing installs keep the consent they gave to the shorter copy.
   - If you bump it, bump the UI tests' `-consentVersion 1` launch arguments in lockstep (`MercuriusUITests.launchApp` and the first-run tests).
2. **AUD-34:** routing "Start" to the frontier lesson is not done. It waits for your OK.
3. **App Store Connect privacy label (AUD-57).** No build is needed for this:
   - In App Privacy, set "Linked to the user" to **Yes** for User ID, Other User Content, Photos or Videos, and Product Interaction.
   - Keep Tracking at No.
   - From this build on, the manifest says Linked = true.
4. **Product calls flagged in the step notes.** Each is a one-line revert:
   - no Retry on the kill switch or the spend cap (`ServerRefusal.isRetryable`);
   - the strict `text/event-stream` check on `/api/chat`;
   - free chat opens a saved thread at its top;
   - "Not now" on the lesson intro leaves through the same path as Done;
   - weekly nudges are skipped rather than replaced once the goal is met;
   - a lapsed student hears at most 16 more nudges.
5. **Server follow-ups**, not in this PR:
   - **Lesson analytics (review finding):** since AUD-29, a student who answers a cut-off opening reply sends `[opener, cut-off reply, answer]`, which `server.js` logs as a `turn`, never a `start`. The funnel undercounts starts, and a retake's `complete` can be dropped as a duplicate. Students see nothing. Fix it on the server by deciding `lessonStart` from `lesson_events`, not from the message history (details in `06-review-fixes.md`).
   - The AUD-30 server half (UTC-midnight quotas; `spend_cap` sends no `retryAfterSec`).
   - `scope` on the SSE refusal frame.
   - The AUD-17 soft-break follow-up.

## Needs a real device (and VoiceOver)

Nothing here was heard with VoiceOver or tapped on a phone. The simulators are iOS 26.4; iOS 17 wasn't run.

- **AUD-02:**
  - tap Call 988, Text 988 (`sms:` prefill), Text HOME to 741741 and Call 911 on an iPhone;
  - check what an iPad without cellular does with `tel:`.
- **AUD-23, 46, 49 (VoiceOver):**
  - Walk a lesson reply: the "Merc's reply" container, each block, and the [Q] options.
  - Check the report actions.
  - Listen for the "Merc replied" and failure announcements.
  - Check the unit test's picked and right values.
- **The consent switch:**
  - VoiceOver should meet one switch labelled with the sentence;
  - at AX sizes, the new hint line ("Turn on the switch above to continue") and the dimmed Agree with its hint;
  - the Copy icon's "Copy session ID".
- **AUD-37:** the Live Activity on a real lock screen and in the Dynamic Island.
- **AUD-36:** the weekly nudges over a real week, including a lesson finished on another device.
- **AUD-32:** a real school network, captive portal or TLS-intercepting filter. Only stand-ins were tested.
- **iOS 17:**
  - the iOS 17 scroll fallback (no scroll phases);
  - the mode menu's `Picker` in a `Menu`;
  - `TextField`'s `prompt` colour.

## Suggested TestFlight plan

`ios/project.yml` is at 2.3.0 (16), and `release.sh` bumps the build number.

1. **Build A, crisis only (if the rest needs more time).** AUD-02 is the safety fix.
   - Cut `release/crisis` from `ccadc0c`: `c84abf0` plus `ccadc0c`, everything else excluded. `c84abf0` stands alone if you want only the unit-test path.
   - Run CI on it. Locally, step 01 ran `swift test` and a simulator build at that commit, but not `xcodebuild test`.
   - Then run `ios/scripts/release.sh` → 2.3.0 (17).
   - It needs no consent decision. On a real phone, tap the 988 and 741741 links before sending it to testers.
2. **Build B, the whole branch,** once you've:
   - decided `ConsentGate.currentVersion`;
   - re-recorded the 12 snapshots;
   - run the VoiceOver pass above.

   Merge, then `release.sh` → 2.3.0 (18) (or (17) if Build A was skipped). Set the App Privacy label in App Store Connect before or with this build's review.
3. **After Build B:** the server follow-ups above, then AUD-34 if you approve it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
