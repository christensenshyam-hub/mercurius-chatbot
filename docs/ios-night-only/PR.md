# The iPhone in Night Studio, dark only; the Mac locked to dark

**Branch:** `feat/ios-night-only`, from `feat/mac-night-studio` (PR #48). Not pushed. Base for every comparison below: `5230c18` (PR #48 plus the `-OpenSettings` shot hook).

The founder asked:
- "change the display modes on iOS to just be the night (dark) mode like on mac";
- then: "lock the mac to dark too".

## How we read it (the lead's interpretation)

1. **The iPhone is dark only.**
   - `UIUserInterfaceStyle = Dark` in the app's Info.plist, set in `ios/project.yml`. The launch, alerts, the keyboard and the system's share and print sheets are dark, with no light flash.
   - Every root applies the dark scheme.
   - The System / Light / Dark picker is gone from Settings. A stored Light or System choice is ignored.
2. **The iPhone wears the Mac's Night palette.** The `BrandColor` surface and text tokens read Night Studio's dark values, so every screen takes the night look without per-view edits. This is a colour-token change, not a redesign: layouts, fonts and components stay as they are.
   - Light-only colour hardcodes would be fixed. None was found: every iPhone view already draws with tokens. The one screen that still didn't read as Night was Settings, with the system's grey form rows and the fill indigo used as text; that is fixed below.
   - Night's "no shadows in dark" rule is applied.
   - The printable certificate stays light paper. The crisis view stays calm and plain.
3. **The Mac is dark only too.**
   - Dark Aqua for the app at launch, and the dark scheme on every scene.
   - The Settings picker is gone.
   - Nothing else on the Mac changes.
4. **The Live Activity and the widgets keep following the system appearance.**

## What changed

### iPhone

**Dark only**
- `ios/project.yml` sets `UIUserInterfaceStyle: Dark` for the app target. xcodegen writes it into `Mercurius/Resources/Info.plist`.
- The widget extension's Info.plist has no such key.
- `LaunchBackground` is now Night's canvas `#0B0E2E` in every appearance (it was `#0B0F30` dark / `#F7FAFC` light). The launch hands over to `BrandColor.background`, the same colour.
- `BrandAppearance.colorScheme` (DesignSystem, `= .dark`) is the one source. It is applied:
  - by `RootView` (the main body and every DEBUG preview root);
  - at the `WindowGroup` root in `MercuriusApp`.

  Before, `RootView` applied `env.themeStore.theme.colorScheme`.
- **Settings:** the Appearance section is gone. `ThemePreferenceStore`, `ThemePreference` and `SettingsViewModel.theme` stay, so the stored key and the hosts' initialisers don't change, but nothing reads them. Each is commented as such; dropping them is a later cleanup.
- **Settings and Privacy choices, the one per-view colour fix** (found in the after shots):
  - the rows sit on Night's lit `surface` (`.listRowBackground`). The system's neutral grey `#2C2C2E` rows were the one screen that didn't read as Night. The Mac's Settings window keeps its own rows: the Privacy choices change is `#if os(iOS)`.
  - "Copy" is tinted `accentText`. It used the fill `accent` as text: 3.12:1 on the grey row, now 8.66:1 on `surface`.
  - The Settings stack is tinted `accentText`, for the pushed pages' back button and the alerts' buttons. The asset `AccentColor` `#6366F1` as text is 4.21:1 on the canvas; `accentText` is 9.43:1.
- The UI test `testTappingSettingsOpensSheetWithAppearanceSection` is renamed `testTappingSettingsOpensSheet`. It never asserted the section.

**The Night palette**

`Color+Brand.swift`'s iPhone branch now reads `BrandNight`, a platform-neutral table of SPEC.md §2.2's mapping. It is the same mapping the Mac's branch spells out with `Night.*`.

Each token is a `UIColor` provider:
- it draws Night's **dark** value whatever the trait's light/dark style says;
- under iOS **Increase Contrast** it draws Night's increased-contrast dark value, as the Mac does.

`NightPalette.swift` lost its `#if os(macOS)` guard (it is Foundation only) so iOS can read it. The Night *components* (canvas, lit surfaces, glass chrome, the Night button and so on) stay Mac only.

| `BrandColor` | iPhone before (light / dark) | iPhone now | Under Increase Contrast |
|---|---|---|---|
| `background` | `#F7FAFC` / `#0B0F30` | `#0B0E2E` (Night `canvasTop`) | `#05071A` |
| `surface` | `#FFFFFF` / `#11163A` | `#121641` | `#0E1238` |
| `surfaceElevated` | `#EEF0F7` / `#1A1F4A` | `#1A1F52` (`surfaceRaised`) | `#161B4A` |
| `border` | `#D9DEEC` / `#242A5A` | `#2E3258` (the hairline, flattened) | `#6E7188` |
| `text` | `#0F142A` / `#E6E9F5` | `#F1F2FF` (`ink`) | `#FFFFFF` |
| `textSecondary` | `#5D6A8A` / `#9AA3C2` | `#B7BDE2` (`ink2`) | `#DDE0F7` |
| `accentText` | `#4F46E5` / `#A5B4FC` | `#A5B4FC` | `#C7D2FE` |
| `successText` | `#166534` / `#22C55E` | `#6EE7A8` | `#A7F3D0` |
| `errorText` | `#B91C1C` / `#F87171` | `#FCA5A5` | `#FECACA` |
| `accent`, `accentLight`, `accentDark`, `mercViolet`, `success`, `error`, gradients, reward golds | fixed hues | unchanged | unchanged |

**Why `success` and `error` keep the iPhone's fill hues** (the Mac uses Night's lighter `#34D399` / `#F87171`): the quiz sheet draws a white letter on the green disc of the correct answer. That is 2.28:1 today, and Night's green would make it 1.84:1. Every *text* token moved; the two fills didn't. The tinted rows built on them are checked below.

**Shadows off (Night SPEC §2.6: no shadows in dark)**
- `brandShadow(_:)` is a no-op on the iPhone, and keeps its presets on the Mac. It covered Home, the path's nodes and checkpoint, the coach card and Merc's badge.
- Eight direct `.shadow` calls (seven files) are wrapped in `#if os(macOS)`, so the Mac compiles the same text, or dropped from iOS-only branches:
  - the lesson reply bubble;
  - the send button's glow;
  - the lesson intro's Continue glow and speech bubble;
  - the chat's "Jump to latest" pill (iOS branch);
  - the celebration sheet (iOS branch);
  - the achievement toast and the progress nudge.
- Merc's own art keeps its tiny internal shading.

**Exceptions**
- **The certificate isn't on this branch.** It lives on `feat/certificate`. I checked that branch's `CertificateView`: it draws with its own `Certificate.Ink`, pins `.environment(\.colorScheme, .light)` and uses no `BrandColor`. So it stays on its light paper after a merge. Its sheet chrome (`CertificateSheet`) uses `BrandColor` and will go dark around it, which is right. Re-check after merging.
- **The crisis view** gets the palette only, like the Mac: no edits, no decoration, no canvas, no glow.

### Mac
- `MacAppDelegate.applicationWillFinishLaunching` sets `NSApp.appearance = NSAppearance(named: .darkAqua)` before the first window. Menus, alerts and panels follow it.
- `MercuriusMacApp` applies `.preferredColorScheme(BrandAppearance.colorScheme)` on the main window, Settings and Help scenes. `RootView`, `MacSettingsView` and `MacHelpView` apply the same value where they used the stored theme.
- **Settings ▸ General:** the System / Light / Dark radio group is replaced by a read-only row, "Appearance: Dark", with the footer "Mercurius always uses its night look, whatever your Mac's appearance."
  - While the progress-nudges flag is off (it is), the picker was the tab's only content, and an empty tab looked broken.
  - Dropping the tab would have changed the window's structure and its ⌘, landing.
- **Nothing else.** `mac-source-diff` (ios-source-diff.py with macOS's conditions) against `5230c18` shows Mac-visible text changes only in:
  - the files above, and `MercuriusMacApp` / `MacAppDelegate`;
  - `Color+Brand.swift`: the Mac's token lines are byte-identical; the dead `adaptive()` helper and `BrandPalette` pairs are removed; the internal `BrandNight` table is added;
  - `RewardTokens.swift`: an explicit `return` around the same `shadow`;
  - `SettingsView.swift`: the iPhone's sheet, which the Mac doesn't host. (`PrivacyChoicesView`, which the Mac does host, compiles the same text on the Mac.)
- The printable certificate stays light paper on the Mac too (same note as above). The print and save panels stay system-styled.

### Not changed
- **The Live Activity and the widgets** (`MercuriusActivity`, `MercuriusWidgets`) still follow the system appearance:
  - they use their own `ActivityTheme` and `@Environment(\.colorScheme)`, not `BrandColor`;
  - the extension's Info.plist has no `UIUserInterfaceStyle`;
  - the in-app DEBUG `-LiveActivityGallery` now renders dark, because it is hosted in the app.
- **The share card image** uses fixed colours and pins light, as before.
- **The notification art** uses no tokens.
- **iOS layouts, fonts, components and copy** are unchanged, apart from the Settings section.

## Contrast

`BrandContrastTests` (DesignSystem, `swift test`) now checks the iPhone's real values: `BrandNight` in Night's `dark` and `darkHC` variants, read from `NightPalette`. Its floors are 4.5:1 for text, and 7:1 for the Increase Contrast inks on plain surfaces.

| | Dark | Increase Contrast |
|---|---|---|
| Lowest text-on-surface pair (all 5 text tokens × background, surface, surfaceElevated) | **7.74** (`accentText` on `surfaceElevated`) | **10.92** |
| Lowest tinted use (12 uses: check question, KEY eyebrow, input hint, history chip, correct/wrong marks and rows, selected row) | **7.12** (wrong mark on an elevated card) | **9.38** |

New tests:
- **`BrandContrastTests`**, rewritten:
  - the iPhone draws dark or dark-HC only;
  - each token is the SPEC §2.2 Night token;
  - the drawn hex values;
  - text on surfaces and tints in both variants;
  - the floors above;
  - the accent fill still fails as text, which is why `accentText` exists;
  - the AUD-21 numbers, on the retired light palette.
- **`NightPaletteMappingTests.iPhoneSharesTheMapping`** (Mac host): replaces "BrandPalette is untouched". The iPhone's table is the Mac's mapping, token for token, except the two fills.
- **`BrandAppearanceTests`:** the scheme is dark.
- **`MercuriusTests/NightOnlyAppearanceTests`** (in the app, on the simulator, in CI's `xcodebuild test`):
  - Info.plist says `Dark`;
  - each `BrandColor` token resolves to Night's dark hex in a light, dark and unspecified trait;
  - each resolves to the HC hex under `accessibilityContrast = .high`;
  - the fixed hues stay fixed.

## Verification

Run on 2026-10-21/22 with Xcode 26.4 / Swift 6.3 on macOS 26.3. CI's Xcode 16.2 / Swift 6.0.3 is covered by the lint only.

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-night-spm` | **1192 tests in 178 suites passed**, after the main change and again after the Settings fix |
| `ios/scripts/ci-compat-lint.py` | **0 findings** |
| `ios-source-diff.py 5230c18` (what iOS compiles) | CHANGED as intended: `Color+Brand`, `NightPalette` (guard lifted), `RewardTokens`, `RootView`, `MercuriusApp`, `SettingsView`, `PrivacyChoicesView`, the 8 shadow sites, the tests. NEW: `BrandAppearance`, two test files |
| `mac-source-diff` (the same script with macOS's conditions) | Only the files listed under "Mac" above |
| iOS `build-for-testing` (Lab B, `/private/tmp/merc-night-ios-dd`) | **TEST BUILD SUCCEEDED**. The first try hit the known stale-module trap ("cannot find 'BrandAppearance'"); the derived data was cleared and rebuilt |
| iOS `xcodebuild test` with CI's flags (skip snapshots, performance and App Store shots; retries 3, relaunch) on Lab B, iPhone 16 Pro Max, iOS 26.4 | **TEST EXECUTE SUCCEEDED:** 25 / 25 UI tests and 3 XCTest unit tests, each on its first try, plus 8 Swift Testing tests, including the 5 new `NightOnlyAppearanceTests`. Run on `9a3292e`. After the Settings fix (the next commit), on the rebuilt products: the whole `MercuriusTests` target except the snapshots (3 XCTest + 8 Swift Testing), plus the three Settings UI tests (`testTappingSettingsOpensSheet`, `testSettingsHasFeedbackAndHowItTeaches`, `testDeleteFailureShowsTheOldIdBeforeADeviceOnlyReset`): **all passed on their first try** |
| Snapshot check, recording forced off (`ios-unchanged-check.sh`, `SIM` Lab B) | **23 / 23 differ from their references**: every one now draws on Night's ink. Listed below. `MercuriusTests/Snapshots` untouched (`git status` clean) |
| Mac Debug build (`/private/tmp/merc-night-mac-dd/after`) | **BUILD SUCCEEDED**, and again after the Settings fix |
| Mac Release, `generic/platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (CI's step) | **BUILD SUCCEEDED** |
| Mac copy shots (`mac-copy-snapshots.sh`, `SUFFIX=macnight N=1` → `….macnight1`, `ACTIVATE=NO`) | before: `today`, `settings-general` and `lesson`, light and dark, from the base build. After: the same three with the harness's **light** flag, its dark flag, and `AQUA=YES VARIANTS=system` (the copy given `NSRequiresAquaSystemAppearance`, i.e. a Mac in light mode, with no harness flag). **All nine after shots are dark** |
| Mac "nothing else changed" | After (light flag, dark, and Aqua) against before-dark, pixel by pixel: `lesson` **identical** (0 px over 8/255); `today` differs only in Merc's idle animation (0.08 %, his box); `settings-general` differs only in the Appearance row (1.8 %, that row) |

The founder's running app (`/private/tmp/merc-mac-user-dd`, PID 94800) was never touched: no `pkill`/`killall`, and the copies ran under their own bundle id. The Aqua run's "running before … is gone" line was another workflow's iOS simulator app (also named Mercurius) relaunching, not ours. Focus never left Safari.

Simulators: at most one of ours was booted at a time, only when fewer than 2 were booted machine-wide (`sim-pick.sh`). Lab B was shut down after each session, with its appearance restored (light). The budget was saturated by other workflows for about 70 minutes before the first session.

**Large text and the SE size.** No SE-class device was created or booted, because the budget never allowed a second device. The large-text check is the 16 Pro Max at **AX3** (`UICTContentSizeCategoryAccessibilityXL`) for every screen.

## Snapshot drift (references not re-recorded; that's the founder's)

Recording was forced off (`TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never`), and nothing was re-recorded. The baseline (`docs/mac-night-studio/ios-snapshot-baseline.txt`) had **11 passing and 12 already stale**. Now **all 23 differ**, for one reason: each test hosts its view on `BrandColor.background` or draws `BrandColor` surfaces and text, and those are now Night's dark values. The renders were checked by eye: all are on the ink canvas, and none is broken.

| Test | Was | Now | What changed in the render |
|---|---|---|---|
| `testBrandButtonPrimary` | pass | differs | the host canvas (ink); the button's gradient is unchanged |
| `testBrandButtonSecondary` | pass | differs | ink canvas; the button's surface, border and label in Night |
| `testBrandLogoFullLightMode` | pass | differs | the logo on ink. This test pins a light trait, so it draws the light logo art; the app can't show that any more |
| `testBrandLogoFullDarkMode` | pass | differs | the logo on ink (was `#0B0F30`) |
| `testBrandLogoMark` | pass | differs | the mark on ink |
| `testMessageBubbleUserShort`, `testMessageBubbleUserLong` | pass | differ | the host canvas only; the student's gradient bubble is unchanged |
| `testQuizViewLoading`, `testQuizViewLoaded`, `testQuizViewFailedRetryable`, `testQuizViewFailedNonRetryable` | pass | differ | the sheet's canvas, question cards, option rows and text in Night |
| `testCurriculumListAtAccessibilityXXL` | stale | new render | canvas and rows |
| `testEmptyChatViewLight`, `testEmptyChatViewDark` | stale | new render | canvas, prompt cards, text. **Light and Dark now render identically** (the same pixel hash): the tokens ignore the trait |
| `testEmptyChatViewAccessibilityXXL` | stale | new render | as above, at XXL |
| `testLessonCompleteOverlayWithNext`, `testLessonCompleteOverlayLastLessonDark` | stale | new render | the sheet surface and text, and no sheet shadow |
| `testMercAllStates` | stale | new render | the canvas behind Merc; Merc unchanged |
| `testMessageBubbleAssistantPlain`, `testMessageBubbleAssistantTyping`, `testMessageBubbleAssistantFailed` | stale | new render | the bubble (`surfaceElevated`), text and `errorText` |
| `testModeSelectorDefault`, `testModeSelectorAtAccessibilityXXL` | stale | new render | the pills on ink, the inactive labels |

**For the founder's re-record:** the tests that pin `userInterfaceStyle: .light` now photograph an appearance the app no longer has. Consider pinning them `.dark`, or dropping the Light/Dark pairs, when re-recording. `docs/mac-night-studio/ios-snapshot-baseline.txt` will need a new baseline from a re-recorded run (`WRITE_BASELINE=1`).

## Shots

Comparison sheets in `docs/ios-night-only/compare/`:

- `ios-1-home-path-lesson.jpg`, `ios-2-complete-keyboard-chat.jpg`, `ios-3-settings-gate-check-crisis.jpg`: each screen four ways.
  - **Screens:** Home, the path, the lesson intro, a lesson (`-LessonReplay`), lesson complete (`-ForceCelebrate`), the keyboard up (`-LessonFocusComposer`), the chat, a chat thread (`-SeedDemoChat`), Settings (`-OpenSettings`), the onboarding gate, the unit check and the crisis view (`-UnitTestCrisisPreview`).
  - **The four columns:** before with the phone in light mode; before with the phone in dark mode; **after with the phone in LIGHT mode** (the lock); after at AX3.
  - The before shots come from the base build (`5230c18`) and the after shots from this branch, all on Lab B (iPhone 16 Pro Max, iOS 26.4).
- `like-on-mac.jpg`: the Mac after, locked dark on a Mac in light mode, above the iPhone after. Both read the same Night tokens.
- `mac-today.jpg`, `mac-settings-general.jpg`, `mac-lesson.jpg`: the Mac before (light, dark) and after (the harness's light flag, and a Mac in light mode).
- **After, phone light against after, phone dark,** pixel by pixel below the status bar: identical except Merc's idle animation, the caret's blink and the session ID (a new ephemeral ID each launch). The appearance setting no longer reaches the app.
- **Under the keyboard:** before, in a light phone, the keyboard was light (the first-run slide-to-type card). After, it is dark.

## Known issues and follow-ups

- **Snapshot references:** 23 to re-record (the founder's). See the drift table.
- **The certificate:** re-check after merging `feat/certificate`. Its paper should stay light; its sheet chrome goes dark.
- **The system tint outside Settings.** The asset `AccentColor` (`#6366F1`, shared with the Mac target) is 4.21:1 as text on the canvas. Settings now tints `accentText`. Anything elsewhere left to the system tint (some alert buttons, for example) still uses it; I didn't find such text in the screens shot. A follow-up could tint the iPhone's root with `accentText`, after checking the default-tinted toggles and pickers, or give `AccentColor` a lighter value on iOS only.
- **Pre-existing, unchanged here:**
  - white on the student bubble's `accent` stop is 4.47:1;
  - the quiz's white letter on the green correct disc is 2.28:1. This is why the iPhone keeps its fill green.
- **`ThemePreferenceStore` / `ThemePreference` / `SettingsViewModel.theme`** are unread. Remove them once nothing needs the initialisers' shape.
- **The AX3 path:** the last node's "Locked" caption runs under the tab bar. That is layout, unchanged by this branch.
- **Not verified on a device:** the Increase Contrast variant on the iPhone. The unit tests pin the resolved values; there are no shots of it.
- **CI's compiler:** Swift 6.0.3 isn't installed here; `ci-compat-lint.py` is the stand-in. The new code uses no 26-only API and no trailing commas in argument lists.
