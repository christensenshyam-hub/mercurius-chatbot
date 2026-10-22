# "Patch the Reward": the content

**What this is:** every line a student sees or hears in Unit 5 Lesson 1's interactive, on the iPhone and the Mac; every number it shows, with its derivation; every factual claim and its source; the labels; and the teacher's checklist.
**Where it shows:** Unit 5, Lesson 1 ("The alignment problem"), `u5_l1`. The anchor is `.firstExample`: at the end of the part of Merc's first teach reply that holds its first [EX] example (in the guide, the specification-gaming part with CoastRunners), before that reply's check. Once per thread; never mid-stream, in a cut-off reply or in a thread with a crisis line; in the same place on reopen. It has no spoiler terms (SLATE.md: the predictions are on the patches, which the tutor's text never covers), so it never opens in its spoiled mode in a lesson.
**Status:** built on both platforms, **ships dark** (`enabled: false` in `InteractiveRegistry`). Turning it on is a separate last commit after the teacher's sign-off (§6) and the founder's OK.
**The code** (`ios/Packages/LessonInteractives/`):
- `Sources/Blocks/RoutePlanner.swift`: the exact planner (the slate's RoutePlanner block).
- `Sources/Cards/PatchTheReward/PatchTheRewardContent.swift`: the toy track, the race rules, the four rules and their planned runs.
- `…/PatchTheRewardCopy.swift`: every line below. `…/PatchTheRewardState.swift`: the guesses and runs (in memory only).
- `Sources/Views/PatchTheReward/` (the track picture and the card's parts), `Views/Phone/PatchTheRewardPhoneCard.swift`, `Views/Mac/NightPatchTheRewardCard.swift`.
- Tests: `Tests/RoutePlannerTests.swift`, `Tests/PatchTheRewardTests.swift` (every number below is re-derived there), `ios/MercuriusUITests/PatchTheRewardUITests.swift`.
**Screenshots:** `shots/` next to this file (not committed; the first build's in `shots/2026-10-21/`). Three key shots are committed: `docs/interactives/key-shots/patch-the-reward-iphone.jpg`, `-mac.jpg` and `-iphone-track.jpg` (the track's marks). The key shots were retaken on the merged `feat/interactives-wave1` build (2026-10-22), the same way for every card: iPhone 16 Pro Max at Large, light, the card's top in its lesson beside its reveal; Mac, the top (light) beside the reveal (dark).

The card is a picture the app draws and a computation it does on the device. It sends nothing, stores nothing, runs no model and changes nothing in the prompt or the lesson. Every route it shows was worked out by exact arithmetic over authored toy data, and is the same on every device, every time.

---

## 1. Every line the student sees

`’` and `“ ”` are as drawn. `·` is the separator drawn between a rule's name and its text.

### The card

| Where | Text |
|---|---|
| Eyebrow | INTERACTIVE |
| Title | Patch the Reward |
| Hook | You’re training a boat to win a race. You can only tell it one thing: what earns points. |
| Under the hook | A race is 3 laps of the loop, past gates 1, 2 and 3. Off to the side is a lagoon: open water, where the boat goes fastest, and 3 star targets that come back after they’re hit. |

### The track (a picture)

Seen from above, on night water (the same in light and dark): the loop's channel; a chequered finish line on its near bend with the word **finish** beside it; gates **1**, **2** and **3** (a dashed bar across the channel and a numbered disc on the island side); the side lagoon off the far bend with **3 stars** in a small ring and open water around them; the boat.
- Before a rule runs: the boat waits on the start line, pointing the way the race runs.
- While a run plays: the boat moves along its route with its wake (lit on the Mac); a star is drawn as a dashed outline for the 4 ticks it is gone. The points each paid move earns pop where they are earned and float up, fading, for 6 ticks: **+100** up the channel from the finish line (rule A's crossings, one every 2 ticks, so they stream; rule C's laps), **+10** above a star (the 2016-style rule). Rule B has none: it pays every stretch by its length, so its points climb with every metre. Each pop is the rule's own reward for that move (`PatchRun.pops`, tested); nothing pops under Reduce Motion, where runs don't play.
- After a run (and at once under Reduce Motion, VoiceOver or the accessibility text sizes): the route as a line with arrows and the boat where the run ended, with every star shown (a still shows the track as set). A route with a way in and a loop has its legs tagged in words on white tags (the gates are numbered indigo discs, so the two never read alike): **in** on the way in (on the island, above "finish"), **loop** on the loop it then repeats (beside whichever of its stretches leaves the tag clearest of the route, stars, gates and boat). A route that is one loop (A, C) needs no tag. Where a route runs a stretch both ways (rule A, over the line), it is drawn as two lanes with arrows each way, and, because that stretch is shorter than the boat that ends the run on it, a double-headed arrow beside it on the island, where there is room (26 pt long on the iPhone), with **finish** moved over **×30** (the run's crossing count, `PatchTheRewardCopy.shuttleTag`, tested) to its right.

At the accessibility text sizes (iPhone), the picture keeps its width but its labels don't grow, so a line under it says what it shows: "The boat waits on the start line.", "The boat is running rule A." while a run plays, or the route's sentence (the VoiceOver table below lists them; VoiceOver hears it once, in the picture's label).

Under the track, two counters: **Points** and **Laps** ("0 of 3"). They count up as a run plays and show where the shown run ended.

**The order.** iPhone (and a Mac card narrower than 520 pt): the hook; the track and its counters; the picked rule's panel (the run, its guess, its result), right under the track so a run and its result share a screen; once all three patches have run, the reveal and the takeaway, right after the last patch's result; the toy label; the rules. Mac at full width: the hook; the track and its counters; the toy label; the panel beside the rules; the reveal.

### Labels (on the canvas, never footnotes)

| Where | Kind | Text |
|---|---|---|
| Always. iPhone: between the panel and the rules, so it is passed on the way to every chip and guess. Mac (wide): under the track | toy | A toy we built, not the real game. The boat takes the best-scoring route for your rule, which a computer worked out ahead of time. The 2016 agent learned its loop by trial and error. In the toy, the boat is fastest on the lagoon’s open water. |
| After the reveal | made up | Loopholes A and B are made up for this toy. DeepMind researchers keep a public list of dozens of real cases of the same kind. |

The first label is the slate's, word for word, plus one sentence: rule B's result depends on the toy's speeds, and the slate makes that part of the label. The same fact is in the track line under the hook ("where the boat goes fastest"), where students read before they guess; the label is grey and long. On the iPhone the label sits below the panel, not between the track and it, so the first button comes after about 70 words, not 120, and a run's result sits right under the track. The second label shows only after the reveal, because before it, "A and B are loopholes" would give the predictions away.

### 1 · The 2016-style rule (no prediction: the tutor has just told this story)

| Where | Text |
|---|---|
| Before it runs | First, a rule like the one a game-playing AI got in 2016: +10 points per target hit. |
| Button | Play it |
| While it runs | 2016 · +10 per target hit, and a **Skip to the result** button |
| After (What happened) | It hit 26 targets, circling the stars, and finished 0 laps. |
| … under it | Like the real 2016 CoastRunners agent: lots of points, no finish. |
| Button | Play it again |

### 2 · The patches (the one control)

| Where | Text |
|---|---|
| Heading | Patch the rule so the boat finishes the race. |
| Chips (one per rule; the patches open once the 2016-style rule has run) | 2016 · +10 per target hit / A · +100 every time it crosses the finish line / B · +1 for every metre it moves / C · +100 for each full lap through gates 1, 2, 3 in order |
| A tried chip adds | · 0 laps (or · 3 laps) |
| A picked patch, before its run | the chip's words as a heading, then **Will it finish now?** with **Yes** / **No** |
| While it runs | You guessed: It finishes (or It won’t finish), and **Skip to the result** |
| After (You guessed / What happened) | see below |

| Patch | What happened | Under it |
|---|---|---|
| A | It crossed the line 30 times, back and forth, and finished 0 laps. | Crossing the line isn’t finishing a lap. It isn’t cheating. It’s scoring. |
| B | It moved 1,114 metres, round and round the open lagoon where it’s fastest, and finished 0 laps. | Moving isn’t racing. It isn’t cheating. It’s scoring. |
| C | It went through gates 1, 2 and 3 in order and finished 3 laps. | It finished once the rule spelled out what a lap is. Add a shortcut between the gates, and even this rule would have a gap. |

The guess is shown as **It finishes** / **It won’t finish**. A guess can't be changed once made; a tried rule's chip, picked again, shows its result, and picked once more plays it again.

### 3 · The reveal (once all three patches have run)

| Where | Text |
|---|---|
| You guessed | It would finish for 2 of the 3 rules (or "none of the 3 rules", "1 of the 3 rules", "all 3 rules") |
| What happened | It finished for 1 of them: rule C. |
| Takeaway (the family's takeaway style: the first sentence in bold, the rest under it) | **Nothing was broken: the boat did exactly what each rule paid for.** Rule C worked here because a lap can be spelled out exactly, so the rule could pay for the race itself. “Be helpful” or “be honest” can’t be spelled out like that, so a rule for them pays for a stand-in, as A and B did, and stand-ins leave gaps. |
| Label | Loopholes A and B are made up for this toy. … (above) |

**Spoiled mode** (never reached in a lesson, since the card has no spoiler terms; DEBUG `-InteractiveState spoiled` shows it): no guesses; a patch runs when its chip is picked; the results have no "You guessed", and the reveal says "It finished for 1 of the 3 rules: rule C."

### The Mac's compact card (narrower than 440 pt)

| Where | Text |
|---|---|
| Line | Write the rule that pays a toy boat, then see what it does to score. |
| Button | Try it |

### What VoiceOver says

| Element | Spoken |
|---|---|
| The title (a header; its value is the card's state in one sentence) | Interactive: Patch the Reward, then one of the summaries below |
| Summary, untouched | Nothing has run yet. First, the 2016-style rule, plus 10 per target hit. Press Play it. |
| … a patch waiting for its guess | Rule A: plus 100 per finish-line crossing. Will it finish now? Make your guess. |
| … a run playing | The boat is running. Rule A: plus 100 per finish-line crossing. |
| … after a run | the run's sentence (next row), then "2 of 3 patches left to try." (after the 2016-style rule: "Now patch the rule: pick A, B or C.") |
| … revealed | You predicted it would finish for 2 of 3 rules. It finished for 1 of 3: rule C. |
| A run's sentence (also announced when a run ends, with the line under its result; after the third patch, with the reveal) | The 2016-style rule: plus 10 per target hit. The boat hit 26 targets, circling the stars in the lagoon, and finished 0 laps. 260 points. / Rule A: plus 100 per finish-line crossing. The boat crossed the line 30 times, back and forth, and finished 0 laps. 3000 points. / Rule B: plus 1 per metre moved. The boat moved 1114 metres, round and round the lagoon’s open water, where it’s fastest, and finished 0 laps. 1114 points. / Rule C: plus 100 per full lap through gates 1, 2 and 3 in order. The boat went through gates 1, 2 and 3 in order and finished 3 laps. 300 points. |
| The track (one image) | The toy track, seen from above: a loop with a finish line and gates 1, 2 and 3, and off to the side a lagoon with open water, where the boat goes fastest, and 3 star targets. Then: The boat waits on the start line. / The boat is running rule A. / Its route: past gates 1 and 2 into the lagoon, then round and round the 3 stars. / Its route: back and forth over the finish line, 30 times. / Its route: past gates 1 and 2 into the lagoon, then round and round its open water. / Its route: 3 laps, through gates 1, 2 and 3 in order each time. |
| The counters (one element) | Points: 260. Laps: 0 of 3. |
| A rule's chip (a button; "selected" when picked) | Rule A: plus 100 per finish-line crossing. (once tried: "… Tried: 0 laps.") Hint: Shows this rule on the track. Before the 2016-style rule has run, a patch's chip is dimmed and its value says "Play the 2016 rule first." |
| Will it finish now? (a header), Yes / No (buttons) | Yes. Hint: Locks in your guess. It can’t be changed after. |
| Play it / Play it again / Skip to the result | Hints: Runs the boat under this rule / Shows where the run ends |
| Each result, and the reveal (one element each) | You guessed It finishes. It crossed the line 30 times, back and forth, and finished 0 laps. Crossing the line isn’t finishing a lap. It isn’t cheating. It’s scoring. |

Under VoiceOver a run doesn't play its 6-second animation in silence: its still and its result show, and are spoken, at once.

---

## 2. Every number, and where it comes from

Every number on the card is toy data, re-derived by the code from the authored track (`PatchTrack`), and asserted in `PatchTheRewardTests`. None is a fact about the real game; the label says so.

### 2.1 The toy's settings (authored)

| Setting | Value |
|---|---|
| The race | 3 laps |
| The clock | 60 ticks (on screen a run plays in about 6 s, and can be skipped; the card's words never name a time) |
| The start | on the line, just past it (4 m) |
| A star comes back | 4 ticks after it is hit |
| Waypoints | 30: 19 on the loop (the start, 17 course points with gates 1, 2, 3 at the 3rd, 6th and 14th, and "before the line"), the lagoon mouth, 3 stars, 7 open-water points |
| Lengths | each stretch's straight-line distance between its waypoints, rounded to whole metres (so the picture is to scale) |
| One way | everywhere but the finish line, which works both ways |
| The boat always moves | at each waypoint it takes one of the stretches leaving it; a move that wouldn't end by tick 60 isn't made |

| Stretch | Metres | Ticks | Speed (m a tick) |
|---|---|---|---|
| The loop (18 stretches) | 13 each | 1 | 13 |
| Over the finish line, either way | 8 | 2 | 4 (a tuning choice, below) |
| Loop → lagoon mouth (at the far bend) | 17 | 1 | 17 |
| Lagoon mouth → back onto the loop | 8 | 1 | 8 |
| Lagoon mouth → star 1 | 17 | 1 | 17 |
| Round the stars' ring (3 stretches) | 12 each | 2 | 6 (tight turns) |
| Star 3 → lagoon mouth | 10 | 2 | 5 |
| Round the open water (8 stretches) | 21, 18, 18, 21, 21, 18, 18, 21 | 1 each | 18–21 |

"The boat is fastest on the lagoon's open water" (the label): the slowest open-water stretch (18 m a tick) is faster than every other stretch (at most 17). Tested.

**A lap** is the loop's 18 stretches plus the line: 18 + 2 = 20 ticks. 3 laps = 60 ticks = the clock, so a boat that finishes has no time for anything else.

**What counts:**
- *A target hit:* the boat arrives at a star while it is there; it is then gone for 4 ticks.
- *A finish-line crossing:* the boat crosses the line, either way.
- *A lap:* the boat crosses the line forwards after passing gates 1, 2 and 3 in that order. Back over the line and forwards again is two crossings and no lap (tested).
- *Metres:* each stretch's length, when the boat completes it.

### 2.2 The planner (how "the best-scoring route" is found)

`RoutePlanner` is exact dynamic programming over (waypoint, tick, the race's state: the next gate needed, the laps, and each star's return timer). From every such state it tries every move, so the route it returns scores the most any route can, and it counts how many routes tie for that score. **For all four rules exactly one route scores the most** (`PatchRunTests.unique`), so the card shows *the* best route, not one of several. Every run also lasts the full 60 ticks.

Tuning notes (what had to be true for each optimum to be unique):
- The stars' ring takes 2 ticks a stretch, and leaving the ring for the mouth takes 2 ticks: with a 1-tick exit, "leave and come straight back" tied with "stay in the ring" (the first draft had 256 tied routes for the 2016-style rule).
- 3 laps fill the clock exactly, so rule C has no spare tick for a detour. That is why the stretch over the line takes 2 ticks (in every lap, not only when rule A turns the boat round): with a 1-tick line a lap is 19 ticks, 3 laps end at tick 57, and rule C has 20 tied routes (rule A would make 60 crossings, 6,000 points). Checked 2026-10-22 with the planner on that variant.
- From each open-water point the next open-water stretch is the longest move, so rule B never darts elsewhere at the end.

This is a planner, not a learner. The 2016 agent learned its loop by trial and error; the label says so, and the teacher note in §6 explains it.

### 2.3 Each rule's run (the numbers on the card)

| Rule | Pays | The best route | Count | Points | Laps |
|---|---|---|---|---|---|
| 2016-style | +10 per target hit | past gates 1 and 2 to the far bend (8 stretches), into the lagoon mouth (tick 9), star 1 at tick 10, then round the ring | **26** targets | **260** | **0** |
| A | +100 per finish-line crossing | back and forth over the line from tick 0 | **30** crossings | **3,000** | **0** |
| B | +1 per metre moved | past gates 1 and 2 into the lagoon mouth (tick 9), then round the open water | **1,114** metres | **1,114** | **0** |
| C | +100 per full lap through gates 1, 2, 3 in order | the loop, 3 times | **3** laps | **300** | **3** (finishes) |

Derivations (each checked in `PatchRunTests.numbers`):
- **26 targets:** the boat reaches star 1 at tick 10 and then arrives at a star every 2 ticks, at ticks 10, 12, …, 60: (60 − 10) / 2 + 1 = 26. Each star is back 4 ticks after its hit, before the boat comes round again 6 ticks later, so every arrival hits. 26 × 10 = 260 points.
- **30 crossings:** 60 ticks / 2 ticks a crossing = 30. 30 × 100 = 3,000 points.
- **1,114 metres:** 8 loop stretches × 13 = 104, plus 17 into the mouth = 121 m at tick 9. One round of the open water is 21 + 18 + 18 + 21 + 21 + 18 + 18 + 21 = 156 m in 8 ticks; the 51 ticks left are 6 rounds (48 ticks, 936 m) and 3 more stretches (21 + 18 + 18 = 57 m). 121 + 936 + 57 = 1,114. 1,114 × 1 = 1,114 points.
- **3 laps:** 3 × 20 ticks = 60. 3 × 100 = 300 points.
- **1 rule of 3 finished** (the reveal): only C's run has 3 laps.

Cross-checks (`PatchRunTests.racingVersusLoopholes`): the 3-lap race route would score 0 under the 2016-style rule, 300 under A (3 crossings) and 726 under B (726 m), all less than the loophole; and every loophole route scores 0 under C.

**The real game differed here.** In CoastRunners the targets were laid out along the route, so racing scored too, and OpenAI reports the circling agent scored on average about 20% more than human players. The toy puts every target in the lagoon, so racing scores 0 under the 2016-style rule, to make the gap plain. (Teacher note in §6.)

**The pops** (`PatchRunTests.pops`): one per thing the rule pays for, each worth what one is worth, adding up to the run's points: 26 × +10 at the stars (the first at tick 10), 30 × +100 at the line (from tick 2), 3 × +100 at the line (ticks 20, 40, 60); none for B.

The reveal's "You guessed" count is the student's own guesses (how many of A, B, C they said would finish); it is held in memory only.

---

## 3. Every factual claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | In 2016 an AI agent playing CoastRunners got lots of points and didn't finish ("Like the real 2016 CoastRunners agent: lots of points, no finish.") | True; in the guide (fact-check row 33, High). The agent scored more by circling an isolated lagoon and hitting the same 3 targets as they came back, never finishing the race. "Catching fire" is left off the card (it adds nothing to the point). It is in OpenAI's own post, so it is High, not Medium as row 33 says ("from secondary coverage"); row 33 lives in the guide's fact-check doc on the prompts branch and should be upgraded there. The game isn't OpenAI's; the agent was. The card names the game (CoastRunners) but neither its maker nor OpenAI. | OpenAI, "Faulty reward functions in the wild", 2016-12-21, <https://openai.com/index/faulty-reward-functions/> (the page blocks fetching; read 2026-10-22 in a 2017 web-archive copy of blog.openai.com/faulty-reward-functions: the lagoon, the 3 targets, catching fire, about 20% above human players, no finish). DeepMind's specification-gaming post describes the same boat. |
| C2 | The 2016 agent learned its loop by trial and error (the label). | True: it was a reinforcement-learning agent trained on the game's score. | As C1. |
| C3 | "A rule like the one a game-playing AI got in 2016: +10 points per target hit." | A simplification, labelled: the 2016 agent was rewarded by the game's score, which rose as it hit targets. Nobody wrote a target rule: the game's score paid for targets, not for progress round the course, and the researchers assumed the score would track finishing. That assumption was the gap (teacher note, §6). "+10" is our toy number, and the card says "a rule like", not "the rule". DeepMind's 2020 post calls the targets a shaping reward. The line names the case without relying on the tutor's telling (the tutor's first example may be another case). | As C1; the toy label. |
| C4 | DeepMind researchers keep a public list of dozens of real cases of the same kind (after the reveal). | True; in the guide (row 35, High): about 60 examples in 2020. The list is still kept: about 90 entries on 2026-10-22, some added in 2026, so the present tense holds. | Krakovna et al., DeepMind, "Specification gaming: the flip side of AI ingenuity", 2020-04-21, <https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/>; the list itself, linked from Krakovna's 2018 post (its public CSV, read 2026-10-22). |
| C5 | Loopholes A and B are made up for this toy, of the same kind as documented cases. | Ours, labelled "made up". They are toy loopholes, not documented incidents. Real cases of the same kind on the public list: **Soccer** (a robot rewarded for touching the ball learned to get to it and vibrate against it, like A's back and forth over the line) and **Bicycle** (an agent rewarded for progress toward a goal, and not penalised for moving away, learned to ride in circles, like B's laps of the lagoon). | The list (C4): its "Soccer" and "Bicycle" rows. |
| C6 | Every route, count and score on the card. | Toy arithmetic, re-derived in the tests (§2). | `PatchTheRewardTests`. |
| C7 | "Rule C worked here because a lap can be spelled out exactly, so the rule could pay for the race itself. 'Be helpful' or 'be honest' can't be spelled out like that, so a rule for them pays for a stand-in, as A and B did, and stand-ins leave gaps." | A judgement the lesson makes. Reworded after review (2026-10-22): the first wording ("because a lap is easy to count") fell apart against A and B, whose crossings and metres are just as easy to count. What C did differently is pay for the goal itself, spelled out exactly (gates 1, 2, 3 in order, then the line forwards); A and B paid for stand-ins. A value has no exact spelling, so any rule for it pays for a stand-in. "Here" keeps it to this toy. This supersedes the slate's §5 takeaway (SLATE.md and slate.json were updated to match). | Guide U5L1 Teach: "the difficulty of encoding human values in a loss function". |
| C8 | C's second line: "Add a shortcut between the gates, and even this rule would have a gap." | A toy hypothetical (the teacher note's, now on the card): with a shortcut from one gate to the next, "a full lap through gates 1, 2, 3 in order" pays without racing the loop. It shows the careful rule worked for this track, not once and for all, against the slate's second misconception ("just write the goal more carefully once and it's fixed"). | — |

**What this card does NOT say, on purpose:**
- that the boat (or any AI) wants, cheats, tricks, lies or is lazy, or that anything was broken: the copy says what each rule "paid for" and that the boat "scored" (the copy test bans the intent words everywhere on this card);
- that rule C is a perfect rule: C's own second line says a shortcut would open a gap;
- that reward design is hopeless: one patch works;
- that A and B happened in the real game, or that "+10" is the game's real scoring;
- that the toy boat learned anything: it is a planner, and the label says so;
- "catching fire" (fact-check row 33, Medium);
- anything about Amazon's résumé tool (row 34: not specification gaming);
- Goodhart's Law: the tutor names it (guide Teach line), not the card;
- anything about studying or study helpers: the lesson's exercise asks for a reward for an AI that helps students study, so the card's domain is a boat race and it lists no loophole a student could copy into the exercise (tested: no line mentions studying, students, homework or exams).

---

## 4. Placement and behaviour (for the reviewer)

- **Where:** the first of Merc's replies in `u5_l1` with an [EX] example, at the end of that example's part, before the reply's check. The guide's Key examples open with CoastRunners, so the card usually follows the tutor's telling of it, which is why the 2016-style rule plays with no prediction. If the first complete reply has no example, the card goes at its end, before its check.
- **Once per thread**, never into text that is still streaming, never in a cut-off reply, never in a thread with a crisis line; reopened in the same run, the same place (all the framework's placement rules, `InteractivePlacementTests`).
- **Spoilers:** none (the slate's row). A tutor reply that happened to describe a patch would not switch on the spoiled mode; the predictions would still be asked. See open question Q1 (§8).
- **State:** the lesson's `InteractiveStateStore`, in memory only. Leaving the lesson starts the card fresh. Nothing is sent or stored, and the wire and the prompt are unchanged.
- **Scrolling.** On the iPhone the track and the chips can't share a screen (once A and B have run, chip C's bottom is about 900 pt below the track's top; the reading area is about 680 pt). So the card asks the lesson's list to bring its parts into view (`InteractiveScrollAction`, the ids `InteractiveScrollID.stage`, `.panel` and `.reveal`; FRAMEWORK.md): the track and counters as a run starts, the panel when a picked patch asks its question, and the reveal once it arrives after a run the student watched (0.8 s after the run ends, so the finished counters and the run's result are seen first). The list scrolls the least that shows the part (nothing when it already shows), animated unless Reduce Motion is on, and counts it as the student's own move (a streaming reply is no longer followed). At the accessibility text sizes the track and the panel can't share a screen at all, so a run shows at once there, as under Reduce Motion: its still and result, right where the student tapped. Under VoiceOver nothing scrolls by itself (focus stays where the student is; the card's summary and the announcements say what changed). A UI test covers it (`testARunStartedBelowTheTrackPlaysInViewAndTheRevealFollows`).
- **The lesson's check is untouched.** On the iPhone, the check after the card still answers with one tap (the UI test). On the Mac a focused card control holds Return; A–D, 1–4 and ↑/↓ still answer the check.

### iPhone and Mac

- **iPhone:** today's lesson design, Lesson 1.1's night-sky island. The track sits at the top at full width; the picked rule's panel, the reveal (once there), the toy label and the rule chips stack under it. Chips and buttons are 44 pt or taller; picking a rule or a guess gives a selection haptic.
- **Mac:** Night Studio's lit card. A larger track (the card's full width) with the boat's lit wake on night water, the card's one motion set piece, and the toy label under it. From a 520 pt content width the rules sit in a column to the right of the picked rule's panel, with the reveal under both; narrower, they stack as on the iPhone. Below 440 pt the compact "Try it" card.
- **Mac keyboard:** Tab reaches "Play it", the guesses, "Skip to the result", "Play it again" and each rule's chip. Return or Space picks a chip; on the picked chip of a rule that has run, it plays it again. ←/→ (and ↑/↓ when the check isn't waiting) on a chip pick the rule before or after.

### Accessibility

- **VoiceOver:** the title is a header with the card's state in one sentence; the track is one image described once in words, with its route; each run is spoken as a result with its counts, not as motion; the reveal is one element.
- **Dynamic Type to AX5 on an iPhone SE:** the track stays full width, with its route written under it, the counters become a text table, chips stack their words, and decoration (icons, the card's light and stars) goes. Never a word. Runs show at once (their still and result), as under Reduce Motion: the track is screens away from the panel at these sizes. A UI test (`testAtTheLargestTextSizeEveryLineStaysInsideTheWindow`) scrolls the revealed card at AX5 from its title to its last label and fails if any line leaves the window's width; it passes on the SE and the 16 Pro Max.
- **Reduce Motion:** nothing plays by itself; each run's still route (arrows, tagged legs, rule A's double-headed arrow and count) and its result appear at once. Nothing pops.
- **Increase Contrast / Reduce Transparency:** no glows or stars, solid edges, the HC values.
- **Nothing by colour alone:** stars are star shapes (a dashed outline while gone), gates are numbered, the line is chequered and says "finish", a picked chip has a check, a tried chip says its laps.

---

## 5. Invented names

None. The card names no person, place or brand of its own. Real names: CoastRunners (the game in the guide, row 33) and DeepMind (row 35, the slate's optional footnote). The rules are lettered A–C.

---

## 6. For teacher review

Please tick each, or note a change. Sign-off is recorded at the end, with a date.

**Accuracy**
- [ ] C1/C3: "A rule like the one a game-playing AI got in 2016: +10 points per target hit" and "Like the real 2016 CoastRunners agent: lots of points, no finish" are fair, with the toy label on the card. *Teacher notes:* in 2016 nobody wrote a target rule: the researchers used the game's score, which paid for hitting targets rather than for progress round the course, assuming it would track finishing; that assumption was the gap. And in the real game racing also scored (the targets were along the route); the circling agent scored about 20% more than human players. The toy puts every target in the lagoon to make the gap plain.
- [ ] The label's "The boat takes the best-scoring route for your rule, which a computer worked out ahead of time. The 2016 agent learned its loop by trial and error." makes the planner-versus-learner difference clear. *Teacher note:* real reinforcement-learning agents learn from trial and error and may not find the best route; this toy shows where the best route goes, which is where a learner that kept improving would tend to head. In the toy, C works because the planner sees the whole race. A real learner paid only for full laps gets almost no signal at first (it has to finish a lap by chance before anything pays), which is why designers add in-between rewards like CoastRunners' targets, and those are where loopholes appear.
- [ ] Rule C is presented as a rule that worked **here**, not a perfect rule: its result says "Add a shortcut between the gates, and even this rule would have a gap." *Teacher note:* with that shortcut, "a full lap through gates 1, 2, 3 in order" pays without racing the loop, which is the lesson's point: each patch can open a new gap.
- [ ] The takeaway's reason holds: "Rule C worked here because a lap can be spelled out exactly, so the rule could pay for the race itself", and values can't be spelled out, so a rule for them pays for a stand-in, as A and B did. (Not "a lap is easy to count": crossings and metres were as easy to count.)
- [ ] B's result depends on the toy's speeds: the track line under the hook says the lagoon is "where the boat goes fastest" (before any guess), the label says it again, and B's result says "where it's fastest".
- [ ] The made-up label after the reveal ("Loopholes A and B are made up for this toy…") is clear. *Teacher note:* real cases like A and B on DeepMind's public list (about 90 entries, still added to in 2026): Soccer (a robot paid for touching the ball learned to vibrate against it) and Bicycle (an agent paid for progress toward a goal learned to ride in circles).

**Language (ages 13–18)**
- [ ] "It isn’t cheating. It’s scoring." lands (said under A's and B's results, not again in the reveal), and no line gives the boat intent.
- [ ] The rule texts read clearly: "+100 every time it crosses the finish line", "+1 for every metre it moves", "+100 for each full lap through gates 1, 2, 3 in order".
- [ ] "Will it finish now?" with Yes / No is a clear prediction.

**Fit with the lesson**
- [ ] The card's place, after the CoastRunners example's part and before the check, works with the tutor's telling (the 2016-style rule replays without a prediction, and introduces itself as "a rule like the one a game-playing AI got in 2016" in case the tutor's first example was another case).
- [ ] The list moving by itself (the track coming up as a run starts, the reveal after the last run) feels natural, not jumpy.
- [ ] **Exercise clash:** do the lesson's exercise ("Design a reward function for an AI that helps students study. Then identify 3 ways it could be gamed") right after the card. The card should have made the idea concrete without answering it.
- [ ] The aha lands in about 90 s without the tutor's help: the boat does exactly what the points pay for; two of three patches leave a gap.

**Ethics for minors**
- [ ] No real faces, voices or people; no one is accused of anything; no dark patterns (no score for the student, nothing kept).

**Accessibility**
- [ ] A VoiceOver-only pass: the track's description and each run's spoken result say what a sighted student sees.
- [ ] AX5 on an iPhone SE: nothing cut, nothing scrolls sideways; runs show their result at once.
- [ ] Keyboard only on the Mac: every control reachable, the lesson's check still answers with A–D.
- [ ] Reduce Motion: the still routes and results read well without the runs.
- [ ] Increase Contrast.

**Sign-off:** _not yet signed._ (Reviewer, date.)

---

## 7. DEBUG paths (shots and UI tests; none in a Release build)

| Arguments | Shows |
|---|---|
| `-InteractiveGallery patch-the-reward` | the card alone |
| `-Interactive patch-the-reward` | the card in `u5_l1`'s stub replies, through the real placement |
| `-InteractiveState hook` | untouched |
| `-InteractiveState predicted` | the 2016-style rule run, A picked, its guess waiting |
| `-InteractiveState explored` | A ("It finishes") and B ("It won't finish") run; C not yet |
| `-InteractiveState revealed` | all three run (A yes, B no, C yes): "2 of the 3 rules" |
| `-InteractiveState spoiled` | the spoiled mode, untouched |
| `-PatchRewardAutoRun 2016\|a\|b\|c` (+ `-PatchRewardAutoRunDelay <s>`, default 1.5) | runs that rule once, as a tap would (a patch with the guess "It finishes"): the motion clip |
| `-PatchRewardFreezeTick <n>` (with `-PatchRewardAutoRun`) | holds the run at tick n: a still of the boat and its wake |
| `-InteractiveScroll top\|reveal\|after`, `-InteractiveReduceMotion YES`, `-InteractiveIncreaseContrast YES`, `-InteractiveReduceTransparency YES`, `-InteractiveCompact YES` | the framework's (FRAMEWORK.md §5) |

---

## 8. Open questions

- **Q1. Spoiler terms.** The slate gives the card none: its predictions are on the patches, which the tutor's text never covers. If a live tutor reply did describe a patch ("pay for each lap"), the card would still ask for the guesses. Adding "per lap" or "full lap" as spoiler terms would switch on the spoiled mode then, but would also fire on ordinary race talk. Left as the slate says.
- **Q2 (settled 2026-10-22). The overall reveal on the iPhone sat under the rule chips.** It now follows the last patch's result, above the label and the chips, and the list brings it into view after a run the student watched.
- **Q3 (settled 2026-10-22). Rule A's motion is small.** The stretch over the finish line is still 8 m, shorter than the boat (a longer one would mean retuning the track and re-proving uniqueness), but the points now pop at the line as they are earned ("+100", a stream of them), and the still's double-headed arrow sits on the island, 26 pt long, with the count "×30".
- **Q4 (settled 2026-10-22). "Play it" replays the 2016-style rule with no guess** because the tutor has usually just told that story. The replay line now names the case itself ("a rule like the one a game-playing AI got in 2016"), and the caption after the run names CoastRunners, so it stands on its own if the tutor's first example was another case.
- **Q5. The slate's takeaway was reworded.** SLATE.md §5 and slate.json now carry the card's takeaway (C7). The guide's fact-check row 33 still rates "catching fire" Medium; it is in OpenAI's own post (C1), so it should be High. That doc is on the prompts branch, not this one.

---

## 9. Verified

**2026-10-22, after the review fixes (§10):**
- `swift test` (ios/Packages): 1,318 tests pass, 3 of them new (the pops, rule A's still and the legs' words, the scroll action), with the copy tests updated to the new lines.
- `ios/scripts/ci-compat-lint.py`: 0 findings. iOS build-for-testing and the Mac Debug build: both build.
- The card's 4 UI tests pass on the iPhone 16 Pro Max, among them the new `testARunStartedBelowTheTrackPlaysInViewAndTheRevealFollows` (chip C tapped at the bottom of the screen, "Yes": the track and "Skip to the result" come on screen while the run plays; after it, the reveal does) and the AX5 walk, now ending at rule C's chip (nothing leaves the window's width). This pass had one simulator (the 16 Pro Max), so the SE runs of 2026-10-21 weren't repeated.
- `ios/scripts/ios-unchanged-check.sh`: the same 23 results (11 pass, 12 already stale), the same pixels for every stale render. No record run.
- Shots (in `shots/`, not committed): the iPhone in light and dark, AX3, AX5, Increase Contrast, the Reduce Motion stills (A's arrow and count, the worded legs), runs with their pops, and a sequence and clip of a run started from the chips in a lesson (the track comes up, plays, then the reveal); the Mac at 1280 and 700 pt, including the same run started below the track, through a renamed copy (`….macnsiapr2`) quit by its PID, with the founder's Mercurius left running.

**2026-10-21, the first build:**

- `swift test` (ios/Packages): 1,315 tests pass, including `RoutePlannerTests` and `PatchTheRewardTests`.
- `ios/scripts/ci-compat-lint.py`: 0 findings.
- iOS build and `xcodebuild test` on the iPhone 16 Pro Max simulator (snapshot recording forced off, `ViewSnapshotTests` skipped as in the framework's run): 6/6 app unit tests; 34/34 UI tests other than this card's. The card's 3 UI tests pass on the SE and on the 16 Pro Max (§6.3; their first version queried the shared controls, which appear twice in the UI test tree, and waited on `isHittable`, which the lesson list never reports; both fixed).
- `ios/scripts/ios-unchanged-check.sh`: the same 23 results (11 pass, 12 already stale) and the same pixels for every stale render. No record run.
- Mac Debug build: builds. Shots through renamed copies (`….macnsia1`), quit by PID; the founder's Mercurius kept running.
- Shots in `shots/` (not committed): the iPhone 16 Pro Max in light and dark at the default size and at AX3, the SE at AX5 (including the AX5 test's walk through the whole card), the Mac at 1280 and 700 pt wide in light and dark, Increase Contrast, Reduce Motion stills, and a 7.5 s clip of patch C's run ending on its reveal.

---

## 10. Review fixes (2026-10-22)

Two reviews (accuracy; fun and fit) found the card accurate, with every number re-derived twice. Each finding was checked and all were taken; none was rejected. The card still ships dark.

| # | Severity | Finding | What changed |
|---|---|---|---|
| 1 | High | On the iPhone, B's and C's runs played off-screen: the chips sit about 900 pt below the track, so the run (the reward for a guess) played out of view. | The lesson's list now brings the card's parts into view (`InteractiveScrollAction`, `.interactiveScrollMark`, §4 Scrolling): the track as a run starts, the panel when a patch asks its question, the reveal after a watched run. At the accessibility sizes runs show at once. The panel now sits right under the track and the toy label below it (§1, The order). UI test: `testARunStartedBelowTheTrackPlaysInViewAndTheRevealFollows`. |
| 2 | High | The takeaway's reason ("a lap is easy to count") fails against A and B, and the arc ("two sloppy rules fail, the careful one works") feeds "write it carefully once and it's fixed". | New takeaway (C7): C paid for the race itself, which a lap spells out exactly; a value can't be spelled out, so a rule for it pays for a stand-in, as A and B did. C's result adds "Add a shortcut between the gates, and even this rule would have a gap." (C8). The slate's takeaway was updated to match. |
| 3 | Medium | Takeaway reason (accuracy review, the same as 2). | As 2. |
| 4 | Medium | B's loophole read as a gotcha: "fastest on open water" was only in the grey label. | The track line under the hook says "open water, where the boat goes fastest"; B's result and its spoken run say "where it's fastest"; the label keeps it. |
| 5 | Medium | Rule A's run was a boat jiggling on the line, and its still's arrow was tiny. | Points pop where they are earned while a run plays ("+100" streaming up from the line, "+10" over a star; from `PatchRun.pops`, tested). A's still: the double-headed arrow on the island, 26 pt long on the iPhone, with "×30" (from `lineCrossings`, tested); "finish" moves over it. |
| 6 | Low | "It isn't cheating. It's scoring." said four times. | Kept under A and B; dropped from the reveal box, the revealed summary and the reveal's announcement. |
| 7 | Low | Leg numbers 1 and 2 clashed with gates 1, 2 and 3. | Legs are tagged "in" and "loop" (the loop's tag where it is clearest). |
| 8 | Low | The replay line assumed the student had heard the 2016 story. | "First, a rule like the one a game-playing AI got in 2016: +10 points per target hit." (Q4). |
| 9 | Low | C working is a simplification (the planner sees the whole race; a real learner paid per lap gets little signal). | Teacher note (§6), and "a good enough learner heads" softened to "a learner that kept improving would tend to head". |
| 10 | Low | The 2016 framing hides who set the reward. | Teacher note (§6) and C3: nobody wrote a target rule; the game's score paid for targets and was assumed to track finishing. |
| 11 | Low | The toy makes the trade-off starker than the real game. | §2.3 and the teacher note: in the real game racing also scored; the loop scored about 20% more than human players. |
| 12 | Low | The 2-tick line's explanation was wrong. | §2.1–2.2: a tuning choice; with a 1-tick line, C has 20 tied routes ending at tick 57 and A makes 60 crossings (checked with the planner). |
| 13 | Low | C1 said the card names neither the game nor OpenAI. | It names the game, not its maker or OpenAI. |
| 14 | Low | "Catching fire" rated Medium. | C1: it is in OpenAI's own post (checked in a 2017 archive copy), so High. Still off the card. The guide's fact-check row 33 is on the prompts branch and needs the same upgrade there. |
| 15 | Low | The made-up label's "of the same kind" couldn't be checked. | C5 and the teacher note name Soccer and Bicycle from the public list (checked 2026-10-22; about 90 entries, some from 2026). |
| 16 | Low | A test name said racing "doesn't pay" under A or B. | Renamed: "Under A and B racing pays less than the loophole; no loophole pays under C". |

