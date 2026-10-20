# Night Studio on the Mac: the architecture

Branch `feat/mac-night-studio` (worktree `.claude/worktrees/mac-night-studio`), stacked on `feat/mac-app-2026-10` (PR #47, itself on PR #43). Written 2026-10-20 with Xcode 26.4 / Swift 6.3 on macOS 26.3. Not pushed.

The founder asked: "make the mac app use the night studio design". This step plans how to theme the native Mac app in Night Studio (direction A of the October UI exploration) without changing a pixel of the iPhone app. It also records the iOS baseline, proves the Mac build-and-photograph recipe once, and checks the CI-safe pattern with a compile. No app code changed in this step. Only tools, a baseline and this note were added.

## The decision

**A hybrid (option c), in four layers:**

1. **Tokens, chosen at compile time per platform.** On macOS, `BrandColor` resolves to Night Studio's palette and `BrandFont` to Night Studio's Lexend roles. Both already branch per platform: `BrandColor.adaptive` has an AppKit branch and `BrandFont` has a `#if os(macOS)` ramp. The iOS branches are not edited. Because the shared views use 463 semantic colour tokens and 172 font tokens, this one layer re-colours and re-sets most of the Mac without touching a call site.
2. **Night components in DesignSystem.** These are new, platform-neutral files with a `Night` prefix: the palette (with Increase Contrast values), radii, motion, type roles, the canvas, lit surfaces, guarded glass chrome, the prominent button, the eyebrow, the rhythm ring and a resolved accessibility value. They compile on both platforms and are tested on every `swift test`. No iOS code path calls them yet.
3. **Shared views change only inside `#if os(macOS)`.** That includes postfix `#if` inside modifier chains (SE-0308, Swift 5.5). This is the pattern PR #47 already uses 80 times. There is never a runtime theme check on an iOS path.
4. **Mac-only views** under `AppFeature/Sources/Mac` (Today, the sidebar, Help, and a Night path view) are written in Night directly.

On iOS, a script proves that the compiler sees exactly the text it saw before for every existing file (§3).

---

## 1. Inventory: every view the Mac shows

Counts are call sites inside each file, measured with a script over the base branch:
- `BrandColor.*` uses (the main tokens, with counts);
- `BrandFont.*` uses;
- fixed-size `.system(size:)` fonts, which `BrandFont` doesn't reach;
- explicit shapes;
- existing `#if os(macOS)` branches.

"Layer" is where the Night change goes (L1–L4 above).

### 1.1 The Mac shell (Mac-only files, free to restyle)

| File | Lines | Colours | Fonts | Shapes / other | Night change | Layer |
|---|---|---|---|---|---|---|
| `MercuriusMac/App/MercuriusMacApp.swift` | 82 | 0 | 0 | the `Window`, `Settings` and Help scenes | Resolve `NightAccessibility` at each scene root | L4 |
| `MercuriusMac/App/MacSnapshot.swift` | 389 | 0 | 0 | the DEBUG harness | Add flags for Increase Contrast, Reduce Transparency and Reduce Motion variants | L4 |
| `Mac/MacShellView.swift` | 571 | 6: accent 2, background 2, text, accentText | 2 | `NavigationSplitView`; `.tint(accent)`; the gate box on `background` | The Night canvas behind the detail column; the gate on a calm canvas (no stars, no glow); tint `accentText` | L4 |
| `Mac/MacSidebar.swift` | 160 | 2: successText, accentText | 2 system | native sidebar `List` | Stays native (the system's sidebar material or glass); glyph tints from Night tokens | L1 |
| `Mac/MacTodayView.swift` | 396 | 28: textSecondary 12, text 7, accentText 2, accent 2, surface, surfaceElevated, border, background, streakFlame | 19: caption 10, body 3, subheading 3, title 2, bodyEmphasized; 2 fixed | one `card` helper (radius 16 plus stroke), a ring on `BrandGradient.mercHorizontal`, Merc, `ProgressView` | Night's Today: the one gradient hero card (Up next), the rhythm ring, a quiet streak line, Merc anchored in the layout, one eyebrow style | L4 |
| `Mac/MacHelpView.swift` | 171 | 7 | 5 | segmented tabs | Night type and tokens; its crisis numbers keep the crisis rules | L1, L4 |
| `Mac/MacSettingsView.swift` + `SettingsFeature/MacSettingsWindowView.swift` | 93 + 255 | 2 + 2 (+ 7 system) | 1 + 1 | the system grouped `Form` | Stays a native Settings window; Night only through tokens and tint. Delete My Data is untouched | L1 |
| `Mac/MacCommands.swift`, `MacShellModel.swift`, `MacSnapshotOptions.swift`, `MacAppSupport.swift`, `ChatFeature/Mac/MacChatSupport.swift` | 136 / 379 / 350 / 18 / 274 | 0, except MacChatSupport (4: the drop highlight) | — | menus, routing, the erase hooks, harness options | None, apart from the drop highlight's tokens. **The erase hooks and the gating are not edited.** | — |

### 1.2 Shared views the Mac hosts

| View (file) | Lines | Mac branches today | Colours | Fonts | Shapes, gradients, shadows, buttons | Night change on the Mac | Layer |
|---|---|---|---|---|---|---|---|
| `RootView` (failure state only on the Mac) | 482 | 3 | 4 | 2 + 1 fixed | `BrandButton` | Tokens; the Night button | L1, L3 |
| `AppEntryView` (the gate decision) | 434 | 3 | 0 | 0 | — | **None.** The consent/age gate stays before any network call | — |
| `OnboardingFlow` / `OnboardingSteps` / `YourPathStep` (gate, age, consent, path) | 236 / 740 / 81 | 0 / 4 / 0 | 2 / 22 (text 6, accent 5, textSecondary 4, background 2, accentText 2, surface 2, border) / 2 | 0 / 12 (body 6, title 3, bodyEmphasized 2, caption) + 2 fixed / 2 | radius 10 ×3 and 16 ×2, 3D `DuoButton` ×8, gradient, Merc ×2, Reduce Motion ×4 | Lexend display title, lit choice rows, `NightPrimaryButton` in place of `DuoButton`. **Logic, order and copy unchanged** | L1, L3 |
| `ChatView` | 1067 | 7 | 16: background 3, textSecondary 3, accentText 3, surfaceElevated 2, accent 2… | 4 + 2 fixed (rounded) | 5 capsules (chips), 1 shadow, Merc | Canvas; chips as quiet chrome | L1, L3 |
| `MessageBubbleView` | 638 | 6 | 19: textSecondary 3, accent 3, success 2, surface 2, accentText 2, user-bubble gradient… | 6 + Lexend reading + 3 fixed (one 11.5 pt heavy rounded) | radius 16 ×3, avatar circles, accent→violet bubble with white text, 1 shadow | Merc's reply full width with no bubble, headed "Merc · AI tutor"; the student's turn as an indigo-tinted card with ink text | L3 |
| `BlockCards` ([KEY], [EX], [Q]) | 222 | 0 | 25: accentText 5, text 3, border 3, accent/success/error ×2 each, surface 2… | 0 BrandFont; 7 fixed (11 pt heavy rounded eyebrows) | radius 16 ×4 and 6 ×2 | [EX] a lit block with mono example text; [KEY] the New York "keep" card (no "Saved to notebook"); [Q] lit option rows with letter discs | L3 |
| `ReplyMarkdownTheme` / `ReadingFace+MarkdownUI` | 162 / 31 | 0 | 6 | Lexend | radius 10, 2 and 6 | Tokens (code blocks on `surfaceRaised`) | L1 |
| `ChatInputBar` | 444 | 11 | 26: textSecondary 7, accent 6, background 4, surfaceElevated 3, border 3, errorText 2 | 3 + 5 fixed (symbols) | radius 10 ×4 and 22 ×2, gradient send button, 1 shadow | Guarded glass composer (an opaque surface under Reduce Transparency); send on `accentDeep` | L2, L3 |
| `ChatInputHint` / `EmptyChatView` / `MercCoachCard` | 100 / 164 / 128 | 0 / 0 / 1 | 8 / 6 / 9 | 1 + 2 fixed / 3 / 2 fixed rounded | — / radius 10 ×2, Merc / radius 16 ×2, `brandShadow` | Lit prompt cards, eyebrow, Lexend | L1, L3 |
| `ModeDescriptionSheet` (sheet) | 185 | 2 | 14 | 7 + 1 fixed | radius 10 ×2, `BrandButton` | Tokens; Night button | L1, L3 |
| `QuizView` ("Quiz me" sheet) | 305 | 0 | 33: text 6, accentText 4, textSecondary 4, accent 4, success 3… | 10 | radius 16 ×3 and 10 ×3, `BrandButton` ×3 | Tokens; Night button; lit option rows | L1, L3 |
| `CurriculumLessonView` | 829 | 9 | 13 | 6 fixed (heavy/black rounded intro and header), 8 `@ScaledMetric` | radius 22 ×2 and 16, gradient, 2 shadows, Merc | Intro and title in Lexend display. "Part N · name" counts parts so far, in the toolbar subtitle (never "of N"). Reading column on the canvas | L3 |
| `LessonCompleteOverlay` (+ `LessonShareCard`) | 427 (+172) | 8 (+1) | 9 | 3 + 2 fixed (black rounded headline) | radius 28 and 16, 2 shadows, `BrandButton` ×5, Merc ×2 | The Mac's centred card in Night: Merc in the layout, the credential line, "Done for now" at equal weight. **The share card image is unchanged** (it is the existing share feature, not a graft) | L3 |
| `CurriculumView` / `LearningPathView` / `LessonNode` / `PathConnector` / `UnitCheckpointHeader` | 96 / 430 / 438 / 41 / 53 | 0 | 1 / 7 / 10 / 1 / 0 | 0 / 3 rounded / 4 rounded + 1 fixed / 0 / 3 rounded | Duolingo zig-zag, 3D nodes, 5 gradients, 4 white-on-gradient labels | Night path: a lit unit cover, the lessons on a thread of light, numbers not padlocks, the checkpoint mark | L4: a Mac-only `MacNightPathView` on `CurriculumProgressStore`, with the node-status rules extracted (below) |
| `UnitTestView` / `UnitTestOptionRow` | 483 / 143 | 9 / 0 | 38 (textSecondary 12, text 7, accentText 5, border 3, surface 3…) / 19 | 24 (body 11, bodyEmphasized 6, caption 5…) / 3 | radius 10 ×10 | Lit question cards, letter discs, Lexend. **The keys (A–D, 1–4, Tab, ⌘Return, Escape) stay** | L1, L3 |
| `CrisisSupportView` (+ `MacCrisisNumbers`) | 330 | 2 | 21: text 7, textSecondary 4, border 4, accent 2, surface 2… | 11 + 1 fixed | radius 10 ×4, `BrandButton` | **Palette only (L1).** No canvas, glow, stars, Merc, gradient or eyebrow. A test pins it | L1 |
| `StreakChip` (toolbar) | 87 | 2 | 5 (streakFlame ×2) | 1 + 1 fixed | capsule | Quiet: a Night glyph and count. Whether the flame stays is the spec's call (§7) | L3 |
| `ProgressHubView`, `ProgressCard`, `StreakHeroView`, `AchievementsGalleryView`, `AchievementToastView`, `ProgressNudgeView`, `RecentCreditsView`, `RemindersSection` (sheets and toasts) | 93 / 73 / 45 / 56 / 78 / 82 / 66 / 172 | 0, except RemindersSection 1 | 3 / 9 / 8 / 8 / 5 / 6 / 8 / 7 | 2 rounded / 4 / 4 + 2 fixed rounded / 3 / 2 / 3 / 3 / 5 | radius 16 cards, 2 shadows | Tokens (L1); rounded tokens become Lexend through `BrandFont.rounded*` | L1 |
| `PrivacyChoicesView`, `DeleteFailureAlert`, `HowMercuriusTeachesView` | 135 / 161 / 110 | 0 | 4 / 7 / 7 | 2 / 4 / 6 | radius 10 | Tokens only. **The delete and withdraw paths are untouched** | L1 |
| DesignSystem: `BrandButton`, `DuoButton`, `MercMascot` | 91 / 145 / 459 | 0 | 7 / 9 / 6 | 1 / 1 / 0 | flat button / 3D button / Merc's badge on `surfaceElevated` | The Mac's call sites switch to the Night button (L3). Merc's own colours are fixed hex and stay. | L2, L3 |

**Not on the Mac** (iOS only; out of scope):
- `HomeView`, `AppShellView`, `ModeSelectorView` (the Mac uses a toolbar picker), `ChatHistoryView` (the Mac uses the sidebar), `GamifiedTopBar`;
- `SettingsView`/`SettingsSheet` as views (the Mac uses only `SettingsSheet.makeModel`);
- `MercLaunchScreen` (the Mac shows `Color.clear`);
- the Live Activity and the widgets.

### 1.3 Totals, and what they decide

Across the 58 files the Mac reaches (14,375 lines):
- **463 `BrandColor` uses, all semantic.** The only raw hex is in Merc's own art. A token swap therefore re-colours nearly everything.
- **172 `BrandFont` uses.**
- **About 52 fixed-size `.system(size:)` fonts**, about 30 of them SF Rounded heavy or black (the lesson intro and header, the celebration, the coach card, the block eyebrows, the path). `BrandFont` can't reach these, so each needs a Mac branch.
- **107 explicit shapes:** 72 rounded rectangles (mostly `BrandRadius.lg` = 16 and `.md` = 10, plus literal 22, 28 and 16), 16 capsules and 19 circles.
- **20 gradients** (13 on `BrandGradient`, whose magenta end Night retires in UI chrome; Merc keeps his), **9 shadows**, **2 button families** (the flat `BrandButton` and the 3D `DuoButton`).
- **80 existing `#if os(macOS)` branches**: the pattern is proven, and PR #47's iOS tests stayed green with it.

---

## 2. The mechanism

### 2.1 The options

| | (a) A `MercTheme` environment value (default = today; the Mac injects `.nightStudio`), read by the shared views | (b) Mac-only replacement views reusing the view models | **(c) Hybrid (recommended)** |
|---|---|---|---|
| **Risk to iOS** | Medium. Every restyled view gains an environment read and a runtime branch that iOS executes. Today's look must be rebuilt exactly in a "classic" branch that no compiler checks. Only about 8 of the 45 views have snapshots. Colours are `static let`s, so either 463 call sites move to `theme.x` (an iOS diff everywhere) or the tokens read a mutable global | None | None for existing files: iOS compiles identical text (proved by `ios-source-diff.py`). New Night files compile on iOS but nothing iOS already compiles calls them |
| **Duplication** | None | High. About 5,000 lines of `ChatView`, `CurriculumLessonView`, `MessageBubbleView`, `ChatInputBar`, `UnitTestView`, `OnboardingSteps` and `CrisisSupportView` would be copied. That includes streaming, scroll policy, Report, crisis routing, the erase stop, the Escape and A–D rules and the consent gate. PLAN.md's "gate logic is shared, not copied" rules it out for safety | Low. Only presentational code is duplicated: one Mac-only path view (the status rules are extracted, not copied) and Today, which is already Mac-only |
| **Safety paths** | Shared, but iOS behaviour now depends on a runtime value | Forked: crisis, report, delete and the gate drift between platforms | Shared and unedited. Only their colours change on the Mac |
| **Later iOS Night (roadmap Q8 / M1)** | Easiest to flip on, but iOS carries both looks in every view until then | Nothing carries over: the Mac views are Mac-shaped | Q8: point the UIKit branch of `BrandColor.adaptive` at the same Night mapping (one function), and `BrandFont`'s iOS branch at Lexend `relativeTo:`. M1 and the screens: lift a view's `#if os(macOS)` Night branch to shared, adding Dynamic Type where the Mac used fixed ramp sizes. The Night components already compile on iOS and are already contrast-tested |
| **Testing** | Snapshots on iOS; both looks need tests | Mac only | iOS: the source diff, the snapshot baseline, the UI suite. Mac: `swift test` (Night tokens, contrast, the crisis rule), the harness |

### 2.2 Why (c), and why the theme switch isn't an environment value

- **The Mac never switches.** The founder asked for the Mac app *in* Night Studio, not for a choice of looks. A compile-time platform choice is the theme, as `MacTypeRamp` already is for type.
- **The tokens are statics read at 635 call sites.** An environment theme can't reach them without rewriting every call site on iOS too.
- **The one environment value Night does need is narrow:** `NightAccessibility` (Increase Contrast, Reduce Transparency, Reduce Motion), resolved once per scene root. SwiftUI's own `colorSchemeContrast`, `accessibilityReduceTransparency` and `accessibilityReduceMotion` are read-only (checked with a compile), and the screenshot harness must not change the Mac's system settings. So the value is the system's setting OR a DEBUG launch override (`-NightIncreaseContrast YES`, `-NightReduceTransparency YES`, `-NightReduceMotion YES`). Colour providers read the same override plus `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`, because a window forced to `.darkAqua` by `.preferredColorScheme` may not carry the high-contrast appearance name.
- **A seam for a later iOS A/B**, if the student test wants grafted A against today on iPhones: make `adaptive` read a launch-time `BrandPalette.active`. That is one function, not 463 call sites. It isn't built now.

### 2.3 Layer 1: the token mapping on the Mac

Only on macOS: the AppKit branch of `BrandColor.adaptive` and the `#if os(macOS)` side of `BrandFont`. `BrandPalette` (the iOS values) and `BrandContrastTests` stay as they are. A new `NightPalette` holds the Night pairs, with Increase Contrast values, and `NightContrastTests` checks them.

| `BrandColor` token (today: light / dark) | On the Mac (Night: light / dark) | Notes |
|---|---|---|
| `background` `#F7FAFC` / `#0B0F30` | `canvasTop` `#F6F5FC` / `#0B0E2E` | The flat fill. Screen roots draw `NightCanvas` (a gradient plus glow pools; stars in dark only) |
| `surface` `#FFFFFF` / `#11163A` | `surface` `#FFFFFF` / `#121641` | Lit surfaces |
| `surfaceElevated` `#EEF0F7` / `#1A1F4A` | `surfaceRaised` `#F2F1FB` / `#1A1F52` | Option rows, wells. Merc's badge too (harmless) |
| `text` `#0F142A` / `#E6E9F5` | `ink` `#0E1230` / `#F1F2FF` | |
| `textSecondary` `#5D6A8A` / `#9AA3C2` | `ink2` `#434A6E` / `#B7BDE2` | `ink3` is new, for captions only |
| `border` `#D9DEEC` / `#242A5A` | `hairline`: ink @ 9% / white @ 10% | Decorative strokes. A boundary that is a control's only outline needs 3:1 (WCAG 1.4.11): under Increase Contrast it becomes solid |
| `accent`, `accentLight`, `accentDark`, `mercViolet` | unchanged (`#6366F1`, `#8B5CF6`, `#4C51BF`, `#7C3AED`) | Fills only. `accentDeep` `#4338CA` is new, for the one prominent control |
| `accentText` `#4F46E5` / `#A5B4FC` | the same values | Night uses the same pair |
| `successText` `#166534` / `#22C55E` | `#166534` / `#6EE7A8` | |
| `errorText` `#B91C1C` / `#F87171` | unchanged | Night defines none; checked on Night surfaces below |
| `streakFlame`, `xpGold*` | unchanged as tokens | Night has no orange or gold. Their Mac call sites are a spec decision (§7) |
| `BrandGradient.merc` / `.mercHorizontal` | unchanged as tokens | Merc and the share card keep the magenta end. The Mac's UI call sites (ring, path, send) move to Night light (indigo→violet) in L3 |

**Type on the Mac** (`BrandFont`'s macOS side, `MacTypeRamp` sizes unchanged):

| Role | Today on the Mac | Night on the Mac |
|---|---|---|
| `largeTitle`, `title`, `subheading` | SF Bold or Semibold at 28 / 22 / 16 pt | Lexend SemiBold at 28 / 22 / 16 pt; tracking −0.7 / −0.5 / 0 |
| `body`, `bodyEmphasized` | SF 15 pt | Lexend Regular / SemiBold, 15 pt |
| `caption` | SF 12 pt | Lexend Regular, 12 pt |
| `rounded*` | SF Rounded | The Lexend equivalents (Night retires SF Rounded) |
| `mono` | SF Mono 12 pt | unchanged |
| `reading` (replies) | Lexend 15 pt | unchanged |
| New roles | — | `NightType.eyebrow` (Lexend SemiBold 12 pt, uppercase, +1.3), `keep` (New York, `.serif` medium, for [KEY]), `machine` (SF Mono, for [EX] tokens) |

The window's own chrome stays the system's: the sidebar, toolbar, menus and the Settings form. None of them uses `BrandFont`, and that is the Mac convention.

**Contrast, computed now from the hex values** (WCAG; the lowest value over canvas top, canvas bottom, surface, surface raised and an accent-tinted row):
- **Light:** ink 15.4, ink2 7.2, ink3 5.0, accentText 5.3, successText 6.0, errorText 5.4.
- **Dark:** ink 13.3, ink2 8.0, ink3 5.2, accentText 7.4, successText 9.6, errorText 5.4.
- White on `accentDeep` is 7.9. White on the hero gradient's lightest stop is 7.1 (light) and 10.3 (dark).

**Two findings for the foundations step:**
1. **The canvas glow is a surface too.** Text directly over the peak of both glow pools falls under 4.5 with the lab's opacities (16% and 10% light, 34% and 22% dark): ink3 drops to 4.07 (light) and 3.41 (dark). Either cap the pools at 10% and 6% (light) and 18% and 12% (dark), the worst case then being 4.58 and 4.74, or keep text off the bare canvas. Whichever is chosen, `NightContrastTests` must include the glow peak.
2. **White on `accent` `#6366F1` is 4.47:1.** Today's student bubble (white text on an `accent`→`accentLight` gradient) is under AA at its lightest stop. Night's tinted card with ink text (15.4) fixes it on the Mac.

### 2.4 Layer 2: Night components in DesignSystem

These are new files under `DesignSystem/Sources/Night/`. They are platform-neutral and not `#if DEBUG`, and every name has a `Night`/`night` prefix, so no new overload or extension member can capture an existing iOS call.

They are ported from `explore-ui-a/…/DesignLab/NightStudio.swift`, with the judges' fixes inside A:

| Component | What it is, and the fixes it carries |
|---|---|
| `NightPalette` + `NightColor` | Pairs: light, dark, light increased contrast, dark increased contrast. `NSColor`/`UIColor` providers. The lab's `Color.night` returned light only on the Mac and must not be copied. |
| `Night.Radius`, `Night.Space` | hero 30, card 22, row 16, chip 10; gutter 20, section 28, stack 14 |
| `Night.Motion` | tap, layout, milestone and fade. Under Reduce Motion, everything is the fade. |
| `NightCanvas` | Glow caps from §2.3. Stars in dark only, and never under Increase Contrast. Never on the crisis view. |
| `nightLit(radius:)` | One shadow on the shape in light, none in dark (roadmap Q8). In dark, a fill plus the top-edge highlight. Under Increase Contrast, a solid border. |
| `nightChrome(in:)` | Glass behind `#if compiler(>=6.2)` and `#available(macOS 26, iOS 26, *)`, a material otherwise, an opaque surface under Reduce Transparency (§5) |
| `nightProminent(in:)`, `NightPrimaryButtonStyle`, `NightSecondaryButtonStyle` | Opaque `accentDeep` outside glass. They are `ButtonStyle`s, so they stay real `Button`s: keyboard shortcuts and Return/Escape keep working, and the spec must check the focus ring with Full Keyboard Access. |
| `NightEyebrow`, `NightType` | One eyebrow style |
| `NightRhythmRing` | Gives a VoiceOver summary ("1 of 2 lessons this week") instead of the lab's hidden week dots |
| `NightAccessibility` | The environment value of §2.2, with its DEBUG overrides |

### 2.5 Layer 3: rules for editing a shared view

1. **Every change sits inside `#if os(macOS)` … `#else` (today's code, untouched) … `#endif`.** Postfix `#if` in a modifier chain is fine.
2. **Don't move or reformat iOS code.** `ios-source-diff.py` must report `same` for the file.
3. **Don't edit the logic files:**
   - `AppEntryView`;
   - `ConsentGate`;
   - `SettingsViewModel`;
   - `MacShellModel`'s erase and gate hooks;
   - `ChatViewModel`;
   - `UnitTestViewModel`.
4. **One exception, for the path.** The node-status rules (`lessonStatus` and `unitTestStatus`, private to `LearningPathView`) move, verbatim, into an internal static function that both views call. That is the one place iOS text may change, and it changes by a move, not by an edit. It needs its own unit tests, and `ios-source-diff` will show it as CHANGED for review. If the spec prefers, the Mac view can call the function without the move, by making it `static` in place.
5. **Crisis:** `CrisisSupportView` gets no Mac edits beyond what L1 gives it. A test asserts its body uses no Night decoration (no `NightCanvas`, `nightLit` glow, Merc or gradient).
6. **Honest copy:**
   - no "Saved to notebook";
   - no "Rest days never reset your progress";
   - "Part N" counts parts so far, never "of N";
   - no time estimates ("about 6 min") unless measured;
   - no "Every lesson is previewable";
   - the path says when a lesson opens, not that it's open.

### 2.6 Layer 4: the Mac-only views

- **`MacTodayView`:** Night's Today.
- **`MacShellView`:** the canvas and `NightAccessibility`.
- **`MacHelpView`.**
- **A new `MacNightPathView`:** it hosts the unit's stretch of the path, and it keeps the Mac's path rules:
  - the unit per sidebar row;
  - the toolbar streak button;
  - no top-bar `safeAreaInset` (it blanked the path once the sidebar folded on macOS 26; see PR #47 step 05).

---

## 3. Proving iOS is unchanged

Four checks. They were run on the base today, and every later step reruns all four.

**1. Source: the iOS compiler sees the same text.**

```bash
ios/scripts/ios-source-diff.py feat/mac-app-2026-10
```

- For each changed Swift file, it reduces the base and the head to what an iOS build compiles: `os(macOS)`, `os(iOS)`, `canImport(UIKit)`, `canImport(AppKit)` and `macCatalyst` are resolved; `DEBUG` and `compiler(...)` keep every branch; comments and whitespace are dropped.
- It exits 1 if any existing file's iOS text changed, and lists new iOS-visible files for review.
- **Today: 0 CHANGED.** Tested two ways:
  - a temporary `#if os(macOS)` addition reports `same`;
  - an unguarded line reports CHANGED with the diff.

  Both edits were reverted.

**2. Pixels: the snapshot comparison, with recording forced off.**

```bash
cd ios && scripts/ios-unchanged-check.sh /private/tmp/merc-mac-ns-logs/ios-check-<step>
```

- It runs `xcodegen generate`, then:

  ```bash
  TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never xcodebuild test \
    -project Mercurius.xcodeproj -scheme Mercurius \
    -destination 'platform=iOS Simulator,id=04DB5F67-DB97-4DCB-B8BC-C050A26AD10A' \
    -derivedDataPath /private/tmp/merc-mac-ns-dd \
    -only-testing:MercuriusTests/ViewSnapshotTests \
    -resultBundlePath <out>/snapshots.xcresult
  ```

  It retries a codesign "detritus" failure up to 3 times.
- It exports the failing tests' renders from the result bundle and hashes their RGBA pixels.
- It compares all 23 results with `docs/mac-night-studio/ios-snapshot-baseline.txt`.
- It fails if anything under `MercuriusTests/Snapshots` changed.

**The baseline**, recorded today at `1466d51` (= `feat/mac-app-2026-10`) on "Audit 16PM" (iPhone 16 Pro Max, iOS 26.4). Two runs gave the same 23 results and identical pixel hashes for all 12 renders.

- **11 pass:**
  - `testBrandButtonPrimary`, `testBrandButtonSecondary`;
  - `testBrandLogoFullDarkMode`, `testBrandLogoFullLightMode`, `testBrandLogoMark`;
  - `testMessageBubbleUserLong`, `testMessageBubbleUserShort`;
  - `testQuizViewFailedNonRetryable`, `testQuizViewFailedRetryable`, `testQuizViewLoaded`, `testQuizViewLoading`.
- **12 fail as already-stale references** (the same 12 PR #43 found stale at its own base; re-recording is the founder's):
  - `testCurriculumListAtAccessibilityXXL`;
  - `testEmptyChatViewAccessibilityXXL`, `testEmptyChatViewDark`, `testEmptyChatViewLight`;
  - `testLessonCompleteOverlayLastLessonDark`, `testLessonCompleteOverlayWithNext`;
  - `testMercAllStates`;
  - `testMessageBubbleAssistantFailed`, `testMessageBubbleAssistantPlain`, `testMessageBubbleAssistantTyping`;
  - `testModeSelectorAtAccessibilityXXL`, `testModeSelectorDefault`.
- `git status` under `__Snapshots__` stayed clean.

**What the pixel check doesn't cover:**
- A passing test compares at the suite's 98% precision, and its render isn't kept.
- Views with no snapshot aren't rendered at all.

Check 1 covers both.

**3. The iOS test suite, with CI's flags.**

```bash
cd ios && xcodebuild test -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,id=04DB5F67-DB97-4DCB-B8BC-C050A26AD10A' \
  -derivedDataPath /private/tmp/merc-mac-ns-dd \
  -skip-testing:MercuriusTests/ViewSnapshotTests \
  -skip-testing:MercuriusUITests/PerformanceTests \
  -skip-testing:MercuriusUITests/AppStoreScreenshots \
  -retry-tests-on-failure -test-iterations 3 -test-repetition-relaunch-enabled YES \
  -resultBundlePath <out>/ios-suite.xcresult
```

- PR #47 recorded 31 / 31 with these flags (6 unit, 25 UI).
- Today's base run: see "Base results" at the end of this note.
- UI-test anchors to keep: the iOS chat header, the "Debate" pill, Settings/Home, the tabs, the lesson intro's Continue, and the `onboarding.*` / `settings.*` identifiers. The Mac work doesn't touch them (they are iOS-only views or iOS branches).

**4. Package tests, with their own scratch path.**

```bash
cd ios/Packages && swift test --scratch-path /private/tmp/merc-mac-ns-spm
```

- Base today: **1026 tests in 153 suites passed** (0 XCTest cases).
- Every later step adds `NightContrastTests` and the crisis rule.

Also, every step:
- `ios/scripts/ci-compat-lint.py` (§5): 0 findings at base;
- the macOS Debug build (§4).

---

## 4. The Mac build, run and snapshot recipe

**The rules:**
- The founder is using the app: `com.mayoailiteracy.mercurius.native.macdev`, built at `/private/tmp/merc-mac-dd`, PID **98503** today.
- Never run `pkill -x Mercurius` or `killall Mercurius`.
- Never read from or write to `/private/tmp/merc-mac-dd`. `mac-snapshots.sh` defaults to that path, so always go through the wrapper below.

**Build** (from `ios/`, after `xcodegen generate`; retried for codesign xattr failures):

```bash
xcodebuild build -project Mercurius.xcodeproj -scheme MercuriusMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/merc-mac-ns-dd
```

Today: BUILD SUCCEEDED. The only warning is the usual `appintentsmetadataprocessor` note.

**Photograph a copy** (from `ios/`):

```bash
N=1 VARIANTS="light dark" scripts/mac-copy-snapshots.sh /private/tmp/merc-mac-ns-shots/<step> today chat lesson …
```

`ios/scripts/mac-copy-snapshots.sh` (new):
1. Copies `/private/tmp/merc-mac-ns-dd/…/Mercurius.app` to `/private/tmp/merc-mac-ns-copies/Mercurius-macns<N>.app`, and refuses a source under `/private/tmp/merc-mac-dd`.
2. Sets `CFBundleIdentifier` to `com.mayoailiteracy.mercurius.native.macns<N>` with PlistBuddy.
3. Re-signs ad hoc with `codesign --force --deep -s - --entitlements <the build's own>`, retrying up to 3 times after an xattr strip. The entitlements are kept so the copy stays sandboxed in its own container. `codesign --verify` passes.
4. Records every running `Mercurius` PID.
5. Runs `mac-snapshots.sh` with `MAC_APP=<copy>` and **`ACTIVATE=NO` by default**. The existing harness launches the copy's binary, moves its window off screen (−20000, −20000), never activates it, photographs it and quits it. A hung copy is killed by the PID the harness started, never by name.
6. Polls the frontmost app twice a second, and fails if the copy ever came to the front.
7. Fails if a PID from step 4 is gone, or if a copy process is left behind.

The copy runs isolated, as every harness run is:
- `-UITests` (in-memory chats, private suites);
- `-EphemeralSession` (no Keychain item);
- `-UseLocalServer` (nothing reaches production).

**The proof, run twice today:**

```
copy: /private/tmp/merc-mac-ns-copies/Mercurius-macns1.app (com.mayoailiteracy.mercurius.native.macns1, ad hoc)
running before: 98503
today: ok (2560x1600)            # second run: today-dark: ok (2560x1600), exit 0
frontmost apps seen: com.apple.Safari
running after: 98503
```

- `pgrep -lx Mercurius` afterwards: `98503 Mercurius`, the founder's, untouched.
- Focus never left Safari.
- The pictures are `/private/tmp/merc-mac-ns-shots/base/today.png` and `today-dark.png`. They show today's Mac look, as an inactive window (grey traffic lights) because `ACTIVATE=NO`. They are the "before" for the Night steps.
- The copy left a container at `~/Library/Containers/com.mayoailiteracy.mercurius.native.macns1` (test data only).

**For variants:** the foundations step adds `-NightIncreaseContrast YES`, `-NightReduceTransparency YES` and `-NightReduceMotion YES`. These are passed through `mac-snapshots.sh` as extra state arguments, or as new `VARIANTS` such as `hc` and `rt`. They avoid touching System Settings. Keep runs short: one state and two variants per check while iterating.

---

## 5. How the Night tokens stay CI-safe

CI compiles with Xcode 16.2 / Swift 6.0.3 on macOS 14 (the macOS 15 and iOS 18 SDKs). Locally we have Xcode 26.4 / Swift 6.3, and no older toolchain is installed (none was downloaded). So the guard pattern is checked with a compile here, and the two things the new compiler can't check are covered by a lint.

**The rules:**
1. **APIs newer than macOS 14 / iOS 17** need `if #available` (for example `MeshGradient`, macOS 15). They also need an SDK that has them: the macOS 15 SDK has nothing from 26.
2. **Liquid Glass** (`glassEffect`, `Glass`, `GlassEffectContainer`, `safeAreaBar`, `.buttonStyle(.glass)`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`) goes inside `#if compiler(>=6.2)`, with `if #available(macOS 26.0, iOS 26.0, *)` inside it and a material fallback in **both** the `else` and the `#else`.
   - Swift 6.0.3 never parses a `#if compiler(>=6.2)` body, so the 26-only symbols never reach it.
   - A forced-fallback flag is nested inside the compiler check, not `&&`-ed onto it.
   - Reduce Transparency comes before all of it: an opaque lit surface.
3. **No Double·CGFloat mixing in `sin`/`cos`/`pow`.** Keep the argument the type of what it multiplies, or convert explicitly: `CGFloat(sin(Double(x)))`. See `a1754ef`.
4. **No Swift 6.1+ syntax.** In particular, no trailing comma in an argument or parameter list.
5. **Packages use Swift 5 mode** (tools 5.10). The app targets use Swift 5 with `SWIFT_STRICT_CONCURRENCY: complete`. Colour providers may read `NSWorkspace.shared` (checked under complete checking and in Swift 6 mode). Launch overrides are `static let`s, not `static var`s.

**The probe:** `docs/mac-night-studio/ci-probe/NightCIProbe.swift` models rules 1–5. It has a palette pair with Increase Contrast values, an `NSColor`/`UIColor` provider with a DEBUG override, the guarded chrome with a Reduce Transparency fallback, and a composer view reading `colorSchemeContrast`, Reduce Transparency and Reduce Motion. Its increased-contrast hex values are placeholders: the foundations step sets the real ones.

`docs/mac-night-studio/ci-probe/run.sh` type-checks it in Swift 5 mode with `-strict-concurrency=complete`. Output today:

```
ok    macOS 14 arm64, glass path
ok    macOS 14 arm64, material fallback
ok    macOS 14 x86_64, glass path
ok    macOS 14 arm64, DEBUG
ok    iOS 17 simulator, glass path
ok    iOS 17 simulator, material fallback
ok    unguarded glassEffect rejected: 'glassEffect(_:in:)' is only available in macOS 26.0 or newer
note  a trailing comma in an argument list compiles here (Swift 6.1+); CI's 6.0.3 rejects it — grep for it
ok    a #if compiler(>=99) body is skipped unparsed (as 6.0.3 skips >=6.2)
```

**The lint:** `ios/scripts/ci-compat-lint.py` catches:
- trailing commas before `)`;
- 26-only symbols outside a `#if compiler(>=6.2)` block (the `#else` counts as outside).

It found **0 findings at base**, and 3 of 3 planted problems in a test file. It can't check trig typing; that stays a review rule.

**Not provable here:** that CI's own Xcode 16.2 compiles the branch. The Mac CI job (PR #47) and the `spm` job are the proof once pushed. The roadmap's CI upgrade (Q5: macos-26 / Xcode 26) would also put the glass path itself under CI.

---

## 6. Proposed steps

Each step ends with:
- the four iOS checks of §3;
- the lint;
- the Mac Debug build;
- copy snapshots, light and dark, plus the accessibility variants once they exist;
- its own `docs/mac-night-studio/<step>.md`;
- a local commit.

1. **Spec.** Screen-by-screen Night for the Mac. It settles §7's questions, the copy, and the Increase Contrast values.
2. **Foundations (L1 + L2):**
   - `NightPalette` and the Mac token swap;
   - the Lexend roles;
   - the Night components;
   - `NightAccessibility` and the harness flags;
   - `NightContrastTests` (every text pair in 4 appearances, including the glow peak);
   - the crisis rule test.
3. **Shell, canvas and Today.**
4. **Chat:** replies without a bubble, student cards, blocks, the composer, the empty chat, the coach card, the Quiz and mode sheets.
5. **Lesson and lesson complete:** the intro, "Part N" in the toolbar, the blocks inline, the Mac celebration card.
6. **Path:** `MacNightPathView` and the extracted status rules.
7. **Unit check, gate and onboarding, the Progress sheets and Help.** Crisis is checked for palette only.
8. **Accessibility and keyboard pass:**
   - Increase Contrast, Reduce Transparency and Reduce Motion shots;
   - VoiceOver labels on custom controls (ring, discs, the beat meter);
   - focus rings with Full Keyboard Access;
   - Return, Escape and A–D still working.
9. **Verify and write up.**

## 7. Questions for the spec (none block the architecture)

- **The streak on the Mac.** Night drops the flame for a quiet line. Is that a look-only change, without "rest days never reset" or any other promise?
- **"Lock it in."** It is A's own commit-before-reveal, but it turns today's one-click [Q] answer into two steps. Adopt it, or keep one click with Night styling? "Sure / Not sure" is a graft and stays out unless honesty needs it.
- **Source chips.** A's chat shows them. A client-side `[SOURCE: …]` parser for both server formats would fix a raw-tag leak too. Is it in scope? If so, the chip shouldn't read as verified ("pinned source").
- **The path's locked lessons:** a number plus "Opens after Lesson 3" (honest copy), not a padlock and not "previewable".
- **The glow pools:** cap them, or keep text off the bare canvas (§2.3).
- **Out of scope unless asked:** the meaning-sky signature (new authored content, roadmap B2), the notebook, the hint ladder and the share-card redesign.

---

## Files added in this step

- `docs/mac-night-studio/ARCHITECTURE.md` (this note).
- `docs/mac-night-studio/ios-snapshot-baseline.txt`: the 23 results and 12 render hashes at base.
- `docs/mac-night-studio/ci-probe/NightCIProbe.swift`, `run.sh`: the compile probe.
- `ios/scripts/mac-copy-snapshots.sh`: photographs a re-identified, ad hoc signed copy without touching a running Mercurius.
- `ios/scripts/ios-unchanged-check.sh`: the snapshot comparison against the baseline, recording off.
- `ios/scripts/ios-source-diff.py`: what the iOS compiler sees differently from base.
- `ios/scripts/ci-compat-lint.py`: Swift 6.1+ syntax and unguarded 26-only symbols.

Scratch outputs (not committed): `/private/tmp/merc-mac-ns-logs/`, `/private/tmp/merc-mac-ns-shots/base/`.

## Base results (2026-10-20, `1466d51`)

| Check | Result |
|---|---|
| `ios-source-diff.py` | 0 CHANGED (nothing changed yet; planted edits tested, then reverted) |
| `ios-unchanged-check.sh` / the snapshot suite, recording off | 11 pass, 12 stale; identical in two runs, pixel hashes included; `__Snapshots__` clean |
| iOS `xcodebuild test`, CI's flags, Audit 16PM | **TEST SUCCEEDED, 31 / 31:** 3 XCTest unit (`ReplyTextScaleTests`), 3 Swift Testing (launch, 2 Live Activity), 25 UI. Each test ran once, with no retries. `testUnderThirteenIsBlocked` was slow (370 s) but passed |
| `swift test --scratch-path /private/tmp/merc-mac-ns-spm` | 1026 tests in 153 suites passed |
| `ci-compat-lint.py` | 0 findings |
| `ci-probe/run.sh` | all checks ok (§5) |
| macOS Debug build into `/private/tmp/merc-mac-ns-dd` | BUILD SUCCEEDED |
| `mac-copy-snapshots.sh` (`today`, light then dark) | ok ×2, exit 0. Founder's PID 98503 before and after; frontmost app only Safari |
