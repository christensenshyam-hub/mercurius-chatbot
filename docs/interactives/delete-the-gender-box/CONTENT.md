# "Delete the Gender Box": the content

**What this is:** every line a student sees or hears in Unit 3 Lesson 1's interactive on the iPhone and the Mac, every number it shows with its derivation, every factual claim with its source, its labels, and a checklist for the teacher who reviews it.
**Where it shows:** Unit 3, Lesson 1 ("AI in hiring and employment", `u3_l1`), the home lesson of the Amazon case. It is a card at the end of the part of Merc's first teach reply that holds its first [EX] example (the Amazon résumé scorer, in a normal run), before that reply's check (anchor `.firstExample`, no spoiler terms; SLATE.md ★4).
**Status:** built on both platforms, **ships dark** (`enabled: false` in `InteractiveRegistry.all`) until the teacher review below is signed off and the founder says OK. DEBUG builds show it with `-Interactive delete-the-gender-box` (in its lesson, with stub replies) or `-InteractiveGallery delete-the-gender-box` (alone).
**The code:** `ios/Packages/LessonInteractives/`
- `Sources/Blocks/ToyFit.swift`: the toy trainer (logistic regression, exact optimum by Newton's method).
- `Sources/Cards/GenderBox/GenderBoxContent.swift`: the 12 rows, the two fits, every number shown.
- `Sources/Cards/GenderBox/GenderBoxCopy.swift`: every line below (`everyLine`).
- `Sources/Cards/GenderBox/GenderBoxState.swift`: guess, gender box kept or deleted (memory only).
- `Sources/Cards/GenderBox/GenderBoxParts.swift`: the pieces both platforms draw; `Views/Phone/GenderBoxPhoneCard.swift`, `Views/Mac/NightGenderBoxCard.swift`.
- Tests: `Tests/GenderBoxTests.swift`, `Tests/ToyFitTests.swift`; on iOS, `ios/MercuriusTests/GenderBoxCardLayoutTests.swift` (the real views at an SE's and a 16 Pro Max's width, Large to AX5: nothing leaves the card) and the UI test `ios/MercuriusUITests/DeleteTheGenderBoxUITests.swift`.

The card is a picture the app draws. It sends nothing, stores nothing, calls no model and changes nothing in the prompt, the wire or the lesson. The toy scorer is fitted on the device from the 12 rows below, the same way every time.

---

## 1. Every line the student sees

Curly quotes and apostrophes are as drawn. Numbers in **bold** are computed from the rows (§2).

### The card

| Where | Text |
|---|---|
| Eyebrow | INTERACTIVE |
| Title | Delete the Gender Box |
| Hook (the audit role) | You’re checking a résumé scorer: a toy we built, not Amazon’s. It learned from **12** made-up past résumés and who got hired: **6** of **8** men, **1** of **4** women. |

### The 12 past résumés

| Where | Text |
|---|---|
| Heading | The **12** past résumés |
| Summary (under the heading at the accessibility sizes; read with the heading by VoiceOver at every size) | **8** men, **6** hired. **4** women, **1** hired. |
| Column heads | Gender box · Clubs · Hired? |
| Gender box cells | man / woman (struck through once the gender box is deleted) |
| Club lines | chess club captain · women’s chess club captain · women’s chess club · coding club · No clubs listed. The toy's words (*women’s*, *captain*, *coding*) are picked out in the accent colour and bold. |
| Outcome cells | ✓ Hired / ✕ Not hired (a glyph and a word) |

The rows, in order (gender box · clubs · outcome):

| # | Gender box | Clubs | Outcome |
|---|---|---|---|
| 1 | man | chess club captain, coding club | Hired |
| 2 | man | chess club captain | Hired |
| 3 | man | coding club | Hired |
| 4 | man | chess club captain, coding club | Hired |
| 5 | man | No clubs listed | Not hired |
| 6 | man | coding club | Hired |
| 7 | man | chess club captain | Not hired |
| 8 | man | No clubs listed | Hired |
| 9 | woman | women’s chess club captain, coding club | Not hired |
| 10 | woman | chess club captain, coding club | Hired |
| 11 | woman | women’s chess club, coding club | Not hired |
| 12 | woman | No clubs listed | Not hired |

### What it learned

| Where | Text |
|---|---|
| Heading | What it learned |
| Intro | It reads the gender box and three words. Each weight pushes a score up or down. |
| Rows, gender box kept | gender: woman · pushes down · **−1.04** / women’s · pushes down · **−1.21** / captain · pushes up a little · **+0.33** / coding · pushes up · **+1.12** |
| Rows, gender box deleted | gender: woman (struck through) · deleted / women’s · pushes down · **−1.53**, was **−1.21** / captain · pushes up a little · **+0.33** / coding · pushes up · **+1.01**, was **+1.12** |
| Under the bars | ← down · up → |
| Label (our arithmetic) | Weights and scores: our arithmetic, from fitting the toy to these **12** résumés. Real scorers learn from far more. |

Each row also has a bar about a zero line: left for "pushes down", right for "pushes up", its length the weight on one scale shared by both states (§2). Sign is shown by "+/−", the words and the bar's side, never by colour.

### Two new résumés

| Where | Text |
|---|---|
| Heading | Two new résumés |
| Intro | Both are women who code. One line is different. |
| First card | With “women’s” · Gender box: woman · women’s chess club captain · coding club · **34** (deleted: **42**) · out of 100 |
| Second card | Without it · Gender box: woman · chess club captain · coding club · **63** (deleted: **77**) · out of 100 |

### Predict, then the one control

| Where | Text |
|---|---|
| Prediction (a heading) | Delete the gender box and train the toy again. Will the résumé with “women’s” still score lower? |
| Chips | Yes, still lower · No, it’ll score higher · They’ll tie |
| The control | Gender box: **kept** · **deleted** |
| Under the control, until a guess is locked | Make your guess first. |

### The reveal (appears the first time the gender box is deleted)

| Where | Text |
|---|---|
| YOU GUESSED | the chip's words, e.g. They’ll tie (left out in the spoiled mode) |
| WHAT HAPPENED | Still lower: **42** vs **77**. With the gender box gone, “women’s” carried more of the weight (from **−1.21** to **−1.53**). |
| The honest nuance (small) | Both scores rose (**34** to **42**, and **63** to **77**), and the gap grew. |
| Takeaway | It learned from past decisions. Delete one column, and other words carry the same pattern. Reuters reported that Amazon’s scorer downgraded résumés containing “women’s” (2018). |
| Label (a toy, made up), at the card's foot | A toy we built from made-up résumés. Amazon’s real tool was never published, and this isn’t how it worked. |

Flipping back to "kept" puts the old weights and scores back; the reveal stays.

### The iPhone at the accessibility sizes (AX1 to AX5)

| Where | Text |
|---|---|
| The table's place | the summary line, then a button: Show all **12** (open: Hide the list) |
| Each résumé in the list | Résumé 9 · Gender box: woman · women’s chess club captain, coding club · Not hired |
| The weights, as rows of text | gender: woman / −1.04, pushes down … women’s / −1.53, pushes down (was −1.21) … gender: woman / deleted |
| The two new résumés | stacked, every word kept |
| Chips and the control | stacked, one under another |

Decoration that goes: the eyebrow's icon, the bars, the "Show all" chevron's icon, the label's info glyph. No word goes.

### The layout on each platform

- **iPhone:** stacked, as SLATE.md asks: the hook, the 12 past résumés, what it learned (each weight in one row: name and words, a bar about zero, the number), the two new résumés side by side, the guess, the control, the reveal, the label.
- **Mac (Night Studio):** from 500 pt of card content, the 12 past résumés sit left (58 % of the width, in whole points) and what it learned sits right; narrower, they stack. Each weight there is its name and number, a bar across the column on a shared track, then its words ("pushes down", "was −1.21"). **The two new résumés span both columns** under them, right above the guess and the control. This departs from SLATE.md's "weights and test résumés right": the lesson's reading column is about 540 pt, so a right column holding both gave each new résumé about 110 pt (its title and lines broke word by word) and squeezed the bars to slivers. The scores also read better next to the question they answer.
- **Both:** deleting the gender box strikes its column, its header, the "gender: woman" weight and each new résumé's "Gender box: woman" line. One-line cells get a line drawn across from the leading edge (a fade under Reduce Motion); lines that can wrap use the text's own strike-through, so every line is struck.

### The compact card (Mac only: when the card is narrower than 440 pt)

The lesson's reading column is wider than that even in the smallest window (700 × 600), so a student meets it only in a narrower layout; `-InteractiveCompact YES` shows it for review.

| Where | Text |
|---|---|
| Title | Delete the Gender Box |
| Line | A toy résumé scorer: delete its gender box, and see what “women’s” does. |
| Button | Try it |

### Hover help (Mac only)

| Control | Help |
|---|---|
| kept | Puts the gender box back, as the toy first learned |
| deleted | Deletes the gender box and fits the toy again on the same résumés |
| Try it | Opens the interactive here, in the lesson |

### What VoiceOver says (the walk-through script)

| Element | Spoken |
|---|---|
| The title (a header; its value is the card's state) | Interactive: Delete the Gender Box. Gender box kept. The new résumé with women’s scores 34; the one without scores 63. Guess what deleting the gender box does. |
| After the reveal | … Gender box deleted. The new résumé with women’s scores 42; the one without scores 77. Women’s now weighs minus 1.53; it was minus 1.21. |
| Hook | (as drawn) |
| Each heading (header) | The 12 past résumés: 8 men, 6 hired. 4 women, 1 hired. / What it learned / Two new résumés / the prediction |
| Summary (accessibility sizes, where it is drawn) | 8 men, 6 hired. 4 women, 1 hired. |
| Each résumé (one element, browsable) | Résumé 9, gender box: woman. Women’s chess club captain, coding club. Not hired. — after deleting: Résumé 9, gender box deleted (it said woman). … |
| Each weight (one element) | women’s: minus 1.21, pushes the score down. — after deleting: women’s: minus 1.53, pushes the score down. It was minus 1.21. / gender: woman: deleted. The toy no longer reads it. |
| Each new résumé | New résumé with women’s: gender box: woman, women’s chess club captain, coding club. Score: 34 out of 100. |
| Each chip (a button; "selected" once picked) | They’ll tie. Hint: Locks in your guess. It can’t be changed after. Value once locked: Your guess, locked in |
| The control (two buttons) | Gender box: kept / Gender box: deleted. Before a guess: dimmed, value "Make your guess first." After: the hint (as the hover help above). |
| Announced the first time the box is deleted | You guessed They’ll tie. Still lower: 42 vs 77. With the gender box gone, “women’s” carried more of the weight (from −1.21 to −1.53). Both scores rose (34 to 42, and 63 to 77), and the gap grew. |
| Announced on later flips | Gender box kept. Weights: gender: woman minus 1.04, women’s minus 1.21, captain plus 0.33, coding plus 1.12. Women’s chess club captain: 34. Chess club captain: 63. — or — Gender box deleted. Weights: women’s minus 1.53, captain plus 0.33, coding plus 1.01. Women’s chess club captain: 42. Chess club captain: 77. Still lower. |
| The reveal (one element) | You guessed They’ll tie. Still lower: 42 vs 77. … |
| Show all 12 (AX sizes) | Show all 12. Hint: Shows each past résumé as text |

---

## 2. Every number, and where it comes from

Every number on the card is computed by the app from the 12 rows (`GenderBoxContent`), and `GenderBoxTests` re-derives each one and holds it to the slate's. `tools/check_slate_numbers.py` (in the slate's folder) runs the same fit in Python and prints the same values (re-run 2026-10-21, all checks "ok").

**The data** (SLATE.md, labelled made-up): 12 rows of (woman, women’s, captain, coding → hired), as in §1's table. The toy reads four things: the gender box (woman = 1) and whether the résumé contains the words "women’s", "captain" and "coding".

**The fit** (the convention is recorded because other conventions give other numbers): logistic regression; loss = summed log-loss + ½·λ·‖w‖² with λ = 0.5; the intercept is not penalised; solved to the exact optimum by Newton's method (steps until no coordinate moves by 1e-12; the gradient there is below 1e-9, tested). Score = 100 × σ(b + w·x), rounded to a whole number.

| Shown | Value | Derivation |
|---|---|---|
| 12 past résumés | 12 | the rows |
| 6 of 8 men, 1 of 4 women hired | 6/8, 1/4 | counted from the rows (woman = 0 / 1, hired = 1) |
| Weights, gender box kept | woman −1.04, women’s −1.21, captain +0.33, coding +1.12 | the fit on all four columns: b = +0.1173, w = (−1.0368, −1.2084, +0.3253, +1.1227), shown to 2 decimals |
| Weights, gender box deleted | women’s −1.53, captain +0.33, coding +1.01 | the fit again without the gender column: b = −0.1268, w = (−1.5308, +0.3292, +1.0117) |
| Scores, kept | 34 vs 63 | 100·σ(b + w·x) for (woman, women’s, captain, coding) = (1,1,1,1) and (1,0,1,1): 33.63 and 62.91, rounded |
| Scores, deleted | 42 vs 77 | the same for (women’s, captain, coding) = (1,1,1) and (0,1,1): 42.15 and 77.10, rounded |
| "Still lower" | 42 < 77 | from the deleted scores |
| "the gap grew" | 29 → 35 points | 63 − 34 and 77 − 42 (from the rounded scores shown; the card says "grew", not the numbers) |
| "Both scores rose" | 34 → 42, 63 → 77 | the two pairs above |
| "was −1.21", "was +1.12" | | the kept fit's weight, shown only where the deleted fit's rounded weight differs (captain stays +0.33, so it has no "was") |
| "pushes … a little" | below 0.5 in size | a wording rule (`GenderBoxContent.aLittleBelow`), so captain's +0.33 reads "pushes up a little" |
| The bars' scale | 1.6 at full length | the largest weight either fit shows (1.53), rounded up to a tenth, so both states share one scale and "women’s" visibly grows |
| (2018) | 2018 | Reuters' report (claim C1) |

---

## 3. Every factual claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | "Reuters reported that Amazon’s scorer downgraded résumés containing “women’s” (2018)." | True; in the guide (U3L1 key examples) and the fact-check (row 24, High). | Reuters, Jeffrey Dastin, 2018-10-10 ([Euronews reprint](https://www.euronews.com/2018/10/10/amazon-scraps-secret-ai-recruiting-tool-that-showed-bias-against-women)); guide U3L1; `fix-prompts-2026-10/docs/prompt-batch/curriculum-factcheck.md` row 24. |
| C2 | "Amazon’s real tool was never published, and this isn’t how it worked." | True as worded: it was an experimental internal project; Reuters' account came from five people familiar with the effort, and Amazon declined to comment on the technology. Its model and data were never released. The card claims nothing about how it did work. | Reuters (above), re-read 2026-10-21 through the Euronews reprint (byline Jeffrey Dastin, Reuters): the headline calls it a "secret" recruiting tool. |
| C3 | The toy "learned from 12 made-up past résumés and who got hired"; "It learned from past decisions." | True of the toy (it is fitted to the hire column). True in kind of Amazon's: Reuters reports it was trained on résumés submitted over ten years, mostly men's (guide: "trained on ten years of mostly men's résumés"). The card doesn't give Amazon's numbers. | Guide U3L1; fact-check row 24. |
| C4 | "Delete one column, and other words carry the same pattern." With the gender box deleted, "women’s" carried more of the weight (−1.21 → −1.53). | True of the toy (a real fit, re-run by the tests): when a column goes, its weight moves onto a correlated word, because in these records "women’s" appears only on women's résumés. This is the proxy effect the lesson's misconception is about. | The fit (§2); design model: PAIR, *Hidden Bias* (Adam Pearce, 2020; <https://pair.withgoogle.com/explorables/hidden-bias/>): with gender hidden, a model with enough detail about each student rebuilds a stand-in for it and still scores women lower. |
| C5 | "Both scores rose … and the gap grew." | True of the toy (§2). Kept on purpose: deleting gender helped both women, so the card doesn't overclaim "deleting made it worse for everyone". | §2. |
| C6 | "Real scorers learn from far more." | True: Amazon's was trained on ten years of résumés (C3); real résumés hold many words, and many of them can carry the same pattern. | Guide U3L1. |

**Teacher note only (not in the guide, not on the card):** Reuters also reported that Amazon edited the program to make it neutral to such terms, with no guarantee it wouldn't find other ways to sort candidates. That is the whack-a-mole point; the tutor may mention it only if the guide adds it.

**What the card avoids saying, on purpose:**
- that the toy is how Amazon's tool worked (the label says it isn't), or any Amazon detail beyond the guide's (no schools, no numbers of résumés, no names). Reuters also reported that it downgraded graduates of two all-women's colleges; the guide leaves that out (CURRICULUM_MAP.md: "any further Reuters details … leave them out"), and so does the card;
- that deleting the gender box made things worse for every woman (both scores rose; the gap grew);
- that an algorithm is objective because it's maths (the card shows a real fit copying a skewed past);
- that gender has two values: the gender box is how the toy's made-up old records were kept, not a recommendation;
- a second proxy (the merged concept's invented school was judged contrived); real résumés hold many correlated words, which is for the teacher to add;
- anything about HireVue, the Illinois Act or NYC Local Law 144 (they stay in the tutor's text);
- vendor questions: the lesson's exercise asks for them, so the card writes none (exercise clash: low).

---

## 4. Labels on the canvas

| Kind | Text | Where |
|---|---|---|
| A toy, made up | You’re checking a résumé scorer: a toy we built, not Amazon’s. It learned from 12 made-up past résumés … | the hook, first thing on the card |
| A toy, made up (the slate's label) | A toy we built from made-up résumés. Amazon’s real tool was never published, and this isn’t how it worked. | the card's foot, always visible |
| Our arithmetic | Weights and scores: our arithmetic, from fitting the toy to these 12 résumés. Real scorers learn from far more. | under the weights |

---

## 5. Placement and behaviour (for the reviewer)

- **Where:** the first of Merc's replies in Lesson 3.1 with an [EX] example, at the end of the part that example is in, before any check (`.firstExample`, the tokenizer's rule). With no example in the first complete reply, at its end before its check. In a normal run the first teach reply's example is Amazon's scorer (the guide's home case), so the card follows it.
- **Once per thread**, never into text that is still arriving, never in a cut-off reply, never in a thread that carried a crisis line, and in the same place when the lesson is reopened in the same run (the framework's rules; `InteractivePlacementTests`).
- **No spoiler terms** (the slate's row). The prediction is about the toy, which the tutor's text never shows. If the tutor says "proxy" above the card the guess is easier but not answered; see the open question in §8.
- **Predict first.** The control stays off ("Make your guess first.") until a guess is locked. A guess can't be changed. Deleting the gender box is the reveal (the new scores are the answer), so there is no "Show me". The box flips freely after; the reveal stays. The spoiled mode (reachable today only with `-InteractiveState spoiled`) skips the guess, and the reveal has no "You guessed".
- **Nothing is kept:** the guess and the gender box live in the lesson's in-memory state store; a new lesson screen starts fresh. Nothing is sent or stored.
- **The lesson's check is untouched.** On the iPhone a tap on an option still grades and sends "I picked A) …" (`DeleteTheGenderBoxUITests`). On the Mac a click on a chip acts without keeping the keyboard; a chip reached with Tab holds Return, and A–D, 1–4 and ↑/↓ still answer the check.

**DEBUG paths (shots and UI tests only; a Release build reads none):**
- `-Interactive delete-the-gender-box`: Lesson 3.1 with the framework's stub replies (they say they are stubs); the card arrives through the real placement while it ships dark.
- `-InteractiveGallery delete-the-gender-box`: the card alone.
- `-InteractiveState hook|predicted|explored|revealed|spoiled`: `predicted` locks "They’ll tie"; `explored` and `revealed` both open with the gender box deleted and the reveal shown (deleting the box is what reveals, so there is no explored-but-hidden state a student could reach).
- `-InteractiveScroll top|reveal|after`, and the text-size and Reduce Motion flags, as in FRAMEWORK.md §5.
- This card's own: `-GenderBoxShowAll YES` (the accessibility sizes' list starts open) and `-GenderBoxAutoplayAt <seconds since 1970>` (at that moment the card locks "They’ll tie" and, 1.6 s later, deletes the gender box: the reveal clip, since simctl can't tap).

---

## 6. Invented names

None. The résumés have no names, photos, schools or places: only a gender box and club lines ("chess club captain", "women’s chess club captain", "women’s chess club", "coding club"). Searched 2026-10-21: nothing to search (BUILD_PLAN.md §4.4 lists this card as "no names"). The only real names are Amazon and Reuters, as the guide gives them.

---

## 7. Screenshots and verification

**Shots** in `shots/` (not committed), taken 2026-10-21 from DEBUG builds of this branch:
- **iPhone 16 Pro Max** (`-InteractiveGallery` for the card's top, `-Interactive` for the lesson with its stub replies):
  - `iphone16pm-light-large-1-top`, `-2-guessed` (the guess locked, the control on), `-3-deleted-top` (the struck column), `-4-reveal`;
  - `iphone16pm-dark-large-1-top`, `-3-deleted-top`, `-4-reveal` (the card is the same night-sky island in both appearances; the lesson around it changes);
  - `iphone16pm-ax3-1-top`, `-4-reveal`, `-5-end` (Accessibility XL);
  - `iphone16pm-reveal-clip.mp4` (6.8 s): "They’ll tie" locks, the gender box is deleted, 34/63 become 42/77 and the reveal arrives (`-GenderBoxAutoplayAt`, since simctl can't tap).
- **iPhone SE at AX5** (Accessibility XXXL): `iphoneSE-ax5-1-top`, `-4-reveal`, `-dark-4-reveal` and `-5-end` (the label and the check after the card). At AX5 the card is many screens tall, so the parts in between (the summary and "Show all 12", the list open, the weights as text rows, the two new résumés stacked, the chips and the control) are in the full-card renders below.
- **Full-card renders** from `GenderBoxCardLayoutTests` at an SE's width (343 pt) and a Pro Max's (408 pt), at about half scale, sliced into 3,000 px pieces: `render-343pt-ax5-hook-1…2` and `render-343pt-ax5-deleted-list-open-1…3` (the summary, the list open, the weights as text rows, the new résumés stacked, the chips and the control stacked, the reveal), `render-343pt-large-deleted` and `render-408pt-large-hook`.
- **Mac**, through a renamed copy of the Debug app (`….macnsia5`), never the founder's: `mac-1280-light-*` and `mac-1280-dark-*` (1280 × 800: the hook, the guess in its lesson, the deleted state with both columns, the reveal in its lesson) and `mac-700-*` (700 × 600, the smallest window: the deleted state and the reveal).

**Verified** on this branch: `swift test` (1,314 tests, including `GenderBoxTests`, `ToyFitTests`, the columns test and the Mac arrows); `ci-compat-lint.py` (0 findings); the iOS build and `xcodebuild test` on IA-5 (the card's UI test, all 8 unit tests including its layout tests, the framework's launch tests; the full suite once, where `testBootCompletes` timed out under load and then passed alone); `ios-unchanged-check.sh` (the same 23 results, 11 pass and 12 already stale, the same pixels); the Mac Debug build and the copied-app shots.

The layout tests now also prove each render drew: a render taller than about 8,000 px comes back empty and passed the overflow check without showing anything (the whole card at AX5 with the list open is about 16,000 pt), so each render picks its scale from the card's height and must cover 90 % of its frame.

**Outside this card (for the framework's owner):**
- `RevealBox` (`Views/Shared/PredictChips.swift`) truncates its "YOU GUESSED" / "WHAT HAPPENED" eyebrows at AX5 on an SE ("YOU GUESS…", `render-343pt-ax5-deleted-list-open-3`): the eyebrow `Text` lacks `.fixedSize(horizontal: false, vertical: true)`. Every card's reveal shares it.
- XCUITest sees two buttons per shared `InteractiveChip` whose label is its title (the chip's element and its inner `Button`), so this card's UI test uses `firstMatch`. Worth a VoiceOver check that a chip is read once.
- `scripts/mac-snapshots.sh` passes `INTERACTIVE_ARGS` after `-InteractiveScroll top`, and the first value wins, so its own example (`-InteractiveScroll reveal`) is ignored. The Mac reveal shots here came from a copy of the script with the order swapped (not committed).

**Fixed during the build:** the first Mac version measured its own width to size its two columns, and the column width fed fractions of a point back into that width for ever (the lesson hung at full CPU). The columns are now a stateless layout (`GenderBoxColumns`), with a test.

---

## 8. For teacher review

Please tick each, or note a change. Sign-off (name, date): ______________________

**Accuracy**
- [ ] C1–C2: the Amazon lines say only what the guide says, and the label ("never published, and this isn’t how it worked") is clear enough that no student thinks the toy is Amazon's tool.
- [ ] C4: "Delete one column, and other words carry the same pattern" is the right lesson from one toy fit, and not an overclaim.
- [ ] C5: the small line "Both scores rose … and the gap grew" reads as honest nuance, not as "deleting helped".
- [ ] The weights shown are a real fit (§2). Is showing signed numbers (−1.53) right for 9th graders, with the words "pushes down" beside them?

**Language (ages 13–18)**
- [ ] "the gender box", "train the toy again", "weight", "pushes the score down" are understood without help.
- [ ] The two-women comparison ("Both are women who code. One line is different.") reads carefully: the student compares two women, not a woman with a man.
- [ ] The binary gender box reads as the toy's old records, not as the app's view (no student should feel the card says gender has two values). Should the card say so in a line?
- [ ] "Hired?" with "✓ Hired / ✕ Not hired" is clear.

**Fit with the lesson**
- [ ] The card's place, after the Amazon example and before the check, is right; the card doesn't answer that check.
- [ ] **Exercise clash:** do the lesson's exercise (the questions an HR director would ask a vendor) right after the card; the card wrote none of them.
- [ ] The prediction wasn't spoiled by the tutor's reply in your run (if the tutor said "proxy" first, was the guess still worth making?).

**Ethics for minors**
- [ ] No real person, face or voice; no student is shown as a candidate; Amazon appears only with the guide's facts.
- [ ] The card shows a toy copying a skewed past without suggesting the skew was deserved.

**Accessibility**
- [ ] A VoiceOver-only pass (script in §1): the summary, each résumé, each weight in signed numbers with words, and both scores after a flip.
- [ ] iPhone SE at AX5: the table behind "Show all 12" with the summary visible; the weights as text; the two new résumés always visible.
- [ ] Mac keyboard only: Tab to the chips and the toggle, Space toggles, the lesson's check still answers with A–D.
- [ ] Reduce Motion (the strike-through, bars and scores crossfade), Increase Contrast, Reduce Transparency.
