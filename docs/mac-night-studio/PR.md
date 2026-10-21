# Mercurius for Mac in Night Studio

> **Stacked on #47** (`feat/mac-app-2026-10`, the native Mac app), which is itself stacked on #43. This PR's base is `feat/mac-app-2026-10`, so the diff shows only the Night Studio work. **After #47 merges, retarget this PR to its new base** (`main`, once #43 and #47 are in).

The founder asked: "make the mac app use the night studio design". This PR does that for the native Mac app, and only for it. **The iPhone and iPad app doesn't change by a pixel** (the proof is below).

## What Night Studio is on the Mac

Night Studio is direction A of October's UI exploration: an ink canvas with soft pools of indigo light, lit cards that sit on it, Lexend type with a few serif moments, and Merc in a lamp of light. On the Mac it becomes:

- **The canvas:** an ink gradient with two light pools (stars in dark mode only). Content sits on lit cards: one soft shadow in light mode, none in dark, a solid hairline under Increase Contrast.
- **Type:** Lexend 30/24/19/15/14/12 on the Mac's own ramp. New York (serif) only for the things to keep or answer: Key idea, Your turn, Think it through, the complete card's key ideas. SF Mono for tokens.
- **Today:** a calm greeting, then **Up next**, the app's only gradient card, with Merc inside it. Below it, **This week** (a rhythm ring and the week's lesson days) and **Think it through** (one of the current mode's real starter prompts, opened in a new chat and not sent).
- **The path:** one page per unit. A lit cover, then the lessons on a thread of light. Numbers, not padlocks: "Opens after 1.2" says when a lesson opens. The current lesson is a card with its objective and the page's one prominent button.
- **A lesson:** Merc's reply is type on the page, not a bubble. Its parts carry marks ("02 —— Tokenization"), and a floating strip says "Part 3 · Check". There is never a total, because nobody knows how many parts a streaming reply will have. Examples are cards with a token line, key ideas are serif cards, and the check is answered with **Lock it in**.
- **Lesson complete:** a card over the dimmed lesson. Merc celebrates inside it. The headline is a credential where the objective allows it ("You can now explain tokenization and next-token prediction."), and the card says where that came from: "Merc marked this lesson complete from your answers." Then the lesson's key ideas, the week, the next stop, and "Done for now" beside "Start Lesson 1.2".
- **Chat:** a Night mode switch in the toolbar. Merc's sources become "Cited by Merc" chips, and in Socratic mode his closing question becomes the **Your turn** card. Explain more and Quiz me are chips.
- **The gate, the unit check, Settings and the sheets:** the same flows in Night's type, buttons and lit rows. **The crisis view stays calm and unbranded:** palette only, system type, no Merc, no light, no glass, no motion.
- **Chrome:** the system's own window, sidebar, toolbar and menus. They are Liquid Glass on macOS 26, with an opaque Night fallback on macOS 14–25 and under Reduce Transparency.

## Screenshots

Taken off screen by the app's DEBUG harness, from a renamed copy of the Debug build. The copy is never activated, so windows are drawn **inactive**: grey traffic lights and a dimmed title. Off screen, Liquid Glass is drawn without its backdrop. Light and dark, 1280 × 800 pt unless noted.

| | |
|---|---|
| ![Today](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/01-today.jpg?raw=true) **Today**, a week in: Up next, This week (lesson days), Think it through | ![Today, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/02-today-dark.jpg?raw=true) **Today** (dark) |
| ![Path](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/03-path.jpg?raw=true) **The path**: Unit 1, two lessons done, 1.3 "You're here" | ![Path, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/04-path-dark.jpg?raw=true) **The path** (dark) |
| ![Lesson check](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/05-lesson-check.jpg?raw=true) **A lesson's check**: "Part 3 · Check", B picked, Lock it in | ![Lesson, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/06-lesson-dark.jpg?raw=true) **A lesson** (dark): a part mark, the example's token line, the key idea |
| ![Lesson complete](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/07-lesson-complete.jpg?raw=true) **Lesson complete**: the credential, its source, the key idea, the week | ![Lesson complete, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/08-lesson-complete-dark.jpg?raw=true) **Lesson complete** (dark) |
| ![Chat](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/09-chat.jpg?raw=true) **Socratic chat**: a "Cited by Merc" chip, the Your turn card, "Your answer…" | ![Chat at 700 pt, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/10-chat-narrow-dark.jpg?raw=true) **700 pt wide** (dark): the mode switch folds into a menu |
| ![Consent](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/11-gate-consent.jpg?raw=true) **The consent step**: the wording unchanged, the checkbox leading its sentence | ![Meet Merc, dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/12-gate-meet-dark.jpg?raw=true) **First run** (dark), before any network call |

**Next to the concept.** Each row shows today's Mac app (#47), then Night Studio on the Mac, then the DesignLab concept (an iPhone). The differences from the concept are the honesty fixes listed below.

![Today compared](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/13-compare-today.jpg?raw=true)
![Lesson check compared](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/14-compare-lesson-check.jpg?raw=true)
![Chat compared](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/mac-night-studio/docs/mac-night-studio/key-shots/15-compare-chat.jpg?raw=true)

## How it's built, and why iOS can't change

The full reasoning is in `docs/mac-night-studio/ARCHITECTURE.md`, and the screen-by-screen design is in `SPEC.md`. There are four layers, and none of them adds a runtime theme check on an iOS path:

1. **Tokens, chosen at compile time.** Under `#if os(macOS)`, `BrandColor` reads Night's palette, and `BrandFont` reads Night's Lexend roles. The ~460 semantic colour uses in the shared views re-colour on the Mac with no call-site edits. The `#else` branch is today's code, untouched.
2. **Night components** in `DesignSystem/Sources/Night/`. Every file is wrapped in `#if os(macOS)`:
   - the palette, with Increase Contrast values;
   - the canvas, lit surfaces and guarded glass chrome;
   - the buttons, eyebrow, rhythm ring and answer row;
   - `@NightSettings` (Increase Contrast, Reduce Transparency, Reduce Motion);
   - `NightTypography`.
3. **Shared views change only inside `#if os(macOS)`.** This includes postfix `#if` in modifier chains. The logic files are not edited: `AppEntryView`, `ConsentGate`, `SettingsViewModel`, `ChatViewModel`, `UnitTestViewModel`, and the shell's erase and gate hooks.
4. **Mac-only views** under `*/Sources/Mac/`: Today, the unit page, the reply renderer, the check, the complete card, the unit check, and the mode and quiz sheets.

**The proof that iOS is unchanged.** Every step ran all four checks:

| Check | Result at the head of this branch |
|---|---|
| `ios/scripts/ios-source-diff.py feat/mac-app-2026-10`: reduces every changed Swift file to what an iOS build compiles (`os()` and `canImport` resolved; comments and whitespace dropped) and compares it with the base | **0 files with iOS-visible changes.** Every new file is `new/mac` |
| `ios/scripts/ios-unchanged-check.sh`: the 23 `ViewSnapshotTests` with recording forced off, compared with `docs/mac-night-studio/ios-snapshot-baseline.txt` (recorded at the base) | **"iOS unchanged: the same 23 results and the same pixels for every stale render as the baseline"**: 11 pass, and 12 were already stale before this branch (re-recording them is the founder's job). `__Snapshots__` is untouched |
| iOS `xcodebuild test` with CI's flags, on an iPhone 16 Pro Max (iOS 26.4) | **TEST SUCCEEDED**: 3 XCTest, 3 Swift Testing and 25 UI tests, 0 failures, no retries |
| `swift test`, every package | **1142 tests in 171 suites passed** (1026 at the base) |

Not in the diff: `project.yml`, `Package.swift`, assets, fonts, `Info.plist`, the pbxproj, the iOS app shell, the server and the web widgets.

## Accessibility

**Contrast.** Every Night text token was checked on every surface it can sit on, in four appearances. That includes the canvas under each light pool at its peak. `NightContrastTests` (Swift) and `docs/mac-night-studio/night_contrast.py` hold the same pairs to the same minimums. The worst case for each token:

| Text token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast |
|---|---|---|---|---|
| `ink` (body) | 14.18 | 12.93 | 17.67 | 16.28 |
| `ink2` (secondary) | 6.66 | 7.80 | 11.31 | 12.47 |
| `ink3` (captions) | 4.83 | 5.45 | 9.29 | 9.90 |
| `accentText` | 4.87 | 7.21 | 8.79 | 10.92 |
| `successText` | 5.53 | 9.35 | 8.06 | 12.70 |
| `errorText` | 5.01 | 7.57 | 7.35 | 11.25 |
| White on `prominent` (the one filled button) | 7.90 | 7.90 | 9.93 | 9.93 |

- **Minimums:** 4.5:1 for text everywhere, 7:1 under Increase Contrast, and 3:1 for non-text marks (WCAG 1.4.11).
- **Tinted uses are tested too:** picked, correct and wrong answer rows and their letters; the student's turn; the key-idea wash; token chips; each hero gradient stop, with and without the lamp; the fallback chrome; the complete card's own canvas; the path's nodes; the written-answer well.
- **The ink3 change:** the concept's `ink3` failed where its two pools overlapped (4.08 and 3.43), so the token moved.

**The accessibility settings change the render** (shown in the step notes' variant shots):
- **Increase Contrast:** a flat canvas with no pools or stars, solid hairlines, stroked answer rows, and focus rings 3 pt wide.
- **Reduce Transparency:** opaque chrome, an opaque sidebar, and an opaque scrim behind the complete card.
- **Reduce Motion:** every transition becomes one crossfade. Merc's idle life stops, the path's halo is still, and the mode switch crossfades in place.

Each comes from the system setting or from a DEBUG launch flag for the screenshot harness.

**VoiceOver:** every custom control has a label. Examples:
- the week card: its count and the days a lesson was finished, in one sentence (the ring itself is decoration);
- each path row: "Lesson 1.3, you're here: …";
- the check's rows, with "Picked, not locked in";
- source chips: "Source Merc cited: …";
- the part strip, which is adjustable.

Decoration (the canvas, stars, the lamp and big numerals) is hidden.

**Keyboard:**
- Return takes each screen's main action, and Escape leaves when nothing would be lost.
- While a lesson's check waits, the lesson's keys go to it: A–D or 1–4 pick, ↑/↓ move, Return locks in.
- A unit check keeps its keys: A–D answer and move on, ⌘Return submits.
- A typed letter in a lesson goes into the composer when no check waits. ⌘L (Chat ▸ Write a Reply) focuses it.
- ⌘1–⌘4 and ⌥⌘1–⌥⌘3 work as in #47.

## Honest copy

The concept promised things the app doesn't do. On the Mac, every line is held by tests (`NightCopyTests`, `NightReplyCopyTests`, `NightCompleteCopyTests`) to a register that bans "notebook", "saved", part totals, time estimates, "previewable" and "never reset", and the tests are shown to catch the concept's own lines.

| Concept | On the Mac | Why |
|---|---|---|
| "Saved to notebook" | (gone) | There is no notebook |
| "Beat 2 of 6" | "Part 3 · Check" | A streaming reply's total isn't known; the count is parts so far |
| "Rest days never reset your progress" | "4 days running. One lesson or chat a day keeps it going." | The daily streak does reset |
| "pinned source" | "Cited by Merc · dl.acm.org", which opens the domain only | Merc picks the citation; nobody verified it. Model-written paths are often invented (AUD-38) |
| "about 6 min" | (gone) | Not measured |
| "Every lesson is previewable" / padlocks | "Opens after 1.2" | What the gating actually does |
| "Nailed it!" | "You can now explain …" (only for "Understand …" objectives, else "Lesson complete"), with "Merc marked this lesson complete from your answers." | The credential is earned by the server's proficiency judgement, and the card says so |
| "Merc" and "Mercurius" for the tutor | "Merc" everywhere on the Mac ("Ask Merc…", "graded by Merc") | "Mercurius" is the app's name |

The reply parser only turns the server's full citation shapes into chips. Prose that says "Source:" stays prose. Under the crisis guard, the rest of a thread that carried 988 or 741741 is plain text, with no cards, chips or Your turn.

## Out of scope

- **The other directions' grafts:** "Sure / Not sure", the notebook, the hint ladder, the share-card redesign and "In your words". The founder asked for Night Studio itself.
- **The meaning-sky signature:** it needs new authored content (roadmap B2).
- **Any server, prompt or web change.** The parser reads both the server's current raw tags and PR #46's plain forms.
- **iOS.** It keeps today's look.

**How iOS could adopt Night later:**
1. Lift the `#if os(macOS)` guard on the Night files (one line each). They are already contrast-tested.
2. Point the UIKit branch of `BrandColor.adaptive` at the same Night mapping (one function), and `BrandFont`'s iOS branch at Lexend `relativeTo:`.
3. Move each view's Mac Night branch to shared code, one screen at a time, swapping fixed ramp sizes for Dynamic Type.

An A/B against today's look would need one launch-time palette switch in `adaptive`, not 460 call sites.

## Tests

| Check | Result |
|---|---|
| `swift test` | 1142 tests in 171 suites passed (1026 at the base): contrast in four appearances, the palette mapping, honest copy, the lesson's parts, sources and parser regressions (with recorded production replies), the closing question, the crisis guard and the crisis view's no-decoration pin, keyboard routing, the unit page, Today, the complete card, the unit check, typography |
| iOS proof | Above: 0 iOS-visible changes, identical snapshot pixels, the iOS suite green |
| macOS Debug build | BUILD SUCCEEDED |
| macOS Release, unsigned, universal (CI's command) | BUILD SUCCEEDED (`x86_64 arm64`) |
| No network before consent | 0 requests to a logging server in the gated states (`VERIFY.md` §5) |
| Screenshots | 80 states in the verification pass, and 64 more after the review fixes, each checked against the harness's size and blank-picture checks |

## CI notes

CI builds with Xcode 16.2 / Swift 6.0.3 on macOS 14. This was built locally with Xcode 26.4 / Swift 6.3, so:
- **Liquid Glass and the macOS 26 scroll-edge style** sit inside `#if compiler(>=6.2)` and `if #available(macOS 26.0, *)`, with a material or opaque fallback in both the `else` and the `#else`.
- **APIs newer than macOS 14** are behind `#available(macOS 15.0, *)`. These are `toolbar(removing: .title)` and `toolbarBackgroundVisibility`, both in the macOS 15 SDK that Xcode 16.2 ships.
- **No Swift 6.1+ syntax:** no trailing commas in argument lists, and no Double·CGFloat trig mixing.
- **`ios/scripts/ci-compat-lint.py`** finds 0 problems, and `docs/mac-night-studio/ci-probe/run.sh` passes every check, including a `#if compiler(>=99)` body skipped unparsed, as 6.0.3 skips `>=6.2`.
- **What only CI can prove:** that Xcode 16.2 compiles the branch. The `spm`, `xcode` and `mac` jobs are that proof once this is pushed.

**For a real screen** (the harness draws inactive windows off screen):
- the Liquid Glass chrome;
- the dark sidebar beside the ink canvas;
- the complete card's "Done for now" and Share in dark mode;
- the lesson's keyboard routing (A–D and Return on a waiting check, typing into the composer, ⌘L);
- focus rings with Full Keyboard Access.

## Notes per step

`docs/mac-night-studio/`:
- `SPEC.md`, `ARCHITECTURE.md`;
- `01-tokens-shell-today.md`, `02-lesson-chat.md`, `03-rest.md`;
- `VERIFY.md`, `04-review-fixes.md`;
- `key-shots/`, `compare/`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
