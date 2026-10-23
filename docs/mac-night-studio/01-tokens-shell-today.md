# Step 01: tokens, the shell and Today

**Branch:** `feat/mac-night-studio`, stacked on `feat/mac-app-2026-10` (PR #47). Not pushed.
**Built from:** `SPEC.md` (token values, screens, copy) and `ARCHITECTURE.md` (the mechanism and the iOS proofs).
**Commits:**
- `3b07035`: the tokens, type, surfaces and components; `BrandColor` reads Night on the Mac.
- `baf5611`: the window chrome, the sidebar and Today.
- `docs` commit: this note and `shots/01/`.

## What changed

### 1. The tokens and the theme mechanism (`DesignSystem/Sources/Night/`, all `#if os(macOS)`)

| File | What it holds |
|---|---|
| `NightPalette.swift` | Every token's raw value in four appearances (light, dark, and both under Increase Contrast), as `SPEC.md` §2.1 sets them. It also holds the pool alphas, the tint alphas and the rule that picks a variant. The tests read this file. |
| `Night.swift` | `Night.*` colours, built as `NSColor(name:dynamicProvider:)` from the palette. Also `Night.Radius`, `Night.Space`, `Night.Motion` and the DEBUG overrides. `NightAccessibility` and the `@NightSettings` property wrapper live here too. |
| `NightType.swift` | The Mac's type ramp as `NightType.Role` (Lexend 30/24/19/15/14/12, New York "keep", SF Mono "machine"). `.nightFont(_:)` applies the face, the tracking and the line spacing together. |
| `NightSurfaces.swift` | `NightCanvas` (the gradient, the two light pools at the spec's alphas, a still star field in dark mode, flat under HC), `nightLit`, `NightHeroSurface`, `nightChrome`, `nightHover`, `nightFocusRing`, plus the window helpers `nightToolbarBackground`, `nightSidebarBackground` and `nightExtendsUnderSidebar`. `nightLit` gives one shadow in light mode only and a solid hairline under HC. `NightHeroSurface` is the only gradient fill. `nightChrome` draws glass, a material fallback, or an opaque surface under Reduce Transparency or HC. |
| `NightComponents.swift` | `NightEyebrow`, and the Primary, Secondary, OnHero, Text and Card button styles. `NightPrimaryButton`, `NightSecondaryButton`, `NightTextButton` and `NightIconButton` are the same styles with focus rings attached. Also `NightButtonLabel`, `NightRhythmRing`, `NightMercLamp` and `NightFlow`. |

How the colours switch:
- On the Mac, `BrandColor` maps to Night in `Color+Brand.swift`, inside `#if os(macOS)`: background, surface, surfaceElevated, text, textSecondary, accentText, border, success, successText, error and errorText.
- Every shared view the Mac hosts takes the palette with no edits. That includes chat, lesson, path, Progress, the gate and the crisis view.
- The fixed hues (`accent`, `accentLight`, `accentDark`, `mercViolet`) and `BrandGradient` are unchanged.
- The `#else` branch is today's code, untouched: `ios-source-diff.py` reports the file as `same`.

**Increase Contrast** has three sources. A colour switches if any one of them says so:
- the appearance's high-contrast name (`bestMatch` over the four `NSAppearance` names);
- `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`;
- DEBUG `-NightContrast increased`.

`@NightSettings` gives each view `increasedContrast`, `reduceTransparency` and `reduceMotion`. Each is SwiftUI's own read-only environment value OR the DEBUG override.

**Deviation from SPEC §1.3:** there is no root `.nightEnvironment()` modifier. The settings are a `DynamicProperty` instead, read per view. Sheets, the Settings window and the Help window get them without extra wiring, and SwiftUI still re-renders when a system setting changes.

DEBUG flags, each with a value, as SPEC §8.4 names them:
- `-NightContrast increased`
- `-NightReduceTransparency YES`
- `-NightReduceMotion YES`
- `-NightNoGlass YES`

`ARCHITECTURE.md`'s `-NightIncreaseContrast` is not used.

**CI-safe:** Liquid Glass appears in three places: `glassEffect`, `backgroundExtensionEffect`, and the "no toolbar background" choice. Each sits inside `#if compiler(>=6.2)`, then `if #available(macOS 26.0, *)`, with the fallback in both the `else` and the `#else`. Trig converts through `Double` explicitly, and no argument list has a trailing comma. `ci-compat-lint.py` finds 0.

### 2. Contrast tests (`DesignSystem/Tests/NightContrastTests.swift`, Mac host)

- Every text token on every Night surface, in all four variants: canvas top, canvas bottom, the canvas under each pool at its peak, surface, surfaceRaised and sidebar. The floor is 4.5:1, or 7:1 for the HC inks.
- Every tinted use, at 4.5:1: picked, correct and wrong rows; the student's turn; the KEY wash; token chips; each hero stop with and without the lamp, with white and with `heroSecondary`; the fallback chrome at its worst case; and white on `prominent`, `prominentHover` and `prominentPressed`.
- Non-text, at 3:1: the focus ring, the field stroke, and under HC the hairline.
- The lowest values reproduce SPEC §2.3's table to within 0.01, so the Swift test and `night_contrast.py` agree.
- **New:** `ink3` is sampled across the canvas as `NightCanvas` draws it, both pools on, at 1040×748, 700×548 and 1600×1000. The worst point is 4.98 (light) and 5.45 (dark), at the indigo pool's peak. The overlap of the two pools stays above 4.5.
  - The pools' geometry is a static function the view and the test share, so a change to the geometry fails the test.
- The concept's `ink3` (#5A6286 / #8E96C4) is shown to fail where its two pools overlapped: 4.08 and 3.43. This is the reason the token moved.
- HC flattens the canvas and turns off the pools and the lamp. `BrandColor.border` equals the hairline flattened over a surface.
- `NightPaletteMappingTests`:
  - each `BrandColor` token on the Mac draws its Night hex in `.aqua` and `.darkAqua` (skipped on a Mac that has Increase Contrast on);
  - the fixed hues stay fixed;
  - `BrandPalette` (the iPhone's values) is untouched.
- **Pixel check** with PIL on the rendered shots: `ink3` on the canvas 5.75:1 (the spec's figure for plain `canvasTop`), `ink2` 7.82, the hero objective 7.14 (light) and 10.76 (dark), the streak line on its card 6.24 and 6.55.

### 3. The window and the sidebar (`AppFeature/Sources/Mac/`)

- **Tint:** `Night.prominent` (#4338CA) for the window and the Progress sheet, in place of `accent`. White on it is 7.9:1; white on `accent` was 4.47:1.
- **Toolbar:**
  - `nightToolbarBackground()` on the detail column: the system's glass on macOS 26 (Xcode 26 builds), and `Night.canvasTop` on macOS 14–25, on CI builds and under `-NightNoGlass`.
  - **Progress button** (`MacProgressButton`, `chart.bar.xaxis`, "Progress and achievements (⌘4)") on Today, the learning path and the chat, in place of `StreakChip` (SPEC D8).
  - **View ▸ Progress, ⌘4** (`MacCommands.progressKey`, `MacShellModel.showProgress()`). It does nothing behind the gate or during an erase.
- **Sidebar:**
  - section headers in `ink3`;
  - unit counts and a chat's mode line in `ink3`, switching to the system's secondary label on a selected row (`backgroundProminence == .increased`), where `ink3` would vanish;
  - unit icons in Night's `accentText` / `successText`, white when selected;
  - glass sidebar on macOS 26; opaque `Night.sidebar` on the fallback and under Reduce Transparency or Increase Contrast;
  - rows, sections, selection, Delete and the fold rule are unchanged.
- **Today's canvas** extends under macOS 26's glass sidebar (`backgroundExtensionEffect`, guarded).
- **New shell API:**
  - `newChat(draft:)`: a new thread with the prompt in the composer, **not sent**;
  - `currentChatMode`: reads the mode without building the chat.

### 4. Today (`MacTodayView`, rewritten; copy in `MacNightCopy`)

At 1280 × 800 it is a 760 pt column with a gutter of 32 (24 below 900 pt). Header, hero and the two cards sit above the fold, and Recent chats starts in view. At 700 × 600 the column is 652 pt, the two cards still sit side by side, and Merc is 72 pt.

- **Header:**
  - the date, from the localised `.dateTime` template, as an `ink3` eyebrow;
  - `HomeState.opener` with a full stop ("Good afternoon.");
  - one subline from SPEC §6's table. It never says "keep your streak alive".
- **Up next (the hero):** the app's only gradient.
  - The eyebrow says "Up next · …", or "Continue · …" when the lesson resumes.
  - Then the title, the objective, and the unit meter: done lessons white, the next half lit, the rest faint, with "2 of 4 lessons done in Unit 1".
  - A white "Start / Continue Lesson N →" (Return), and a white text button "Learning Path".
  - **Merc is inside the card**, in his own 128 pt column, with his lamp.
  - The hero's text reads to VoiceOver as one header: "Lesson 3: … . … . 2 of 4 lessons done in Unit 1."
- **This week** (a lit card; a button that opens Progress):
  - the rhythm ring;
  - "N of M lessons" and the existing goal line;
  - the week's seven days from the plan's Thursday, with a brand-light dot on each day a lesson was finished and a ring around today;
  - the streak as one `ink3` line, **only when it is 1 or more**: "4 days running. One lesson or chat a day keeps it going."
  - VoiceOver hears the week, which days had lessons, and the streak.
- **Think it through:**
  - one of the **current mode's real starter prompts** (`ModePromptProvider`), picked by the day of the year;
  - the mode's `ModeDescription.purpose` under it.
  - A click opens a new chat with the prompt in the composer. Nothing is sent until the student sends it.
- **Recent chats** and the **weekly-nudge offer** as lit cards, with Night secondary and text buttons. The accessibility identifiers are kept.
- **DEBUG `-TodayDemo YES`** (shots only):
  - Unit 1's first two lessons finished this week and Lesson 3 opened, in the `-UITests` progress suite, which is emptied at every launch. Nothing is pushed: the progress PUT is skipped while it is on.
  - A 4-day streak passed straight to `HomeState`. The streak store is never written.

### 5. Tooling

`ios/scripts/mac-snapshots.sh` gains:
- the `today-week` state;
- the variants `hc`, `hc-dark`, `rt`, `rt-dark`, `rm`, `noglass` and `noglass-dark`, which pass the DEBUG overrides and never touch System Settings.

## Tests

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-mac-ns-spm` | **1054 tests in 156 suites passed** (base: 1026 in 153) |
| New suites | `NightContrastTests` (13 tests), `NightPaletteMappingTests`, `NightCopyTests` (the banned-phrase register over more than 100 generated lines, and proof it catches the concept's own lines) |
| Extended suites | `MacTodayTests`: subline, greeting, streak line, week days and their sentence, prompt choice, meter segments, hero label, fold. `MacShellModelTests`: ⌘4, Progress gated, `newChat(draft:)` unsent and gated, mode read without building the chat |
| `ios/scripts/ios-source-diff.py` | **0 files with iOS-visible changes.** Every edited file reports `same`; the new files report `new/mac` |
| `ios/scripts/ios-unchanged-check.sh` (snapshot comparison, recording forced off, Audit 16PM) | **"iOS unchanged":** 11 pass, 12 stale, the same 23 results and the same pixel hashes for every stale render as the baseline; `__Snapshots__` untouched |
| `ios/scripts/ci-compat-lint.py` | 0 findings |
| macOS Debug build (`/private/tmp/merc-mac-ns-dd`) | BUILD SUCCEEDED |
| iOS `xcodebuild test`, CI's flags (`-retry-tests-on-failure -test-iterations 3`), Audit 16PM | **TEST SUCCEEDED:** 3 XCTest unit (`ReplyTextScaleTests`) and 25 UI tests, 0 failures, plus the Swift Testing cases. The first attempt's build hit the known xattr-strip race ("xattr: No such file"); the retry built and passed |

## Screenshots (`shots/01/`)

All shots were taken from a renamed, ad hoc signed copy (`com.mayoailiteracy.mercurius.native.macns1`) with `ACTIVATE=NO`, off screen. Each is full resolution (2×), saved as JPEG at quality 90. The original PNGs are in `/private/tmp/merc-mac-ns-shots/01-final/`.

- **Today with a week in it:** `today-week`, `-dark`, `-min`, `-min-dark` (700 × 600).
- **Fresh Today:** `today`, `-dark`, `-min`, `-min-dark`.
- **Accessibility variants:** `today-week-hc`, `-dark-hc` (Increase Contrast), `-rt`, `-dark-rt` (Reduce Transparency), `-noglass`, `-dark-noglass` (the macOS 14–25 / CI fallback), `-rm` (Reduce Motion: the same picture with Merc still).
- **The shell elsewhere:** `path*` and `chat-thread*` show the Progress toolbar button, the sidebar and the Night palette arriving through `BrandColor`. The path and the chat themselves are later steps.

Looked at, and polished:
- "Think it through" now keeps its purpose line under the prompt and pins the arrow to the bottom corner. It used to leave a gap mid-card.
- `-TodayDemo` was added so the shots show the week dots, the streak line and a recent chat.
- The crisis view and the consent gate were photographed too (not committed). They take only the palette: flat, calm, no Merc, no motion. Their wording and logic are untouched.

## Skipped, and why

- **`BrandButton` / `DuoButton` Mac branches (SPEC §3.2, E1):** they would restyle the crisis view's button and the gate's buttons. The crisis view must stay palette-only, and the gate has its own step. They go with the gate/crisis step, where the crisis view can keep a plain button.
- **The gate's canvas, the Settings tint (§5.8), Help:** later steps own these screens. Today they get the palette only.
- **Week headline at the goal:** it stays the existing, tested "2 of 2 lessons", not SPEC §5.1's "Weekly goal met". Its own detail line already says "Goal met. Anything more is a bonus.", so "Weekly goal met" would say it twice.
- **Glass judged on screen:**
  - The harness photographs glass dark or missing, and runs never put a window in front of the founder.
  - So the macOS 26 glass sidebar with Today's canvas extended under it, and the glass toolbar button, still need one look on screen.
  - The fallback (`-noglass`) and the opaque variants are photographed.
- **Focus rings with Full Keyboard Access:** drawn by `nightFocusRing` (@FocusState, `focusEffectDisabled`). They can't be shown in an off-screen, never-activated run, so they need a check on screen with Full Keyboard Access on.

## Founder's app

- PID 98503 was running before and after every run.
- Nothing was killed by name, and `/private/tmp/merc-mac-dd` was never read or written.
- **One focus event:** in the very first run, the copy showed up once among the frontmost apps (the log saw Claude, Chrome and the copy). The harness never activates the copy under `ACTIVATE=NO`. The likeliest cause is macOS handing focus to the next window while the founder switched apps, but this is a guess. Every run after it saw only Chrome in front.
- The copy's container `~/Library/Containers/com.mayoailiteracy.mercurius.native.macns1` holds test data only.

## Notes for the next steps

- Use the role fonts: `.nightFont(.body)` and the rest. Use `Night.*` for every colour, and never `.secondary` on Night surfaces (use `ink3`).
- One prominent button per screen: `NightPrimaryButton`. Content goes on `nightLit`; floating chrome goes on `nightChrome`.
- Read `@NightSettings` for HC, Reduce Transparency and Reduce Motion. Use `Night.Motion.resolved(_:reduceMotion:)`, or `night.animation(_:)`.
- New UI copy goes into a copy enum and into `NightCopyTests`' generated lines.
- Shots: `N=1 VARIANTS="light dark min min-dark" scripts/mac-copy-snapshots.sh <out> <state>`, with `hc`, `rt` and `noglass` added for the accessibility pass.
