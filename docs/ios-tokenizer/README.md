# Lesson 1.1's interactive on the iPhone

**What it is:** "How a model reads “bank”", the Mac's tokenization interactive (PR #48), in the iPhone app. It is the same four steps with the same words, drawn as a self-contained night-sky card in today's lesson screens. The iPhone hasn't adopted Night Studio, so the card brings its own night.

**Where it shows:** Unit 1, Lesson 1 only, inside Merc's first reply that has an [EX] example, after that example's part and before its check. The rules are the Mac's, from one shared source.

**The words and their sources:** `docs/mac-night-studio/tokenizer/CONTENT.md`, which now covers both platforms. That includes the three lines only the iPhone has: the map in words, "Show the map" and "Hide the map".

**Branch:** `feat/ios-tokenizer`, stacked on `feat/mac-night-studio` (PR #48 → #47 → #43). Not pushed.

## What changed

### 1. One source for both platforms

The platform-neutral half moved out of `ChatFeature/Sources/Mac/` into code that compiles on iOS and macOS:

| File | Holds | Was |
|---|---|---|
| `Lesson/LessonParts.swift` | a reply's parts between `---` breaks | `NightSection`, `NightParts` |
| `Lesson/LessonCrisisGuard.swift` | the crisis guard (988 / 741741) and its index | `NightCrisisGuard`, `NightCrisisIndex` |
| `Tokenizer/TokenizerInteractive.swift` | the content, the openings, the map's geometry (now with a label scale, 1 on the Mac), the card's state, every line (`TokenizerCopy`), the map's line shape, and how the iPhone sizes the map (`TokenizerMapScale`) | `NightTokenizer`, `NightTokenizerContext`, `NightMeaningMap`, `NightTokenizerState`, `NightTokenizerCopy`, `NightLinkLines` |
| `Tokenizer/LessonInteractive.swift` | the placement anchor, once per thread, the complete-reply rule, the in-memory index, and `LessonInteractiveSplit` (where the iPhone's bubble is cut) | `NightInteractive*` |
| DesignSystem `NightPalette`, `NightStarField`, `NightFlow` | now compile on iOS too | Mac only |
| DesignSystem `NightSkyCard` | the iPhone card's colours: Night's dark values, its dark HC values under Increase Contrast, solid under Reduce Transparency | new |

`MessageListView` now shares the lesson id, the crisis index, the interactive index, the tokenizer state and the DEBUG jump to the card. Only `NightTokenizerLayout`, the Mac's compact "Try it" rule, stays in the Mac's folder.

**The Mac is unchanged.** Its views use the shared types under their new names, at label scale 1. The copied-app shots of the map and of each opening match the base build's pixel for pixel (see Verification).

### 2. The iPhone's card (`Tokenizer/LessonTokenizerCard.swift`, iOS only)

- **A night-sky card in both appearances.** It uses Night Studio's lit surface at night (#121641), a 1 pt lumen edge, a little corner light and a few stars. In light mode it has the lesson bubble's soft shadow; in dark mode the edge separates it from the screen. Its type, spacing and shapes are the iPhone's (`BrandFont`, `BrandSpacing`, `BrandRadius`). The typed sentence is drawn as the student's own bubble, on the trailing side, in the bubble's hues a step deeper (`accentDark` → `mercViolet`, white at 5.5:1 or better).
- **The same four steps and words**, from `TokenizerCopy`: the sentence; the tokens with leading-space dots and "illustrative IDs, from GPT-4’s tokenizer"; "a list of numbers"; and the map with its 2-D-sketch caption and the accuracy note.
- **The openings** ("I got my paycheck, so…", "I wanted to go fishing, so…") are buttons 44 pt or taller. They sit side by side when both fit and one under the other when they don't, and a long one wraps rather than leaving the card. A pick plays `.sensoryFeedback(.selection)`, and VoiceOver hears the finished sentence and where "bank" went.
- **Dynamic Type through AX5. I decided this by testing.** First I let the map's labels grow with the text up to xxxLarge, with the panel growing too. The geometry tests then failed at the phone's widths: the river pill met the start caption and "water", and the money line crossed the caption. So now:
  - the labels grow only as far as the panel's width keeps every rule (`TokenizerMapScale.maximum(forPanelWidth:)`): the Mac's size on an SE (311 pt panel), and xLarge's from 340 pt (a 16 Pro Max's panel is 376 pt);
  - from xxLarge up, the card also says where "bank" is in words ("On the map, “bank” is now near loan and deposit.");
  - at the accessibility sizes the map starts folded behind "Show the map", with those words in its place;
  - also at the accessibility sizes, the decoration goes: the step discs ("1 · You type" stays as text), the arrow in step 3, the bars over the numbers (the values read as one line), the icons. The check on a picked opening moves above its words so "paycheck," isn't split. No word is cut.
- **Reduce Motion:** "bank" and its lines crossfade instead of moving. **Increase Contrast:** a flat sky with no glows or stars, solid lines and edges, and the HC values. **Reduce Transparency:** every wash and edge is solid, and there are no glows.
- **VoiceOver:** the title and each step are headers with Mac-identical labels. Each step's picture is one sentence, and so is the map ("Map of meaning, a 2-D sketch drawn by hand. With “I got my paycheck, so” before it, bank is near loan and deposit.").

### 3. Placement in the lesson reader

`MessageListView` asks the shared `LessonInteractiveIndex` where the card goes, then passes `interactiveAfter` to that reply's `MessageBubbleView`. The rules are the Mac's:
- Unit 1 Lesson 1 only;
- never mid-stream (the example's part must have ended: a later part, a check, or a complete reply);
- never in a thread with a crisis line;
- once per thread, and in the same place when the lesson is reopened in the same run of the app;
- never in a cut-off reply (AUD-29), including one rebuilt from storage as `.idle`.

The card needs the whole row, so the bubble that holds it is drawn in two: the reply up to the card, the card (the row's width less its 16 pt margins, at most 560 pt), and then the rest of the reply. The "● Merc" line heads the first half, and a failure or cut-off line ends the second. When the card stands at the end of a part, that part's `---` rule isn't drawn, because the card divides the parts. Every other block and every other reply draw exactly as before (`interactiveAfter` defaults to nil). Nothing changes on the wire, in the prompt or in storage.

- **The [Q] check** is the same `CheckQuizCard` with the same `quizInteraction`: a tap grades and sends "I picked B) …". There is no "Lock it in" on iOS.
- **The reading position and "Jump to latest" (AUD-09):** the card appears while the reply streams (once the check begins). It is inserted below the reply's top, so a reply held at its top stays held. The `slow-*` shots show the reading position steady from 13 s to 23 s while the card arrives below it.
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

## Tests

- **`TokenizerInteractiveTests`** (shared, run by `swift test` on the macOS host):
  - placement: the recorded lesson, streaming, a check in the same part, no example, cut-off, a cut reply rebuilt as `.idle`, Retry, a bare failure, once per thread, kept and reopened, crisis lines, other lessons;
  - the bubble cut: the recorded lesson, a check in the same part, no example, the reply's end, text after the break, a fenced `---`, streaming, and every place in every recorded reply without losing a word;
  - content;
  - the map at the Mac's nine widths and the iPhone's ten widths at every label size it draws;
  - the iPhone's map scale and fold rules;
  - the words and VoiceOver lines;
  - the state.
- **`NightTokenizerTests`** (Mac): where Night's reply draws the card, and the keys.
- **`MercuriusTests/TokenizerCardLayoutTests`** (iOS, in CI's `xcode` job):
  - the card renders at an SE's (343 pt) and a 16 Pro Max's (408 pt) width at Large, xxxLarge, AX3 and AX5, unpicked and with each opening, and nothing lands outside it;
  - it grows with the text;
  - the recorded reply holds it only where the placement says.

  Set `TEST_RUNNER_TOKENIZER_RENDER_DIR` to keep the renders.
- **`MercuriusUITests/LessonInteractiveUITests`** (iOS, in CI's `xcode` job). On the recorded lesson, it checks that:
  - the card arrives in Lesson 1.1;
  - an opening is a button that picks;
  - one touch on the check's option B after the card still sends "I picked B) …".

  XCUITest reports the lesson's option rows as not hittable even when they are on screen, so the test scrolls by swiping and touches the row's centre.
- **`NightSkyCardTests`** (DesignSystem, shared): the card's colours are Night's dark (and dark HC) values, flattened under Reduce Transparency, and every word on it reads at 4.5:1 (7:1 under HC).

## Verification

See [VERIFY.md](VERIFY.md).

## Shots

**In the repo:** `key-shots/`, six JPEGs (quality 82, no side over 1600 px) and the motion clip:

| File | Shows |
|---|---|
| `01-pm-light.jpg` | 16 Pro Max, Large, light: steps 1–3, then step 4 after "I got my paycheck, so…" |
| `02-pm-dark.jpg` | 16 Pro Max, Large, dark: step 4 before a pick, then after "I wanted to go fishing, so…" |
| `03-se-accessibility-sizes.jpg` | SE at AX3 (the map in words, behind "Show the map") and AX5 (the check above a picked opening; the map shown, in dark) |
| `04-placement.jpg` | 16 Pro Max, light: the example's part ends and the card begins; the card ends and the check follows |
| `05-contact-sheet-dark.jpg` | every dark-appearance state on both phones, Large to AX5, with Increase Contrast |
| `06-reduce-motion.jpg` | the pick moving, and the same pick as a crossfade under Reduce Motion |
| `pick-money.mp4` | the motion clip (see Motion below) |

The 01–04 frames were taken again on the final build after review. They match the earlier set within JPEG noise (mean difference 0.9 to 1.5 of 255, and no pixel more than 40 apart outside the system's status bar and home indicator), so the full set still shows the final code.

**Outside the repo:** the full set (61 simulator shots, the whole-card renders, the stream and cut-off checks, the clip and the light contact sheet) is in `.claude/worktrees/explore-ui-shared/ios-tokenizer-shots/`, with the final build's raw PNGs in `final-build-raw/`. Start with `contact-sheet.jpg`, which shows every simulator shot.

**Simulator shots** are `se-*` (iPhone SE 3, 750×1334 px) and `pm-*` (16 Pro Max, halved to 660×1434 px). They are named `<device>-<text size>-<appearance>-<state>`:
- text sizes: `large`, `xxxl`, `ax3`, `ax5`;
- states:
  - `top`, `step2`, `step3`: the card's top and its steps;
  - `map`: the map before a pick;
  - `money`, `river`: after each pick;
  - `openings`, `sentence`: step 4's chips, and the finished sentence with the map in words;
  - `shown`: the folded map opened;
  - `context`: the reply's text before the card;
  - `after`: the card's end and the check after it;
- variants: `hc` is Increase Contrast, `rt` Reduce Transparency, `rm` Reduce Motion.

The sims were reset to Large, light and Increase Contrast off afterwards.

**Whole-card renders** are `render-se-<size>-money-full-card.jpg`: the card at an SE's width (343 pt, at 1×) at Large, xxxLarge, AX3 and AX5, from `TokenizerCardLayoutTests`. At AX5 an SE's reading area shows only a few lines at a time, so these are the way to see the whole card at once.

**Stream and cut-off checks:**
- `pm-slow-13s` … `pm-slow-23s` (`-LessonReplaySlow`): the first reply held at its top while it streams and the card arrives below. The reading position doesn't move.
- `se-cut-next` (`-LessonReplayCut -LessonAutoAnswer …`): the first reply was cut mid-part, so the card is in the next reply, after its example's part.

**Motion:**
- `pick-money.mp4` (also in `key-shots/`, 2.7 MB): 6.3 s, h264, the 16 Pro Max. "I got my paycheck, so…" is picked by `-NightTokenizerAutoPick money` 2.1 s in, and "bank" glides from its ring to loan and deposit.
- `rm-crossfade.jpg`: frames from that clip and from the same pick under Reduce Motion, where the two differ. The move is 0.7 s; the crossfade is 0.35 s and moves nothing. The stills of a settled pick are the same either way.

## For a real device

The simulator can't check these:
- the selection haptic;
- VoiceOver's walk through the card;
- a real tap on an opening while the check below is waiting;
- the system's own Reduce Motion and Reduce Transparency switches (the shots use the DEBUG overrides).
