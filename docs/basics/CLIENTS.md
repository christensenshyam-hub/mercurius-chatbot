# Basics track: iPhone and Mac

Branch `feat/basics-clients`, on top of `feat/mac-night-studio` (PR #48: the iPhone app of PR #43 plus the Mac app in Night Studio). Not pushed.

The founder asked for "a separate 'easy' curriculum that can just teach people the basics of how to use AI … (think of a grandma wanting to learn how to use ChatGPT)." The server half is `feat/basics-server` (`docs/basics/SERVER.md` there). This branch is the client half: the Basics course in the iPhone app and the Mac app, beside the existing course, which the apps now call **Deep dive** where the two sit side by side.

**Ship order: the server first.** A server without `feat/basics-server` (production today) answers a `[BASICS: …]` opener as free chat, and its progress route refuses `b` ids. The apps cope with the second (see Progress), but a Basics lesson only teaches on a server that has the Basics guide. The server branch's A/B gate has not run yet. The Anthropic credit balance ran out three minutes into it; see SERVER.md for the commands.

## Defaults chosen (the founder can change any of these)

- **A separate track called "Basics".** The existing 8-unit course is "Deep dive" wherever the two appear together. "Easy" never appears on screen. The app stays 13+. Basics is written for any adult beginner and works for teens too.
- **Choosing by experience, never by age.** The last onboarding step offers "I'm new to AI: start with the Basics" and "Take the Deep dive". Installs from before Basics, and anyone who never chooses, stay on the Deep dive, so nothing changes for current students.
- **Tutor-led, with practice right there.** A Basics lesson is the existing lesson screen: Merc teaches in the chat, and the learner practises on Merc.
- **Tool-neutral, plain language, safety first.** That is the server's guide (`lib/basicsGuide.js`); the apps add no lesson text of their own beyond the curriculum's titles, objectives and "Try this today" lines.
- **No streak pressure in Basics.** Basics screens show no streak, flame, XP, level, weekly goal or badge toast, and starting a Basics lesson doesn't start the Lock Screen card (it shows the streak and a countdown). Progress is check marks and "You've finished 3 lessons."
- **Both courses stay open.** The choice only decides where Home, Today and the path open. Each course keeps its own progress, and its counts never include the other's lessons.

## What the learner sees

### iPhone

| Where | What |
|---|---|
| Onboarding, "Your path" | Two pinned, full-width, equal buttons, "I'm new to AI: start with the Basics" and "Take the Deep dive"; above them a line on what each course is, the reminder switches (off unless turned on) and "Just chat instead". A button remembers the choice and opens that course's first lesson. The first build had the two courses as tappable cards in the scrolling part; at AX3 and AX5 the Deep-dive card was below the fold and only "Just chat instead" was pinned, which broke AUD-12 (`testFirstRunGateCompletesAtLargestTextSize` caught it), so the choices became the step's pinned CTA. |
| Path (Curriculum tab) | A two-segment switch, "Basics \| Deep dive", across the top (44 pt, labelled, remembered). Basics' path has no unit checks, a plain top bar with only Home (no streak bar), a header that says lessons finished in words, and Text size. Its path-side Merc says calmer lines ("Take your time."). |
| Home | The chosen course's next lesson: "Start the Basics", then "Continue Basics: What chatbots are good at". For Basics no streak greeting and no week ring; "You've finished 1 Basics lesson." instead. |
| Text size | The first Basics screen offers "Want the words bigger?" with A / A+ / A++, each drawn at the size it gives. It is a floor: the learner's own larger system size always wins. After that, Text size on the Basics header opens the same choice. Basics lessons and the Basics path use it; the Deep dive is untouched. |
| A Basics lesson | The existing lesson screen with: an intro that says the objective in the learner's words and "One small step at a time. You can stop whenever you like, and I'll save your place."; a labelled "‹ Lessons" back button at the top left; "Type your message here"; the reply's practice line (`Try asking me: "…"`) as a chip that fills the box without sending; Copy on Merc's replies (press and hold), before Report. |
| After a Basics lesson | "Lesson complete", then **Try this today** (the curriculum's line, with Copy when it quotes a message, for example "What could go wrong?"), then "Next: \<lesson\>" and "That's enough for today", and "Your place is saved." No share card, no "Nailed it!". After a unit's last lesson it carries on to the next unit (there is no check). |

### Mac

| Where | What |
|---|---|
| Sidebar | Two folding sections, **Basics** and **Deep dive**, each listing its units with lessons done; the learner's own course first. Basics' units have no mastery seal. |
| A Basics unit page | Night Studio's unit page, without the check: "Basics · Unit 01 · In progress", "1 of 3 lessons done", the thread ending at the last lesson, and the next Basics unit. |
| The course follows what opens | Opening a Basics unit or lesson makes Basics the course Today and View ▸ Learning Path (⌘2) lead into; a Deep-dive one switches back. Today and the chats leave it alone. |
| Today | For Basics: "Basics · Up next · Lesson 1.1", "All Basics lessons", no streak line and no week card (Think it through takes the row). |
| A Basics lesson | The same lesson additions as the iPhone (plain intro, practice chip, "Type your message here"). The complete card shows Try this today, "That's enough for today" and "Start Lesson 1.2", with no week ring and no share. |

## The server contract, as the apps send it

- **Opener.** Each Basics starter begins at index 0 with `[BASICS: Unit N, Lesson M]`, then the curriculum's starter text, then the completion contract the Deep dive appends. The alias in the curriculum file (`[CURRICULUM: Basics …]`) is never sent. `docs/basics/basics.json` is the curriculum file with its tags rewritten to the canonical form, and a test holds the Swift data (`BasicsCurriculum.swift`) to it word for word.
- **Follow-up turns.** `[opener, …thread]`, with the last user turn re-tagged by the existing legacy-server bridge. Fixed here: the bridge checked only for `[CURRICULUM`, so on a Basics lesson's first request it would have tagged the opener twice, and that request's opener would have differed from every later one's (a history-cache miss). `ChatViewModel.carriesLessonTag` now knows both tags; Deep-dive bytes are unchanged.
- **Ids.** Lessons `b1_l1` … `b5_l4`; units `basics_1` … `basics_5`. `CurriculumTrack.of(id:)` tells the two courses apart by shape.
- **Progress.** One store, one sync, one list. A push sends `b` and `u` ids together under `MercuriusCurriculum.version` (1), never a separate number. A pull merges both; every count, frontier and "next" is per course (`totalCompleted(in:)`, `frontier(in:)`), and the weekly plan still counts only the Deep dive. If a server refuses the push with a 400 (what one from before Basics does for a `b` id), the sync retries once with the Deep dive's ids alone, so the Deep dive keeps syncing.
- **Capabilities.** Every chat request now declares the device beside `blocks_v1`: `platform_ios` or `platform_mac`. Only the Basics guide reads it (b1_l1's "tap the microphone on your keyboard" becomes "type … then click the arrow" on a Mac). Production's schema accepts any well-formed token, and nothing else on the server reads it.
- **Completion.** Unchanged: `lessonComplete: true` (or the inline marker) completes the lesson.

## Where the code is

| Piece | File |
|---|---|
| Courses, Basics data, Try this today | `CurriculumFeature/Sources/BasicsCurriculum.swift` (`CurriculumTrack`, `BasicsCurriculum`) |
| The choice and the text size | `CurriculumFeature/Sources/CurriculumTrackStore.swift`, `DesignSystem/Sources/ReadingSize.swift` |
| Per-course progress | `CurriculumFeature/Sources/ProgressStore.swift` (`totalCompleted(in:)`, `frontier(in:)`, `frontierLessonId(in:)`) |
| Path switch, Basics header | `CurriculumFeature/Sources/CurriculumView.swift` (`TrackSwitch`), `LearningPathView.swift`, `BasicsPath.swift` |
| Lesson additions | `ChatFeature/Sources/BasicsLesson.swift` (`BasicsLessonOptions`, `PracticeLine`, copy), `CurriculumLessonView.swift` (`basics:`), `LessonCompleteOverlay.swift`, `Mac/NightLessonComplete.swift`, `MessageBubbleView.swift` (Copy) |
| Opener tag, platform | `ChatViewModel.swift` (`carriesLessonTag`), `NetworkingKit/Sources/ClientCapabilities.swift` |
| iPhone wiring | `AppFeature/Sources/AppShellView.swift` (`lessonCover`, `basicsNextStop`, `BasicsTopBar`), `AppEntryView.swift`, `HomeState.swift`, `HomeView.swift`, `YourPathStep.swift`, `OnboardingFlow.swift`, `CurriculumProgressSync.swift` |
| Mac wiring | `AppFeature/Sources/Mac/MacSidebar.swift`, `MacShellModel.swift`, `MacShellView.swift`, `MacUnitPage.swift`, `MacTodayView.swift`, `MacNightCopy.swift` |

### DEBUG launch arguments (screenshots)

- `-CurriculumTrack basics|deepDive` picks the course at launch; `-BasicsReadingSize standard|larger|largest` sets the size; `-BasicsSizeOffered YES` answers the one-time offer.
- `-OpenLesson <id>` opens a lesson through the route a tapped reminder takes. `-LessonSkipIntro YES` now works in the iPhone shell too.
- `-LessonReplay YES` on a Basics lesson replays a real recorded Basics session (Unit 1, Lesson 1, from the server branch's smoke run 3), its last reply completing the lesson as the server would. No server with Basics is deployed, so this is how the Basics lesson is seen. `-LessonReplayScript <n>` answers it with the session's recorded learner turns, `n` of them (0: the practice chip; 2: the check; 3: the completion). `-LessonJumpToLatest YES` takes the "Jump to latest" jump after each reply.
- `-SeedCompleted b1_l1,b1_l2` (with `-UITests`, whose progress suite is emptied at launch and never synced) counts lessons as done.
- `ios/scripts/mac-snapshots.sh` has `basics-today`, `basics-path`, `basics-intro`, `basics-lesson`, `basics-lesson-check` and `basics-lesson-complete`.

## Verification

All on the final code of this branch, 2026-10-21.

| Check | Result |
|---|---|
| `swift test --parallel` (`ios/Packages`, ArchitectureTests included) | 1,233 tests in 183 suites passed: the base's 1,187 plus 46 new (Basics curriculum 19, Basics in the app 11, Basics lesson 11, Mac Basics 5). |
| CI lint, `ios/scripts/ci-compat-lint.py` (Xcode 16.2 / Swift 6.0.3 traps) | 0 findings. |
| iOS, CI's flags, "Lab B 16PM" (iPhone 16 Pro Max, iOS 26.4), derived data `/private/tmp/merc-basics-ios-dd`, after `xcodegen generate` | Build for testing succeeded. `test-without-building` with CI's `-skip-testing` (ViewSnapshotTests, PerformanceTests, AppStoreScreenshots), `-retry-tests-on-failure -test-iterations 3 -test-repetition-relaunch-enabled YES`: MercuriusTests 3 of 3 and MercuriusUITests 26 of 26 passed, all on the first try (no retries). That includes the new `testFirstRunCanStartTheBasics` and the AUD-12 `testFirstRunGateCompletesAtLargestTextSize`. Recording was forced off. |
| Snapshot comparisons, `ios/scripts/ios-unchanged-check.sh` on Lab B, recording off | The same 23 results as the baseline (`docs/mac-night-studio/ios-snapshot-baseline.txt`): 11 pass and 12 fail, the 12 being references that were already stale. Every stale render is pixel-identical (same SHA-256). **No snapshot comparison changed.** None of the 23 draws the track UI: the snapshot test builds `CurriculumView` without a track store, which is the Deep dive's path exactly as before. Nothing under `MercuriusTests/Snapshots` changed. |
| Mac Debug build into `/private/tmp/merc-basics-mac-dd` | Succeeded. |
| Mac shots, `ios/scripts/mac-copy-snapshots.sh` only (the copy is `com.mayoailiteracy.mercurius.native.macns31`, ad hoc, never activated) | 28 pictures, all ok: 7 states, each light and dark, at 1280×800 and the 700×600 minimum. The script exited 1 for one reason only: its "a Mercurius running before is gone" check. The processes that went away were other sessions' simulator apps and copies. The founder's Mercurius (PID 83916, the `merc-mac-tok-dd` build) was running before and after. The copy never came to the front. |
| iPhone shots, "Lab B 16PM" and "Lab C 16PM", Large and AX3, light and dark | 80 pictures (10 states × 2 sizes × 2 appearances × 2 devices), all taken and looked over. The two devices show the same screens. The Deep dive's top bar differs between them ("🔥 1" or "Start your streak today"), because each simulator keeps its own cached streak. Each simulator was booted only for its step and shut down after it. |

Kept outside the repo, in `.claude/worktrees/basics-shared/shots/`:

- `iphone-labB/` and `iphone-labC/`, ten states each as `NN-<state>-<large|ax3>-<light|dark>.png`:
  1. `01-track-choice`: onboarding's "Your path".
  2. `02-basics-path`: the Basics path, fresh, with the text-size offer.
  3. `03-basics-path-progress`: the path with 2 lessons done.
  4. `04-home-basics`: Home leading into Basics.
  5. `05-lesson-intro`: the lesson's intro, with the offer.
  6. `06-lesson-practice`: the replayed first reply and its practice chip.
  7. `07-lesson-check`: the check.
  8. `08-lesson-complete`: the completion after the replayed session.
  9. `09-complete-copy`: Try this today with Copy.
  10. `10-deepdive-path`: the switch on the Deep dive, whose path is otherwise unchanged.
- `mac/`: `gate-path`, `basics-today`, `basics-path` (the sidebar's Basics section and a Basics unit), `basics-intro`, `basics-lesson`, `basics-lesson-check` and `basics-lesson-complete`, each with `-dark`, `-min` and `-min-dark`.

At AX3 the text-size offer is absent. That is by design: the system size is already above the largest choice, so every choice would look the same. The key shots in `docs/basics/key-shots/` (JPEG, at most 1600 px, quality 82):

| File | What |
|---|---|
| `01-iphone-track-choice.jpg` | "Your path": Large light, AX3 dark |
| `02-iphone-basics-path-home.jpg` | The Basics path (Large light) and Home (Large dark) |
| `03-iphone-basics-lesson.jpg` | The intro with "Want the words bigger?", the first reply with the practice chip, the check at AX3 dark |
| `04-iphone-basics-complete.jpg` | The completion (Large light) and Try this today with Copy (AX3 dark) |
| `05-mac-basics-sidebar-path.jpg` | The Mac sidebar's Basics section and a Basics unit page |
| `06-mac-basics-lesson.jpg` | A Basics lesson on the Mac, with the practice chip |

## Not done, and why

- **Mac text size.** Night Studio's sizes are fixed and macOS has no Dynamic Type, so the A / A+ / A++ choice is iPhone only. BEGINNER_GUIDE §2.2 asks for ⌘+ / ⌘− and View ▸ Bigger Text on the Mac: its own piece of work.
- **"Try it with Merc".** The free chat's modes are Socratic, Debate and Discussion; none does the task the way a Basics lesson's practice does, so a "Try this today" message sent there would get questions back. Copy is there; the button waits for a Basics-style free chat (or a server mode for it).
- **"Say that more simply" and "I'm stuck" buttons** (BEGINNER_GUIDE §2.3) need a new server nudge; "Explain more" means "go deeper".
- **The printable completion and "Who to call" cards** (curriculum §6) are the certificate work's.
- **The web widgets** don't offer Basics.
- **Reminders** keep their existing copy (opt-in, as before). A Basics learner who turns them on gets a lesson link into Basics, but the daily reminder is still the streak one.
- **The App Store review prompt** still counts Basics completions toward its 3rd and 10th.
- **The recorded replay is the phone's.** The chip's hint says "Click" on a Mac, but the replayed session was recorded with `platform_ios`, so the Mac shots show "tap the microphone" in Merc's first reply. Live, the server words it for a Mac.
- **Return on the Mac's "Your path".** Return used to start Lesson 1. With two equal choices neither is the default, so Return now does nothing there and the learner clicks one. Founder question 1 below would settle it.
- **The model still says "just" sometimes.** The recorded reply in the shots has "just like this one" and "just by asking". The apps' own Basics words are held free of it by a test, but the server's guide doesn't fully stop the model (SERVER.md: about 1 reply in 4).
- **At AX3 and above the completion sheet scrolls.** Like the Deep dive's, it is capped at 86% of the screen; "Next" can sit below "Try this today" until the learner scrolls.

## Founder questions this branch adds

1. Basics and the Deep dive are equal choices on "Your path" (same style, Basics first). Should one be the default?
2. On the Mac, the course follows what the learner opens. Would an explicit switch on Today be clearer?
3. The Deep dive's sidebar section used to be "Learning path"; it is now "Deep dive" for everyone. OK?
