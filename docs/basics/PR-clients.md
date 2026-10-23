# Basics: a separate beginner course in the iPhone and Mac apps (stacked on #48)

**Base: `feat/mac-night-studio` (#48).** Head: `feat/basics-clients`. **Merge only after the server PR (`feat/basics-server`, stacked on #44) is deployed.** A server without it answers a `[BASICS: …]` opener as free chat, so a Basics lesson only teaches on a server that has the Basics guide.

## What this is

The founder asked for "a separate 'easy' curriculum that can just teach people the basics of how to use AI … (think of a grandma wanting to learn how to use ChatGPT)." This PR is the client half: the **Basics** course in the iPhone app and the Mac app, beside the existing course, which the apps now call **Deep dive** where the two sit side by side. Merc teaches each lesson in the existing lesson chat, and the learner practises on Merc right there.

### The curriculum: 5 units, 18 lessons

| Unit | Lessons |
|---|---|
| 1. Meet AI chatbots | What is an AI chatbot? · What chatbots are good at · What chatbots get wrong |
| 2. Your first conversations, safely | Asking a real question · Following up · What never to share · Fake calls that sound like family |
| 3. Getting good answers | Be specific · Tell it your situation · Ask for the downsides |
| 4. Everyday tasks | Write an email or letter · Understand a confusing letter · Meals, plans and lists · Learn something new, with a photo |
| 5. Using it wisely on your own | Checking answers that matter · Health, money and legal: ask a person · Other scams that use AI · On your own |

The data is `CurriculumFeature/Sources/BasicsCurriculum.swift`, held word for word to `docs/basics/basics.json` by a test.

## Defaults chosen (the founder can change any of these)

- **A separate track called "Basics"**; the existing course is "Deep dive" wherever the two appear together. "Easy" never appears on screen. The app stays 13+; Basics is written for any adult beginner and works for teens too.
- **Choosing by experience, never by age.** The last onboarding step offers "I'm new to AI: start with the Basics" and "Take the Deep dive", as two equal pinned buttons. Installs from before Basics, and anyone who never chooses, stay on the Deep dive, so nothing changes for current students.
- **Tutor-led, with practice right there.** A Basics lesson is the existing lesson screen; Merc's practice line becomes a chip that fills the box (never sends).
- **Tool-neutral, plain language, safety first.** That is the server's guide; the apps add no lesson text beyond the curriculum's titles, objectives and "Try this today" lines.
- **No streak pressure in Basics.** No streak, flame, XP, level, weekly goal or badge toast on Basics screens, and no Lock Screen card for a Basics lesson. Progress is check marks and "You've finished 3 lessons."
- **Both courses stay open**, each with its own progress; the choice only decides where Home, Today and the path open.

## What the learner sees

![Your path: one plain reminder switch, two equal choices](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/01-iphone-track-choice.jpg?raw=true)

"Your path" (Large light, AX3 dark): what each course is, one plain switch ("Remind me to practice", twice a week; no streak switch), and the two choices pinned at every text size.

![The Basics path titled Lessons, and Home on Basics](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/02-iphone-basics-path-home.jpg?raw=true)

The path with the "Basics | Deep dive" switch, titled "Lessons" (tab too), and Home leading into the next Basics lesson. Home's second button on Basics is "All Basics lessons", not "Chat with Merc".

![A Basics lesson: intro, practice chip, check](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/03-iphone-basics-lesson.jpg?raw=true)

The intro offers bigger text (A / A+ / A++, a floor under the system size); Merc's practice line is a chip with a pencil; the check at AX3.

![Lesson complete at Large and AX3](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/04-iphone-basics-complete.jpg?raw=true)

"Lesson complete", Try this today, "Next: …" and "That's enough for today". At AX3 the two choices are pinned to the bottom of the sheet and Merc stays off it.

![Mac: the sidebar's Basics section and a unit page](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/05-mac-basics-sidebar-path.jpg?raw=true)

![Mac: a Basics lesson with the practice chip](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/06-mac-basics-lesson.jpg?raw=true)

![Mac: Today on Basics, and the check card's "Pick one"](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/basics-clients/docs/basics/key-shots/07-mac-basics-today-check.jpg?raw=true)

The Mac: Basics and Deep dive as two sidebar sections; Today on Basics has no week card and no Think it through; the check card says "Pick one". (The Mac shots replay a recorded iPhone session, so Merc's first reply says "tap the microphone"; live, the server words it for a Mac.)

## The server contract, as the apps send it

- **Opener:** `[BASICS: Unit N, Lesson M]` at index 0, the curriculum's starter text, then the Deep dive's completion contract. The `[CURRICULUM: Basics …]` alias is never sent.
- **Follow-up turns:** `[opener, …thread]`, the last user turn re-tagged by the existing bridge (`ChatViewModel.carriesLessonTag` now knows both tags, so a Basics opener is never tagged twice).
- **Ids:** `b1_l1` … `b5_l4`, `basics_1` … `basics_5`; one store, one sync, under `MercuriusCurriculum.version`. Every count, frontier and the weekly plan are per course.
- **Capabilities:** `platform_ios` or `platform_mac` beside `blocks_v1` on every chat request (only the Basics guide reads it).
- **A server from before Basics** refuses `b` ids with a 400; the sync then sends the Deep dive's ids alone and remembers that until the next launch (or a pull that shows a `b` id).

## Review fixes in this PR (2026-10-22)

| Finding | Fix |
|---|---|
| Medium. Basics learners were steered into the Socratic free chat (Mac Today's "Think it through · Socratic", Home's "Chat with Merc"). | No Think it through on Basics' Today; Home's second button is "All Basics lessons"; no mode names on Basics screens (tested). |
| Medium. At AX3 the completion's choices were below the fold and Merc covered text. | Choices pinned and never squeezed when the sheet overflows; Merc off the Basics sheet at accessibility sizes; a short sheet sits on the bottom edge. Deep dive unchanged. |
| Medium. "Your path" offered a "Daily streak reminder" next to the Basics choice. | One plain switch, "Remind me to practice"; the streak reminder stays in the Progress hub. |
| Low. The weekly plan counted only the Deep dive. | `WeeklyPlan.compute(progress:track:)`, used by Home and the reminder planner. |
| Low. The pre-Basics sync fallback sent two PUTs on every pull. | The refusal is remembered; an unchanged snapshot isn't re-sent. |
| Low. `readingSizeFloor` had two branches (state reset on a size pick). | One modifier; a test guards the identity. |
| Low. The chip's `text.cursor` icon read as "AI". | A pencil. |
| Low. Mac check card "YOUR TURN FIRST". | "Pick one" on Basics. |
| Low. A completion key idea "…just like this one". | Basics drops key ideas that point back into the chat. |
| Low. "Curriculum" on a Basics learner's tab and title. | "Lessons". |
| Low. Snapshot tests didn't draw the tracked path the app shows. | Two new tests (Deep dive, Basics) with **no reference images**: the founder records them. |

Not changed: iOS's own glass tab bar at AX3 (its labels don't grow; content shows through while scrolling).

## Verification

Run on this branch's final code, 2026-10-22.

| Check | Result |
|---|---|
| `swift test --parallel` (`ios/Packages`, ArchitectureTests included) | 1,242 tests in 185 suites passed (the base's 1,187, the first build's 46, and 9 for the review fixes) |
| CI lint, `ios/scripts/ci-compat-lint.py` (Xcode 16.2 / Swift 6.0.3 traps) | 0 findings |
| iOS build for testing after `xcodegen generate` (iPhone 16 Pro Max sim, iOS 26.4) | succeeded |
| iOS tests with CI's flags (`-skip-testing` ViewSnapshotTests, PerformanceTests, AppStoreScreenshots; retries on; snapshot recording forced off) | MercuriusTests 3/3, MercuriusUITests 26/26, no failure and no retry, including `testFirstRunCanStartTheBasics` and the AUD-12 largest-text-size gate test |
| Mac Debug build | succeeded |
| Snapshot comparisons (first build, `ios-unchanged-check.sh`, recording off) | the same 23 results as the baseline: no comparison changed. The two new tracked-path tests have no reference yet (see below). |
| Screenshots | iPhone (Large and AX3, light and dark) and Mac (light and dark), all looked over; the key shots above were retaken on this code |

Details: `docs/basics/CLIENTS.md`.

## For the founder

- **Record two snapshot references:** `testCurriculumTrackedDeepDive` and `testCurriculumTrackedBasics` in `ViewSnapshotTests` (until then they fail with "no reference" when that class runs; CI skips it).
- **Questions:**
  1. Basics and the Deep dive are equal choices on "Your path" (Basics first). Should one be the default?
  2. On the Mac, the course follows what the learner opens. Would an explicit switch on Today be clearer?
  3. The Deep dive's sidebar section used to be "Learning path"; it is now "Deep dive" for everyone. OK?
  4. The daily streak reminder is off the first-run screen for everyone (one plain switch there now). Keep it that way for Deep-dive learners too, or bring it back once a course is chosen?
  5. A Basics-style free chat (or "Try it with Merc") would let "Try this today" happen inside the app; today Basics learners are kept out of the Socratic free chat. Build one?
  6. Mac text size (⌘+ / ⌘−, View ▸ Bigger Text) for Basics: its own piece of work. Worth it?

🤖 Generated with [Claude Code](https://claude.com/claude-code)
