# The Doubt Dial: the content

**What this is:** every line a student sees or hears in Lesson 6.4's interactive on the iPhone and the Mac, every number it shows with how it is counted, every claim it makes and its source, the invented-name searches, the VoiceOver script, and the checklist for the teacher who reviews it.
**Where it shows:** Unit 6, Lesson 4 ("Misinformation and the liar's dividend", `u6_l4`), as a card at the end of the part of Merc's first teach reply that holds its first example (synthetic media in the news; cheapfake vs. deepfake), before that reply's check. That is before the reply that names the liar's dividend: the student meets the trap, and the tutor names it next. Anchor: `.firstExample`, no spoiler terms (the card never uses the term "liar's dividend", so if the tutor names it in the first reply the card still works unchanged).
**Status:** built on both platforms, **ships dark** (`enabled: false` in `InteractiveRegistry`) until the teacher review below is signed off. Turning it on is a separate last commit and needs the founder's explicit OK.
**The code** (`ios/Packages/LessonInteractives/`):
- `Sources/Cards/DoubtDial/DoubtDialContent.swift`: the ten posts, the dial's stops and every count (pure; through the shared `ThresholdCounters` block).
- `Sources/Cards/DoubtDial/DoubtDialCopy.swift`: every line below (`everyLine`), the labels, `accessibilitySummary`, `predictionLines`.
- `Sources/Cards/DoubtDial/DoubtDialState.swift`: the guess, the dial's stop and "Check first", in memory only; its DEBUG shot arguments.
- `Sources/Cards/DoubtDial/DoubtDialSections.swift`, `DoubtDialPieces.swift`: the sections and pieces both platforms draw.
- `Sources/Views/Phone/DoubtDialPhoneCard.swift` (iPhone), `Sources/Views/Mac/NightDoubtDialCard.swift` (Mac).
- `Tests/DoubtDialTests.swift` (every number re-derived, the register, VoiceOver, the state machine) and `ios/MercuriusUITests/DoubtDialUITests.swift` (end to end in the lesson).
**Screenshots:** `docs/interactives/doubt-dial/shots/` (kept out of git; see §9). Two key shots are committed: `docs/interactives/key-shots/doubt-dial-*.jpg`. The key shots were retaken on the merged `feat/interactives-wave1` build (2026-10-22), the same way for every card: iPhone 16 Pro Max at Large, light, the card's top in its lesson beside its reveal; Mac, the top (light) beside the reveal (dark).

The card is a picture the app draws. It sends nothing, stores nothing and changes nothing in the prompt or the lesson. Every post and every "what checking found" line is authored for this lesson, about a made-up town, and labelled so on the canvas. It shows no statistics.

---

## 1. Every line the student sees

Curly quotes and apostrophes are as drawn. A number in **bold** is counted by the code (§2), never typed in.

### The card

| Where | Text |
|---|---|
| Eyebrow | INTERACTIVE |
| Title | The Doubt Dial |
| Hook | **Ten** posts about the made-up town of Port Avery: **5** are real and **5** are fake. We wrote them all, so we know which. |
| Dots line | The dots show how surprising each post looks, from 1 to **5**. |
| Label (on the canvas) | A made-up feed. Real feeds aren’t half fake. The dial judges only by how surprising a post looks. |

### 1 · The guess (before anything else works)

| Where | Text |
|---|---|
| Question (a header) | Which setting will fool you least? |
| Chips | Believe everything / Somewhere in the middle / Doubt everything |

One tap locks the guess; it can't be changed. The picked chip keeps a check mark, and the others dim as inactive controls (2.6:1, which WCAG 1.4.3 exempts for inactive controls; the guess is also printed in the reveal). The picked chip's 4.2:1 is an open framework question (§10).

### 2 · The dial (the one control)

| Where | Text |
|---|---|
| Caption | How much doubt? |
| The stop, as a heading | Believe everything / Believe most / In the middle / Doubt most / Doubt everything |
| Under the track | Believe everything … Doubt everything (its two ends) |
| Before the guess (VoiceOver) | Make your guess first. |
| After the guess, before "Show me" | Turn the dial and watch both counters. |
| The stop's rule | Shares every post. / Shares posts with up to **4** dots. Waves away the rest. / Shares posts with up to **3** dots. Waves away the rest. / Shares only posts with **1** dot. Waves away the rest. / Waves away every post. |
| The strip (under the rule) | The ten posts in one row, least surprising first: **R** or **F** in each cell, its glyph (↗ shared, ⊘ waved away), a ring and a ✕ under each post the setting gets wrong, and the dial's cut between the shared posts and the rest. |
| The strip's key | R real · F fake · ↗ shared · ⊘ waved away · ✕ a mistake |
| Counter 1 | Fakes you’d share: **n** |
| Counter 2 | Real stories you’d wave away: **n** |
| Under the counters | **4** mistakes out of **10** at this setting. |
| Button, after two settings | Show me |

The dial starts at Believe everything once the guess is locked, so turning it adds doubt. "Show me" appears after two moves (`DoubtDialState.showMeAfter`).

**The strip** keeps the dial's effect in view: on a phone the feed sits below the fold, so without it turning the dial mostly changed two numbers. Each turn now moves the cut and flips cells in place, right under the dial; at every setting R and F cells sit on both sides of the cut (R R F R F R F R F F), which is the aha in one picture. It is display only (the dial stays the one control), never moves (cells and the cut crossfade), and is one VoiceOver element that says it in words. At the accessibility sizes it is that line of words under the counters:

| Setting | The strip in words |
|---|---|
| Believe everything | Mistakes at this setting: School board, Water tower, Shark photo, Leaked audio, Lighthouse (fakes shared). |
| Believe most | Mistakes at this setting: School board, Water tower, Shark photo (fakes shared); Bridge (real story waved away). |
| In the middle | Mistakes at this setting: School board, Water tower (fakes shared); Seal, Bridge (real stories waved away). |
| Doubt most | Mistakes at this setting: Ferry fares, May snow, Seal, Bridge (real stories waved away). |
| Doubt everything | Mistakes at this setting: Library, Ferry fares, May snow, Seal, Bridge (real stories waved away). |

### 3 · The reveal (the guess beside the result; never a score)

| The guess | YOU GUESSED | WHAT HAPPENED |
|---|---|---|
| Believe everything | Believe everything | Believe everything never waved away a real story, but it shared all **5** fakes: **5** mistakes, the same as doubting everything. The middle did a little better, but no setting got below **4** mistakes out of **10**. |
| Somewhere in the middle | Somewhere in the middle | You’re right: the middle fooled you least. But even there it made **4** mistakes out of **10**, and moving within the middle only swapped one kind of mistake for the other. |
| Doubt everything | Doubt everything | Doubt everything never shared a fake, but it waved away all **5** real stories: **5** mistakes, the same as believing everything. That’s just what someone caught in a real story would want: everyone calling it fake. The middle did a little better, but no setting got below **4** mistakes out of **10**. |
| (spoiled mode: no guess) | — | Doubt everything never shared a fake, but it waved away all **5** real stories: **5** mistakes, the same as believing everything. The middle did a little better, but no setting got below **4** mistakes out of **10**. |

**"Show me" turns the dial to the setting the result names**, so the counters, the lit mistakes cell, the strip and the feed beside the sentence all agree with it: the guess's end for Believe everything or Doubt everything; for "Somewhere in the middle", the middle stop the student is on (or In the middle if they were at an end); Doubt everything in spoiled mode. (Before this fix the dial stayed where the student left it, usually In the middle after two moves, so a "Doubt everything" guesser read "It shared no fakes" under counters showing 2 fakes shared.) Each result names its setting rather than "it", so it stays true if the student turns the dial on. It happens in two beats: the dial turns in place to that setting (the card's change animation, a crossfade under Reduce Motion, and the iPhone's selection haptic), and about 0.7 s later, once its words and colours have settled, the reveal fades in, so the layout never moves while the dial’s words are still changing.

The middle guess is the right one under this card's own data (4 against 5), and its reveal says so. The ends' reveals say they tied for worst (5 = 5, a test) and that the middle did a little better. The Doubt-everything reveal names the cost for a student who reads "fool you least" as "believe the fewest fakes": waving away every real story is as bad as believing everything, and it is what someone caught in a real story would want.

Once revealed, a row appears under the dial's stops: **Mistakes out of 10 at each setting**, with **5 · 4 · 4 · 4 · 5** under the five stops (the current one lit). The reveal and the row fade in once the card's layout has settled, so no text draws over the feed while it moves.

### 4 · Check first (the move that works)

| Where | Text |
|---|---|
| Intro | The dial only looks at how surprising a post seems. Checking looks at where it came from, and who else reports it. |
| Button | Check first |
| After it: three counters | Fakes shared: **0** · Real stories waved away: **0** · Not sure yet: **2** |
| What checking did | Checking sorted **8** of **10**, and was honest about the other **2**: not sure yet. |
| Label (on the canvas) | These checks are made up too, like the feed. Real checking is messier. |
| Button | Back to the dial (turning the dial leaves "Check first" too) |

The dial's own counters stay where they are, so the student sees the dial's mistakes and checking's side by side.

**Not like for like, on purpose, and said so.** Checking may hold a post back ("not sure yet"); the dial can't (every stop shares or waves away every post). The seal is a real story checking holds back: it is counted under "Not sure yet", not under "Real stories waved away", and never marked a mistake. The line under the counters reports what checking did (8 settled, 2 held back) rather than claiming checking sorts everything; the general rule ("how to avoid both believing everything and believing nothing") is left for the lesson's exercise.

### 5 · The feed (least surprising first)

Heading **The feed**, caption **Least surprising first.** Each post shows its title, its surprise dots, **Real** or **Fake** (we wrote them, so we know), and once the guess is locked a glyph and a word: **Shared** (↗) or **Waved away** (⊘); under "Check first", **Shared**, **Not shared** (⊘) or **Not sure yet** (…), with what checking found under the title.

A post the setting gets wrong (a fake **Shared**, a real story **Waved away**) also carries **✕ Mistake** in a small well beside its verdict, so the feed shows the counters' posts one by one: at In the middle, the school board and the water tower (fakes shared) and the seal and the bridge (real stories waved away). "Not sure yet" is never marked: it is an honest answer, not a mistake. After "Check first" nothing is marked.

| # | Post | Real or fake | Surprise | What checking found | Checking says |
|---|---|---|---|---|---|
| 1 | Library lends fishing rods | Real | 1 | The library’s own page lists the rods, and the Port Avery Gazette ran it too. | Shared |
| 2 | Ferry fares drop to $1 for the summer | Real | 2 | The ferry company and the Port Avery Gazette both report it. | Shared |
| 3 | School board adds Saturday classes | Fake | 2 | The school board’s meeting notes show no such vote, and the Gazette hasn’t reported it. | Not shared |
| 4 | May snow closes schools for a day | Real | 3 | The school district’s notice and the town’s weather report both say so. | Shared |
| 5 | Water tower to be torn down Friday | Fake | 3 | One post, and no town notice yet. | Not sure yet |
| 6 | A seal naps on the ferry dock, and the ferry waits | Real | 4 | One video, posted an hour ago. No one else has it yet. | Not sure yet |
| 7 | Photo: a shark in the town pool | Fake | 4 | Reverse search: this photo first appeared years ago, somewhere else. A real photo, a false story. | Not shared |
| 8 | Council votes to paint the old bridge purple | Real | 5 | The council’s meeting notes record the vote, and the Gazette covered it. | Shared |
| 9 | Leaked audio: the mayor cancels summer break | Fake | 5 | The words come from an old speech, cut up and put back in a new order. The full speech is on the town’s site. | Not shared |
| 10 | Video: lightning knocks out the lighthouse | Fake | 5 | The harbor office says the light never went out, and its live camera shows it lit tonight. | Not shared |

The "leaked audio" and the "video" are one line of text each: nothing is played or shown. The mayor has no name. Each post also has a short name for the strip's words (Library, Ferry fares, School board, May snow, Water tower, Seal, Shark photo, Bridge, Leaked audio, Lighthouse). Every "Not shared" verdict rests on two things (a record that contradicts it and no coverage, or the original found); the two posts with one thin source each (the water tower, the seal) stay not sure yet.

### The Mac

The same lines, in the same order, drawn in Night Studio. The feed sits in two columns that crossfade as the dial turns:

| Where | Text |
|---|---|
| Before the guess | The feed in two halves, no verdicts |
| Column headers (dial) | SHARED · **n** / WAVED AWAY · **n** |
| Column headers (Check first) | SHARED · **4** in the left column; NOT SURE YET · **2** over NOT SHARED · **4** in the right (the seal, real and held back, never sits among the fakes) |
| An empty column | No posts at this setting. |
| Compact card (narrower than 440 pt) | INTERACTIVE · The Doubt Dial · "Turn a dial from believing everything to doubting everything, and count the mistakes in a made-up feed." · Try it |

The counters glow in lumen (not under Increase Contrast or Reduce Transparency).

### The iPhone at the accessibility sizes (AX1 to AX5)

Decoration goes, never a word: the eyebrow's icon, the dots and the glyphs go; each post becomes its title over a line of words ("Real · surprise 4 of 5 · Waved away · Mistake"); the dial becomes two buttons, **Less doubt** and **More doubt**, under its stop's name; the counters and the mistakes row become text tables; the strip becomes its line of words ("Mistakes at this setting: …") under the counters. The counters stay above the feed.

---

## 2. Every number, and how it is counted

All of these are toy data (the made-up feed) or arithmetic over it. `DoubtDialTests` re-derives each by counting the posts directly and holds it to the slate's table. Two kinds of check cover the lines: the key lines are pinned word for word with their numbers (every stop's VoiceOver value, mistakes line, strip line and Mac column headers; the three reveals and the spoiled one; the takeaway; checking's counters and groups), and a set-membership test checks that every number in every other line is one the content counts somewhere (it would not catch a wrong number that happens to be in that set, which is why the key lines are pinned).

| Number | Where | How it is counted |
|---|---|---|
| Ten (10), 5, 5 | Hook, VoiceOver | `posts.count` (spelled out where it starts a sentence); real posts; fake posts |
| 1 to 5 | Dots line, each post | Authored surprise scores: real 1, 2, 3, 4, 5; fake 2, 3, 4, 5, 5 (slate.json) |
| 4, 3, 1 dots | The stop's rule | The stops' limits, 5, 4, 3, 1, 0 (slate.json): a post is shared when its surprise is at most the limit |
| Counters at each stop | Counters, VoiceOver | Fakes with surprise ≤ limit; real posts with surprise > limit (table below) |
| 5, 4, 4, 4, 5 | Mistakes row, reveal | The two counters added at each stop |
| 4 (fewest) | Reveal ("no setting got below 4") | The smallest of the row; also the smallest over every limit from 0 to 5 (5, 4, 4, 4, 4, 5: a test), not only the dial's five |
| 4 (middle) | Reveal ("even there it made 4") | Believe most, In the middle and Doubt most all make 4 (the test checks they are equal, and that 4 is under both ends' 5: "You’re right") |
| 5 (an end) | Reveal ("5 mistakes, the same as …") | Each end's two counters added; the test checks the two ends are equal (5 = 5) |
| 0, 0, 2 | Check first | Fakes that checking shares (0); real posts checking marks Not shared (0); posts it holds back as not sure yet (2: the water tower, fake, and the seal, real). The seal is a real story checking doesn't share, but it is held back as "not sure yet" and counted there, not as a real story waved away |
| 8 of 10, the other 2 | What checking did | Posts checking settled (shared or not shared: 4 + 4), of all 10; the 2 it held back |
| The strip's cells and cut | Under the dial | Each post's verdict at the stop; the cut sits after the shared run (shared posts are always a run at the start, a test); a ring and ✕ on exactly the posts the counters count (a test checks the strip's words name exactly those) |
| Posts marked "Mistake" | The feed | At each stop, exactly the posts the two counters count (fakes with surprise ≤ limit, real posts with surprise > limit), so their number is the mistakes row's: 5, 4, 4, 4, 5; none after checking (a test) |
| Column counts (Mac) | Column headers | Shared at each stop: 10, 7, 5, 1, 0 (so waved away 0, 3, 5, 9, 10); after checking 4 shared, 2 not sure yet, 4 not shared (they sum to 10; not sure yet equals its counter, and no real post is in Not shared: tests) |
| $1 | Post 2's title | Made-up content of the made-up feed (the only number inside a post; the test holds it there) |

| Dial stop | Limit | Fakes you'd share | Real stories you'd wave away | Mistakes out of 10 |
|---|---|---|---|---|
| Believe everything | 5 | 5 | 0 | 5 |
| Believe most | 4 | 3 | 1 | 4 |
| In the middle | 3 | 2 | 2 | 4 |
| Doubt most | 1 | 0 | 4 | 4 |
| Doubt everything | 0 | 0 | 5 | 5 |

The slate's own cross-check, `tools/check_slate_numbers.py` (U6L4 section, in the `interactives-shared` worktree), gives the same table and "at least 4 mistakes" at every stop.

---

## 3. Every claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | Doubt alone can't sort real from fake: at every setting of a dial that judges by how surprising a post looks, there are at least 4 mistakes out of 10. | True of the card's made-up feed (§2), and labelled as such on the canvas ("A made-up feed. Real feeds aren’t half fake. The dial judges only by how surprising a post looks."). In this feed surprise only weakly tracks truth (fakes average 3.8 dots, real posts 3.0; every level from 2 to 5 holds one of each, a test), so no cut-off, at any limit from 0 to 5, gets below 4 mistakes (a test runs every limit). The weak link is why the middle (4) beats the ends (5), and the middle reveal says so. It doesn't claim real feeds have these numbers. | Toy data; design from SLATE.md card 1 and RESEARCH.md M13. |
| C2 | Doubting everything isn't the safe default: it shares no fakes, and waves away every real story. Both count as mistakes. | The card scores both kinds of mistake on purpose, and weighs them the same (one each in "mistakes out of 10"): a simplification, see the accuracy notes below. | Design rationale, not shown: Modirrousta-Galian & Higham 2023 (*J. Exp. Psychol.: General* 152(9), 2411–2437; status **secondary**: the PubMed and Southampton pages refused an automated read on 2026-10-21, so this rests on their indexed summaries and RESEARCH.md): a signal-detection reanalysis found gamified inoculation (Bad News, Go Viral!) made players answer "false" to more news of every kind, without telling true from fake any better. The finding is contested by the games' authors (RESEARCH.md row 14: "Proponents dispute this"). <https://pubmed.ncbi.nlm.nih.gov/36996156/> · <https://eprints.soton.ac.uk/475360> |
| C3 | "That’s just what someone caught in a real story would want: everyone calling it fake." | The payoff of blanket doubt to someone caught in a true story, without naming or defining the term: the trap is denying a real story that is already out, which is why the line says "caught in", not "hiding". The tutor's next reply names the liar's dividend and attributes it. Chesney and Citron's own point, as summaries report it (status **secondary**: the article itself not read here), is that the more the public is taught that anything could be fake, the more believable a liar's denial of real evidence becomes. | Guide U6L4 Teach line and Common mistake ("Swinging to ‘everything is fake.’ That IS the liar’s dividend working on you."); fact-check row 50: Chesney & Citron, 107 Calif. L. Rev. 1753 (2019), status High. <https://law.utexas.edu/faculty/publications/2019-deep-fakes-a-looming-challenge-for-privacy-democracy-and-national-security/> |
| C4 | Checking looks at where a post came from, and who else reports it. | The two SIFT moves the "Check first" lines use: find better coverage (the ferry company and the Gazette both report it; the harbor office and its camera) and trace claims, quotes and media to the original context (the reverse image search; the old speech). Status **read** (2026-10-21) for the moves. The SIFT post doesn't name reverse image search; Caulfield's own textbook does, as a chapter under "Go Upstream to Find the Source" (status **secondary**: its place in the book confirmed from the table of contents on 2026-10-21; the chapter page refused an automated read). Library guides built on Caulfield's materials teach the same under "Trace" (status **secondary**). | Mike Caulfield, "SIFT (The Four Moves)", 2019-06-19. <https://hapgood.us/2019/06/19/sift-the-four-moves/> · Mike Caulfield, *Web Literacy for Student Fact-Checkers* (2017), "Using Google Reverse Image Search". <https://ecampusontario.pressbooks.pub/webliteracycaulfield/chapter/using-google-reverse-image-search/> · e.g. Paradise Valley Community College library, SIFT: Trace ("Finding the History of Images", crediting Caulfield). <https://paradisevalley.libguides.com/sift/trace> |
| C5 | "A real photo, a false story." (the shark photo) | A cheapfake: real media given a false context. It ties to the first reply's cheapfake vs. deepfake distinction without using either word. | Guide U6L4 Teach line ("the cheapfake vs. deepfake distinction"). Paris & Donovan, *Deepfakes and Cheap Fakes: The Manipulation of Audio and Visual Evidence* (Data & Society, 2019-09-18), list re-contextualizing real footage among cheap-fake techniques (status **read**, 2026-10-21). <https://datasociety.net/library/deepfakes-and-cheap-fakes/> |
| C6 | "Checking sorted 8 of 10, and was honest about the other 2: not sure yet." Checking doesn't settle everything. | Two of ten posts stay not sure yet (one real, one fake), so the card doesn't promise that checking always resolves a claim. | Design (SLATE.md accuracy notes); RESEARCH.md §4: "treat ‘I’d check’ as a valid answer". |
| C7 | "Real feeds aren’t half fake." (the label) | A plain statement, with no number, that the card's 5-and-5 split is not what real feeds look like. No prevalence number is shown on the card or added to the tutor's text (none is in the guide's fact-check). | Allen, Howland, Mobius, Rothschild & Watts, "Evaluating the fake news problem at the scale of the information ecosystem", *Science Advances* 6(14), eaay3539 (2020): fake news was about 0.15% of Americans' daily media diet and about 1% of their news (status **secondary**: abstract and indexed summaries, 2026-10-21). <https://doi.org/10.1126/sciadv.aay3539> · Design rationale: Acerbi, Altay & Mercier, "Research note: Fighting misinformation or fighting for information?", *HKS Misinformation Review* 3(1) (2022): misinformation is a small share of what people see, and interventions aimed only at it risk raising skepticism toward reliable news, the trap this lesson is about (status **read**, 2026-10-21). <https://misinforeview.hks.harvard.edu/article/research-note-fighting-misinformation-or-fighting-for-information/> |

**Accuracy notes (simplifications the card makes on purpose):**
- **The feed is half fake.** Real feeds are overwhelmingly not fake (C7). The 5-and-5 split makes both kinds of mistake visible in ten posts; the label says real feeds aren't half fake.
- **Both kinds of mistake cost the same.** "Mistakes out of 10" counts a fake shared and a real story waved away as one each. In life the costs differ by story; the card only needs both to count.
- **Checking may hold back; the dial can't.** Checking has a third answer, "not sure yet", that no dial stop has. The card counts it on its own (never as a mistake, never as a real story waved away), the Mac shows it as its own group, and the line under checking's counters says 2 were held back. So "0 real stories waved away" is true, and the comparison with the dial is visibly not like for like.
- **One check per verdict is thin.** Each "Not shared" verdict rests on two things (a record that contradicts the post plus no coverage, or the original found); posts with one thin source stay "not sure yet". The lighthouse check was strengthened after review to the harbor office's word plus its camera.

**What the card does NOT say, on purpose:**
- the term "liar's dividend" (a test checks no line says "liar" or "dividend"), or that doubting is the liar's dividend;
- that surprising means fake (some real posts are very surprising; some fakes are plain);
- that checking always settles a claim, or that "Checking can" sort them (it reports 8 of 10 settled);
- anything about the Biden robocall, Steve Kramer or any real person or event (they stay in the tutor's text, never simulated);
- any statistic about real misinformation (the label's "Real feeds aren’t half fake" has no number);
- that the "how surprising" scores or the checks come from a model: they are authored, and labelled made up.

**Exercise clash (medium-low).** The lesson's exercise is a real clip and a fake clip about the same event. The card uses neither: no clips, no one event, and its checking moves are general.

### Departures from the slate (after the 2026-10-21 review)

SLATE.md card 1 (in the shared slate) still has the original wording; these lines differ on purpose, and the slate should take them when it is next revised:

| Slate | Card now | Why |
|---|---|---|
| Stop "Unsure" | "In the middle" | The stop makes firm calls (shares up to 3 dots, waves away the rest) and earned 4 "Mistake" marks, while the takeaway praised "not sure yet"; a student could leave thinking being unsure is a mistake. "Not sure" wording now belongs to checking alone. |
| Label "A made-up feed. Here the dial judges by how surprising a post looks. Real checking is messier." | "A made-up feed. Real feeds aren’t half fake. The dial judges only by how surprising a post looks." | "Real checking is messier" above the dial, before checking appears, made the dial read as a simple kind of checking. The caveat moved under Check first; the label now says the half-fake mix is made up too (C7). |
| Reveal (doubt): "It shared no fakes, and waved away all 5 real stories. That's exactly what someone hiding a real story would want." | §1 · 3 | It read as a win for the student it was aimed at (it never said 5 = 5), "it" didn't name the setting, and "hiding" was the wrong idea (the trap is denying a story that is already out). |
| Reveal (middle): "Every setting in the middle still makes 4 mistakes." (+ "Turning the dial only moved your mistakes around.") | "You’re right: the middle fooled you least. …" | The middle guess is right under the card's own data (4 against 5); "only moved your mistakes around" was false across the whole dial. |
| (not in the slate) | The strip under the dial | The feed was below the fold, so turning the dial mostly changed two numbers. |
| Check first's two columns (Mac) | Three groups | The seal (real, held back) sat in "Not shared" with the fakes. |
| Takeaway "Doubt alone can't sort them. Checking can, …" | "Checking sorted 8 of 10, and was honest about the other 2: not sure yet." | Reports what happened instead of handing over the exercise's answer, and no longer overclaims (2 of 10 stay unsorted). |

---

## 4. Placement and behaviour (for the reviewer)

- **Where:** in the first of Merc's replies in Lesson 6.4 that has an [EX] example, at the end of the part that example is in, before any check (or, with no example, at the first complete reply's end before its check). This is today's `.firstExample` rule, shared with Lesson 1.1, run by ChatFeature's `LessonInteractiveAnchor`.
- **Once per thread**, never into text still streaming, never in a cut-off reply, never in a thread with a crisis line (988 or 741741), and in the same place when the lesson is reopened in the same run. No wire or prompt change.
- **Not spoiled by the tutor:** the card has no spoiler terms. If the tutor folds the liar's dividend into the first reply, the prediction loses some surprise but the card still works (SLATE.md risk). `-InteractiveState spoiled` shows the spoiled mode for review anyway.
- **The lesson's check is untouched.** On the iPhone a tap on an option grades and sends "I picked A) …" as before (the UI test does exactly this below the card). On the Mac A–D, 1–4 and ↑/↓ still answer the check: the dial takes ←/→ only while it has focus, and a focused card control holds Return so the check never locks in from it.
- **State** lives in the lesson's `InteractiveStateStore` for the open lesson only: never encoded, stored or sent; a new lesson screen starts fresh.

### Mac keyboard

| Key | Does |
|---|---|
| Tab / Shift-Tab | The three guesses, the dial, "Show me", "Check first" / "Back to the dial" (whatever the Full Keyboard Access setting) |
| Space or Return | Locks a guess, presses a button |
| ← / → | Turn the dial, only while it has focus |
| A–D, 1–4, ↑/↓ | Still answer the lesson's check |

---

## 5. Invented names (searched 2026-10-21)

| Name | Search | Result |
|---|---|---|
| Port Avery (the town) | GeoNames full-text search (geonames.org/search.html?q=Port+Avery) | "no records found in geonames database" (only unrelated Wikipedia hits) |
| Port Avery | USGS GNIS, The National Map geonames service: `gaz_name LIKE '%PORT AVERY%'` on every place, physical, cultural and historical layer | 0 features (a control query for "Avery" returned many, so the search works) |
| Port Avery | Canadian Geographical Names Database (geogratis.gc.ca geonames, q=Port Avery) | 0 results (a control query for "Avery" returned 25) |
| Port Avery | Web search ("Port Avery" town) | No town or place of that name; only places called Avery |
| Port Avery Gazette | Web search ("Port Avery Gazette") | No such publication (only Port Phillip, Port Fairy, Port Pirie and Port Sunlight papers) |
| The mayor, the council, the school board, the library, the ferry company | Unnamed | — |

No brands, platforms or real people appear. The slate's own example of an unusable name was "Larkfield" (Larkfield-Wikiup, California).

---

## 6. The VoiceOver walk-through

| Element | Spoken |
|---|---|
| The card's title (a header; its value is the state) | Interactive: The Doubt Dial. Ten made-up posts, 5 real and 5 fake. Make your guess, then turn the dial. |
| Hook, dots line, label | Read as text |
| The question (a header) | Which setting will fool you least? |
| Each guess chip (a button) | Doubt everything. Hint: Locks in your guess. It can’t be changed after. (Once picked: selected, "Your guess, locked in".) |
| The dial (one adjustable element), before the guess | Doubt dial. Make your guess first. |
| The dial, after it (swipe up or down) | Doubt dial. Believe most. You’d share 3 fakes and wave away 1 real story. |
| The strip (one element) | Mistakes at this setting: School board, Water tower, Shark photo (fakes shared); Bridge (real story waved away). |
| The counters (one element) | Fakes you’d share: 3. Real stories you’d wave away: 1. |
| Show me (a button) | Show me. Hint: Shows what happened, beside your guess |
| Announced on Show me; the reveal (one element) | You guessed Doubt everything. Doubt everything never shared a fake, but it waved away all 5 real stories: 5 mistakes, the same as believing everything. That’s just what someone caught in a real story would want: everyone calling it fake. The middle did a little better, but no setting got below 4 mistakes out of 10. (The dial is now at Doubt everything, and says so when focused.) |
| The mistakes row (one element) | Mistakes out of 10 at each setting. Believe everything: 5 mistakes. Believe most: 4 mistakes. In the middle: 4 mistakes. Doubt most: 4 mistakes. Doubt everything: 5 mistakes. |
| Check first (a button) | Check first. Hint: Shows what checking found for each post |
| Announced on Check first | Check first: 0 fakes shared, 0 real stories waved away, 2 not sure yet. Checking sorted 8 of 10, and was honest about the other 2: not sure yet. |
| Checking's counters (one element) | Fakes shared: 0. Real stories waved away: 0. Not sure yet: 2. |
| The feed's heading (a header) | The feed |
| Each post (one element, ending in its state) | A seal naps on the ferry dock, and the ferry waits. Real. Surprise 4 of 5. Waved away. A mistake. (A post the setting gets right ends at its verdict: "… Shared.") |
| Each post under Check first | … Real. Surprise 4 of 5. Not sure yet, so don’t share yet. What checking found: One video, posted an hour ago. No one else has it yet. |
| Mac column headers (headers) | Shared: 7 posts / Waved away: 3 posts; under Check first, Shared: 4 posts / Not sure yet: 2 posts / Not shared: 4 posts |
| Back to the dial (announced) | The dial's line at its stop |

The dial's own moves aren't announced: VoiceOver reads an adjustable control's new value itself.

---

## 7. Accessibility and motion

- **Dynamic Type to AX5 on an iPhone SE:** §1's accessibility sizes. Nothing scrolls sideways; checked in the AX5 SE shot.
- **Reduce Motion:** every change crossfades in place (`theme.animation`, `InteractiveMotion`); nothing slides or flips, nothing plays by itself. On the Mac, posts crossfade between columns either way. The strip never moves: its cells and its cut crossfade. The reveal and Check first fade in once the layout has settled (a short delay, with or without Reduce Motion), so their text never draws over the moving feed.
- **Increase Contrast / Reduce Transparency:** no glows or stars, solid edges (`theme.lit` false; the counters' lumen glow goes).
- **Never colour alone:** each post's state is a glyph and a word; a mistake is "✕ Mistake"; Real/Fake are words; the lit mistakes cell is also the dial's current stop, named above it.
- **Targets:** 44 pt on the iPhone (chips, stop marks, buttons), 36 pt on the Mac; a selection haptic on each guess, stop and "Check first".
- **Contrast:** only the theme's roles (each text role reads at 4.5:1 or better on the card). Measured on the 16 Pro Max shot: "Mistake" in its well 10.2:1, "Shared" on the card 8.7:1.

---

## 8. DEBUG arguments for review and shots

| Argument | Effect |
|---|---|
| `-Interactive doubt-dial` | Lesson 6.4 with stub replies (they say they are stubs) and the card through the real placement, even while it ships dark |
| `-InteractiveGallery doubt-dial` | The card alone |
| `-InteractiveState hook\|predicted\|explored\|revealed\|spoiled` | Opens the card in that state |
| `-DoubtDialGuess believe\|middle\|doubt` | The guess those states lock (default: doubt), and the stop they show (its end, or In the middle; `revealed` shows where "Show me" leaves the dial on the real path) |
| `-DoubtDialCheckFirst YES` | "Check first" showing (with `revealed`) |
| `-DoubtDialScrollFeed YES` | Moves the card's scroll mark from the reveal to the feed's heading, so `-InteractiveScroll reveal` brings the feed (the Mac's column headers) to the top |
| `-InteractiveScroll top\|reveal\|after` | Scrolls the card's top, reveal or end into view in the lesson |
| `INTERACTIVE_SCROLL=top\|reveal\|after` (Mac shot script) | The same, for `scripts/mac-snapshots.sh interactive-doubt-dial` (the first `-InteractiveScroll` on a launch wins, so it can't go in `INTERACTIVE_ARGS`) |

---

## 9. Verification (2026-10-22, after the review)

- **`swift test`** (ios/Packages): 1,316 tests pass, 29 of them this card's. New since the review: the reveal moves the dial to the setting it names (the real path: lock Doubt everything, turn to 1 and 2, Show me → stop 4 and counters 0 and 5; Believe everything → 0; a middle guess stays on its middle stop, or goes to In the middle from an end; spoiled → 4); the two ends tie (5 = 5) and the middle beats them; every cut-off limit from 0 to 5 makes 5, 4, 4, 4, 4, 5; every stop's dial value, mistakes line, strip line and Mac headers pinned word for word; the strip's cut and its words; checking's three groups (4, 2, 4; sum 10; matching the counters; the seal in Not sure yet); 8 settled of 10. ArchitectureTests and every other card's tests pass unchanged.
- **CI lint:** `ios/scripts/ci-compat-lint.py` finds 0 issues.
- **iOS** (iPhone 16 Pro Max simulator, iOS 26.4; snapshot recording forced off): the app builds; 8 of 8 app unit tests pass, including `DoubtDialCardLayoutTests` (the whole card at 343 and 408 pt, at Large, xxxLarge, AX3 and AX5, in six states: nothing lands outside the card). `DoubtDialUITests` passes at Large and at AX5 (the simulator's text size set to AX5): guess Doubt everything; turn the dial two stops (its stop marks at Large, its "More doubt" button at AX5); the strip names In the middle's four mistakes; Show me pairs the guess with the result, and the dial then reads "Doubt everything. You’d share 0 fakes and wave away 5 real stories."; Check first shows 0, 0 and 2; and the lesson's check below the card still answers with one tap. It scrolls with drags that don't fling, so it reaches the check at AX5 too, and keeps a screenshot at each step. The rest of the UI suite wasn't re-run: nothing outside this card changed.
- **Snapshots:** `ios-unchanged-check.sh` (run with this card's simulator and derived data) gives the same 23 results as the baseline (11 pass, 12 already stale), with the same pixels for every stale render. No record run.
- **Mac:** the Debug build succeeds. Shots through a renamed copy (`com.mayoailiteracy.mercurius.native.macnsia2`, `N=ia2`), each quit by its own PID; the founder's running app was untouched (the script's "running before, is gone" lines are other agents' copies that quit on their own).
- **Contrast** (measured on the shots): the strip's letters 8.5:1 (shared, iPhone), 8.3:1 (waved away, iPhone), 12.4:1 and 7.7:1 (Mac light), 8.5:1 and 8.4:1 (Mac dark); its key 8.7 to 9.4:1.

**Shots** (in `shots/`, not committed; the pre-review set is in `shots/before-review/`):
- iPhone 16 Pro Max, light and dark at Large: `16pm-light-gallery-middle` and `16pm-dark-gallery-middle` (the card alone at In the middle: the strip with its cut and four ringed mistakes right under the dial, then the counters); in the lesson, `-lesson-reveal` (Doubt everything: the reveal, and the feed below it all "Waved away" with five "Mistake" marks, agreeing with it), `-lesson-reveal-middle` ("You’re right"), `-lesson-checked` (checking's three counters and "Checking sorted 8 of 10…"), `-lesson-checked-feed` (every post's "What checking found" line, the two "Not sure yet" verdicts, the lighthouse's two sources), `-lesson-feed-middle` (the feed at In the middle with its four "Mistake" posts).
- iPhone 16 Pro Max at AX3 and AX5: `16pm-ax3-lesson-middle`, `16pm-ax5-lesson-{explored,reveal,checked,checked-feed}`; the dial's two step buttons, the counters and the strip's line of words at AX5 come from the UI test's kept screenshots: `16pm-ax5-uitest-{1-turned,2-strip-words,3-revealed,4-revealed-dial,5-checked}` (after Show me the dial reads Doubt everything, "More doubt" is dimmed at the end, and the counters read 0 and 5).
- iPhone SE width (343 pt), from the layout test: `render-se-large-explored`, `render-se-xxxLarge-{middle,checked}` (the strip at its narrowest: 10 cells of about 22 pt, every letter whole), `render-se-accessibility3-explored` (the strip as its line of words), `render-se-accessibility5-hook`.
- Mac at 1280 × 800 and 700 × 600, light and dark (taken before the last two motion-only changes, the strip's glyph crossfade and the two-beat Show me, which change no still picture): `mac-middle-gallery*` (the strip under the dial), `mac-revealed-gallery-tall` (1280 × 880: after Show me the dial sits at Doubt everything, the lit 5, the strip all waved away, counters 0 and 5), `mac-reveal-lesson*` (the reveal beside a feed of Shared · 0 | Waved away · 10), `mac-checked-lesson-min*` (700 × 600: checking's counters and line), `mac-checked-feed-lesson*` (SHARED · 4 | NOT SURE YET · 2 over NOT SHARED · 4, at both sizes), `mac-middle-feed-lesson-min*` (700 × 600: the two columns at In the middle, with "Mistake" marks).
- The reveal on the real path: `16pm-reveal-clip.mov` (56 s, the UI test at Large, recorded: guess Doubt everything, two stops to In the middle, Show me; the dial turns to Doubt everything in place, then the reveal fades in; Check first; the lesson's check). Frames around Show me were checked one by one: no text draws over other text.

**Still to check on a real iPhone SE at AX5.** This card's agent may use only its own 16 Pro Max simulator, so the SE at AX5 is covered by the layout test at 343 pt (nothing leaves the card at any state) and by the 16 Pro Max at AX5 on the simulator; the tallest AX5 renders at 343 pt can't be saved (an `ImageRenderer` limit). A look on an SE at AX5 remains on the teacher checklist (§11).

**Polish after looking at the shots and the clip:** the strip's ✕ marks sit on one line (one height for ↗ and ⊘); Show me now runs in two beats (the dial turns in place, then the reveal fades in about 0.7 s later, once the dial has settled; "Show me" leaves with a quick fade in place), because doing both at once, or the second before the first had settled, moved the layout while the dial’s words were still changing; the strip's glyphs crossfade in place instead of being swapped, because a swapped glyph overlapped its letter for a frame while the card moved.

**Before the review** (2026-10-21): 1,310 SPM tests, the same unit, UI and snapshot runs; the polish then was the feed's "✕ Mistake" marks and counter tiles of one height.

## 10. Open questions (for the framework, not this card)

- **Resolved in the wave-1 merge (2026-10-22):** a locked chip is no longer a disabled button (`isLocked`), so the pick keeps white on `prominent` and the others read in `ink2`, 4.5:1 or better on both platforms. The note as written before the merge: **The chips after the guess is locked are under 4.5:1.** The picked chip reads at 4.18:1 (white words dimmed by `.disabled` on the shared `InteractiveChip`, measured on the 16 Pro Max shot); the unpicked chips dim to 2.56:1. WCAG 1.4.3 exempts inactive controls, and the guess is printed again in the reveal ("You guessed …"), but the project's rule is 4.5:1 for text. A fix belongs in `InteractiveControls.swift` (don't dim the picked chip; dim the unpicked ones only as far as 4.5:1), so every card gets it; it is left out of this card's branch because the shared controls are the framework's, and every card branch would otherwise carry its own copy of the change.
- **A chip reaches XCUITest as a button inside a button** with the same label (`InteractiveChip` puts `.accessibilityElement(children: .ignore)` and the button trait over a SwiftUI `Button`). This card's UI test takes the first match. Worth a VoiceOver pass on a device to confirm VoiceOver stops on each chip once.
- **At the accessibility sizes the dial's "Less doubt" and "More doubt" buttons sit inside the dial's one adjustable element** (`StopControl` ignores its children for VoiceOver). VoiceOver users swipe up and down on the dial, which works; but Voice Control ("Tap More doubt") and XCUITest can't name the buttons, so this card's UI test touches "More doubt" where it is drawn. Worth deciding in `StopControl.swift` whether the buttons should also be their own elements at those sizes.

---

## 11. For teacher review

Please tick each, or note a change. Sign-off is recorded below with a date; only then may the card be enabled (with the founder's OK).

**The aha**
- [ ] Without the tutor's help, in about 75 s, a student comes away with: no amount of doubt sorts real from fake; doubting everything waves away every real story, as bad as believing everything; checking does better, and may say "not sure yet".
- [ ] The guess ("Which setting will fool you least?") is one a student holding "doubting everything is safe" gets wrong, and the reveal ("… 5 mistakes, the same as believing everything. That’s just what someone caught in a real story would want: everyone calling it fake.") lands without naming the liar's dividend.
- [ ] A student who guessed "Somewhere in the middle" is told they were right ("You’re right: the middle fooled you least"), and still sees the floor of 4.
- [ ] After "Show me" the dial sits at the guessed setting, and the counters, the strip and the feed agree with the sentence.
- [ ] Turning the dial is fun enough: the strip's cut moves and posts flip right under the dial.
- [ ] The tutor's next reply, which names the liar's dividend, follows naturally from the card.

**Accuracy and labels**
- [ ] "A made-up feed. Real feeds aren’t half fake. The dial judges only by how surprising a post looks." is visible and understood: the half-fake mix and the 4-mistakes floor are facts about this feed, not about real feeds (C7, accuracy notes).
- [ ] "These checks are made up too, like the feed. Real checking is messier." under Check first.
- [ ] Checking's "not sure yet" is visibly its own answer (its own counter; its own group on the Mac), so "0 real stories waved away" doesn't hide the seal.
- [ ] No post reads as real news about a real place (Port Avery searched, §5).
- [ ] The "Check first" lines are fair examples of finding better coverage and tracing to the original (C4), and two "not sure yet" posts keep checking honest (C6).
- [ ] The shark photo's "A real photo, a false story." fits the reply's cheapfake vs. deepfake point (C5).
- [ ] The leaked audio stays a line of text about an unnamed, fictional mayor; nothing recalls the Biden robocall.

**Language (ages 13–18)**
- [ ] "Waved away", "Believe most", "In the middle" and "Doubt most" read naturally. (Alternatives: "Ignored", "Dismissed"; "Half and half" for the centre stop.)
- [ ] "Moving within the middle only swapped one kind of mistake for the other." is clear.
- [ ] The strip's "R" and "F" with its key read easily.
- [ ] "✕ Mistake" beside a post the setting gets wrong reads as feedback on the dial's setting, not on the student.
- [ ] Nothing reads as live AI or as Mercurius's own output.

**Fit with the lesson**
- [ ] The card's place, after the first reply's example part and before its check, is right.
- [ ] Exercise clash: doing the exercise (a real clip and a fake clip about one event) right after the card, the card hasn't answered it.

**Ethics for minors**
- [ ] No real faces, voices, people or brands; no graphic content; no dark patterns (no timer, no score, no "wrong!").

**Accessibility**
- [ ] A VoiceOver-only pass matches §6.
- [ ] AX5 on an iPhone SE: every word is there, nothing scrolls sideways (checked here by the layout test at 343 pt and on a 16 Pro Max at AX5; see §9 for what still needs an SE).
- [ ] Keyboard only on the Mac (§4), and A–D still answer the check with the card on screen.
- [ ] Reduce Motion: crossfades only. Increase Contrast: solid, readable.

**Sign-off:** _not yet signed_ (reviewer, date).
