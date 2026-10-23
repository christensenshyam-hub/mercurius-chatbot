> **Stacked on #48** (`feat/mac-night-studio`, itself on #47 → #43). This PR's own changes are the commits after `9504c58`. Once #48 merges, retarget this PR to `main`.

## What it is

Lesson 1.1's tokenization interactive, **"How a model reads “bank”"**, now on the iPhone. The Mac got it in #48. It has the same four steps and the same words, from one source the two apps share:

1. **You type:** "I went to the bank".
2. **It's cut into tokens:** `I` `·went` `·to` `·the` `·bank`, with a dot for the space that travels with each word and GPT-4's IDs 40, 4024, 311, 279, 6201, labelled "illustrative IDs, from GPT-4’s tokenizer".
3. **Each token becomes a list of numbers:** "·bank" → "a list of numbers", "+ thousands more".
4. **The numbers land in a map of meaning:** the hand-drawn 2-D sketch with its caption and accuracy note. Two openings start the sentence, "I got my paycheck, so…" and "I wanted to go fishing, so…". "bank" then moves from its ring toward loan and deposit, or toward shore and water.

The iPhone hasn't adopted Night Studio, so the card brings its own night: Night's lit surface, a thin edge, a little corner light and a few stars, in both the light and dark lesson screens. Its type, spacing and corner shapes come from the iPhone's DesignSystem (`BrandFont`, `BrandSpacing`, `BrandRadius`). The sentence in step 1 is drawn as the student's own bubble.

On a phone the card is long (on an SE at Large the openings are about two screens below its top), so its first screen says what it does and has **"Try it ↓"**, which brings step 4 up.

## Where it appears

The rules are the Mac's, from the same code:
- **Unit 1, Lesson 1 only.** It goes in the first of Merc's complete replies that has an [EX] example, after that example's part and before its check.
- **Never mid-stream:** only once the example's part has ended.
- **Never in a thread that has carried a crisis line** (988 or 741741).
- **Once per thread.** Reopened in the same run of the app, the lesson puts it back in the same place.
- **Never in a cut-off reply (AUD-29),** including one rebuilt from storage as `.idle`.

The card needs the row's full width, so the bubble that holds it is drawn in two parts: the reply up to the card, the card, then the rest of the reply. Where the card ends a part, that part's `---` rule isn't drawn, whether the part ends in text or in an [EX] or [KEY] card. Every other reply draws exactly as before.

**Unchanged:**
- **The [Q] check:** a tap still grades and sends "I picked B) …". There is no "Lock it in" on iOS.
- **The reading position and "Jump to latest" (AUD-09):** the card is inserted below a reply held at its top, and the reply stays held. "Try it" is a move of the student's own (the scroll policy's `partJumped`, as the Mac's part strip uses), so a reply still streaming is no longer followed and "Jump to latest" offers the way back.
- **Cut-off replies (AUD-29).**
- **No wire, prompt or storage change.**

## Screenshots

![16 Pro Max, light](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/01-pm-light.jpg?raw=true)
**16 Pro Max, Large, light:** the card after the example's part; its first screen with "Try it ↓"; step 4 after "I got my paycheck, so…"; the card's end, then the check.

![16 Pro Max, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/02-pm-dark.jpg?raw=true)
**16 Pro Max, Large, dark:** the first screen; the map before a pick; after "I wanted to go fishing, so…"; Increase Contrast.

![SE at AX3 and AX5](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/03-se-accessibility-sizes.jpg?raw=true)
**iPhone SE at AX3 and AX5:** "Step 2: …" titles; the map said in words; the ring over a picked opening's words; the map shown, in dark.

![SE at Large](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/04-se-large.jpg?raw=true)
**iPhone SE at Large:** "Try it ↓" and where it goes; the map before and after a pick at the same scroll place (the sentence wraps, the map stays put); the map in a 320 pt window.

![Dark contact sheet](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/05-contact-sheet-dark.jpg?raw=true)
**Every dark state on both phones,** from Large to AX5, including Increase Contrast.

![A pick, moving and under Reduce Motion](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/06-pick-motion.jpg?raw=true)
**A pick on the SE:** "bank" glides while the chip and sentence change at once and the map holds still (top row); under Reduce Motion it crossfades in place (bottom row).

**Motion clip:** [pick-money-se.mp4](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/key-shots/pick-money-se.mp4?raw=true) (5.8 s, the SE at Large): "I got my paycheck, so…" is picked and "bank" glides to loan and deposit.

The full set (66 simulator shots on the SE and the 16 Pro Max from Large to AX5, light and dark, every state, plus whole-card renders, the stream and cut-off checks and three clips) is kept outside the repo.

## Accessibility

- **Touch targets:** both openings and "Try it" are buttons at least 44 pt tall. Each opening has a ring that fills with a check when picked; the ring is there in both states, so a pick never moves the words. A pick plays `.sensoryFeedback(.selection)`.
- **Dynamic Type through AX5,** decided by testing:
  - **The map's labels.** Growing them up to xxxLarge broke the map's no-overlap rules at phone widths. So the label size is capped by the map's width: the Mac's size on an SE, and xLarge's size from a 340 pt map (a 16 Pro Max's is 376 pt).
  - **From xxLarge up,** the card also says where "bank" is in words: "On the map, “bank” is now near loan and deposit."
  - **At the accessibility sizes,** the map starts folded behind "Show the map", with those words in its place.
  - **Decoration goes at the accessibility sizes:** the step discs (the titles then read "Step 2: It’s cut into tokens", VoiceOver's own line), the arrows, the bars over the numbers (the values read as one line) and the icons. The ring on an opening moves above its words. No word is cut.
  - **A pick never moves the map.** The finished sentence and the map in words are laid out for every state, so step 4's height doesn't change when the sentence wraps onto a second line.
  - **Widths:** an iPhone SE (a 343 pt card), a 16 Pro Max (408 pt) and a 320 pt window (an SE or a mini with Display Zoom, iPad Slide Over: 288 pt). Under a 300 pt map the 300 pt map is drawn and scaled down, so every label and line rule holds; its words stay 11 pt or more.
- **Reduce Motion:** a crossfade in place of the move; "Try it" jumps without animating.
- **Increase Contrast:** a flat sky with no glows or stars, solid lines and edges, and Night's high-contrast colours.
- **Reduce Transparency:** solid washes and edges, and no glows.
- **Contrast:** every word on the card reads at 4.5:1 or better, and 7:1 under Increase Contrast (`NightSkyCardTests`). White on the sentence bubble is at 5.5:1 or better.
- **VoiceOver:** the title and each step are headers with the Mac's labels. Each step's picture is one sentence, and so is the map ("Map of meaning, a 2-D sketch drawn by hand. With “I got my paycheck, so” before it, bank is near loan and deposit."). A pick announces the finished sentence and where "bank" went. "Try it" (hint: "Goes to step 4, where you start the sentence") moves VoiceOver to step 4's title.

## One source for both platforms (and proof the Mac is unchanged)

The platform-neutral half moved out of `ChatFeature/Sources/Mac/` into code that builds on iOS and macOS:

| New file | Holds | Was (Mac only) |
|---|---|---|
| `Lesson/LessonParts.swift` | a reply's parts between `---` breaks | `NightSection`, `NightParts` |
| `Lesson/LessonCrisisGuard.swift` | the crisis guard and its index | `NightCrisisGuard`, `NightCrisisIndex` |
| `Tokenizer/TokenizerInteractive.swift` | the content and openings, the map's geometry (with a label scale, 1 on the Mac), the card's state, every line (`TokenizerCopy`), the VoiceOver lines, the iPhone's map sizing | `NightTokenizer*`, `NightMeaningMap`, `NightLinkLines` |
| `Tokenizer/LessonInteractive.swift` | the placement anchor, once per thread, the complete-reply rule, the in-memory index, and where the iPhone's bubble is split | `NightInteractive*` |
| DesignSystem `NightPalette`, `NightStarField`, `NightFlow` | now build on iOS too | Mac only |
| DesignSystem `NightSkyCard` | the iPhone card's colours | new |

The iPhone card itself is `Tokenizer/LessonTokenizerCard.swift` (iOS only). The Mac's views changed only to use the shared types under their new names; the Mac's compact "Try it" rule (`NightTokenizerLayout`) stays in the Mac's folder.

**The Mac is unchanged:**
- **Pixels.** The Mac app was photographed as a renamed copy (`scripts/mac-copy-snapshots.sh`: off screen, never activated) on the base build (`9504c58`) and again on this branch's final code. The map before a pick and after each opening are **pixel-identical**, with no differing pixel.
- **Tests.** The Mac's tokenizer tests (`NightTokenizerTests`, `NightReplyTextTests`, the sky contrast tests) pass.
- **Build.** The Mac Debug build succeeds.

## Snapshot status

**No reference was recorded or changed.**
- `scripts/ios-unchanged-check.sh` ran the 23 `ViewSnapshotTests` with recording forced off. It reports **"the same 23 results and the same pixels for every stale render as the baseline"**: 11 pass, and 12 were already stale before this branch, with the same render hashes.
- No snapshot covers the lesson thread, which is the only screen this PR changes.
- CI skips `ViewSnapshotTests` as before. Re-recording the 12 stale references is still the founder's job.

## Tests

- **`TokenizerInteractiveTests`** (shared; `swift test` runs them on the macOS host):
  - **placement:** the recorded lesson, streaming, a check in the same part, no example, cut-off, a cut reply rebuilt as `.idle`, Retry, a bare failure, once per thread, reopening, crisis lines, other lessons;
  - **the bubble split:** at every place in every recorded reply without losing a word, and parts that end in a [KEY] or [EX] card (no rule at the top of the second bubble);
  - **the map:** at the Mac's nine widths and the iPhone's fifteen (240 to 528 pt), at every label size it draws, and the scaled-down map under 300 pt;
  - **the words:** every line and every VoiceOver line, including the "Step 2: …" titles and "Try it"'s hint.
- **`NightSkyCardTests`** (DesignSystem): the card's colours, and contrast in every mode.
- **`TokenizerCardLayoutTests`** (iOS, in CI's `xcode` job): at 288, 343 and 408 pt and Large, xxxLarge, AX3 and AX5, unpicked and with each opening, nothing lands outside the card; **a pick never moves the map panel or changes the card's height** (Large to AX5); the card grows with the text; and the recorded reply holds it only where the placement says.
- **`LessonInteractiveUITests`** (iOS, in CI's `xcode` job), on the recorded lesson:
  - the card arrives, an opening is a button that picks, and one touch on the check's option B still sends "I picked B) …";
  - "Try it" brings the openings from below the screen onto it, and they pick from there. It passes on the 16 Pro Max and the SE.

**Results** (Xcode 26.4 locally; simulators Audit 16PM and Audit SE3):

| Check | Result |
|---|---|
| `swift test` from an empty scratch path | 1215 tests in 182 suites passed (1187 / 177 on the base) |
| `scripts/ci-compat-lint.py` (and on the two test targets) | 0 findings |
| `xcodebuild test` with CI's flags | TEST SUCCEEDED: 7 XCTest, 3 Swift Testing, 27 UI; 34 test cases, 0 failures, no retries |
| `scripts/ios-unchanged-check.sh` | same 23 results, same pixels |
| Mac Debug build | succeeded |
| Mac copied-app shots, before vs after | pixel-identical |

Only CI can confirm that the branch compiles on Xcode 16.2 / Swift 6.0.3.

## For teacher review

The words and every factual claim, with sources, are in [`docs/mac-night-studio/tokenizer/CONTENT.md`](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/mac-night-studio/tokenizer/CONTENT.md), which covers both apps, including the lines only the iPhone has (the line under the title, "Try it ↓", the map in words, "Show the map" / "Hide the map", the "Step 2: …" titles). The checklist is [§4, For teacher review](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/mac-night-studio/tokenizer/CONTENT.md#4-for-teacher-review).

## Before merging, on a real iPhone

- **The haptic:** tap an opening and feel the selection haptic.
- **VoiceOver:** walk through the card, and check that "Try it" lands on step 4's title.
- **Tap timing:** tap an opening while the check below is waiting, then answer the check by tap.
- **System switches:** turn on Reduce Motion and Reduce Transparency in Settings. The shots used DEBUG overrides for these; Increase Contrast was the simulator's own setting.

Notes, DEBUG launch arguments and the full verification are in [`docs/ios-tokenizer/README.md`](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/README.md) and [`VERIFY.md`](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-tokenizer/docs/ios-tokenizer/VERIFY.md).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
