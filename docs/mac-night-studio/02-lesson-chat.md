# Step 02: the lesson reader and the chat

**Branch:** `feat/mac-night-studio`, stacked on `feat/mac-app-2026-10` (PR #47). Not pushed.
**Built from:** `SPEC.md` §5.3 (lesson reader), §5.4 (chat), §5.10 (errors), §6 (copy), and step 01's tokens and components.
**Commits:**
- `90f24a9`: the lesson reader and the chat (code and tests).
- `a00cfa9`: the snapshot harness's Night lesson and chat states.
- `9966db6`: the harness's `lesson-cut` state (AUD-29).
- `docs` commit: this note and `shots/02/`.

Mac only. Every change sits behind `#if os(macOS)`. `ios-source-diff.py` reports **0 files with iOS-visible changes**, and the iPhone still draws the bubble.

## What changed

### 1. How a reply is read (`ChatFeature/Sources/Mac/NightReplyText.swift`, pure, tested)

| Piece | Rule |
|---|---|
| `NightParts` | Splits a reply into **parts** at Markdown thematic-break lines (`---`, `***`, `___`, spaced or not, indented 3 or fewer). It splits **after** `BlockParser`, so a break inside `[KEY]`/`[EX]` or a fenced code block stays put. A part counts once something in it has arrived: whitespace-only sections and a marker still being withheld don't count. While streaming, a last line of one or two dashes (`-`, `--`) is held back so it never flashes as text. **Naming:** "Check" for a part with a `[Q]`; else its first `**bold**` term, trimmed of a trailing `:`, if 32 characters or fewer; else none. The recorded lesson's parts are `—, Tokenization, Check · —, next-token prediction, Check · —, —, Exercise`. No "Hook", no invented names. |
| `NightPartPlan` / `NightPartIndex` | Numbers parts across the whole lesson thread, over Merc's replies only. It splits each reply once per change of its text, because a lesson re-renders on every streamed delta. |
| `NightSourceParser` | Turns citations into chips, after the paragraph that cited them. It reads both server formats. **Production today:** `[SOURCE: label — domain/path]`, with every separator the server's `parseSourceTag` accepts (`—`, `–`, ` - `, `:`, `,`, `|`, `(…)`, a bare address), quotes stripped from the title. **PR #46's plain forms:** `Source: label (domain)` on its own line or after a sentence, `(Source: label, domain)` mid-sentence, and `Source: label` with no address. A tag still arriving mid-stream is held back. A look-alike that never closes, or one with a newline or `[` before its `]`, stays as written. Code is left alone. Only a paragraph a source was taken from is tidied, so every other paragraph stays byte for byte (two trailing spaces are a Markdown line break). |
| `NightYourTurn` | A reply's **closing question**. Its last paragraph, sources aside, must end in `?` (closing `*`, `_`, quotes or `)` allowed), be 400 characters or fewer, and be a plain paragraph (not a list item, heading, quote, table or code). |
| `NightCrisisGuard` | The server's own crisis-reply signal: `988` or `741741` as a whole word (`server.js` `CRISIS_RESOURCE_RE`). "1988" and "9880" don't match. |
| `NightTokenLine` | The `[EX]` token line, drawn only for this pattern: a quoted word, then in the same sentence "token(s)" and two or more quoted pieces that join to **exactly** that word. Straight or curly quotes. The recorded example gives `unbelievable → un · believ · able`. A mismatch, a single piece, no "token" word, or pieces in another sentence give nothing. Nothing is tokenised on the device. |
| `NightCheckKeys` | A–D (either case) and 1–4 within the options, ↑/↓ clamped. A check is answerable only when Merc's latest reply holds a well-formed, complete `[Q]` and nothing is in flight. |
| `NightReplyLayout` | Builds a reply as the pieces it is drawn from: part marks, Markdown, source chips, example, key idea, open question, check, Your turn, or plain text. |
| `NightReplyCopy` | Every new line of UI text, held to the honest-copy register by `NightReplyCopyTests`. |

### 2. What it looks like (`NightReplyViews.swift`, `NightCheckCard.swift`, `NightPartStrip.swift`)

`MessageListView` draws `NightMessageRow` on the Mac in place of `MessageBubbleView`. The list's scroll logic is the same code, untouched: AUD-09's open-at-the-top hold, following, the lazy/eager stacks and Jump to latest.

**Merc's reply:**
- Type on the page: Lexend 15 on a line spacing of 5, in `ink`, the full 580 pt measure, with no bubble (`nightReplyMarkdown`).
- **Free chat:** a "Merc · AI tutor" line heads each reply, with a 20 pt badge that carries the live thinking state on the latest reply. It doesn't name the mode.
- **Lessons:** no label line, no avatar and no presence line.

**The student's turn:** a tinted card at the trailing edge, at most 465 pt wide (75% of the column), with a 6 pt bottom-trailing corner. A photo sits inside it. VoiceOver reads it as "You: …".

**Lesson parts:**
- **Part marks:** "02", a short lumen stroke, then the name as an `ink3` eyebrow. Each mark is a VoiceOver header ("Part 2, Tokenization"). Part 1 has no mark.
- **The part strip** pins to the top of the column as floating chrome:
  - "Part 3 · Check", then one segment per part so far: lit before the current part, lumen for the current one, hairline after it.
  - A dashed segment means "more may follow". It goes once the lesson is complete.
  - There is never a total and never a time.
  - Clicking a segment jumps to that part. VoiceOver reads the strip as one adjustable element: "Lesson parts so far: 3. Now reading part 3, Check."
- **"Now reading"** is the last part whose mark is within 48 pt of the reading area's top. At the end of the thread it is the last mark in view, so a short last part still counts.

**Blocks:**
- **`[EX]`:** a lit card with the token line when the example's own words give one, then the example verbatim in `ink2`.
- **`[KEY]`:** a lit card under the lumen wash, with the idea in New York 18. No "Saved to notebook" and no bookmark.
- **`[CHECK]`:** the Your turn card. A click moves to the composer, as the iPhone's callout does.
- **`[Q]`, the check:**
  - The stem in `title2`, then 44 pt rows with 26 pt letter discs.
  - **A pick sends nothing.** **Lock it in** grades on the device, says the result to VoiceOver, and calls the existing `onPick`, which sends `I picked B) …` exactly as today. Merc's real reply then streams below. There is no canned feedback and no "Next beat".
  - While the card has focus (Tab or Shift-Tab to it, or a click): A–D or 1–4 pick, ↑/↓ move the pick, Return locks it in. Typing in the composer never picks.
  - The eyebrow says "Check · your turn first", then "Check · answered", or plain "Check" on an older, unanswered card.
  - After lock-in the right answer turns green with a check, and a wrong pick turns red with a cross.
  - While a check waits, the composer says "Or answer in your own words…".
  - Escape no longer leaves the lesson over a pick that isn't locked in (`escapeLeaves(…, hasUncommittedPick:)`, through a preference).

**Sources:** a lit row with the title and "Cited by Merc · dl.acm.org".
- It opens `https://domain/path` (the domain alone for PR #46's form) only when `ReplyLinkPolicy` allows it. It then shows ↗, the pointing hand, and the help "Merc picked this source. Open it and check that it says what Merc says."
- A source with no address is an inert citation.
- Nothing is fetched for a chip.

**Your turn (free chat):**
- When it shows: on the latest completed reply in **Socratic**, when the closing question test passes.
- The question moves into a lit card under the wash, set in New York 18.
- The question's text is **selectable**, and Copy still copies the whole reply.

**The crisis guard:** a reply carrying 988 or 741741 is drawn as plain reading text, with no card, no chip, no serif and no wash. Its sources become the server's plain "Source: label (domain)". In a lesson its part marks stay, so the count stays true.

**Chrome and states:**
- **The composer:**
  - One floating-chrome field: the attach button (30 pt), the field, and a 30 pt `prominent` send circle that turns into stop.
  - Its edge is `fieldStroke`, which becomes the 2 pt focus ring (3 pt under Increase Contrast) while the field has focus.
  - The placeholder is drawn by the field itself in `ink3`. The Mac draws a `TextField` prompt in its own placeholder grey whatever style it is given, measured at **3.88:1**; ours measures **5.82:1** light and **6.84:1** dark.
  - Return, Shift-Return, ⌘V image paste, drop, the open panel and the character note are unchanged.
- **The mode switch in the toolbar:**
  - Night's: the current mode on an opaque `prominent` capsule (white on it 7.9:1) that slides, and a crossfade under Reduce Motion.
  - The same modes, rule (no switch mid-reply), help text and ⌥⌘1–3.
  - Each mode is a button VoiceOver reads as selected or not.
  - On macOS 26 the toolbar's glass is its track; on 14–25 and CI builds it sits on Night chrome.
- **Explain more, Quiz me, Jump to latest, Retry:**
  - Night chrome, with hover and focus rings.
  - Retry sits under the failure line, which is an `errorText` mark and the existing reason in reading text.
- **The empty chat:** Merc in his lamp, "Hi, I'm Merc", the mode's purpose, and its four real prompts as lit rows. A click sends, as before.
- **The lesson intro:** Merc waving, "Unit 1 · Lesson 1 of 4", the title in `display`, the existing line, and Continue (Return). There is no speech bubble.
- **The coach row:** Merc in his lamp beside his line, on the page.
- **The thread:** fades into the canvas over its last 18 pt.

### 3. DesignSystem

- `NightTokenChip`.
- `nightWash`: the KEY / Your turn wash, off under Increase Contrast.
- A public `Night.Tint`.
- `NightMercLamp` now takes `activity` and `antics`.

### 4. Snapshot harness (`ios/scripts/mac-snapshots.sh`) and DEBUG flags

| State | What it shows |
|---|---|
| `lesson` | The recorded first reply, held at its top (AUD-09). |
| `lesson-top` | `-NightScrollToPart 1`: the strip's jump to the start. |
| `lesson-cut` | `-LessonReplayCut`: AUD-29. The reply drops mid-stream and is kept, with its failure line and Retry. |
| `lesson-check` | `-NightScrollToPart 3 -NightCheckState picked`: the check with B picked and Lock it in. |
| `lesson-answered` | `-NightCheckState answered`: the same check locked in. It sends "I picked B) …" through the real path; the replay streams Merc's second reply, then the strip jumps back to the check. |
| `chat-socratic` | `-NightChatDemo YES`: the first three turns of a **real recorded Socratic session**, verbatim (`docs/evals/pacing-gate8-flag-off.json`, run 2, `socratic-1`), written to the in-memory store. The last reply cites a source with today's raw tag and closes on a question. |

`-NightCheckState` and `-NightScrollToPart` are read only in DEBUG builds. `-NightChatDemo` is compiled only into DEBUG builds.

## Tests

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-mac-ns-spm` | **1100 tests in 163 suites passed** (step 01: 1054 in 156) |
| New: `NightReplyTextTests.swift` | 6 suites, 43 tests. **Parts:** the three recorded replies' parts and names; breaks; whitespace; streaming counts; held-back dashes; fences; breaks inside blocks; naming at 32 characters; numbering across the thread; failed replies; "now reading". **Sources:** raw tags in every separator form; PR #46's four placements; label-only; address-only; path vs domain; streaming hold-back; look-alikes; code; byte-for-byte untouched prose; plain text under the crisis guard. **Your turn:** the recorded reply; statements, lists, headings, quotes and numbered items stay prose; closing emphasis; the 400-character limit; a trailing source; gating; the crisis guard in chat and lessons; whole-word 988/741741. **Token line:** the recorded example, curly quotes, every mismatch. **Check keys:** letters, digits, arrows, answerability, Escape with an uncommitted pick. **Copy:** every line against the register (`notebook`, `saved`, `part N of M`, `beat N`, minutes, `pinned`, `hint`, `verified`, …), with proof it catches the concept's own lines. |
| New: `NightReadingContrastTests` | Text on fallback chrome at its worst (`ink`, `ink2`, `ink3`, `accentText` ≥ 4.5:1, all four variants); white on `prominent`; the wrong pick's letter; resting letters; the correct disc's check (≥ 3:1); the picked row's edge against the row and the card (≥ 3:1); and proof that white on `accent` fails (4.47:1), the reason the picked disc is `prominent`. |
| Pixel checks on the shots (PIL) | The Your turn question measures 18.3:1 light and 15.6:1 dark. Its eyebrow is 6.0 and 7.4. The source caption is 6.24 and 6.55. The student card is 13.4 and 12.4. The composer placeholder is 5.82 and 6.84 (it was 3.88 before the fix). The "AI tutor" caption is 5.47. The part mark's name is 5.56 and 7.19. The picked letter is 8.17. |
| `ios/scripts/ios-source-diff.py` | **0 files with iOS-visible changes.** Every edited shared file reports `same`. |
| `ios/scripts/ci-compat-lint.py` | 0 findings. |
| macOS Debug build (`/private/tmp/merc-mac-ns-dd`) | BUILD SUCCEEDED |
| `ios/scripts/ios-unchanged-check.sh` (recording forced off, Audit 16PM) | **"iOS unchanged":** 11 pass, 12 stale. The same 23 results and the same pixel hashes for every stale render as the baseline; `__Snapshots__` untouched |
| iOS `xcodebuild test`, CI's flags, Audit 16PM | **TEST SUCCEEDED:** 3 XCTest unit and 25 UI tests, 0 failures, plus the Swift Testing cases (3 tests in 2 suites). Snapshot, performance and App Store screenshot tests skipped, as CI does |

## Screenshots (`shots/02/`)

All are from a renamed, ad hoc signed copy (`com.mayoailiteracy.mercurius.native.macns2`), run with `ACTIVATE=NO` and off screen. They are full resolution (2×), saved as JPEG at quality 90. The PNGs are in `/private/tmp/merc-mac-ns-shots/02-final2/`.

- **Lesson** (replay content): `lesson-intro`, `lesson`, `lesson-cut`, `lesson-check`, `lesson-answered`, each in light, dark, 700 pt and 700 pt dark.
- **Chat:** `chat` (empty), `chat-socratic` (the recorded thread: source chip, Your turn, Explain more, Quiz me) and `chat-failed` (the failure line and Retry), at the same four sizes, and `chat-typing` (two typed lines in the composer; the text starts where the placeholder did) in light.
- `lesson-top` was taken and looked at, but isn't kept. With the coach row collapsed (see Decisions 8), the strip's jump to part 1 gives the same picture as `lesson`.
- **Accessibility:** `lesson-check` and `chat-socratic` under Increase Contrast (`-hc`, `-dark-hc`), Reduce Transparency (`-rt`, `-dark-rt`) and the macOS 14–25 / CI fallback (`-noglass`, `-dark-noglass`); `lesson-check-rm` (Reduce Motion).

**Looked at, and fixed:**
- The strip said "Part 2" while part 1 filled the screen. The top-third rule became "within 48 pt of the top", plus the end-of-thread rule.
- The composer drew two rings while focused; now there is one.
- The placeholder measured 3.88:1; it is now drawn in `ink3`.
- A contrast test caught the picked disc's fill at 1.7:1 against its row in dark mode. That fill is decoration: the state is the 2 pt `accentText` edge (≥ 3:1) and the white letter (8.2:1), and the test now checks those.

## Decisions and deviations, and why

1. **Your turn is Socratic only** (`NightYourTurn.modes`). The step asked for "the closing question of a Socratic reply"; SPEC §5.4 named no mode. Debate's "Your move — …?" and Discussion's questions stay prose. Widening it is one set.
2. **The mode switch is Night's own, not the native segmented picker.** The step asked for it "in Night style in the toolbar", and SPEC §5.4 had kept the system control. It keeps the picker's behaviour, help and shortcuts. With Full Keyboard Access each mode is a button in the Tab loop. Arrow keys don't move between modes as in a segmented control; ⌥⌘1–3 does.
3. **The picked disc is `prominent`, not `accent`** (SPEC §5.3.3), so its white letter is 7.9:1 rather than 4.47:1.
4. **A source opens its path when the raw tag gives one**, as SPEC §5.4 says, and the chip shows the domain only. Once PR #46 is live the server sends no path, so it opens the domain. The help text tells the student to check it says what Merc says, because Merc chose the citation and paths have been invented (AUD-38).
5. **The part strip sits above the scroll view**, not in a `safeAreaInset`, so the list's coordinates (AUD-09's hold, the pill, the coach rule) don't move. Content clips under the strip rather than passing beneath it.
6. **VoiceOver walks a settled chat reply block by block**, as lessons already did (AUD-23). A source chip is a button and must stay one, so the reply can't be read as a single element.
7. **Only the Your turn question is selectable.** Making all reply text selectable could take right-click (Copy and Report) from the reply. Copy still copies the whole reply.
8. **The coach row still steps aside while the composer has focus** (the existing AUD-08 rule). On the Mac the composer takes focus as a lesson opens, so the row is usually collapsed. The rule was made for a phone's keyboard; whether the Mac should keep it is a founder question, and it wasn't changed here.

## Skipped, and why

- **The mode explainer sheet, the unit check, lesson complete, the gate, the crisis view:** later steps (SPEC §8.1). They take the palette only for now. The crisis view stays palette-only on purpose.
- **Glass on screen:** the harness photographs glass dark or missing, and runs never bring a window to the front. The macOS 26 composer, part strip, chips and the toolbar's mode switch on glass still need one look on screen. The `-noglass` fallback and the opaque Reduce Transparency and Increase Contrast versions are photographed.
- **Focus rings and keyboard on screen:** the shots are of an inactive window, so the check card's ring, Tab/Shift-Tab between the composer and the check, A–D, Return to lock in, and Escape with a pick each need a check on screen. The rules are unit-tested.

## Founder's app

- PID 98503 ran before and after every run, and nothing was killed by name.
- `/private/tmp/merc-mac-dd` was never read or written.
- The frontmost-app watcher saw only Claude in front in every run; the copy never came forward.
- The copy's container `~/Library/Containers/com.mayoailiteracy.mercurius.native.macns2` holds test data only.
