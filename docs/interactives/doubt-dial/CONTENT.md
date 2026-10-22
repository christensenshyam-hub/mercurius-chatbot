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
**Screenshots:** `docs/interactives/doubt-dial/shots/` (kept out of git; see §9).

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
| Label (on the canvas) | A made-up feed. Here the dial judges by how surprising a post looks. Real checking is messier. |

### 1 · The guess (before anything else works)

| Where | Text |
|---|---|
| Question (a header) | Which setting will fool you least? |
| Chips | Believe everything / Somewhere in the middle / Doubt everything |

One tap locks the guess; it can't be changed. The picked chip keeps a check mark, and the others dim (still readable).

### 2 · The dial (the one control)

| Where | Text |
|---|---|
| Caption | How much doubt? |
| The stop, as a heading | Believe everything / Believe most / Unsure / Doubt most / Doubt everything |
| Under the track | Believe everything … Doubt everything (its two ends) |
| Before the guess (VoiceOver) | Make your guess first. |
| After the guess, before "Show me" | Turn the dial and watch both counters. |
| The stop's rule | Shares every post. / Shares posts with up to **4** dots. Waves away the rest. / Shares posts with up to **3** dots. Waves away the rest. / Shares only posts with **1** dot. Waves away the rest. / Waves away every post. |
| Counter 1 | Fakes you’d share: **n** |
| Counter 2 | Real stories you’d wave away: **n** |
| Under the counters | **4** mistakes out of **10** at this setting. |
| Button, after two settings | Show me |

The dial starts at Believe everything once the guess is locked, so turning it adds doubt. "Show me" appears after two moves (`DoubtDialState.showMeAfter`).

### 3 · The reveal (the guess beside the result; never a score)

| The guess | YOU GUESSED | WHAT HAPPENED |
|---|---|---|
| Believe everything | Believe everything | It shared all **5** fakes, and waved away no real stories. No setting got below **4** mistakes out of **10**. |
| Somewhere in the middle | Somewhere in the middle | Every setting in the middle still made **4** mistakes out of **10**. Turning the dial only moved your mistakes around. |
| Doubt everything | Doubt everything | It shared no fakes, and waved away all **5** real stories. That’s exactly what someone hiding a real story would want. |
| (spoiled mode: no guess) | — | No setting got below **4** mistakes out of **10**. Doubt everything shared no fakes, and waved away all **5** real stories. |

Once revealed, a row appears under the dial's stops: **Mistakes out of 10 at each setting**, with **5 · 4 · 4 · 4 · 5** under the five stops (the current one lit). This is the aha in one picture: no amount of doubt gets below 4.

### 4 · Check first (the move that works)

| Where | Text |
|---|---|
| Intro | The dial only looks at how surprising a post seems. Checking looks at where it came from, and who else reports it. |
| Button | Check first |
| After it: three counters | Fakes shared: **0** · Real stories waved away: **0** · Not sure yet: **2** |
| Takeaway | Doubt alone can’t sort them. Checking can, and “not sure yet” is an honest answer. |
| Label (on the canvas) | These checks are made up too, like the feed. |
| Button | Back to the dial (turning the dial leaves "Check first" too) |

The dial's own counters stay where they are, so the student sees the dial's mistakes and checking's side by side.

### 5 · The feed (least surprising first)

Heading **The feed**, caption **Least surprising first.** Each post shows its title, its surprise dots, **Real** or **Fake** (we wrote them, so we know), and once the guess is locked a glyph and a word: **Shared** (↗) or **Waved away** (⊘); under "Check first", **Shared**, **Not shared** (⊘) or **Not sure yet** (…), with what checking found under the title.

A post the setting gets wrong (a fake **Shared**, a real story **Waved away**) also carries **✕ Mistake** in a small well beside its verdict, so the feed shows the counters' posts one by one: at Unsure, the school board and the water tower (fakes shared) and the seal and the bridge (real stories waved away). "Not sure yet" is never marked: it is an honest answer, not a mistake. After "Check first" nothing is marked.

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
| 10 | Video: lightning knocks out the lighthouse | Fake | 5 | The harbor’s live camera shows the lighthouse lit tonight. | Not shared |

The "leaked audio" and the "video" are one line of text each: nothing is played or shown. The mayor has no name.

### The Mac

The same lines, in the same order, drawn in Night Studio. The feed sits in two columns that crossfade as the dial turns:

| Where | Text |
|---|---|
| Before the guess | The feed in two halves, no verdicts |
| Column headers (dial) | SHARED · **n** / WAVED AWAY · **n** |
| Column headers (Check first) | SHARED · **4** / NOT SHARED · **6** |
| An empty column | No posts at this setting. |
| Compact card (narrower than 440 pt) | INTERACTIVE · The Doubt Dial · "Turn a dial from believing everything to doubting everything, and count the mistakes in a made-up feed." · Try it |

The counters glow in lumen (not under Increase Contrast or Reduce Transparency).

### The iPhone at the accessibility sizes (AX1 to AX5)

Decoration goes, never a word: the eyebrow's icon, the dots and the glyphs go; each post becomes its title over a line of words ("Real · surprise 4 of 5 · Waved away · Mistake"); the dial becomes two buttons, **Less doubt** and **More doubt**, under its stop's name; the counters and the mistakes row become text tables. The counters stay above the feed.

---

## 2. Every number, and how it is counted

All of these are toy data (the made-up feed) or arithmetic over it. `DoubtDialTests` re-derives each by counting the posts directly, holds it to the slate's table, and checks that every number in every line the card can show is one of them ("Every number any line shows is one the content counts").

| Number | Where | How it is counted |
|---|---|---|
| Ten (10), 5, 5 | Hook, VoiceOver | `posts.count` (spelled out where it starts a sentence); real posts; fake posts |
| 1 to 5 | Dots line, each post | Authored surprise scores: real 1, 2, 3, 4, 5; fake 2, 3, 4, 5, 5 (slate.json) |
| 4, 3, 1 dots | The stop's rule | The stops' limits, 5, 4, 3, 1, 0 (slate.json): a post is shared when its surprise is at most the limit |
| Counters at each stop | Counters, VoiceOver | Fakes with surprise ≤ limit; real posts with surprise > limit (table below) |
| 5, 4, 4, 4, 5 | Mistakes row, reveal | The two counters added at each stop |
| 4 (fewest) | Reveal ("No setting got below 4") | The smallest of the row |
| 4 (middle) | Reveal ("Every setting in the middle still made 4") | Believe most, Unsure and Doubt most all make 4 (the test checks they are equal) |
| 0, 0, 2 | Check first | Fakes that checking shares (0); real posts it waves away or doesn't share (0); posts it leaves not sure yet (2: the water tower, fake, and the seal, real) |
| Posts marked "Mistake" | The feed | At each stop, exactly the posts the two counters count (fakes with surprise ≤ limit, real posts with surprise > limit), so their number is the mistakes row's: 5, 4, 4, 4, 5; none after checking (a test) |
| Column counts (Mac) | Column headers | Shared at each stop: 10, 7, 5, 1, 0 (so waved away 0, 3, 5, 9, 10); after checking 4 shared, 6 not |
| $1 | Post 2's title | Made-up content of the made-up feed (the only number inside a post; the test holds it there) |

| Dial stop | Limit | Fakes you'd share | Real stories you'd wave away | Mistakes out of 10 |
|---|---|---|---|---|
| Believe everything | 5 | 5 | 0 | 5 |
| Believe most | 4 | 3 | 1 | 4 |
| Unsure | 3 | 2 | 2 | 4 |
| Doubt most | 1 | 0 | 4 | 4 |
| Doubt everything | 0 | 0 | 5 | 5 |

The slate's own cross-check, `tools/check_slate_numbers.py` (U6L4 section, in the `interactives-shared` worktree), gives the same table and "at least 4 mistakes" at every stop.

---

## 3. Every claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | Doubt alone can't sort real from fake: at every setting of a dial that judges by how surprising a post looks, there are at least 4 mistakes out of 10. | True of the card's made-up feed (§2), and labelled as such on the canvas ("A made-up feed. Here the dial judges by how surprising a post looks. Real checking is messier."). The feed is built so surprise doesn't track truth: every surprise level from 2 to 5 holds a real post and a fake (a test). It doesn't claim real feeds have these numbers. | Toy data; design from SLATE.md card 1 and RESEARCH.md M13. |
| C2 | Doubting everything isn't the safe default: it shares no fakes, and waves away every real story. Both count as mistakes. | The card scores both kinds of mistake on purpose. | Design rationale, not shown: Modirrousta-Galian & Higham 2023 (*J. Exp. Psychol.: General* 152(9), 2411–2437; status **secondary**: the PubMed and Southampton pages refused an automated read on 2026-10-21, so this rests on their indexed summaries and RESEARCH.md): a signal-detection reanalysis found gamified inoculation (Bad News, Go Viral!) made players answer "false" to more news of every kind, without telling true from fake any better. <https://pubmed.ncbi.nlm.nih.gov/36996156/> · <https://eprints.soton.ac.uk/475360> |
| C3 | "That’s exactly what someone hiding a real story would want." | The payoff of blanket doubt to someone hiding the truth, without naming or defining the term. The tutor's next reply names the liar's dividend and attributes it. Chesney and Citron's own point, as summaries report it (status **secondary**: the article itself not read here), is that the more the public is taught that anything could be fake, the more believable a liar's denial of real evidence becomes. | Guide U6L4 Teach line and Common mistake ("Swinging to ‘everything is fake.’ That IS the liar’s dividend working on you."); fact-check row 50: Chesney & Citron, 107 Calif. L. Rev. 1753 (2019), status High. <https://law.utexas.edu/faculty/publications/2019-deep-fakes-a-looming-challenge-for-privacy-democracy-and-national-security/> |
| C4 | Checking looks at where a post came from, and who else reports it. | The two SIFT moves the "Check first" lines use: find better coverage (the ferry company and the Gazette both report it) and trace claims, quotes and media to the original context (the reverse image search; the old speech). Status **read** (2026-10-21) for the moves. The post itself doesn't name reverse image search; library guides built on Caulfield's materials teach finding an image's history (where it was first used, and whether it was taken out of context) under "Trace" (status **secondary**). | Mike Caulfield, "SIFT (The Four Moves)", 2019-06-19. <https://hapgood.us/2019/06/19/sift-the-four-moves/> · e.g. Paradise Valley Community College library, SIFT: Trace ("Finding the History of Images", crediting Caulfield). <https://paradisevalley.libguides.com/sift/trace> |
| C5 | "A real photo, a false story." (the shark photo) | A cheapfake: real media given a false context. It ties to the first reply's cheapfake vs. deepfake distinction without using either word. | Guide U6L4 Teach line ("the cheapfake vs. deepfake distinction"). |
| C6 | "Not sure yet" is an honest answer; checking doesn't settle everything. | Two of ten posts stay not sure yet (one real, one fake), so the card doesn't promise that checking always resolves a claim. | Design (SLATE.md accuracy notes); RESEARCH.md §4: "treat ‘I’d check’ as a valid answer". |

**What the card does NOT say, on purpose:**
- the term "liar's dividend" (a test checks no line says "liar" or "dividend"), or that doubting is the liar's dividend;
- that surprising means fake (some real posts are very surprising; some fakes are plain);
- that checking always settles a claim;
- anything about the Biden robocall, Steve Kramer or any real person or event (they stay in the tutor's text, never simulated);
- any statistic about real misinformation;
- that the "how surprising" scores or the checks come from a model: they are authored, and labelled made up.

**Exercise clash (medium-low).** The lesson's exercise is a real clip and a fake clip about the same event. The card uses neither: no clips, no one event, and its checking moves are general.

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
| The counters (one element) | Fakes you’d share: 3. Real stories you’d wave away: 1. |
| Show me (a button) | Show me. Hint: Shows what happened, beside your guess |
| Announced on Show me; the reveal (one element) | You guessed Doubt everything. It shared no fakes, and waved away all 5 real stories. That’s exactly what someone hiding a real story would want. |
| The mistakes row (one element) | Mistakes out of 10 at each setting. Believe everything: 5 mistakes. Believe most: 4 mistakes. Unsure: 4 mistakes. Doubt most: 4 mistakes. Doubt everything: 5 mistakes. |
| Check first (a button) | Check first. Hint: Shows what checking found for each post |
| Announced on Check first | Check first: 0 fakes shared, 0 real stories waved away, 2 not sure yet. Doubt alone can’t sort them. Checking can, and “not sure yet” is an honest answer. |
| Checking's counters (one element) | Fakes shared: 0. Real stories waved away: 0. Not sure yet: 2. |
| The feed's heading (a header) | The feed |
| Each post (one element, ending in its state) | A seal naps on the ferry dock, and the ferry waits. Real. Surprise 4 of 5. Waved away. A mistake. (A post the setting gets right ends at its verdict: "… Shared.") |
| Each post under Check first | … Real. Surprise 4 of 5. Not sure yet, so don’t share yet. What checking found: One video, posted an hour ago. No one else has it yet. |
| Mac column headers (headers) | Shared: 7 posts / Waved away: 3 posts |
| Back to the dial (announced) | The dial's line at its stop |

The dial's own moves aren't announced: VoiceOver reads an adjustable control's new value itself.

---

## 7. Accessibility and motion

- **Dynamic Type to AX5 on an iPhone SE:** §1's accessibility sizes. Nothing scrolls sideways; checked in the AX5 SE shot.
- **Reduce Motion:** every change crossfades in place (`theme.animation`, `InteractiveMotion`); nothing slides or flips, nothing plays by itself. On the Mac, posts crossfade between columns either way.
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
| `-DoubtDialGuess believe\|middle\|doubt` | The guess those states lock (default: doubt), and the stop they show (its end, or Unsure) |
| `-DoubtDialCheckFirst YES` | "Check first" showing (with `revealed`) |
| `-InteractiveScroll top\|reveal\|after` | Scrolls the card's top, reveal or end into view in the lesson |

---

## 9. Verification (2026-10-21)

- **`swift test`** (ios/Packages): 1,310 tests pass, 23 of them this card's (`DoubtDialTests`: every number re-derived by counting the posts, the posts marked "Mistake" at every stop, the register, VoiceOver lines, the state machine, the DEBUG states). ArchitectureTests and Lesson 1.1's tests pass unchanged.
- **CI lint:** `ios/scripts/ci-compat-lint.py` finds 0 issues.
- **iOS build and `xcodebuild test`** on an iPhone 16 Pro Max simulator (iOS 26.4), snapshot recording forced off and the snapshot suite run separately: 8 of 8 app unit tests pass, including `DoubtDialCardLayoutTests` (the whole card at 343 and 408 pt, at Large, xxxLarge, AX3 and AX5, in six states: nothing lands outside the card). In the full run 34 of 35 UI tests passed; the 35th, `DoubtDialUITests`, failed on its first query because a prediction chip reaches XCUITest as a button inside a button with the same label. With first-match queries it passes (guess, two stops, Show me, Check first, then the lesson's check still answers by one tap), run alone.
- **Snapshots:** `ios-unchanged-check.sh` gives the same 23 results as the baseline (11 pass, 12 already stale), with the same pixels for every stale render. No record run.
- **Mac:** the Debug build succeeds. Shots through a renamed copy (`com.mayoailiteracy.mercurius.native.macnsia2`, `N=ia2`), quit by its own PID; the founder's running app was untouched.

**Shots** (in `shots/`, not committed):
- iPhone 16 Pro Max, light and dark at Large: `16pm-{light,dark}-*` (the card alone at Unsure; in the lesson: its top, the feed at Unsure with its four "Mistake" posts, the reveal, Check first).
- iPhone 16 Pro Max at AX3: `16pm-ax3-*`.
- iPhone SE at AX5: `se-ax5-*`, plus `render-se-ax5-hook.png` (the whole card at 343 pt from the layout test: one column, the dial as two buttons, every word kept).
- Mac at 1280 × 800 and 700 × 600, light and dark: `mac-hook-lesson*`, `mac-middle-lesson*` (Shared | Waved away, with "Mistake" marks), `mac-middle-gallery*`, `mac-revealed-gallery*`.
- The reveal, 7.8 s: `16pm-reveal-clip.mov` (the dial from Believe everything to Unsure, Show me, the guess beside the result).

**The dial at AX5 on a device.** The layout test's AX5 renders of the longer states draw the two step buttons squeezed, and the tallest ones aren't saved at all: an `ImageRenderer` limit on very tall images (the hook and spoiled renders, which are shorter, draw them right). Run on the simulator at AX5 (the UI test, recorded), both buttons are full capsules of 44 pt or more with their words inside.

**Polish made after looking at the shots:** the feed now marks each post the setting gets wrong with "✕ Mistake" (a word in a small well; VoiceOver adds "A mistake."), so the two counters can be traced post by post; the verdict drops to its own line when a narrow Mac column or a large text size has no room. The counter tiles now share one height when a label wraps.

## 10. Open questions (for the framework, not this card)

- **The picked chip after the guess is locked reads at 4.2:1** (white words dimmed by `.disabled` on the shared `InteractiveChip`, measured on the 16 Pro Max shot), under the 4.5:1 rule; the unpicked chips dim to 2.6:1 (inactive controls, which WCAG exempts). The guess is also printed in the reveal ("You guessed …"). A fix belongs in `InteractiveControls.swift` (don't dim the picked chip), so every card gets it.
- **A chip reaches XCUITest as a button inside a button** with the same label (`InteractiveChip` puts `.accessibilityElement(children: .ignore)` and the button trait over a SwiftUI `Button`). This card's UI test takes the first match. Worth a VoiceOver pass on a device to confirm VoiceOver stops on each chip once.

---

## 11. For teacher review

Please tick each, or note a change. Sign-off is recorded below with a date; only then may the card be enabled (with the founder's OK).

**The aha**
- [ ] Without the tutor's help, in about 75 s, a student comes away with: no amount of doubt sorts real from fake; doubting everything waves away every real story; checking is what works.
- [ ] The guess ("Which setting will fool you least?") is one a student holding "doubting everything is safe" gets wrong, and the reveal ("That’s exactly what someone hiding a real story would want.") lands without naming the liar's dividend.
- [ ] The tutor's next reply, which names the liar's dividend, follows naturally from the card.

**Accuracy and labels**
- [ ] "A made-up feed. Here the dial judges by how surprising a post looks. Real checking is messier." is visible and understood: the 4-mistakes floor is a fact about this feed, not about real feeds.
- [ ] No post reads as real news about a real place (Port Avery searched, §5).
- [ ] The "Check first" lines are fair examples of finding better coverage and tracing to the original (C4), and two "not sure yet" posts keep checking honest (C6).
- [ ] The shark photo's "A real photo, a false story." fits the reply's cheapfake vs. deepfake point (C5).
- [ ] The leaked audio stays a line of text about an unnamed, fictional mayor; nothing recalls the Biden robocall.

**Language (ages 13–18)**
- [ ] "Waved away", "Believe most", "Doubt most" and "Unsure" read naturally. (Alternatives: "Ignored", "Dismissed".)
- [ ] "Turning the dial only moved your mistakes around." is clear.
- [ ] "✕ Mistake" beside a post the setting gets wrong reads as feedback on the dial's setting, not on the student.
- [ ] Nothing reads as live AI or as Mercurius's own output.

**Fit with the lesson**
- [ ] The card's place, after the first reply's example part and before its check, is right.
- [ ] Exercise clash: doing the exercise (a real clip and a fake clip about one event) right after the card, the card hasn't answered it.

**Ethics for minors**
- [ ] No real faces, voices, people or brands; no graphic content; no dark patterns (no timer, no score, no "wrong!").

**Accessibility**
- [ ] A VoiceOver-only pass matches §6.
- [ ] AX5 on an iPhone SE: every word is there, nothing scrolls sideways.
- [ ] Keyboard only on the Mac (§4), and A–D still answer the check with the card on screen.
- [ ] Reduce Motion: crossfades only. Increase Contrast: solid, readable.

**Sign-off:** _not yet signed_ (reviewer, date).
