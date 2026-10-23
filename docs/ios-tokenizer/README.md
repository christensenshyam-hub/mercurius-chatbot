# Lesson 1.1's interactive on the iPhone

**What it is:** "How a model reads “bank”", the Mac's tokenization interactive (PR #48), in the iPhone app. It is the same four steps with the same words, drawn as a self-contained night-sky card in today's lesson screens. The iPhone hasn't adopted Night Studio, so the card brings its own night.

**Where it shows:** Unit 1, Lesson 1 only, inside Merc's first reply that has an [EX] example, after that example's part and before its check. The rules are the Mac's, from one shared source.

**The words and their sources:** `docs/mac-night-studio/tokenizer/CONTENT.md`, which covers both platforms. It includes the lines only the iPhone has: the line under the title, "Try it ↓", the map in words, "Show the map" and "Hide the map", and the "Step 2: …" titles at the accessibility sizes.

**Branch:** `feat/ios-tokenizer`, stacked on `feat/mac-night-studio` (PR #48 → #47 → #43). Not pushed. The PR description is [PR.md](PR.md).

## What changed

### 1. One source for both platforms

The platform-neutral half moved out of `ChatFeature/Sources/Mac/` into code that compiles on iOS and macOS:

| File | Holds | Was |
|---|---|---|
| `Lesson/LessonParts.swift` | a reply's parts between `---` breaks | `NightSection`, `NightParts` |
| `Lesson/LessonCrisisGuard.swift` | the crisis guard (988 / 741741) and its index | `NightCrisisGuard`, `NightCrisisIndex` |
| `Tokenizer/TokenizerInteractive.swift` | the content, the openings, the map's geometry (with a label scale, 1 on the Mac), the card's state, every line (`TokenizerCopy`), the map's line shape, and how the iPhone sizes the map (`TokenizerMapScale`) | `NightTokenizer`, `NightTokenizerContext`, `NightMeaningMap`, `NightTokenizerState`, `NightTokenizerCopy`, `NightLinkLines` |
| `Tokenizer/LessonInteractive.swift` | the placement anchor, once per thread, the complete-reply rule, the in-memory index, and `LessonInteractiveSplit` (where the iPhone's bubble is cut) | `NightInteractive*` |
| DesignSystem `NightPalette`, `NightStarField`, `NightFlow` | now compile on iOS too | Mac only |
| DesignSystem `NightSkyCard` | the iPhone card's colours: Night's dark values, its dark HC values under Increase Contrast, solid under Reduce Transparency | new |

`MessageListView` shares the lesson id, the crisis index, the interactive index, the tokenizer state and the DEBUG jump to the card. On the iPhone it also hands the card its "Try it" jump (`LessonInteractiveJump`). Only `NightTokenizerLayout`, the Mac's compact "Try it" rule, stays in the Mac's folder.

**The Mac is unchanged.** Its views use the shared types under their new names, at label scale 1. The copied-app shots of the map and of each opening match the base build's pixel for pixel, on the final code too (see [VERIFY.md](VERIFY.md)).

### 2. The iPhone's card (`Tokenizer/LessonTokenizerCard.swift`, iOS only)

- **A night-sky card in both appearances.** It uses Night Studio's lit surface at night (#121641), a 1 pt lumen edge, a little corner light and a few stars. In light mode it has the lesson bubble's soft shadow; in dark mode the edge separates it from the screen. Its type, spacing and shapes are the iPhone's (`BrandFont`, `BrandSpacing`, `BrandRadius`). The typed sentence is drawn as the student's own bubble, on the trailing side, in the bubble's hues a step deeper (`accentDark` → `mercViolet`, white at 5.5:1 or better).
- **Its first screen says there is something to try.** Under the title, the Mac's reviewed compact line ("See “I went to the bank” become tokens, then numbers, then a place on a map of meaning."), then **"Try it ↓"**, a 44 pt button. On an SE at Large the openings are about 990 pt into a 1,546 pt card, two screens down; "Try it" scrolls step 4 to the top of the reading area through the list's scroll policy (`partJumped`, a move of the student's own, as the Mac's part strip's jump is: a reply still streaming is no longer followed, and "Jump to latest" offers the way back), and moves VoiceOver to "Step 4: The numbers land in a map of meaning", with the openings next.
- **The same four steps and words**, from `TokenizerCopy`: the sentence; the tokens with leading-space dots and "illustrative IDs, from GPT-4’s tokenizer"; "a list of numbers"; and the map with its 2-D-sketch caption and the accuracy note.
- **The openings** ("I got my paycheck, so…", "I wanted to go fishing, so…") are buttons 44 pt or taller, each with a ring that fills with a check when picked. The ring is there in both states and the same size, so a pick never moves the chip's words (a check that appeared beside them slid them over and was drawn on the "I" for a moment). The chip's own change takes 0.2 s. They sit side by side when both fit and one under the other when they don't, and a long one wraps rather than leaving the card. A pick plays `.sensoryFeedback(.selection)`, and VoiceOver hears the finished sentence and where "bank" went.
- **A pick moves only "bank".** The finished sentence ("… I went to the bank", then "I got my paycheck, so I went to the bank.") and the map in words are laid out for every state with the current one shown, so step 4 is as tall before a pick as after it. On an SE the sentence wraps onto a second line after a pick; before this, the map slid down 26 pt while "bank" moved inside it.
- **Dynamic Type through AX5. I decided this by testing.** Growing the map's labels to xxxLarge broke the map's geometry tests at the phone's widths. So:
  - the labels grow only as far as the panel's width keeps every rule (`TokenizerMapScale.maximum(forPanelWidth:)`): the Mac's size on an SE (311 pt panel), and xLarge's from 340 pt (a 16 Pro Max's panel is 376 pt);
  - from xxLarge up, the card also says where "bank" is in words ("On the map, “bank” is now near loan and deposit.");
  - at the accessibility sizes the map starts folded behind "Show the map", with those words in its place;
  - also at the accessibility sizes, the decoration goes: the step discs, the arrows in step 3 and on "Try it", the bars over the numbers (the values read as one line), the icons. A step's title then reads as VoiceOver says it, "Step 2: It’s cut into tokens" (a "2 · …" here read as the tokens' space dot one line below). The ring on an opening moves above its words so "paycheck," isn't split. No word is cut.
- **Narrow windows.** A 320 pt window (an SE or a mini with Display Zoom, iPad Slide Over or a third of Split View) leaves the map a 256 pt panel, where its label and line rules broke (they hold down to about 284 pt). Under 300 pt the map is now drawn at 300 pt and scaled down to fit (`TokenizerMapScale.drawnWidth`/`fitScale`), so every rule holds and its words are 11 pt or more; with Display Zoom a point is that much bigger on the glass. Step 3's list shows four values there, so "…" stays on their line.
- **Reduce Motion:** "bank" and its lines crossfade instead of moving. **Increase Contrast:** a flat sky with no glows or stars, solid lines and edges, and the HC values. **Reduce Transparency:** every wash and edge is solid, and there are no glows.
- **VoiceOver:** the title and each step are headers with Mac-identical labels. Each step's picture is one sentence, and so is the map ("Map of meaning, a 2-D sketch drawn by hand. With “I got my paycheck, so” before it, bank is near loan and deposit.").

### 3. Placement in the lesson reader

`MessageListView` asks the shared `LessonInteractiveIndex` where the card goes, then passes `interactiveAfter` to that reply's `MessageBubbleView`. The rules are the Mac's:
- Unit 1 Lesson 1 only;
- never mid-stream (the example's part must have ended: a later part, a check, or a complete reply);
- never in a thread with a crisis line;
- once per thread, and in the same place when the lesson is reopened in the same run of the app;
- never in a cut-off reply (AUD-29), including one rebuilt from storage as `.idle`.

The card needs the whole row, so the bubble that holds it is drawn in two: the reply up to the card, the card (the row's width less its 16 pt margins, at most 560 pt), and then the rest of the reply. The "● Merc" line heads the first half, and a failure or cut-off line ends the second. When the card stands at the end of a part, that part's `---` rule isn't drawn, because the card divides the parts; that holds whether the part ends in text or in an [EX] or [KEY] card. Every other block and every other reply draw exactly as before (`interactiveAfter` defaults to nil). Nothing changes on the wire, in the prompt or in storage.

- **The [Q] check** is the same `CheckQuizCard` with the same `quizInteraction`: a tap grades and sends "I picked B) …". There is no "Lock it in" on iOS.
- **The reading position and "Jump to latest" (AUD-09):** the card appears while the reply streams (once the check begins). It is inserted below the reply's top, so a reply held at its top stays held. The `slow-*` shots show the reading position steady from 13 s to 23 s while the card arrives below it. "Try it" is a move of the student's own, like the Mac's part jump.
- **Cut-off replies (AUD-29):** with `-LessonReplayCut` the first reply is cut mid-part, so it never gets the card. After the student answers, the next reply takes it, after its example's part (`cut-next`).

## DEBUG launch arguments (iPhone)

Start with `-LessonPreview -LessonSkipIntro -LessonReplay`. Then add:

| Argument | Does |
|---|---|
| `-NightScrollToInteractive top\|map` | once a reply settles, scrolls the card (or its map step) to the top. Both platforms |
| `-NightScrollToInteractive context\|step2\|step3\|openings\|sentence\|panel\|after` | iPhone only: the card's top under the end of the text before it; step 2; step 3; step 4's openings; the finished sentence; the map; or the card's end with what follows |
| `-NightTokenizer money\|river` | an opening already picked. Both platforms |
| `-NightTokenizerAutoPick money\|river` (+ `-NightTokenizerAutoPickDelay <s>`, default 2) | picks that opening once, as a tap would, that long after the card appears (for the motion clip) |
| `-NightTokenizerShowMap YES` | the folded map already shown (accessibility sizes) |
| `-NightTokenizerReduceMotion YES`, `-NightTokenizerReduceTransparency YES`, `-NightTokenizerIncreaseContrast YES` | the card's accessibility settings for shots. Increase Contrast can also be set with `xcrun simctl ui <udid> increase_contrast enabled` |

simctl can't tap, so "Try it" is shot by `LessonInteractiveUITests` (run it with `TEST_RUNNER_TOKENIZER_SHOTS=1` to keep the screen before and after the jump in the result bundle).

## Tests

- **`TokenizerInteractiveTests`** (shared, run by `swift test` on the macOS host):
  - placement: the recorded lesson, streaming, a check in the same part, no example, cut-off, a cut reply rebuilt as `.idle`, Retry, a bare failure, once per thread, kept and reopened, crisis lines, other lessons;
  - the bubble cut: the recorded lesson, a check in the same part, no example, the reply's end, text after the break, a part that ends in a [KEY] or an [EX] card (no rule at the top of the second bubble), a break that isn't the part's end, a fenced `---`, streaming, and every place in every recorded reply without losing a word;
  - content;
  - the map at the Mac's nine widths and the iPhone's fifteen (240 to 528 pt; under 300 as drawn, at 300 scaled down) at every label size it draws;
  - the iPhone's map scale, the narrow-panel scaling and the fold rules;
  - the words and VoiceOver lines, including the "Step 2: …" titles (no space dot) and "Try it"'s hint;
  - the state.
- **`NightTokenizerTests`** (Mac): where Night's reply draws the card, and the keys.
- **`MercuriusTests/TokenizerCardLayoutTests`** (iOS, in CI's `xcode` job):
  - the card renders at a 320 pt window's (288 pt), an SE's (343 pt) and a 16 Pro Max's (408 pt) width at Large, xxxLarge, AX3 and AX5, unpicked and with each opening, and nothing lands outside it;
  - **a pick never moves the map or resizes the card:** the map panel's top is the same before a pick and after each one at all three widths from Large to AX5 (the folded map shown), and the card's height is the same;
  - it grows with the text;
  - the recorded reply holds it only where the placement says.

  Set `TEST_RUNNER_TOKENIZER_RENDER_DIR` to keep the renders.
- **`MercuriusUITests/LessonInteractiveUITests`** (iOS, in CI's `xcode` job). On the recorded lesson, it checks that:
  - the card arrives in Lesson 1.1;
  - an opening is a button that picks;
  - one touch on the check's option B after the card still sends "I picked B) …";
  - "Try it" brings the openings from below the screen onto it (more than 200 pt up), and they pick from there.

  XCUITest reports the lesson's option rows as not hittable even when they are on screen, so the first test scrolls by swiping and touches the row's centre. The second drags the list and holds before letting go: on an SE a swipe's momentum carried "Try it" under the header.
- **`NightSkyCardTests`** (DesignSystem, shared): the card's colours are Night's dark (and dark HC) values, flattened under Reduce Transparency, and every word on it reads at 4.5:1 (7:1 under HC).

## Verification

See [VERIFY.md](VERIFY.md).

## Shots

**In the repo:** `key-shots/`, six JPEGs (quality 82, no side over 1600 px) and the motion clip:

| File | Shows |
|---|---|
| `01-pm-light.jpg` | 16 Pro Max, Large, light: the card after the example's part; its first screen with "Try it ↓"; step 4 after "I got my paycheck, so…"; the card's end and the check |
| `02-pm-dark.jpg` | 16 Pro Max, Large, dark: the card's first screen; the map before a pick; after "I wanted to go fishing, so…"; Increase Contrast |
| `03-se-accessibility-sizes.jpg` | SE at AX3 ("Step 2: …"; the map in words after a pick) and AX5 (the ring over a picked opening's words; the map shown, in dark) |
| `04-se-large.jpg` | SE at Large: "Try it ↓" on the card's first screen and step 4 after the jump (from the UI test); the map before and after a pick, at the same scroll place (the map holds still); and the map in a 320 pt window (a test render at 288 pt, shown at the same scale) |
| `05-contact-sheet-dark.jpg` | every dark-appearance state on both phones, Large to AX5, with Increase Contrast |
| `06-pick-motion.jpg` | frames from the SE clips: the pick moving, and the same pick under Reduce Motion, before, at the pick, +0.1, +0.2, +0.35 s and settled |
| `pick-money-se.mp4` | the motion clip (see Motion below) |

**Outside the repo:** the full set is in `.claude/worktrees/explore-ui-shared/ios-tokenizer-shots/`: 66 simulator shots, the whole-card renders, the stream and cut-off checks, three clips, the light contact sheet (`contact-sheet.jpg`, start there), the final build's raw PNGs in `final-build-raw/`, and the Mac copied-app shots (base and this branch) in `mac-copy-shots/`. The set from before the review fixes is kept in `before-review-fixes/`.

**Simulator shots** are `se-*` (iPhone SE 3, 750×1334 px) and `pm-*` (16 Pro Max, halved to 660×1434 px). They are named `<device>-<text size>-<appearance>-<state>`:
- text sizes: `large`, `xxxl`, `ax3`, `ax5`;
- states:
  - `top`, `step2`, `step3`: the card's top and its steps;
  - `map`: step 4 before a pick;
  - `money`, `river`: after each pick, at the same scroll place as `map`;
  - `openings`, `sentence`: step 4's chips, and the finished sentence with the map in words;
  - `shown`: the folded map opened;
  - `context`: the reply's text before the card;
  - `after`: the card's end and the check after it;
  - `try-it-before`, `try-it-after`: "Try it" on the card's first screen, and where it went (from `LessonInteractiveUITests` on the SE);
- variants: `hc` is Increase Contrast, `rt` Reduce Transparency, `rm` Reduce Motion.

The sims were reset to Large, light and Increase Contrast off afterwards.

**Whole-card renders** from `TokenizerCardLayoutTests` (at 1×): `render-se-<size>-money-full-card.jpg` (343 pt at Large, xxxLarge, AX3 and AX5), `render-320pt-window-<size>-river-full-card.jpg` (288 pt at Large, xxxLarge and AX3) and `render-pm-large-none-full-card.jpg` (408 pt). At AX5 an SE's reading area shows only a few lines at a time, so these are the way to see the whole card at once. (The 288 pt AX5 render is over 9,000 px tall, which the test host's PNG writer refuses; the test still checks it.)

**Stream and cut-off checks:**
- `pm-slow-13s` … `pm-slow-23s` (`-LessonReplaySlow`): the first reply held at its top while it streams and the card arrives below. The reading position doesn't move.
- `se-cut-next` (`-LessonReplayCut -LessonAutoAnswer B -LessonAutoAnswerDelay 10`): the first reply was cut mid-part, so the card is in the next reply, after its example's part.

**Motion:**
- `pick-money-se.mp4` (also in `key-shots/`, 1.1 MB): 5.8 s, h264, the SE at Large, light. `-NightTokenizerAutoPick money` picks "I got my paycheck, so…" 4.3 s in: the ring fills, the sentence changes at once and wraps to two lines, the map stays where it is, and "bank" glides to loan and deposit.
- `pick-money-se-rm.mp4`: the same under Reduce Motion: "bank" crossfades in 0.35 s, nothing moves.
- `pick-money-pm.mp4`: the same pick on the 16 Pro Max.
- `pick-motion-strip.jpg` (= `key-shots/06-pick-motion.jpg`): frames from the two SE clips.

## For a real device

The simulator can't check these:
- the selection haptic;
- VoiceOver's walk through the card, including "Try it" moving the focus to step 4's title;
- a real tap on an opening while the check below is waiting;
- the system's own Reduce Motion and Reduce Transparency switches (the shots use the DEBUG overrides).
