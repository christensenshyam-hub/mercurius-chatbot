# The iPhone dark only, in Night Studio's palette; the Mac locked dark

**Stacked on #48** (`feat/mac-night-studio`). Merge #48 first, then point this PR at `main`.

- **Branch:** `feat/ios-night-only`.
- **Base for every before/after below:** `5230c18`. That is #48 plus this branch's first commit, a DEBUG-only shot hook.

The founder asked:
- "change the display modes on iOS to just be the night (dark) mode like on mac";
- then: "lock the mac to dark too".

## How we read it (the lead's interpretation)

1. **The iPhone is dark only.**
   - The launch, alerts, the keyboard and the system's sheets are dark too, with no light flash.
   - The System / Light / Dark picker is gone from Settings. A stored Light or System choice is ignored.
2. **The iPhone wears the Mac's Night palette.** The `BrandColor` surface and text tokens read Night Studio's dark values, so every screen takes the night look without per-view edits.
   - This is a colour-token change, not a redesign: iOS layouts, fonts and components stay as they are.
   - Where a view still read as light or system-grey, it is fixed so it reads on the ink canvas.
   - Night's rule of no shadows in dark is applied.
   - The printable certificate stays on light paper. The crisis view stays calm and plain.
3. **The Mac is dark only too.** Every window, sheet, menu and panel is dark, and the Settings picker is gone. Nothing else on the Mac changes.
4. **The Live Activity and the widgets keep following the system appearance.** They are separate targets on the Lock Screen.

## Shots

All "after" iPhone shots are taken with the **phone set to Light**: the lock wins. The phone set to Dark gives the same pixels, apart from Merc's idle animation, the caret and the session ID. The full sets are outside the repo, in `.claude/worktrees/explore-ui-shared/ios-night-only-shots/`: the iPhone before and after shots (phone Light, phone Dark and AX3, for 12 screens), the first round's after shots, the alert tour, the Mac shots and full comparison sheets.

**Home and the path.** Before with the phone in Light, before in Dark, and after.

![Home and the path](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/01-iphone-home-path.jpg?raw=true)

**A lesson and a chat thread**

![A lesson and a chat](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/02-iphone-lesson-chat.jpg?raw=true)

**Settings and the crisis view.** The Appearance section is gone. The crisis view gets the palette only.

![Settings and the crisis view](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/03-iphone-settings-crisis.jpg?raw=true)

**System-drawn surfaces, after.** Three alerts, the History sheet and the keyboard, with the phone in Light.

![Alerts, a sheet and the keyboard](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/04-iphone-system-surfaces.jpg?raw=true)

**The Mac.** Before (Light), then after in two ways: with the screenshot harness asking for Light, and as a copy run on a Mac in Light mode (`NSRequiresAquaSystemAppearance`). Today, a lesson and Settings ▸ General.

![The Mac locked dark](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/05-mac-dark-lock.jpg?raw=true)

**The iPhone next to the Mac.** Both read the same Night tokens. The iPhone's canvas is flat: the Mac's stars, glow and glass are Night *components*, and they stay Mac only.

![The iPhone like the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/ios-night-only/docs/ios-night-only/key-shots/06-iphone-like-mac.jpg?raw=true)

## What changed

### iPhone: dark only

- **Info.plist:** `ios/project.yml` sets `UIUserInterfaceStyle: Dark` for the app target, and xcodegen writes it into `Mercurius/Resources/Info.plist`. The widget extension's Info.plist has no such key.
- **No light flash at launch:** `LaunchBackground` is Night's canvas `#0B0E2E` in every appearance. It was `#0B0F30` dark and `#F7FAFC` light. The launch hands over to `BrandColor.background`, the same colour.
- **One source:** `BrandAppearance.colorScheme` (DesignSystem, `= .dark`). `RootView` (the main body and every DEBUG preview root) and the `WindowGroup` in `MercuriusApp` apply it. Before, `RootView` applied `env.themeStore.theme.colorScheme`.
- **Settings:** the Appearance section is gone.
  - `ThemePreferenceStore`, `ThemePreference` and `SettingsViewModel.theme` stay, so the stored key and the hosts' initialisers don't change. Nothing reads them now; each is commented as such.
  - The UI test `testTappingSettingsOpensSheetWithAppearanceSection` is renamed `testTappingSettingsOpensSheet`. It never asserted the section.

### iPhone: the Night palette

`Color+Brand.swift`'s iPhone branch now reads `BrandNight`. This is a platform-neutral table of SPEC.md §2.2's mapping, the same mapping the Mac's branch spells out with `Night.*`.

Each token is a `UIColor` provider:
- it draws Night's **dark** value whatever the trait's light/dark style says;
- under iOS **Increase Contrast** it draws Night's increased-contrast dark value, as the Mac does.

`NightPalette.swift` lost its `#if os(macOS)` guard (it is Foundation only) so the iPhone can read it.

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

**Why `success` and `error` keep the iPhone's fill hues.** The Mac uses Night's lighter `#34D399` / `#F87171`. But the quiz sheet draws a white letter on the green disc of the correct answer: 2.28:1 today, and Night's green would make it 1.84:1. So every *text* token moved, and the two fills didn't.

### iPhone: per-view fixes, where a screen didn't yet read as Night

- **The interface tint** is `BrandAppearance.tint`, which is `accentText`. It is set on:
  - the tab shell (`AppShellView`);
  - Home;
  - the first-run gate;
  - Settings;
  - the History and Progress sheets.

  It draws the tab bar's selected item, back and toolbar buttons, text buttons, links, the alerts' buttons and the text caret. Before, it was the fill indigo `#6366F1`, which is 4.21:1 as text on the canvas. The selected tab's label was 3.2:1 on its highlight. Switches still tint themselves with the fill indigo.
- **Settings and Privacy choices:**
  - the rows sit on Night's lit `surface`, not the system's neutral grey `#2C2C2E`;
  - Night's hairline (`border`) divides the rows;
  - section headers and footers are in `textSecondary`, not the system grey `#9193A5`;
  - "Copy" is in `accentText` (it was 3.12:1);
  - the Session row's divider now spans the row; it was a stub under "Copy".

  The Mac's own Settings window is untouched. On the Mac, `nightSectionCaption()` is a no-op.
- **Home's "This week" ring and the top bar's level ring:** the empty track is `border`, as on the Mac's Today ring. `surfaceElevated` all but vanished on the canvas (1.22:1, now 1.53:1). The "This week · 0 of 2" label still carries the meaning.
- **Shadows off** (Night SPEC §2.6, no shadows in dark):
  - `brandShadow(_:)` is a no-op on the iPhone and keeps its presets on the Mac.
  - Eight direct `.shadow` calls in seven files are wrapped in `#if os(macOS)` or dropped from iOS-only branches: the lesson reply bubble, the send button's glow, the lesson intro's Continue glow and speech bubble, "Jump to latest", the celebration sheet, the achievement toast and the progress nudge.
  - Merc's own art keeps its small internal shading.
- **No light-only hardcodes were found.** No iOS view hardcodes a white background, a light gradient or black text, and no iOS view uses materials.

### Exceptions

- **The certificate** lives on `feat/certificate`, not on this branch.
  - That branch's `CertificateView` draws with its own `Certificate.Ink`, pins `.environment(\.colorScheme, .light)` and uses no `BrandColor`. Its paper stays light after a merge, on both platforms.
  - Its sheet chrome uses `BrandColor` and goes dark around it, which is right.
  - When merging it, change `CertificateWiring.swift`'s `.tint(BrandColor.accent)` to `.tint(BrandAppearance.tint)`.
- **The crisis view** gets the palette only, as on the Mac. It has no edits, no decoration, no canvas and no glow.

### Mac

- **App level:** `MacAppDelegate.applicationWillFinishLaunching` sets `NSApp.appearance = NSAppearance(named: .darkAqua)` before the first window. Menus, alerts and panels follow it.
- **Scenes:** `MercuriusMacApp` applies `.preferredColorScheme(BrandAppearance.colorScheme)` on the main window, Settings and Help scenes. `RootView`, `MacSettingsView` and `MacHelpView` apply it where they used the stored theme.
- **Settings ▸ General:** the System / Light / Dark radio group is replaced by a read-only row, "Appearance: Dark", with the footer "Mercurius always uses its night look, whatever your Mac's appearance."
  - While the progress-nudges flag is off (it is), the picker was the tab's only content, and an empty tab looked broken.
  - Removing the tab would have changed the window's structure and where ⌘, lands.
- **Nothing else changed on the Mac.** `mac-source-diff` (the `ios-source-diff.py` reduction with macOS's conditions) against `5230c18` shows Mac-compiled text changes only in:
  - the files above;
  - `Color+Brand` (the Mac's token lines are byte-identical; the internal `BrandNight` table is added);
  - `RewardTokens` (an explicit `return` around the same shadow);
  - `PrivacyChoicesView` (`nightSectionCaption()`, which returns `self` on the Mac);
  - iPhone-only views the Mac compiles but never shows (`AppShellView`, `HomeView`, `GamifiedTopBar`, `SettingsView`).

  The branch's first commit (`5230c18`, the comparison base) adds a DEBUG-only `-OpenSettings` hook in `ChatView`, and a bundle-id suffix to the Mac shot scripts.
- **The print and save panels** stay system-styled.

### Not changed

- **The Live Activity and the widgets** (`MercuriusActivity`, `MercuriusWidgets`) still follow the system appearance:
  - they use their own `ActivityTheme` and `@Environment(\.colorScheme)`, not `BrandColor`;
  - the extension's Info.plist has no `UIUserInterfaceStyle`.

  The in-app DEBUG `-LiveActivityGallery` now renders dark, because it is hosted in the app.
- **The share card image** uses fixed colours and pins light, as before.
- **The notification art** uses no tokens.
- **iOS layouts, fonts, components and copy** are unchanged, apart from the Settings section that was removed.

## Contrast

**The tokens.** `BrandContrastTests` (`swift test`) checks the iPhone's real values: `BrandNight` in Night's `dark` and `darkHC` variants. The floors are 4.5:1 for text, and 7:1 for the Increase Contrast inks on plain surfaces.

| | Dark | Increase Contrast |
|---|---|---|
| Lowest text-on-surface pair: 5 text tokens on `background`, `surface` and `surfaceElevated` | **7.74** (`accentText` on `surfaceElevated`) | **10.92** |
| Lowest tinted use, out of 12 (check question, KEY eyebrow, input hint, history chip, correct and wrong marks and rows, selected row) | **7.12** (wrong mark on an elevated card) | **9.38** |
| The selected tab's label (`accentText`) on the tab bar's highlight, as iOS 26.4 draws it (`#393F6A` over the path, `#343650` over the chat) | **5.03 / 5.89** | higher, on the same highlight |

**Measured on the renders** (iPhone 16 Pro Max, iOS 26.4). Each value is the text's core pixel against its background. The system draws the tab label slightly lighter than the tint.

| Where | Before, phone Light | Before, phone Dark | After |
|---|---|---|---|
| Selected tab label, Curriculum | 4.27 | 3.19 | **6.76** (`#C2D4FF` on `#393F6A`) |
| Selected tab label, Chat | 4.27 | 3.56 | **7.59** (`#BFCFFF` on `#343650`) |
| Settings headers and footers | – | – | **10.20** (`#B7BDE2` on the canvas; the system grey was 6.20) |
| Alert buttons: the chat's alert "OK", "Delete my data?" "Cancel", the failed delete's three buttons | – | – | **6.73–6.83** (`#A5B4FC` on the alert's glass `#2C2D3B`) |
| Settings "Done", History "Close" | – | – | **8.08** (on their capsule) |
| "Back to lessons" | – | – | **8.66** |
| Privacy choices "Withdraw consent" (system red in a row) | – | – | **5.03** |

**Below 4.5:1, and not changed here:**
- **White on the solid fill indigo `#6366F1`: 4.47:1.** This is the student's bubble at its top stop, the lesson-complete "Next lesson" button and the Socratic pill's start colour. It is pre-existing; the fill hue is unchanged.
- **The quiz's white letter on the green "correct" disc: 2.28:1.** Pre-existing. This is why the iPhone keeps its fill green.
- **The "Delete" button in the "Delete my data?" alert: 3.97:1** (`#FF4245` on `#2C2D39`). This is the system's destructive red, which the app can't restyle without dropping the destructive role.

## Tests

- **`BrandContrastTests`**, rewritten for the iPhone's dark-only values. It checks:
  - the iPhone draws `dark` or `darkHC` only;
  - each token is the SPEC §2.2 Night token;
  - the drawn hex values;
  - text on surfaces and on tints, in both variants;
  - the floors above;
  - the fill indigo fails as text, which is why `accentText` exists;
  - **new:** the selected tab label on the measured highlights. `accentText` passes and the fill indigo didn't;
  - the AUD-21 numbers, on the retired light palette.
- **`NightPaletteMappingTests.iPhoneSharesTheMapping`** (Mac host): the iPhone's table is the Mac's mapping, token for token, except the two fills.
- **`BrandAppearanceTests`:** the scheme is dark, and the interface tint is `accentText`, not the fill.
- **`MercuriusTests/NightOnlyAppearanceTests`** (in the app, on the simulator, in CI's `xcodebuild test`):
  - Info.plist says `Dark`;
  - every `BrandColor` token resolves to Night's dark hex in a light, a dark and an unspecified trait, and to the increased-contrast hex under `accessibilityContrast = .high`;
  - the interface tint resolves to `#A5B4FC`, or `#C7D2FE` under Increase Contrast;
  - the fixed hues stay fixed.

## Verification

Run on 2026-10-22 with Xcode 26.4 / Swift 6.3 on macOS 26.3. CI's Xcode 16.2 / Swift 6.0.3 is covered by the lint only.

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-night-spm` | **1194 tests in 178 suites passed** |
| `ios/scripts/ci-compat-lint.py`, on its default roots and on `MercuriusTests` and `MercuriusUITests` | **0 findings** |
| `xcodegen generate` | Leaves the committed Info.plist byte-identical, with `UIUserInterfaceStyle = Dark`. The built app carries the key |
| iOS `build-for-testing` (`/private/tmp/merc-night-ios-dd`) | **TEST BUILD SUCCEEDED** |
| iOS `xcodebuild test` with CI's flags (skips snapshots, performance and the App Store shots; retries 3) on Lab C, an iPhone 16 Pro Max on iOS 26.4 | **TEST EXECUTE SUCCEEDED.** 37 of 37 passed on their first try: 25 UI tests, 3 XCTest unit tests and 9 Swift Testing tests, including the 6 `NightOnlyAppearanceTests` |
| Alert and sheet tour: a temporary UI test, not committed, shot through `XCUIScreen` | Three alerts, Settings, Privacy choices, History and both tabs. All dark; numbers above. The share-sheet tap didn't open the sheet, so the share and print sheets aren't shot |
| Snapshot check, recording forced off (`ios-unchanged-check.sh`, on Lab C) | **23 of 23 differ from their references**, listed below. Every render hash is identical to the first round's, so this round's fixes touched no snapshot. `MercuriusTests/Snapshots` is untouched |
| Mac Debug build, and Release with `generic/platform=macOS` and `CODE_SIGNING_ALLOWED=NO` (CI's step) | **BUILD SUCCEEDED**, both |
| Mac copy shots (`mac-copy-snapshots.sh`, `SUFFIX=macnight N=1`, so the copy is `….macnight1`, with `ACTIVATE=NO`) | Before: `today`, `settings-general` and `lesson`, light and dark, from the base build. After: the same three with the harness's **light** flag, its dark flag, and `AQUA=YES VARIANTS=system` (a Mac in Light mode). **All nine after shots are dark** |
| Mac "nothing else changed" | Against before-dark, pixel by pixel: `lesson` is **identical**, `settings-general` differs only in the Appearance row, and `today` differs only in Merc's idle animation. This round's after shots match the first round's exactly for `lesson` and `settings-general`. `today` changed only where the date did (the run crossed midnight: the date line, today's dot and the day's question) and in Merc's animation |

**Things kept safe:**
- **The founder's running Mac app** (`/private/tmp/merc-mac-user-dd`, PID 94800) was never touched: no `pkill` or `killall`, and the copies ran under their own bundle id. The harness's "running before … is gone" lines were other workflows' simulator apps (also named Mercurius) relaunching.
- **Simulators:** one of ours at a time, booted only when fewer than 2 were booted machine-wide, and shut down after each session.
- **Large text:** checked on the 16 Pro Max at AX3 for every screen. No SE-class device was booted, because the simulator budget never allowed a second device.

## Snapshot references to re-record (the founder's)

Recording was forced off (`TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never`), and nothing was re-recorded. The baseline (`docs/mac-night-studio/ios-snapshot-baseline.txt`) had **11 passing and 12 already stale**. Now **all 23 differ**, for one reason: each test hosts its view on `BrandColor.background`, or draws `BrandColor` surfaces and text, and those are now Night's dark values. Every render was checked by eye: all are on the ink canvas, and none is broken.

| Test | Was | Now | What changed in the render |
|---|---|---|---|
| `testBrandButtonPrimary` | pass | differs | the host canvas (ink); the button's gradient is unchanged |
| `testBrandButtonSecondary` | pass | differs | ink canvas; the button's surface, border and label in Night |
| `testBrandLogoFullLightMode` | pass | differs | the logo on ink. The test pins a light trait, so it draws the light logo art, which the app can't show any more |
| `testBrandLogoFullDarkMode` | pass | differs | the logo on ink (was `#0B0F30`) |
| `testBrandLogoMark` | pass | differs | the mark on ink |
| `testMessageBubbleUserShort`, `testMessageBubbleUserLong` | pass | differ | the host canvas only; the student's gradient bubble is unchanged |
| `testQuizViewLoading`, `testQuizViewLoaded`, `testQuizViewFailedRetryable`, `testQuizViewFailedNonRetryable` | pass | differ | the sheet's canvas, question cards, option rows and text in Night |
| `testCurriculumListAtAccessibilityXXL` | stale | new render | canvas and rows |
| `testEmptyChatViewLight`, `testEmptyChatViewDark` | stale | new render | canvas, prompt cards and text. **Light and Dark now render identically** (the same pixel hash): the tokens ignore the trait |
| `testEmptyChatViewAccessibilityXXL` | stale | new render | as above, at XXL |
| `testLessonCompleteOverlayWithNext`, `testLessonCompleteOverlayLastLessonDark` | stale | new render | the sheet's surface and text, and no sheet shadow |
| `testMercAllStates` | stale | new render | the canvas behind Merc; Merc is unchanged |
| `testMessageBubbleAssistantPlain`, `testMessageBubbleAssistantTyping`, `testMessageBubbleAssistantFailed` | stale | new render | the bubble (`surfaceElevated`), text and `errorText` |
| `testModeSelectorDefault`, `testModeSelectorAtAccessibilityXXL` | stale | new render | the pills on ink, and the inactive labels |

**When re-recording:**
- Tests that pin `userInterfaceStyle: .light` now photograph an appearance the app no longer has. Consider pinning them `.dark`, or dropping the Light/Dark pairs.
- Then write a new baseline from the re-recorded run (`WRITE_BASELINE=1 scripts/ios-unchanged-check.sh`).

## App Store screenshots to retake

Every current store screenshot shows the light appearance, which the app no longer has.

- **iPhone 6.9" (1320 × 2868) and iPad 13" (2064 × 2752).** Retake all six listing shots: the path, a lesson with cards, the Socratic chat, Home, Settings with delete, and the consent screen. Settings has also lost its Appearance section. `ios/scripts/screenshots.sh` makes both sets.
- **Mac (2560 × 1600).** Retake all six: path, lesson, chat, today, gate-consent and chat-thread, with `scripts/mac-store-screenshots.sh`. The harness still asks for light, but the windows stay dark.
- **The Mac description.** The bullet "Light and dark appearance." is no longer true. `docs/APP_STORE_LISTING.md` now reads "One night look: dark, whatever your Mac's appearance." Confirm the wording, then paste it into App Store Connect.

`docs/APP_STORE_LISTING.md` and the comment in `mac-store-screenshots.sh` now say the sets are dark.

## The review round

The review found one real contrast problem and three polish items. All four are fixed.

| Finding | Done |
|---|---|
| **Medium:** the selected tab's label was the fill indigo, 3.2 to 3.6:1 on its highlight | Fixed: the interface tint is `accentText` on the tab shell, and on Home, the gate, and the History and Progress sheets. Now 6.76 / 7.59 measured. Tested |
| **Low:** Home's ring track nearly vanished (1.22:1) | Fixed: `border`, the same as the Mac's Today ring. The top bar's level ring too |
| **Low:** the Settings headers and footers used the system grey | Fixed: `textSecondary`, plus Night's hairline between rows and the About header in the same form. The same on the iPhone's Privacy choices |
| **Low:** a stub divider under "Copy" in the Session row | Fixed: the divider starts at "Session ID" (`.alignmentGuide(.listRowSeparatorLeading)`) |

**Not done, and why:**
- **Giving the asset `AccentColor` a lighter iOS value.** Not needed for the alerts: the shots show that SwiftUI alerts take the presenting view's tint. The chat's alert, under the tab shell, and the Settings alerts both draw their buttons in `#A5B4FC`, at 6.7 to 6.8:1. The asset is also one catalog shared with the Mac target, so a new value would change the Mac unless it were an iPhone/iPad idiom variant. And the asset fills system controls that put white on top, so a light value needs its own pass with shots of the share and print sheets.
- **Re-applying `.tint(BrandColor.accent)` inside the tabs.** Nothing in the chat or curriculum tabs uses the inherited tint as a fill: the switches set their own, and there are no prominent bordered buttons. Spinners and the caret now draw in `accentText`.
- **The level ring and the Progress sheet's tint** are behind the gamification flag (off), so they are fixed in code but not visible in any shot.

## Known issues and follow-ups

- **Snapshot references:** 23 to re-record (the founder's). See the table above.
- **The certificate:** re-check after merging `feat/certificate`, and switch its `CertificateWiring` tint to `BrandAppearance.tint`.
- **Below 4.5:1, pre-existing:** white on the fill indigo (4.47:1), the quiz's green disc (2.28:1), and the system's destructive red in alerts (3.97:1).
- **`ThemePreferenceStore`, `ThemePreference` and `SettingsViewModel.theme`** are unread. Remove them once nothing needs the initialisers' shape.
- **The AX3 path:** the last node's "Locked" caption runs under the tab bar. That is layout, unchanged by this branch.
- **Not verified on a device:** the Increase Contrast variant on the iPhone (the unit tests pin the resolved values), and the share and print sheets.
- **CI's compiler:** Swift 6.0.3 isn't installed here, so `ci-compat-lint.py` stands in for it. The new code uses no 26-only API and no trailing commas in argument lists.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
