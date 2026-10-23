# Step 05: first run, engagement and polish

Branch `fix/ios-student-2026-10`. Nothing is pushed.

Done: AUD-27, AUD-28, AUD-35 (first run); AUD-36, AUD-37, the rest of AUD-44 (engagement); AUD-50, AUD-52, AUD-54, AUD-57 (polish).
Not done, as instructed: AUD-34, the AUD-17 follow-up, snapshot recording, `ConsentGate.currentVersion`.

## Commits

| Commit | Subject | AUD |
|---|---|---|
| `c8d284d` | First run: put the blocked age last on the wheel; resume at Your path | 28, 35 |
| `0f2b3c8` | Tell students how long chats are kept; pin the consent switch on small phones | 27, 50 |
| `f565a0b` | Skip the weekly nudges once the week's goal is met; stop calling Sunday a new week | 36 |
| `8513073` | Live Activity: show the week, and a countdown only when a streak ends tonight | 37 |
| `1f1e305` | Drop the late-night pep talk and the scrolling lecture | 44 |
| `3e543c6` | Keep the next step above the fold on an iPhone SE | 50 |
| `d5e587f` | Attach Merc's cheering arm at the shoulder | 52 |
| `c7dbb52` | Show the old ID and what stays on the server before a device-only reset | 54 |
| `a4232eb` | Privacy manifest: mark the collected data as linked | 57 |
| `f403674` | Consent row: the sentence turns the switch on; the heading scrolls away | 50 follow-up |
| `4a669b0` | Keep the privacy@ address off the main actor | 54 follow-up |

Each commit's message has the detail. Package tests were run after each commit's changes; the simulator build and UI tests ran at the end (and at `8513073`, `3e543c6`, `c7dbb52` along the way). I did not build every commit on its own.

## What changed

### First run

- **AUD-28, age wheel.** The order is now: placeholder, "18 or older", 17 … 13, "12 or younger". A one-row nudge from the placeholder picks an eligible age. No under-13-only confirmation was added (the audit warns it would reveal the blocking answer).
- **AUD-35, resume.** Consent is recorded at "Got it", one screen before the end. A full run that finds consent current now reopens on Your path instead of replaying Meet Merc, age, disclosure and limits. An age block still wins. Consent is read from `UserDefaults.standard`, the same place `@AppStorage` reads, so the UI tests' argument domain works.
- **AUD-27, consent copy.**
  - **New disclosure row:** "Our server keeps your messages for 90 days and photos for 24 hours, then deletes them. You can delete them sooner in Settings → Delete my data. Deleting the app doesn't."
  - **New limits row:** "Don't share your full name, address or anything private." The subtitle now says "Four things".
  - **Unchanged:** the agreement sentence on the switch.
  - **Settings → Privacy choices** now says 90 days too.
  - **Left out:** the audit's draft said the 90 days are "so lessons can pick up where you left off". That isn't true (the conversation lives on the phone, per `privacy.html`), so I dropped that clause. The numbers match `lib/scheduler.js` and the privacy page.
- **AUD-50, consent switch.** Up to xxxLarge, the switch is pinned right above "Agree and continue", outside the scroll view. At accessibility sizes it still scrolls with the rows, because its label alone can fill the screen.
  - **Follow-up, `f403674`.** Pinning surfaced a dead tap: a SwiftUI `Toggle` only flips on its switch, so tapping the sentence did nothing. Two UI tests that tap the row's centre failed every time. The sentence is now part of the tap target. The switch carries the sentence as its VoiceOver label, and the visible copy is hidden from VoiceOver so it isn't read twice.
  - **Heading.** The disclosure's heading now scrolls with the rows, which gives them its room when the pinned switch is tall.
  - **Scroll hint.** The gate's scroll indicator flashes on appear.

### Engagement

- **AUD-36, weekly nudges.**
  - **Dated, not repeating.** The Sunday 18:00 and Wednesday 19:00 nudges are now one-off dated reminders. They cover the current Thursday-to-Wednesday week and the 7 after it, and are re-planned on every refresh (launch, foreground, streak change, progress change).
  - **Goal met.** A week whose goal is met gets no nudges: no "This week's lesson is waiting" after two lessons. Later weeks start from zero.
  - **Copy follows the count.**
    - Sunday: "This week's first lesson is ready…" or "One lesson down this week. Ready for the next one with Merc?"
    - Wednesday: "This week's lesson is waiting…" or "One more lesson rounds out your week…"
    - No line says "new week" any more.
  - **Wiring.** `NotificationScheduler.weekProgress` is a closure that `AppEntryView` sets from `WeeklyPlan`, because EngagementFeature can't import CurriculumFeature.
  - **Daily-reminder overlap.** The daily reminder now skips only the days that actually get a nudge, so a skipped nudge gives that day's daily slot back.
  - **Upgrades.** The old repeating pair, "mercurius.weekly.wed" and "…sun", shares the weekly prefix, so the first re-plan clears it.
- **AUD-37, Live Activity.**
  - **Headline:** "In a lesson" until something is done this week, then "On a roll".
  - **Second line:** "Unit 1 · 0 of 4 done".
  - **Meta line:** "This week · 0 of 2" (the island adds "lessons").
  - **The only countdown:** "Streak ends in 4:59:59". It shows only when a fresh, live streak's last save day is today and today isn't saved yet (`AppShellView.streakEndsTonight`).
  - **Streak updates:** the shell re-pushes the card when the streak store updates, so the lesson's first confirmed reply removes the countdown.
  - **Older activities:** `ContentState`'s new fields are optional, so an activity started by an earlier build still decodes. It shows the unit's lessons left and no countdown.
- **AUD-44.** Home's 10 PM–5 AM opener is now "Hi there!" instead of "Up late? Perfect time to learn.". The scrolling line is gone from the daily rotation. The composer placeholder was done in step 02.

### Polish

- **AUD-50, iPhone SE.**
  - **Home.** Below 700 pt (only SE-class phones), Merc is 120 pt instead of 216, and the reminder offer sits under the CTAs. Both CTAs and the whole card fit.
  - **Empty chat.** Below 440 pt, Merc (84 pt) sits beside "Hi, I'm Merc" and all four Socratic starters show.
  - **Hint.** "Try a prompt above…" is part of the scroll content, under the starters. On an SE it is now just below the fold.
  - **Accessibility sizes** keep the stacked layout.
- **AUD-52, Merc's arm.** The celebrating arm turns about a shoulder inside the toga and is drawn behind it, so it comes out from under the toga. It pumps between -40° and -130° (it was -32°/-98° about a point in the gap beside his head). Every other pose is unchanged.
  - Left as designed: Merc bursting over the overlay sheet's edge.
- **AUD-54, delete failure.**
  - **The alert** says "Resetting only this device leaves your chats on our server." Its fallback reads "Reset this device only…" and opens a sheet instead of resetting.
  - **The sheet** says the server still has the chats and progress under the ID shown, and that afterwards only an email to privacy@trymercurius.com with that ID can delete them. It shows the ID, a Copy ID button (device-local pasteboard, 10 min), then "Reset this device only" and Cancel.
  - **Unreadable ID:** the sheet says so and offers no Copy button.
  - **Where:** both Settings and Privacy choices.
- **AUD-57, privacy manifest.** All four collected types (User ID, Other User Content, Photos or Videos, Product Interaction) are now `Linked = true`. Tracking stays false and the purposes are unchanged. `docs/APP_STORE_LISTING.md` §3 now says Linked: Yes for the four, with the reason, so the doc still matches the manifest. A contract test keeps the two in step.

## Tests

- **`swift test --parallel` from a clean scratch path, at `f403674`:** 915 tests in 137 suites passed (872 before this step; 43 added). `4a669b0` only moves a constant; after it, the SettingsFeature tests pass (33) and `xcodebuild build` for the simulator succeeds with no warning from this step's files.
- **New and updated package tests:**
  - **AppFeature:**
    - first-run routing (resume on Your path) and `consentIsCurrent`;
    - the age-wheel order;
    - gate copy and switch placement;
    - the heading scroll rule;
    - Home's short-screen rules and the neutral late-night opener;
    - `streakEndsTonight`;
    - the planner's Thursday matching `WeeklyPlan`'s on every weekday, and two finished lessons dropping this week's Wednesday nudge;
    - the privacy manifest against the listing's §3.
  - **EngagementFeature (ReminderPlanner):**
    - the week start;
    - weeks with nothing done, one done, and the goal met;
    - other goals, past slots and a DST week;
    - the schedule's quiet days and legacy ids;
    - no line lecturing about scrolling.
  - **MercuriusActivity:**
    - the first-lesson copy, and the countdown only when at risk;
    - older activities, and no clock beside lessons-left;
    - the lock card and headline length budgets.
  - **DesignSystem (MercArmPose):** the shoulder and its round cap are inside the toga; the cheer clears the head and stays inside the art; other poses are unchanged.
  - **ChatFeature:** the empty chat's short-screen rule and the hint rules.
  - **SettingsFeature:** the device-only reset notice (old ID, the privacy@ route, the unreadable variant) and the alert copy.
- **New simulator tests:**
  - **`MercuriusTests/LiveActivityStateTests`:** a pre-AUD-37 `ContentState` JSON decodes, and the new fields round-trip. `project.yml` gives `MercuriusTests` the `MercuriusActivity` product.
  - **UI tests:**
    - `testInterruptedFirstRunResumesOnYourPath`;
    - `testConsentSentenceTogglesTheSwitch`;
    - `testDeleteFailureShowsTheOldIdBeforeADeviceOnlyReset`. It points the app at a closed localhost:3000 with `-UseLocalServer`, and is skipped if a server is listening there.
- **`xcodebuild test` with CI's flags on Audit 16PM, at `f403674`:** TEST SUCCEEDED. All 24 UI tests passed (21 before this step), plus the 3 `MercuriusTests`.
  - **Earlier run, before `f403674`:** `testFirstRunGateLandsInFirstLesson` and `testExistingInstallSeesGateOnceThenHome` failed every iteration. Tapping the pinned row's centre hit the label and did nothing. That is what `f403674` fixes.
- **On Audit SE3:** the AX5 gate test, the consent-sentence test, the first-run gate test and the delete-failure test pass.
- **Snapshots:** comparison only, on Audit 16PM. No references changed (`git status` is clean under `__Snapshots__`).
  - **The result:** the same 13 failed as at step 03, and no others.
  - **Changed by this step (visually checked, not pixel-diffed against step 04):**
    - `testMercAllStates`: the celebrate arm.
    - `testLessonCompleteOverlayWithNext` and `testLessonCompleteOverlayLastLessonDark`: the celebrate arm.
  - **Wrapped, layout unchanged:** `testEmptyChatView{Light,Dark,AccessibilityXXL}` now render inside a `GeometryReader`. At iPhone 13 height that is the same stacked layout with the hint off, and the render looks right, but I didn't diff it against the old one.
  - All 13 needed a re-record before this step anyway.

## Screenshots (`docs/ios-batch/shots/`, Audit SE3 in dark mode unless noted)

- **Before (baseline):**
  - `05-before-disclosure-se3-L.png`
  - `05-before-home-se3-L.png`, which shows "Up late? Perfect time to learn."
  - `05-before-chat-se3-L.png`
- **First run:**
  - **Disclosure:** `05-disclosure-se3-L.png`, `05-disclosure-se3-xxxL.png`, `05-disclosure-se3-AX5.png`
  - **Limits:** `05-limits-se3-L.png`
  - **Age:** `05-age-se3-L.png` ("18 or older" right under the placeholder)
  - **Resume:** `05-resume-path-se3-L.png`, a relaunch with consent on record
- **Home:**
  - `05-home-se3-L.png` ("Hi there!", Merc 120)
  - `05-home-card-se3-L.png`, `05-home-card-se3-xxxL.png` (reminder offer under the CTAs)
- **Chat:** `05-chat-empty-se3-L.png`, `05-chat-empty-se3-xxxL.png`
- **Merc:**
  - `05-celebrate-se3-L.png`
  - `05-celebrate-arm-frames-se3.png`: five frames of the pumping arm, all attached
- **Live Activity:** `05-liveactivity-lock-se3.png`, `05-liveactivity-island-se3.png`. These are from the DEBUG `-LiveActivityGallery`: first lesson, active, and streak ends tonight.
- **Delete failure:**
  - `05-device-reset-sheet-se3-L.png`, from the UI test
  - `05-device-reset-sheet-16pm-L.png` (light mode)

Both simulators are back at text size "large".

## For the founder

- **`ConsentGate.currentVersion` is still 1.** AUD-27 changed the consent screens' copy (a new disclosure row and a new limits row; the agreement sentence is unchanged). Bumping it would re-show the agreement to every existing install. That's your call.
- **App Store Connect (AUD-57):** in App Privacy, set "Linked to the user" to **Yes** for User ID, Other User Content, Photos or Videos and Product Interaction. Keep Tracking at No and the purposes as they are. No build is needed for this. The manifest says Linked = true from the next build.
  - **`privacy.html`:** its "What 'not linked to you' means" section belongs to the content PR and isn't changed here.
- **AUD-54:** a Keychain pending-erasure list retried at launch (PR #33 #16) would make the device-only fallback lossless. Not done.
- **AUD-36, two product calls:**
  - **Goal met:** nudges are skipped, not replaced with a "Week done — nice".
  - **Lapsed students:** a student who stops opening the app now hears at most 16 more nudges over 8 weeks, instead of forever. The window is `ReminderPlanner.weeklyHorizonWeeks`.
- **AUD-34** (routing to the frontier lesson) and the **AUD-17 follow-up** are untouched.

## Open risks

- **Streak days.** The Live Activity's "Streak ends in" uses the reminders' window, which counts days on the device's clock while the server counts them in STREAK_TZ (a known limitation). The countdown is rare in a lesson: the lesson's first reply saves the day, and the card drops the countdown when the streak store updates.
- **The empty-chat hint on an SE** now sits just below the four starters, off screen until the student scrolls. That is the trade the audit asked for.
- **xxxLarge on an SE:** the disclosure's rows still get a small window above the pinned switch until the heading scrolls away. The indicator flashes to show there's more.
- **Weekly nudges only refresh when the app runs.** A lesson finished on another device (the progress merge) counts at the next launch's re-plan.
- **Not heard on a device:** the consent switch's VoiceOver label. The UI test reads it from the accessibility tree.
- **Not checked visually on a real lock screen:** the Live Activity. The DEBUG gallery renders the same views in the app.
- **Runtime warning in the mode menu (step 03):** XCTest logged a "_UIReparentingView added to UIHostingController.view" warning on the two accessibility-size mode-menu tests. Both pass. It isn't from this step.
