# Step 04: the review's findings, fixed

**Branch:** `feat/mac-night-studio`, stacked on `feat/mac-app-2026-10` (PR #47). Not pushed.
**Input:** the review of `b0214e0`/`c659d07` (24 findings: 3 high, 10 medium, 11 low), its two verdicts and VERIFY.md's own notes.
**Result:** all 24 were real. 23 are fixed as the review proposed or close to it; one (the composer's focus) is fixed by a different mechanism, explained below. None was rejected. Mac only: `ios-source-diff.py` reports **0 files with iOS-visible changes**, and the snapshot comparison matches the baseline pixel for pixel.

## What changed, finding by finding

### Layout seams

| # | Finding | Fix |
|---|---|---|
| H1 | The complete card ran into the composer; clipped lesson words showed around it | The composer steps away while the card is up (`opacity 0`), the lesson behind it blurs 8 pt and is disabled, and the scrim is 90% (opaque under Reduce Transparency and Increase Contrast). The card is centred in the whole lesson with nothing under it. `lesson-complete*` at 1280 and 700 pt: no overlap, one calm field |
| H2 | At 700 pt the chat toolbar overflowed and hid New Chat | Below 860 pt of detail width the mode switch is a native pop-up menu ("Socratic ▾", `NightModeMenu`) and the "Chat" title steps aside (macOS 15+, `toolbar(removing: .title)` behind `#available`). Progress, Explain More and New Chat all show at 700 pt (`chat-socratic-min*`, `chat-debate-min*`) |
| M3 | The part strip sliced the reading column | The thread's mask now fades its first 22 pt under the strip (and the content has 12 pt more top margin), so text passes under the strip and fades instead of being cut (`lesson-check*`) |
| M4 | At 700 pt the lesson got an opaque grey title bar | The lesson's title bar shows the canvas (`nightCanvasTitleBar()`: the window toolbar's background hidden on macOS 15+, painted `canvasTop` on 14), and its reader gets `.scrollEdgeEffectStyle(.soft, for: .top)` behind `#if compiler(>=6.2)` + `#available(macOS 26)`. Measured on `lesson-min-dark`: the band is `#151841`, was `#1B1A1F` |
| L10 | The gate had a neutral title-bar strip | The same `nightCanvasTitleBar()` on the gate: the ink runs to the top (`gate-meet-dark`: `#151841`). "Welcome to Mercurius" stays the window title |
| L11 | The consent checkbox trailed its sentence, in a narrower box | Mac only: `Toggle(isOn:) { sentence }.toggleStyle(.checkbox)`, so the box leads and the whole sentence is the click target, and the pinned controls use the step's column (`GatePinnedCTA`, Mac branch), so the row lines up with the disclosure rows. Wording, binding, identifier and `ConsentGate.currentVersion` untouched. The Agree button's VoiceOver hint says "Tick the box above" on the Mac |
| L17 | Progress took the leading slot and vanished in lessons | One trailing `.primaryAction` Progress button on the shell's detail column, on every screen past the gate (lessons and the unit check included). The per-screen leading items and the chat's `headerAccessory` are gone; the leading slot is a lesson's or check's way back only |

### Coherence and copy

| # | Finding | Fix |
|---|---|---|
| M6 | "Merc" and "Mercurius" side by side | Mac-only overrides, iOS untouched: `NightModeCopy.purpose` ("Merc asks questions back…", "Merc argues back. You take a side, he pushes the other.", "Merc treats you as an intellectual peer…") in the empty chat, the mode explainer and Today; the composer says "Ask Merc…", or "Your answer…" when Merc's last reply ends on the Your turn card; "graded by Merc"; VoiceOver "Merc is replying" / "Merc replied". "Mercurius" stays the app's name (window title, Settings, consent, Help) |
| M9 | "Continue Lesson 3" on Today, "Start Lesson 1.3" on the path, "Start Lesson 2" on the card | One predicate (`MacNightCopy.resumes`: opened last or in progress, `HomeState`'s rule) and one label, the path's code: Today "Continue · Lesson 1.3" / "Continue Lesson 1.3", the unit page "Continue Lesson 1.3", the complete card "Lesson 1.1 · Complete", "Up next · Lesson 1.2", "Start Lesson 1.2", the lesson's subtitle "Unit 1 · Lesson 1.1". "2 of 4" is the unit meter's caption only. A test pins Today and the path to the same word for the seeded week |
| L12 | "Check" three times in 140 pt | The card's eyebrow is "Your turn first" ("Answered" once locked in); the strip and the part mark already say Check |
| L13 | Today said "anything more is a bonus" twice; Think it through had an empty block | At the goal the greeting's line is "Your next lesson is there whenever you want it."; the week card keeps "Goal met. Anything more is a bonus." The cards are top-aligned at their own heights, and Think it through has "Ask Merc →" on its eyebrow row instead of a lone arrow at the foot |
| L14 | "Merc · AI tutor" over every reply, with a muddy 20 pt bust | The label heads the thread's first reply only, as type (no bust): the bubble-less reply already says who is speaking |
| L15 | The path's status column used three hues | Every status ("Done", "Opens after 1.3", "Opens after 1.4", "Mastered") is `ink3`; `accentText` is "You're here" only |
| L16 | Straight quotes drawn as inch marks | `NightTypography.curlQuotes` (DesignSystem/Night): curly quotes in Merc's prose, the cards, the check's stem and options, the complete card's key ideas, and the curriculum's lines on Today and the path. Fenced code, `inline code` and Markdown link addresses stay byte for byte; the student's own turns are verbatim. Copy still copies the reply as it came |

### Clarity

| # | Finding | Fix |
|---|---|---|
| M5 | Two week dots above "4 days running" | The streak line moved under the greeting (it counts lesson **or chat** days); the dots are captioned "Lesson days". The streak's wording is unchanged and nothing says it doesn't reset. VoiceOver's week card no longer reads the streak; the header does |
| M7 | The graded unit check still opened on "Answer all 5 questions" | Once graded, the score ("You got 4 of 5 correct.") and the next step (⌘Return) replace the instructions at the top, the page scrolls back to its top, and the button repeats at the foot. Every row keeps its letter (a graded row's letter in its grade's colour, in a ring of it) with one trailing mark: a check (filled when it was the pick) or a cross |
| M8 | The composer kept the keyboard (and its ring) while a check waited | A lesson no longer focuses its composer when it opens or after a reply. **While a check waits, the lesson's keys go to the check** — A–D / 1–4 pick, ↑/↓ move, Return locks in — unless the composer (or any text field, or the sidebar's list) has the keyboard, and the check wears the focus ring to say so. With no check waiting, a printable key typed in the lesson focuses the composer and goes into it (type to focus). **Chat ▸ Write a Reply (⌘L)** focuses the composer any time; Tab and a click still do |

**Why M8 isn't SwiftUI focus.** The review asked for focus on the check card. I tried five ways to move SwiftUI focus there (the card's own `@FocusState`, a list-owned `FocusState<UUID?>`, synchronous and delayed sets, always-focusable, and with the context menu, the row's `equatable()`, the scroll mask, the blur and the composer each removed in turn). The window's first responder moved to the hosting view, but the card never became focused (logged each time). The unit check's cards do take focus in the same window, so it is something about a card deep in the lesson's thread that I didn't pin down. Instead a small router (`NightCheckKeyRouter`) takes the lesson's keys to the waiting check through a local key monitor, which doesn't depend on SwiftUI focus; the card's own focus path (Tab, click) is kept as well. The routing is unit-tested (key mapping, register and unregister); it can't be photographed with keys, because the harness's window is never key. **Worth a look on screen** (below).

### The reply parser (NightReplyText.swift)

| # | Finding | Fix |
|---|---|---|
| H18 | Prose with "Source:" became a fake "Cited by Merc" chip and was deleted | Only the server's full shapes count: a raw tag; `(Source: label[, domain])`; and `Source: label (domain)` as a whole line or closing a line after a sentence, with no "?" and no further sentence in the label. The label-only rules (a line starting "Source: ", a trailing "Source: label") are gone: a label-only form stays prose, as the server's own `REWRITTEN_SOURCE_RE` treats it. Mid-stream, a line's plain form waits for the line to end, so no chip grows and vanishes. Tests: PR #46's line-context rewrite followed by more text, a Source/Evidence/Context checklist, "**Who made it?** Source: …", and a closing "Source: who benefits…?" question that stays the Your turn card |
| M19 | Link-wrapped tags left "(http://…)"; tags inside [EX]/[KEY]/[CHECK]/[Q] showed raw | A "(" right after a tag's "]" that closes within 300 characters, holds an address and no space (the server's `LINK_DEST_RE`) goes with the tag, and its host fills in a missing domain; mid-stream the "(…" is held until its ")". A tag that is a sentence's subject ("[SOURCE: Gender Shades — …](…) backs your bias data") leaves its title in the sentence. Cards' text and a check's question are parsed too (their chips follow the card; the options, which "I picked B) …" sends, are untouched), as are the complete card's key-idea recap and the crisis guard's plain text. Both recorded production replies (debate eval :1108 and :1148) and the server's `[EX][SOURCE: …] shows the gap.[/EX]` are fixtures |
| M20 | A follow-up question in a crisis thread became a "Your turn" card | The guard covers the thread: from the first reply carrying 988 or 741741, it and every later reply are plain text (no Your turn, no chips, no cards, no serif), until a new thread (`NightCrisisGuard.guardedReplies`, cached per thread change). Test: a crisis reply, then a follow-up question without the numbers |
| L21 | Source chips opened the model's invented path | The chip opens `https://<domain>` only, as the server's rewrite keeps the domain only (AUD-38). SPEC §5.4 updated |

### Tests, motion and dead code

| # | Finding | Fix |
|---|---|---|
| L22 | No test pinned the crisis view | `NightCrisisViewTests` (AppFeature): `CrisisSupportView.swift` and `MacCrisisNumbers` use none of Night's decoration, Merc, gradients or motion; the close button keeps `.environment(\.brandButtonClassic, true)` and `BrandButton` still reads it; the Quiz sheet and the unit check draw it on a flat canvas, and the unit check's support branch is the view alone |
| L23 | The mode switch's capsule still slid under Reduce Motion | Under Reduce Motion each segment draws its own capsule with an opacity transition (no `matchedGeometryEffect`), so the selection crossfades in place |
| L24 | Dead code | `NightIconButton` and `Night.Space.stack` deleted (SPEC's three mentions now describe the built circles), `MacTodayView.streakHeadline` and its test deleted, the unreachable Mac modifiers on `continueButton` removed |

## Not changed, and why

- **The complete card as a window sheet** (H1's first suggestion). The overlay fix removes the collision and keeps the card's own canvas, its arrival sequence, Return/Escape and the click on the backdrop; a macOS 26 sheet would add its own glass frame around the card.
- **The week dots for chat days** (M5's first suggestion). There is no per-day chat history to draw them from; the streak moved instead.
- **The dark sidebar's grey, the near-black "Done for now"/Share pills in dark mode, and focus rings with Full Keyboard Access.** The verdict says these need a real macOS 26 screen; off-screen pictures draw glass without its backdrop. Listed for the founder.

## Tests

| Check | Result |
|---|---|
| `swift test` (incremental scratch path, then again from an empty one) | **1142 tests in 171 suites passed** (step 03: 1128 in 168; one test, `streakHeadline`'s, went with the dead code). New: the parser regressions, the thread-wide crisis guard, the key routing and type-to-focus key rules, `NightCrisisViewTests`, `NightTypographyTests`, Today/path agreement; updated: copy, subtitle, the disc contrast pairs (`successText` letter on the correct row ≥ 4.5:1 in all four variants) |
| `ios/scripts/ios-source-diff.py feat/mac-app-2026-10` | **0 files with iOS-visible changes** (`OnboardingSteps.swift`, `UnitTestView.swift`, `ChatView.swift`, `ChatInputBar.swift`, `CurriculumLessonView.swift`, `EmptyChatView.swift` all `same`; the new test files `new/mac`) |
| `ios/scripts/ios-unchanged-check.sh` (recording forced off, Audit 16PM) | **"iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline"**: 11 pass, 12 already stale |
| iOS `xcodebuild test`, CI's flags, Audit 16PM | **TEST SUCCEEDED**: 3 XCTest unit, 3 Swift Testing, 25 UI, 0 failures, no retries. One UI test (`testDeleteFailureShowsTheOldIdBeforeADeviceOnlyReset`) skipped itself because my `/api/mode` stub was still on :3000; with the stub stopped it ran alone and passed |
| `ci-compat-lint.py`, `ci-probe/run.sh` | 0 findings; every probe check ok |
| Mac Debug build, Mac Release (unsigned, universal) | BUILD SUCCEEDED |

## Screenshots

64 full-resolution PNGs at `/private/tmp/merc-mac-ns-shots/fix/` (not committed), from a renamed, ad hoc signed copy (`com.mayoailiteracy.mercurius.native.macns5`) with `ACTIVATE=NO`: lesson complete, the Socratic thread, the lesson check, Debate and Discussion (through a local `POST /api/mode` stub), Today with a week, the path, the unit check, the lesson and the gate at 1280 and 700 pt, light and dark; Today (fresh), consent, age, crisis, the lesson intro and the seeded thread; the lesson check, Today and the chat under Increase Contrast and Reduce Transparency.

**Committed:**
- `key-shots/`: 12 screens (Today, path, lesson, complete, chat, gate; light and dark; the chat at 700 pt) and the 3 concept comparisons, 2000 px wide at most, quality 82, 2.0 MB in all.
- `compare/`: the six side-by-sides re-made from the new shots (2000 px wide).

**The founder's app:** PID 98503 ran before and after every batch; nothing was killed by name; `/private/tmp/merc-mac-dd` was never touched; the frontmost-app watcher saw only Safari or Chrome, never the copy.

## For the founder

On a real screen, please check:
1. In a lesson whose reply ends in a check: A–D and Return answer it without clicking, and the check wears the ring; a letter typed when no check waits goes into the composer; ⌘L focuses the composer.
2. The dark sidebar: if it stays neutral grey beside the ink canvas on macOS 26, the opaque Night sidebar can be used in dark mode (one line).
3. The complete card's "Done for now" and Share in dark mode (glass), and focus rings with Full Keyboard Access.
