# AI Basics certificate: integrating the Basics course

**Status: wired (`feat/basics-certificate`, 2026-10-22).** Basics is on main (PR #52 clients, PR #54 server), and the certificate is on, on the iPhone and the Mac:

- `CertificateCourses.basicsLessons` returns `BasicsCurriculum`'s 18 lessons in course order, titled "Unit N · <lesson>".
- `AppShellView.handleLessonComplete` and `MacShellView.handleLessonComplete` mark every lesson inside `recordingNewlyEarned`. A Deep-dive lesson earns nothing there, so they don't branch.
- The card is on the lesson's complete screen. ChatFeature can't see CurriculumFeature's `\.unitMasteryAccessory`, so the screen has its own slot, `\.lessonCompleteAccessory`, under the headline (`LessonCompleteOverlay`, `NightLessonComplete`).
- `.certificateLessonSlot(env.certificates)` on the lesson fills the slot and presents `CertificateSheet`. On the iPhone the card is compact (a small preview beside the words), so the sheet keeps room for "Try this today"; when the sheet still has to scroll, the line under its pinned buttons fades out.
- The card stays while the complete screen does, even after its sheet has opened and closed. Basics lets nothing disappear before the learner is done with it, and on the iPhone neither Home nor the Basics path leads to Progress ▸ Certificates. So on the iPhone, while the card shows, only the screen's buttons close it: a tap on the dimmed lesson doesn't. On the Mac, Escape or a click beside the card still closes it, and Progress (⌘4) is in every toolbar.
- The Certificates list names only the next Basics lesson still to finish ("Next: Unit 4 · Meals, plans and lists"), under "12 of 18 lessons finished". The real titles hold commas and "and", so two of them in one comma list ran together.
- `justEarned` is cleared when the lesson goes:
  - iPhone: in the cover's `onDismiss`, `lessonWindowDismissed`;
  - Mac: on a change of `shell.activeLesson?.id`.
- `CertificateDebug.demoBasicsLessons` is gone; the DEBUG shots use the real lessons.

The rest of this note is the plan as written before the merge.

The AI Basics certificate (`LaurelBasics.dc.html`) is built and tested on `feat/certificate`, but the Basics course itself lives on another branch. Until that branch hands its lessons in, this build doesn't offer the Basics certificate. The Progress hub and the Certificates list show only the Deep dive.

This note says what the Basics branch needs to do. There are two calls and one card.

## What's already here

- **The rule.** `CertificateEligibility.basics(lessons:completedLessonIds:completedAt:)` in `EngagementFeature/Sources/Certificates/CertificateEligibility.swift`. It's a pure function, and the Basics lesson ids go in as input:
  - the certificate is earned when every lesson in `lessons` is in `completedLessonIds`;
  - an empty list earns nothing;
  - extra ids are ignored, so Deep-dive ids in the same set don't count;
  - the date is the latest completion date, but only when every lesson has one.
- **The seam.** `CertificateCenter.basicsLessons`, which is nil today. Setting it is all it takes to turn the Basics certificate on. `CertificateCenter.status(.basics)` then reads its progress through the closures `AppEnvironment` passes in, which read `CurriculumProgressStore`:
  - `completedIds` for the lessons finished;
  - `completedAt(_:)` for their dates.
- **The default.** `CertificateCourses.basicsLessons` in `AppFeature/Sources/CertificateWiring.swift` returns `nil`. `CertificateCenter.make` passes it to the center.
- **The moment.** `CertificateCenter.recordingNewlyEarned { … }` runs a progress change. If the change completes a certificate, it:
  - stores the moment (`CertificateStore.earnedAt`);
  - sets `justEarned`, which shows the "Get your certificate" card.
- **The card and the sheet.**
  - `CertificateReadyCard(kind: .basics, …)` and `CertificateSheet(center:kind: .basics, …)` are ready, with the Basics copy ("You finished AI Basics", "Every lesson done.").
  - `CertificateMasterySlot` (`.certificateMasterySlot(center)`) puts the card in a view's `\.unitMasteryAccessory` slot and presents the sheet.

The tests that cover this:
- `EngagementFeature/Tests/CertificateTests.swift`: "Basics with injected lesson ids", "Basics through the seam";
- `AppFeature/Tests/CertificateWiringTests.swift`: "Basics lessons in the shared progress store".

## What the Basics branch does

1. **Hand in the lessons, in course order.** Replace the body of `CertificateCourses.basicsLessons` with the Basics curriculum's lessons:

   ```swift
   static var basicsLessons: [CertificateRequirement]? {
       BasicsCurriculum.lessons.map {
           CertificateRequirement(id: $0.id, title: "Unit \($0.unit) · \($0.title)")
       }
   }
   ```

   - **The ids** must be the ones the progress store records. The server's notes (`lib/curriculumTag.js`, `lib/schemas.js` on `feat/basics-server`) use `b{unit}_l{lesson}`: 18 lessons, `b1_l1` … `b5_l4`, with the unit sizes 3, 4, 3, 4 and 4.
   - **The titles** are what "Still to finish: …" lists, two at a time.

2. **Mark Basics completions inside `recordingNewlyEarned`.** Wherever the Basics lesson view's `[LESSON_COMPLETE]` handler calls `progress.markCompleted(lessonId)`, wrap it like this:

   ```swift
   env.certificates.recordingNewlyEarned { progress.markCompleted(lessonId) }
   ```

   The Deep dive already does this around `markUnitMastered`:
   - `AppShellView.handleUnitMastered`;
   - `MacShellView.handleUnitMastered`.

   Without the wrapper the certificate still unlocks, but its date falls back to the day it's first made. The card doesn't show either.

3. **Show the card on the last lesson's celebration.** The Deep dive's card sits in the unit check's result (`\.unitMasteryAccessory`, read by `UnitTestView` and the Mac's `NightUnitTestContent`). For Basics, put it where the final lesson's complete overlay can show it, for example:

   ```swift
   if let card = env.certificates.masteryAccessory(open: { kind in sheet = kind }) { card }
   ```

   Present `CertificateSheet(center: env.certificates, kind: .basics, onClose: …)` from the same view. `.certificateMasterySlot(env.certificates)` does both when the view reads `\.unitMasteryAccessory`. Clear `env.certificates.justEarned` whenever that view goes, by any way out:
   - iPhone: in the cover's `onDismiss`, as `unitTestDismissed` does;
   - Mac: on a change of the open lesson, as `MacShellView` does for the check (`.onChange(of: shell.activeUnitTest?.id)`). The sidebar, ⌘1–⌘3 and Settings all close it without its own Done.

## If Basics keeps its own progress store

The center reads progress only through `CertificateCenter.Progress`, which has three closures:
- `masteredUnitIds`;
- `completedLessonIds`;
- `completedAt`.

If Basics completions don't go into `CurriculumProgressStore`, change `CertificateCenter.make` so that `completedLessonIds` and `completedAt` read the Basics store as well, for example as a union of the two stores' ids. Nothing else changes.

## Checks once it's wired

- [ ] `swift test` passes, including the certificate suites above.
- [ ] Progress ▸ Certificates lists AI Basics with "N of 18 lessons finished" and what's left.
- [ ] Finishing the 18th lesson shows "You finished AI Basics" and opens the sheet.
- [ ] Its PDF prints "AI BASICS", the date of the 18th lesson, and "Instructor or family member".
- [ ] "Delete my data & start over" erases the name: `SettingsSheet` already calls `CertificateCenter.reset()`.
- [ ] Remove `CertificateDebug.demoBasicsLessons` once real lessons exist. It's DEBUG-only and used only for screenshots.
