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
**Screenshots:** `shots/` next to this file (not committed).

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
| Under the hook | A race is 3 laps of the loop, past gates 1, 2 and 3. Off to the side is a lagoon: open water, and 3 star targets that come back after they’re hit. |

### The track (a picture)

Seen from above, on night water (the same in light and dark): the loop's channel; a chequered finish line on its near bend with the word **finish** beside it; gates **1**, **2** and **3** (a dashed bar across the channel and a numbered disc on the island side); the side lagoon off the far bend with **3 stars** in a small ring and open water around them; the boat.
- Before a rule runs: the boat waits on the start line, pointing the way the race runs.
- While a run plays: the boat moves along its route with its wake (lit on the Mac); a star is drawn as a dashed outline for the 4 ticks it is gone.
- After a run (and at once under Reduce Motion or VoiceOver): the route as a line with arrows and the boat where the run ended, with every star shown (a still shows the track as set). A route with a way in and a loop has its legs numbered in order on white squares (the gates are indigo discs): **1** the way in, **2** the loop it then repeats. A route that is one loop (A, C) needs no number. Where a route runs a stretch both ways (rule A, over the line), it is drawn as two lanes with arrows each way, and, because that stretch is shorter than the boat that ends the run on it, a double-headed arrow beside it, on the loop's outer side.

At the accessibility text sizes (iPhone), the picture keeps its width but its labels don't grow, so a line under it says what it shows: "The boat waits on the start line.", "The boat is running rule A." while a run plays, or the route's sentence (the VoiceOver table below lists them; VoiceOver hears it once, in the picture's label).

Under the track, two counters: **Points** and **Laps** ("0 of 3"). They count up as a run plays and show where the shown run ended.

### Labels (on the canvas, never footnotes)

| Where | Kind | Text |
|---|---|---|
| Under the track, always | toy | A toy we built, not the real game. The boat takes the best-scoring route for your rule, which a computer worked out ahead of time. The 2016 agent learned its loop by trial and error. In the toy, the boat is fastest on the lagoon’s open water. |
| After the reveal | made up | Loopholes A and B are made up for this toy. DeepMind researchers keep a public list of dozens of real cases of the same kind. |

The first label is the slate's, word for word, plus one sentence: rule B's result depends on the toy's speeds, and the slate makes that part of the label. The second shows only after the reveal, because before it, "A and B are loopholes" would give the predictions away.

### 1 · The 2016-style rule (no prediction: the tutor has just told this story)

| Where | Text |
|---|---|
| Before it runs | First, a rule like the one in 2016: +10 points per target hit. |
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
| B | It moved 1,114 metres, round and round the open lagoon, and finished 0 laps. | Moving isn’t racing. It isn’t cheating. It’s scoring. |
| C | It went through gates 1, 2 and 3 in order and finished 3 laps. | It finished once the rule spelled out what a lap is. |

The guess is shown as **It finishes** / **It won’t finish**. A guess can't be changed once made; a tried rule's chip, picked again, shows its result, and picked once more plays it again.

### 3 · The reveal (once all three patches have run)

| Where | Text |
|---|---|
| You guessed | It would finish for 2 of the 3 rules (or "none of the 3 rules", "1 of the 3 rules", "all 3 rules") |
| What happened | It finished for 1 of them: rule C. |
| Under it | It isn’t cheating. It’s scoring. |
| Takeaway | Nothing was broken: the boat did exactly what each rule paid for. Paying for laps worked here because a lap is easy to count. “Be helpful” or “be honest” isn’t. |
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
| … revealed | You predicted it would finish for 2 of 3 rules. It finished for 1 of 3: rule C. It isn’t cheating. It’s scoring. |
| A run's sentence (also announced when a run ends, with the line under its result; after the third patch, with the reveal) | The 2016-style rule: plus 10 per target hit. The boat hit 26 targets, circling the stars in the lagoon, and finished 0 laps. 260 points. / Rule A: plus 100 per finish-line crossing. The boat crossed the line 30 times, back and forth, and finished 0 laps. 3000 points. / Rule B: plus 1 per metre moved. The boat moved 1114 metres, round and round the lagoon’s open water, and finished 0 laps. 1114 points. / Rule C: plus 100 per full lap through gates 1, 2 and 3 in order. The boat went through gates 1, 2 and 3 in order and finished 3 laps. 300 points. |
| The track (one image) | The toy track, seen from above: a loop with a finish line and gates 1, 2 and 3, and off to the side a lagoon with open water and 3 star targets. Then: The boat waits on the start line. / The boat is running rule A. / Its route: past gates 1 and 2 into the lagoon, then round and round the 3 stars. / Its route: back and forth over the finish line. / Its route: past gates 1 and 2 into the lagoon, then round and round its open water. / Its route: 3 laps, through gates 1, 2 and 3 in order each time. |
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
| Over the finish line, either way | 8 | 2 | 4 (the boat turns round) |
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
- 3 laps fill the clock exactly, so rule C has no spare tick for a detour.
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

The reveal's "You guessed" count is the student's own guesses (how many of A, B, C they said would finish); it is held in memory only.

---

## 3. Every factual claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | In 2016 an AI agent playing CoastRunners got lots of points and didn't finish ("Like the real 2016 CoastRunners agent: lots of points, no finish.") | True; in the guide (fact-check row 33, High). The agent scored more by circling and hitting the same reward targets, never finishing the race. "Catching fire" (Medium) is left off the card. The game isn't OpenAI's; the agent was, and the card names neither. | OpenAI, "Faulty reward functions in the wild", 2016-12-21, <https://openai.com/index/faulty-reward-functions/> (the page blocks fetching; confirmed through mirrors, row 33). DeepMind's specification-gaming post describes the same boat. |
| C2 | The 2016 agent learned its loop by trial and error (the label). | True: it was a reinforcement-learning agent trained on the game's score. | As C1. |
| C3 | "A rule like the one in 2016: +10 points per target hit." | A simplification, labelled: the 2016 agent was rewarded by the game's score, which rose as it hit targets. "+10" is our toy number, and the card says "a rule like", not "the rule". | As C1; the toy label. |
| C4 | DeepMind researchers keep a public list of dozens of real cases of the same kind (after the reveal). | True; in the guide (row 35, High): about 60 examples in 2020. | Krakovna et al., DeepMind, "Specification gaming: the flip side of AI ingenuity", 2020-04-21, <https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/>. |
| C5 | Loopholes A and B are made up for this toy, of the same kind as documented cases. | Ours, labelled "made up". They are toy loopholes, not documented incidents. | — |
| C6 | Every route, count and score on the card. | Toy arithmetic, re-derived in the tests (§2). | `PatchTheRewardTests`. |
| C7 | "Paying for laps worked here because a lap is easy to count. 'Be helpful' or 'be honest' isn't." | A judgement the lesson makes (the slate's takeaway): a goal that can be counted exactly can be paid for exactly; values like helpfulness can't be counted that way. "Here" keeps it to this toy. | Guide U5L1 Teach: "the difficulty of encoding human values in a loss function". |

**What this card does NOT say, on purpose:**
- that the boat (or any AI) wants, cheats, tricks, lies or is lazy, or that anything was broken: the copy says what each rule "paid for" and that the boat "scored" (the copy test bans the intent words everywhere on this card);
- that rule C is a perfect rule (see the teacher note);
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
- **The lesson's check is untouched.** On the iPhone, the check after the card still answers with one tap (the UI test). On the Mac a focused card control holds Return; A–D, 1–4 and ↑/↓ still answer the check.

### iPhone and Mac

- **iPhone:** today's lesson design, Lesson 1.1's night-sky island. The track sits at the top at full width; the label, the picked rule's panel, the rule chips and the reveal stack under it. Chips and buttons are 44 pt or taller; picking a rule or a guess gives a selection haptic.
- **Mac:** Night Studio's lit card. A larger track (the card's full width) with the boat's lit wake on night water, the card's one motion set piece. From a 520 pt content width the rules sit in a column to the right of the picked rule's panel; narrower, they stack. Below 440 pt the compact "Try it" card.
- **Mac keyboard:** Tab reaches "Play it", the guesses, "Skip to the result", "Play it again" and each rule's chip. Return or Space picks a chip; on the picked chip of a rule that has run, it plays it again. ←/→ (and ↑/↓ when the check isn't waiting) on a chip pick the rule before or after.

### Accessibility

- **VoiceOver:** the title is a header with the card's state in one sentence; the track is one image described once in words, with its route; each run is spoken as a result with its counts, not as motion; the reveal is one element.
- **Dynamic Type to AX5 on an iPhone SE:** the track stays full width, with its route written under it, the counters become a text table, chips stack their words, and decoration (icons, the card's light and stars) goes. Never a word. A UI test (`testAtTheLargestTextSizeEveryLineStaysInsideTheWindow`) scrolls the revealed card at AX5 from its title to its last label and fails if any line leaves the window's width; it passes on the SE and the 16 Pro Max.
- **Reduce Motion:** nothing plays by itself; each run's still route with numbered arrows and its result appear at once.
- **Increase Contrast / Reduce Transparency:** no glows or stars, solid edges, the HC values.
- **Nothing by colour alone:** stars are star shapes (a dashed outline while gone), gates are numbered, the line is chequered and says "finish", a picked chip has a check, a tried chip says its laps.

---

## 5. Invented names

None. The card names no person, place or brand of its own. Real names: CoastRunners (the game in the guide, row 33) and DeepMind (row 35, the slate's optional footnote). The rules are lettered A–C.

---

## 6. For teacher review

Please tick each, or note a change. Sign-off is recorded at the end, with a date.

**Accuracy**
- [ ] C1/C3: "A rule like the one in 2016: +10 points per target hit" and "Like the real 2016 CoastRunners agent: lots of points, no finish" are fair, with the toy label under the track.
- [ ] The label's "The boat takes the best-scoring route for your rule, which a computer worked out ahead of time. The 2016 agent learned its loop by trial and error." makes the planner-versus-learner difference clear. *Teacher note:* real reinforcement-learning agents learn from trial and error and may not find the best route; this toy shows where the best route goes, which is where a good enough learner heads.
- [ ] Rule C is presented as a rule that worked **here**, not a perfect rule. *Teacher note:* on a track with a shortcut, "a full lap through gates 1, 2, 3 in order" could still be gamed (a shorter way between gates), which is the lesson's point: each patch can open a new gap.
- [ ] B's result depends on the toy's speeds, and the label says the boat is fastest on the lagoon's open water.
- [ ] The made-up label after the reveal ("Loopholes A and B are made up for this toy…") is clear.

**Language (ages 13–18)**
- [ ] "It isn’t cheating. It’s scoring." lands, and no line gives the boat intent.
- [ ] The rule texts read clearly: "+100 every time it crosses the finish line", "+1 for every metre it moves", "+100 for each full lap through gates 1, 2, 3 in order".
- [ ] "Will it finish now?" with Yes / No is a clear prediction.

**Fit with the lesson**
- [ ] The card's place, after the CoastRunners example's part and before the check, works with the tutor's telling (the 2016-style rule replays without a prediction).
- [ ] **Exercise clash:** do the lesson's exercise ("Design a reward function for an AI that helps students study. Then identify 3 ways it could be gamed") right after the card. The card should have made the idea concrete without answering it.
- [ ] The aha lands in about 90 s without the tutor's help: the boat does exactly what the points pay for; two of three patches leave a gap.

**Ethics for minors**
- [ ] No real faces, voices or people; no one is accused of anything; no dark patterns (no score for the student, nothing kept).

**Accessibility**
- [ ] A VoiceOver-only pass: the track's description and each run's spoken result say what a sighted student sees.
- [ ] AX5 on an iPhone SE: nothing cut, nothing scrolls sideways.
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
- **Q2. The overall reveal on the iPhone sits under the rule chips.** After the third patch's run, the patch's own result shows in the panel above the chips, and the reveal ("You guessed … What happened …") appears below them, so a student scrolls past the chips to reach it (VoiceOver speaks it with the run's result). Scrolling the lesson to it is the lesson list's job (ChatFeature), not the card's; worth a look in the teacher pass.
- **Q3. Rule A's motion is small.** The stretch over the finish line is 8 m, shorter than the boat, so the run rocks the boat across the line rather than travelling. The still adds a double-headed arrow beside it. A longer stretch would mean retuning the toy track and re-proving that every rule's best route is unique.
- **Q4. "Play it" replays the 2016-style rule with no guess** because the tutor has just told that story (the card sits after the CoastRunners example). If the tutor's first example is a different case, the replay still introduces itself ("First, a rule like the one in 2016"), but it then plays without a prediction to a student who hasn't heard the story.

---

## 9. Verified (2026-10-21)

- `swift test` (ios/Packages): 1,315 tests pass, including `RoutePlannerTests` and `PatchTheRewardTests`.
- `ios/scripts/ci-compat-lint.py`: 0 findings.
- iOS build and `xcodebuild test` on the iPhone 16 Pro Max simulator (snapshot recording forced off, `ViewSnapshotTests` skipped as in the framework's run): 6/6 app unit tests; 34/34 UI tests other than this card's. The card's 3 UI tests pass on the SE and on the 16 Pro Max (§6.3; their first version queried the shared controls, which appear twice in the UI test tree, and waited on `isHittable`, which the lesson list never reports; both fixed).
- `ios/scripts/ios-unchanged-check.sh`: the same 23 results (11 pass, 12 already stale) and the same pixels for every stale render. No record run.
- Mac Debug build: builds. Shots through renamed copies (`….macnsia1`), quit by PID; the founder's Mercurius kept running.
- Shots in `shots/` (not committed): the iPhone 16 Pro Max in light and dark at the default size and at AX3, the SE at AX5 (including the AX5 test's walk through the whole card), the Mac at 1280 and 700 pt wide in light and dark, Increase Contrast, Reduce Motion stills, and a 7.5 s clip of patch C's run ending on its reveal.

