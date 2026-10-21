# Night Studio for the Mac app: the spec

**Branch:** `feat/mac-night-studio` (worktree `.claude/worktrees/mac-night-studio`), stacked on `feat/mac-app-2026-10` (PR #47), which is stacked on PR #43. Not pushed.
**Step:** this is step 01, the spec. Later steps write their own notes in this folder.
**Asked for:** "make the mac app use the night studio design".
**Sources:**
- the DesignLab concept (`explore-ui-a/…/DesignLab/NightStudio.swift` and the six `Night*.swift` screens) and its shots (`explore-ui-shared/dir-a/`);
- the four judges and `SYNTHESIS.md` ("Fix inside A before anyone sees it", the honesty rules);
- the Mac app as it is on PR #47 (`docs/mac-app/`, `key-shots/`).

This spec is what three engineers build from. Where the concept and the Mac disagree, the Mac wins and the reason is given. Every value below is a decision, not a suggestion. If something here is wrong, change the spec first, then the code.

---

## 0. Decisions at a glance

| # | Decision | Why |
|---|---|---|
| D1 | **iOS does not change.** Every Night API is inside `#if os(macOS)`. The Mac gets the Night palette by remapping `BrandColor` under `#if os(macOS)`; the iOS branch of every file compiles exactly as today. | Hard rule. The iOS snapshot tests and `BrandContrastTests` keep testing today's iOS values. |
| D2 | **Night Studio itself, no other directions' grafts.** No "Sure / Not sure", no notebook, no hint ladder, no "In your words", no share card, no unit-mastery ceremony. | The founder asked for Night Studio. §7 says how each could come later. |
| D3 | **The judges' "fix inside A" list applies,** translated for a Mac: the gradient once (Today only), Merc anchored in the layout, the curiosity card above the fold, 44 pt-class targets, Increase Contrast and Reduce Transparency variants, one shadow per shape and none in dark mode. The docked check tray is **not** built on the Mac (the check stays inline; §5.3). | SYNTHESIS §2; the engineer judge's conditions. |
| D4 | **No UI text promises a feature that doesn't exist.** The register of rewrites is §6. | Hard rule; all four judges. |
| D5 | **Content is never on glass.** Glass (macOS 26) or a material (macOS 14–25, and every CI build) is only for floating chrome: the composer, the lesson's part strip, the Jump to latest pill, the reply chips. Prominent buttons are **opaque on every OS**, so white text has a computed contrast. | A's own rule, plus certainty: glass contrast can't be computed and the harness can't photograph it. |
| D6 | **The crisis view gets the palette only:** flat canvas, plain card, system type, no Merc, no light, no motion. | Hard rule. |
| D7 | **The consent gate's wording, order and logic don't change.** Its steps get Night type and colour only. | Versioned consent text; no network before consent. |
| D8 | **The streak leaves the toolbar.** Path and Chat get a Progress button (chart icon, ⌘4) instead of the flame and count. The streak stays on Today as one quiet line, and in Progress. | A's "no number on chrome". Reversible in one toolbar item; listed for the founder (§8.6). |
| D9 | **"Lock it in" on the Mac's lesson checks.** Pick an answer (click, or A–D on the focused card), then Lock it in (button or Return) grades it and sends "I picked B) …" exactly as today. iOS keeps tap-to-answer. | A's commit-before-reveal; it's Night Studio's own, not a graft. |
| D10 | **Settings stays a native Mac settings window,** with the Night accent. | Mac convention; the Delete my data path is untouched. |

---

## 1. Ground rules for the code

### 1.1 Where things live

| What | Where | Guard |
|---|---|---|
| Night tokens, type, surfaces, components, environment | `DesignSystem/Sources/Night/` (new folder, five files: `NightPalette.swift`, `Night.swift`, `NightType.swift`, `NightSurfaces.swift`, `NightComponents.swift`) | every file wrapped in `#if os(macOS)` |
| `BrandColor` on the Mac reads Night | `DesignSystem/Sources/Color+Brand.swift` | `#if os(macOS)` branch per token (§2.2); `#else` is today's code, unchanged |
| `BrandButton`, `DuoButton` on the Mac draw Night buttons | their own files | `#if os(macOS)` branch inside `body` |
| Today, the unit page, the shell's chrome | `AppFeature/Sources/Mac/` (`MacTodayView` rewritten, `MacUnitPage` new, `MacShellView`, `MacSidebar`) | already all `#if os(macOS)` |
| Reply rendering (no bubble, parts, sources, Your turn, blocks) | `ChatFeature/Sources/Mac/NightReply*.swift` (new) called from `MessageBubbleView`'s Mac branch; `BlockCards.swift` Mac branches | `#if os(macOS)` |
| Composer, chat, lesson, complete | `ChatInputBar`, `ChatView`, `CurriculumLessonView`, `LessonCompleteOverlay`: existing Mac branches | `#if os(macOS)` |
| Unit check | `CurriculumFeature/Sources/UnitTestView.swift` Mac branches | `#if os(macOS)` |
| First-run gate | `AppFeature/Sources/OnboardingSteps.swift` Mac branches | `#if os(macOS)` |
| New UI copy | one `enum` per module (`MacNightCopy` in AppFeature, `NightReplyCopy` in ChatFeature, …), so a test can check it (§8.2) | `#if os(macOS)` |

`CurriculumView`/`LearningPathView` are no longer used on the Mac (the unit page replaces them), so their iOS code is not touched at all.

### 1.2 CI and compiler rules (Xcode 16.2 / Swift 6.0.3 / macOS 14 on CI)

- Nothing newer than macOS 14 without `#available` **and** a compiler that has it. Safe on 14: `Animation.snappy/smooth/spring(duration:bounce:)`, `PhaseAnimator`, `onKeyPress`, `focusable(_:interactions:)`, `focusEffectDisabled()`, `UnevenRoundedRectangle`, `scrollPosition(id:)`, `defaultScrollAnchor`, `Canvas`, `Font.custom(_:fixedSize:)`, `toolbarBackground(_:for:)`, `symbolEffect(.bounce)`, `contentTransition(.numericText(value:))`.
- **Not allowed without a guard:** `onScrollGeometryChange` (15), `MeshGradient` (15), `toolbarBackgroundVisibility` (15), `symbolEffect(.breathe)` (15), everything Liquid Glass (26).
- Liquid Glass (`glassEffect`, `GlassEffectContainer`, `backgroundExtensionEffect()`, `scrollEdgeEffectStyle`) only as:
  ```swift
  #if compiler(>=6.2)
  if #available(macOS 26, iOS 26, *), !Night.debugForcesMaterial { /* glass */ } else { /* fallback */ }
  #else
  /* fallback */
  #endif
  ```
  CI compiles only the fallback. Both branches must be built locally (Xcode 26.4) and the fallback looked at with `-NightNoGlass YES` (§8.4).
- Trig and geometry in `Double`, converted to `CGFloat` once at the end (`CGFloat(x)`). No `Double`·`CGFloat` mixes (a1754ef).
- No Swift 6.1+ syntax: no trailing commas in argument or parameter lists.
- `@ScaledMetric` and `.dynamicTypeSize` do nothing on a Mac (measured in step 02). Mac sizes are fixed points (§3).
- No `sensoryFeedback` in any Night component (§4.6).

### 1.3 The Night environment

`MacShellView`'s root applies `.nightEnvironment()`, which resolves three flags once and passes them down as environment values that every Night view reads:

| Environment value | True when |
|---|---|
| `\.nightIncreasedContrast` | `colorSchemeContrast == .increased`, or DEBUG `-NightContrast increased` |
| `\.nightReduceTransparency` | `accessibilityReduceTransparency`, or DEBUG `-NightReduceTransparency YES` |
| `\.nightReduceMotion` | `accessibilityReduceMotion`, or DEBUG `-NightReduceMotion YES` |

(`colorSchemeContrast` is read-only, so the DEBUG overrides need our own keys.) The colour tokens themselves switch on the window's `NSAppearance` (§2.1), so they also cover sheets and the Settings window. The DEBUG flags also tell the token provider to resolve the increased-contrast values.

---

## 2. Tokens

### 2.1 Colour

Every token has four values: light, dark, and the same two under Increase Contrast ("HC"). They're built like `BrandColor.adaptive`: an `NSColor(name:dynamicProvider:)` that picks with `appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])`. The raw values live in `NightPalette` (internal, read by the tests), mirroring `BrandPalette`.

**Check on a real Mac early (E1, day 1):** turn on Increase Contrast and confirm the provider is handed the high-contrast names. If it isn't, the provider also reads `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`, and the shell re-resolves on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.

**Surfaces**

| Token | Light | Dark | HC light | HC dark | Use |
|---|---|---|---|---|---|
| `canvasTop` → `canvasBottom` | `#F6F5FC` → `#ECEBF8` | `#0B0E2E` → `#05071A` | `#FAFAFE` flat | `#05071A` flat | Every detail screen's background, top to bottom |
| `surface` | `#FFFFFF` | `#121641` | `#FFFFFF` | `#0E1238` | Lit surfaces: cards, the check, the complete card |
| `surfaceRaised` | `#F2F1FB` | `#1A1F52` | `#F1F0FA` | `#161B4A` | Answer rows, inner wells, hover on lit rows |
| `sidebar` | `#EEEDF7` | `#0A0D29` | `#F1F0FA` | `#05071A` | The sidebar's opaque fill on macOS 14–25 only (§5.0) |
| `hairline` | `#1B1F4B` @ 10% | white @ 12% | `#1B1F4B` @ 55% | white @ 40% | Strokes, separators, unlit segments |
| `border` (opaque) | `#E8E9ED` | `#2E3258` | `#82849C` | `#6E7188` | `hairline` flattened over `surface`, for `BrandColor.border` |

**Text** (every one is checked in §2.3)

| Token | Light | Dark | HC light | HC dark | Use |
|---|---|---|---|---|---|
| `ink` | `#0E1230` | `#F1F2FF` | `#05071A` | `#FFFFFF` | Primary text |
| `ink2` | `#434A6E` | `#B7BDE2` | `#2A3052` | `#DDE0F7` | Secondary text, objectives, summaries |
| `ink3` | `#575F83` | `#959DCB` | `#363D62` | `#C3C8EA` | Captions, metadata, placeholders |
| `accentText` | `#4F46E5` | `#A5B4FC` | `#3730A3` | `#C7D2FE` | Eyebrows, links, selected glyphs, the focus ring |
| `successText` | `#166534` | `#6EE7A8` | `#14532D` | `#A7F3D0` | "Done", correct marks |
| `errorText` | `#B91C1C` | `#FCA5A5` | `#991B1B` | `#FECACA` | Failures, wrong marks |

`ink3` moved from the concept's `#5A6286` / `#8E96C4` (4.6 / 5.0:1 at worst under the pools) to keep a margin over 4.5:1 on the canvas under its light pools, which the concept didn't check. `errorText` dark is red 300 (`#FCA5A5`, 7.57:1 at worst), not the iPhone's red 400 (5.20:1), for the same reason.

**Fills and light** (never used for text, except white on the fills noted)

| Token | Light | Dark | HC light | HC dark | Use |
|---|---|---|---|---|---|
| `accent` | `#6366F1` | same | same | same | Rings, selection tints, the student's turn tint |
| `violet` | `#8B5CF6` | same | same | same | The second stop of the brand light |
| `lumen` | `#6366F1` | `#9EA4FF` | `#4F46E5` | `#C7D2FE` | Glows, lit edges, the current node's halo, washes |
| `success` / `error` | `#16A34A` / `#DC2626` | `#34D399` / `#F87171` | `#15803D` / `#B91C1C` | `#34D399` / `#F87171` | Correct / wrong row tints and strokes |
| `prominent` | `#4338CA` | same | `#3730A3` | `#3730A3` | The one prominent button per screen. White on it: 7.90:1 (9.93:1 HC) |
| `prominentHover` / `prominentPressed` | `#4F46E5` / `#3730A3` | same | `#312E81` / `#312E81` | same as HC light | Hover and press of that button (white ≥ 6.29:1) |
| `fieldStroke` | `#4F46E5` @ 72% | `#A5B4FC` @ 62% | `#3730A3` solid | `#C7D2FE` solid | The composer's and the defense field's boundary (≥ 3:1) |
| `focusRing` | = `accentText` | | | | Keyboard focus (§4.4) |
| `progressLight` | `accent` → `violet`, a 2-stop `LinearGradient` | | flat `accentText` | flat `accentText` | Strokes 6 pt or thinner that show progress: the week ring, the unit meter, the path thread |
| `hero` | `#4338CA` → `#5B32D6` → `#6D28D9` | `#2B2486` → `#3B2A92` → `#4E2A8E` | `#3730A3` → `#4C1D95` → `#5B21B6` | `#1E1B4B` → `#2E1065` → `#3B0764` | Today's Up next card **only** (§2.5) |
| `heroLamp` | `#B9B7FF` @ 22% | same | none | none | The radial light at Merc's corner of the hero |
| `heroSecondary` | white @ 92% | same | white | white | Secondary text on the hero |

Not used anywhere in Night UI: the magenta `#B53BE8` end of `BrandGradient` (Merc's skin and the logo keep it), `BrandColor.userBubbleTop/Bottom` (the student's gradient bubble), `streakFlame`.

### 2.2 `BrandColor` on the Mac

Under `#if os(macOS)`, `BrandColor` reads Night. That gives every shared view (Progress, sheets, alerts, toasts, the crisis view) the Night palette without per-view edits:

| `BrandColor` | Mac value |
|---|---|
| `background` | `canvasTop` |
| `surface` | `surface` |
| `surfaceElevated` | `surfaceRaised` |
| `border` | `border` (opaque) |
| `text` / `textSecondary` | `ink` / `ink2` |
| `accentText` / `successText` / `errorText` | the Night tokens of the same name |
| `success` / `error` | Night `success` / `error` (now adaptive on the Mac) |
| `accent`, `accentLight`, `accentDark`, `mercViolet` | unchanged (fixed hues) |
| `BrandGradient.*` | unchanged; call sites that drew buttons or bars with it get Night components in their Mac branches (§3.2) |

`BrandPalette` keeps today's values, and `BrandContrastTests` and its `paletteMatchesPreviousTokens` test keep pinning them. iOS can't see the Mac branch.

### 2.3 Contrast: computed, every pair

`docs/mac-night-studio/night_contrast.py` computes WCAG contrast for every text token on every surface, in all four variants, plus the tinted surfaces and the non-text strokes. Translucent fills are composited in sRGB over their base, the same model as `BrandContrastTests`. The canvas is checked under its light pools at their peak (`canvasPool`, `canvasViolet`). **All pairs pass;** run it with `--markdown` for the full tables.

Lowest values per variant, text on plain surfaces:

| Variant | Floor | `ink` | `ink2` | `ink3` | `accentText` | `successText` | `errorText` |
|---|---|---|---|---|---|---|---|
| Light | 4.5 | 14.18 | 6.66 | 4.83 | 4.87 | 5.53 | 5.01 |
| Dark | 4.5 | 12.93 | 7.80 | 5.45 | 7.21 | 9.35 | 7.57 |
| HC light | 7.0 | 17.67 | 11.31 | 9.29 | 8.79 | 8.06 | 7.35 |
| HC dark | 7.0 | 16.28 | 12.47 | 9.90 | 10.92 | 12.70 | 11.25 |

(The light minimums are all on the canvas under the violet pool; on plain `canvasTop`, `ink3` is 5.75 and `accentText` 5.80.)

Tinted and special surfaces (lowest across the four variants):

| Use | Lowest | Where |
|---|---|---|
| Option text on a selected / correct / wrong row | 12.00 | dark, correct |
| Option letter on the selected row (`accentText` over `accent` 10% / 20%) | 5.55 | light |
| Correct mark (`successText` over `success` 14%) | 6.10 | light |
| Wrong mark (`errorText` over `error` 14%) | 5.20 | light |
| The student's turn (`ink` over `accent` 11% / 24% on the pooled canvas) | 9.85 | dark |
| KEY / Your turn text under the lumen wash (12% light, 16% dark) | 11.59 | dark |
| Eyebrow and token chip text on their washes | 5.41 | light |
| White on the hero, any stop | 7.10 | light |
| White on the hero under the lamp | 5.40 | light |
| Hero secondary (white 92%) under the lamp | 4.83 | light |
| `prominent` label on Today's white hero button (`#4338CA` on white) | 7.90 | |
| White on `prominent` / `prominentHover` | 7.90 / 6.29 | |
| Placeholder (`ink3`) on fallback chrome, worst case (the 92% surface tint over a line of `ink`) | 5.28 | light |
| Non-text: focus ring on canvas / surface | 5.02 | light, pooled canvas |
| Non-text: `fieldStroke` on canvas / surface | 3.09 | light, pooled canvas |
| Non-text: HC `hairline` on surface / canvas | 3.63 | HC light |

Rules that keep these numbers true:
- Text on the hero is solid white, or `heroSecondary`. Never `.opacity()` lower than 0.92 on hero text.
- The sidebar's secondary text uses `ink3`, **not** `.secondary`: the system's secondary label on the light sidebar is 3.86:1.
- `ink3` is never set on the KEY or Your turn wash, and never on a tint other than those in the table.
- Light pools stay at or below the alphas in §2.4.

**`NightContrastTests`** (DesignSystem, Swift Testing, runs in `swift test` on the Mac host): the same pairs, the same floors (4.5 normal, 7.0 for the HC inks on plain surfaces, 4.5 for HC tints, 3.0 non-text), read from `NightPalette`. The script is the reference: if a value changes, change both and keep them equal.

### 2.4 Canvas, light pools and stars

`NightCanvas` is the background of every detail screen (not of the split view), so each screen chooses its pools and stars:

- **Gradient:** `canvasTop` at the top of the detail column to `canvasBottom` at the bottom. HC: flat.
- **Pool 1 (indigo):** a `RadialGradient` of `accent` at the top-trailing corner (centre at 85% of the width, y = 0), radius `min(0.65 × width, 720)`, peak alpha 12% light / 24% dark.
- **Pool 2 (violet):** `violet` at the leading edge, 55% down, radius `min(0.5 × width, 560)`, peak 8% light / 16% dark.
- **Stars:** dark mode only. A static `Canvas`: `min(140, width × height / 9000)` dots, radius 0.4–1.4 pt, white at 8–32%, positions from the concept's seeded generator (`0x9E3779B97F4A7C15`) as fractions of the size, so they don't reshuffle per launch. Never animated.
- HC: no pools, no stars. Reduce Transparency: unchanged (pools and stars are drawn, not see-through).
- The canvas is `accessibilityHidden(true)` and never takes hits.

| Screen | Pools | Stars (dark) |
|---|---|---|
| Today, Learning path, Lesson complete | both | yes |
| Lesson, Chat, Unit check | pool 1 only | no |
| Gate | pool 1 only | no |
| Crisis, errors that replace a screen | none (flat `canvasTop`) | no |

### 2.5 The gradient rule

- The `hero` gradient fills **one** shape in the whole app: Today's **Up next** card.
- `progressLight` (two stops) may stroke progress shapes 6 pt or thinner: the week ring, the unit meter segments, the lit path thread. Nothing else.
- No other gradient fills: no gradient buttons (`prominent` is a solid fill), no gradient student turns, no gradient unit covers, no gradient text.
- Radial **light** (pools, the Merc lamp, the current node's halo, the KEY / Your turn wash, the hero's lamp) is not "the gradient" and is allowed where §2.4 and §2.6 say.

### 2.6 Lit surfaces and shadows

A **lit surface** (`.nightLit(radius:)`) is how content sits on the canvas:

```swift
let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
content
    .background {
        shape.fill(Night.surface)
            // One shadow, on the shape, light mode only, never under HC.
            .shadow(color: castsShadow ? Night.shadowInk : .clear, radius: 12, x: 0, y: 4)
    }
    .overlay { shape.strokeBorder(edge, lineWidth: 1) }
```

- **Shadow:** exactly one per lit shape, applied to the background shape (never to the content, never to text). Light: `#1B1F4B` at 7%, radius 12, y 4. Today's hero: `#4338CA` at 18%, radius 20, y 8. **Dark mode: no shadows anywhere.** HC: no shadows.
- **Edge (the lit top):** a 1 pt stroke. Light: white 90% at the top, `#1B1F4B` 6% in the middle, 10% at the bottom. Dark: white 14% → 4% → 2%. HC: solid `hairline`.
- **Glows** are radial gradients behind a shape, never `.shadow`: the Merc lamp (`lumen` 30% light / 50% dark, radius 0.62 × Merc's size); the current path node's halo (`lumen` 16% ↔ 30%, 1.8 s, still at 22% under Reduce Motion); the KEY / Your turn wash (`lumen` 12% light / 16% dark from the top-leading corner, end radius 320). HC: no glows.
- One level of containment: prose sits on the canvas; only blocks become surfaces. No card inside a card except answer rows inside the check.

### 2.7 Radii and spacing (Mac)

| Radius | Value | Use |
|---|---|---|
| `hero` | 24 | Today's Up next, the lesson-complete card |
| `card` | 18 | Lit cards: week, recent chats, KEY, EX, the check, unit cover, question cards |
| `row` | 12 | Answer rows, sidebar-like rows inside cards, source chips |
| `chip` | 8 | Token chips |
| capsule | | Every button, the composer, the part strip, the reply chips, Jump to latest |

Inner shapes are concentric: an inner radius is the outer radius minus the padding between them, never more.

| Spacing | Value |
|---|---|
| Page gutter | 32 when the detail column is 900 pt or wider; 24 below |
| Between sections | 24 |
| Inside a stack | 12 |
| Card padding | 20 (hero 24) |
| Row padding | 14 horizontal, 10 vertical |

Columns: the reading column stays `MacLayout.readableWidth` (620). Today uses 760. The gate stays `MacLayout.gateWidth` (600). The complete card is 520.

### 2.8 Glass and materials, by OS

| Element | macOS 26, built with Xcode 26 | macOS 14–25, and every CI build | Reduce Transparency | Increase Contrast |
|---|---|---|---|---|
| Window toolbar | System Liquid Glass. No `toolbarBackground`. The detail canvas runs under it; the system scroll-edge effect keeps the title readable. | `toolbarBackground(Night.canvasTop, for: .windowToolbar)` with `toolbarBackground(.visible, for: .windowToolbar)` | System (opaque) | System |
| Sidebar | System glass sidebar; the detail canvas gets `.backgroundExtensionEffect()` so the ink shows through it. No fill of our own. | `.scrollContentBackground(.hidden)` over an opaque `Night.sidebar` | Opaque `sidebar` on both | Opaque HC `sidebar` |
| Floating chrome in the detail (composer, part strip, Jump to latest, reply chips) | `glassEffect(.regular, in: shape)`; `.regular.interactive()` on buttons; the composer row in one `GlassEffectContainer(spacing: 8)` | `.regularMaterial` + `Night.surface` at 92% + 1 pt `hairline` | Opaque `surface` + 1 pt `hairline` | Opaque `surface` + 1 pt HC `hairline`; the composer gets `fieldStroke` |
| Scroll edges under floating chrome | `scrollEdgeEffectStyle(.soft, for: .top / .bottom)` | A plain 24 pt gradient from the canvas colour to clear (no material: the concept's buried blur is gone) | Same plain fade | Same |
| Prominent button | Opaque `prominent` (never tinted glass) | Opaque `prominent` | Same | HC `prominent` |
| Lit surfaces, content | Never glass | Never material | | |

`Night.debugForcesMaterial` (`-NightNoGlass YES`, DEBUG) draws the fallback column on macOS 26, so the fallback can be reviewed and photographed.

The harness's pictures show glass dark or missing (`MacSnapshot.swift`): judge glass on screen, never from a PNG.

### 2.9 What changes under each accessibility setting

| Setting | Changes |
|---|---|
| **Increase Contrast** | The HC token column. Pools, stars, glows and the hero lamp off. Lit edges become a solid HC `hairline`. Glass and materials become opaque `surface`. Answer rows get a 1.5 pt `hairline` stroke at rest. The focus ring is 3 pt. Shadows were already off in dark; now off in light too. |
| **Reduce Transparency** | Glass and materials become opaque `surface` + `hairline` (the third column of §2.8). Colours unchanged. |
| **Reduce Motion** | §4.5. |
| **VoiceOver** | Labels for every custom control (each screen in §5 lists them). Decoration hidden: canvas, stars, pools, the Merc lamp, big numerals, the path thread, ring art. |

---

## 3. Type

### 3.1 The Mac ramp

Fixed sizes (a Mac has no Dynamic Type). Nothing a student reads is under 12 pt, keeping `MacTypeRamp`'s rule. `NightType` builds each font with `Font.custom(name, fixedSize:)` or `.system(size:weight:design:)` and calls `BrandFontRegistrar.registerReadingFonts()` first.

| Role | Face | Size / weight | Tracking | Line spacing | Use |
|---|---|---|---|---|---|
| `display` | Lexend SemiBold | 30 | −0.75 (−0.025 em) | | Today's greeting, "Lesson complete", gate step titles, the lesson intro title |
| `title` | Lexend SemiBold | 24 | −0.5 | | The hero's lesson title, the unit cover's title, "Hi, I'm Merc" |
| `title2` | Lexend SemiBold | 19 | −0.3 | 2 | Card headlines, the current lesson's title on the path, the check's stem, question stems |
| `headline` | Lexend SemiBold | 15 | 0 | | Night buttons, row titles, "Merc" |
| `body` (reading) | Lexend Regular | 15 | 0 | 5 | Merc's replies, the student's turns, objectives, card text, answer rows (= `MacTypeRamp.reading`) |
| `callout` | Lexend Regular | 14 | 0 | 3 | Secondary lines: mode purpose, unit summary under a title, the week card's detail |
| `calloutStrong` | Lexend SemiBold | 14 | 0 | | The reply chips, Jump to latest, the part strip's "Part 3" |
| `caption` | Lexend Regular | 12 | 0 | | Metadata: "Done", counts, dates, "AI tutor", the source's domain |
| `eyebrow` | Lexend SemiBold, uppercase | 12 | +1.2 | | **The one eyebrow style.** `accentText` by default; `ink3` for neutral ones (the date); white 92% on the hero |
| `keep` | New York Medium (`.system(size:weight: .medium, design: .serif)`) | 18 | 0 | 4 | What the student keeps or answers: `[KEY]`, `[CHECK]`, the Your turn card, the written-defense prompt. 16 in the complete card's key list. |
| `machine` | SF Mono Medium (`.system(size:weight: .medium, design: .monospaced)`) | 14 | 0 | | Token chips, and the word they split |
| system | SF, the control's own size | | | | The sidebar, toolbar, menus, native pickers and checkboxes, the Settings window, Help, and the crisis view |

- Lexend has only Regular and SemiBold in the bundle. No bold, no black.
- SF Rounded is not used in any Night view on the Mac (`BrandFont.rounded*` stays for the iOS path). The current Mac's rounded "Continue", "Nailed it!" and heavy eyebrows go.
- `.monospacedDigit()` on every number that changes in place (week counts, part numbers, "2/4").

### 3.2 Night components (DesignSystem, Mac only)

| Component | Spec |
|---|---|
| `NightPrimaryButton` | Capsule, min height 36 (large 44 on Today's hero and the complete card), `headline` white on `prominent`; hover `prominentHover`; pressed `prominentPressed`; disabled: `surfaceRaised` fill, `ink3` label. Takes `.keyboardShortcut(.defaultAction)` where the screen says so. **One per screen.** |
| `NightSecondaryButton` | Capsule, same heights, `headline` `ink` on floating chrome (§2.8). |
| `NightTextButton` | No fill; `headline` `accentText`; hover underlines. For "Learning Path", "See progress", "Not now". |
| ~~`NightIconButton`~~ | Not built as a shared component (fix pass): its two uses draw their own 30 pt circle, the composer's attach button (inside the field, with hover) and the complete card's Share (a `ShareLink`). Each has its `.accessibilityLabel` and `.help`. |
| `NightEyebrow` | `eyebrow` style, optional leading SF Symbol at 11 pt bold, 6 pt gap. |
| `NightRhythmRing` | The concept's ring: one arc per lesson in the weekly goal, 3.5% gaps, unlit `hairline`, lit `progressLight`, no glow. Hidden from VoiceOver (its card speaks). |
| `NightMercLamp` | `MercMascot` with the radial lamp behind it; `idleLife` off under Reduce Motion; hidden from VoiceOver. |
| `NightTokenChip` | `machine` text in `accentText`, `lumen` 12% light / 16% dark wash, `lumen` 55% 1 pt stroke, radius `chip`, padding 10 × 5. No shadow. |
| `NightFlow` | The concept's wrapping layout, with its rounding tolerance. |
| `BrandButton` / `DuoButton` (Mac branch) | `.primary` → `NightPrimaryButton`; `.secondary` → `NightSecondaryButton`; `.ghost` → `NightTextButton`. Same titles, actions and enabled state. |

---

## 4. Motion and feedback

### 4.1 Three springs and a fade

| Name | Value | Used for |
|---|---|---|
| `tap` | `.snappy(duration: 0.2)` | Selecting an answer, toggles, the part strip's highlight |
| `layout` | `.smooth(duration: 0.35)` | Reveals, a card appearing, the check locking in, a reply's Your turn card settling |
| `milestone` | `.spring(duration: 0.6, bounce: 0.25)` | Only the lesson-complete card's arrival and Merc's celebrate |
| `fade` | `.easeInOut(duration: 0.2)` | Everything under Reduce Motion |

Shorter than the iPhone concept's (0.28 / 0.5 / 0.7): a Mac answers a click faster than a phone answers a thumb.

### 4.2 Hover

- Clickable lit surfaces and rows: a `lumen` 6% overlay and a 1 pt `accentText` 50% stroke on the shape, in 0.12 s ease-out (instant under Reduce Motion). This is a Night version of `macHoverHighlight`; the iOS no-op stays.
- Buttons: Night buttons change fill (§3.2). Native controls do what macOS does.
- The pointer stays an arrow on buttons and cards. The pointing hand is for links only (the step-05 rule): the source chip, "Learning Path", the crisis view's links.
- No scale or lift on hover.

### 4.3 Press

A Mac control doesn't squash. Pressed = the pressed fill (`prominentPressed` for the prominent button, a `ink` 8% overlay on everything else). No scale, so nothing changes under Reduce Motion.

### 4.4 Focus rings

- Night controls and focusable cards draw their own ring: 2 pt `focusRing` (3 pt under HC), 3 pt outside the shape, following it (capsule, or radius + 3). They call `.focusEffectDisabled()` so the system's rectangle doesn't double it.
- The ring shows while the view has keyboard focus (`@FocusState` / `\.isFocused`). It appears and disappears without animation.
- Contrast: 5.02:1 at worst (§2.3).
- In the Tab loop whatever the Full Keyboard Access setting (`.focusable(interactions: .edit)`, as the unit check's cards are today): the lesson's check card, the unit check's question cards, the defense field, the composer. Buttons are in the loop when Full Keyboard Access is on, as on every Mac; every screen's main action also has a key (§4.7), so nothing needs it.

### 4.5 Reduce Motion

| Moving thing | Under Reduce Motion |
|---|---|
| Card reveals, the check's lock-in, the Your turn card settling | A 0.2 s crossfade to the final state |
| Lesson complete's sequence | Everything at its final state in one crossfade; the ring is drawn full, not filled |
| The current node's halo | Still, at 22% |
| Merc | `idleLife: false`; the celebrate state shows without the jump |
| Scroll-to (Jump to latest, a part strip click, a unit-check question) | Instant |
| Star field | Never moves anyway |

### 4.6 No haptics

None on the Mac. No `sensoryFeedback` in Night components. The existing shared views' `sensoryFeedback` calls are iOS behaviour; their Mac branches don't add any.

### 4.7 Keyboard

Everything from PR #47 stays (Return sends, Shift-Return breaks a line, Escape leaves when nothing is lost, A–D in the unit check, ⌘1–⌘3 destinations, ⌥⌘1–⌥⌘3 modes, ⌘N, ⌘R, ⇧⌘E, ⇧⌘A, ⌘?, ⌘,). New:

| Keys | Does | Where |
|---|---|---|
| ⌘4 | View ▸ Progress (the Progress sheet) | Anywhere past the gate; off while gated or erasing, like the other shell commands |
| Return | The screen's one prominent button | Today (Up next), the unit page (the current lesson), the lesson intro, the complete card, each gate step (as now) |
| A–D, 1–4, ↑, ↓, Return | Pick an answer on the lesson's check card, then lock it in | While the check waits, the lesson's keys go to it (`NightCheckKeyRouter`; the card wears the focus ring to say so), and when it has focus (Tab, a click). Never while the composer, or any text field, has the keyboard, so typing "B" there still types. (Fix pass: a lesson opens on Merc's reply, not on a focused composer; a printable key typed with no check waiting focuses the composer and goes into it; Chat ▸ Write a Reply, ⌘L, focuses it any time.) |
| Return | Lock it in | While the focused check card has a pick |
| Tab / ⇧Tab | Composer ↔ the open check card | Lesson |

---

## 5. Screens

Window sizes: **1280 × 800** gives a 240 pt sidebar and a detail of about 1040 × 748 under the toolbar. **The 700 × 600 minimum** folds the sidebar (below 860 pt, as now) and gives a detail of 700 × 548.

### 5.0 Window and sidebar chrome

**1280 × 800.** Sidebar 240 pt (range 200–340, as now). Toolbar as in §2.8. Every detail screen draws its own `NightCanvas`.

**700 minimum.** The sidebar folds (existing rule). The toolbar keeps its title and the screen's prominent toolbar items; the rest goes to the » menu (existing behaviour).

**Sidebar:**
- Rows keep their system type and height. Titles in `ink`, counts ("0/4") and the chat rows' mode line in `ink3` (§2.3: not `.secondary`).
- Unit icons: the numbered circle in `accentText`; a mastered unit's seal in `successText`.
- Section headers: system style, tinted `ink3`.
- Selection: the system's.
- Nothing else changes: the sections, New Chat row, Delete key, context menu and fold rule stay.

**Toolbar items:**
- Every screen past the gate: the streak chip is replaced by a standard toolbar button (the system draws it; glass on macOS 26) with `chart.bar.xaxis`, label "Progress", help "Progress and achievements (⌘4)" (D8). Fix pass: it is a trailing `.primaryAction`, in the same place on every screen (lessons and the unit check too); the leading slot is a lesson's or check's way back only.
- Lessons, unit checks and Support keep their title, subtitle and back button.

**Carries over:** the concept's canvas, the tint, the idea that chrome floats and content is lit.
**Mouse and keyboard:** ⌘4 is new. Everything else is the system's.
**Judges' fixes:** no number on chrome (D8). Reduce Transparency is handled (§2.8).
**Honest copy:** none needed.
**VoiceOver:** the Progress button reads "Progress".

### 5.1 Today

Screen: `MacTodayView`, rewritten. Same inputs (`HomeState`, the progress store, conversations, reminders, the callbacks). Nothing on it talks to the server.

**1280 × 800** (a 760 pt column, centred, gutter 32, top padding 28):

1. **Header** (no card).
   - Eyebrow, `ink3`: the date, from `Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())`, uppercased. This is the localised template, not the concept's hard-coded `DateFormatter`.
   - `display`: `HomeState.opener(hour:)` with its "!" turned into "." ("Good evening.").
   - `callout` `ink2`: the subline (§6).
2. **Up next**, the hero: the **only** gradient fill in the app.
   - Two columns: text on the leading side, Merc on the trailing side. Merc is a 128 pt-wide column inside the card: `NightMercLamp(.wave, size: 96)`, top-aligned, **inside the card's bounds** (no negative padding).
   - The text column:
     - eyebrow "Up next · Unit 1 · Lesson 3 of 4" (or "Continue · …" when it resumes), white 92%;
     - `title` white: the lesson title;
     - `body` `heroSecondary`: the objective;
     - the unit meter: one 5 pt capsule per lesson (done white, current white 55%, ahead white 18%), then `caption` white "2 of 4 lessons done in Unit 1";
     - the buttons: a white capsule with a `prominent` label, `headline`, "Start Lesson 3 →" or "Continue Lesson 3 →" (Return), and a white `NightTextButton` "Learning Path" (⌘2).
   - Background: `hero`, plus `heroLamp` from Merc's corner, plus 24 stars (light and dark: the hero is always dark). Its one shadow is in §2.6. Radius `hero`, padding 24.
   - Unit check next, or the whole path done: the same card with `MacTodayView.upNext`'s existing copy.
3. **A row of two cards** (`ViewThatFits`: side by side when each gets 300 pt or more, stacked otherwise).
   - **This week** (lit card): `NightRhythmRing` at 56 pt; eyebrow "This week"; `title2` "1 of 2 lessons" (or "Weekly goal met"; past the goal, "3 lessons"); `callout` `ink2` with the existing `weekDetail` copy.
     - Then a hairline, then **seven day dots** for the student's week (`WeeklyPlan.weekStart`, so it starts on the same day the goal counts from). A day with a lesson completed (from `CurriculumProgressStore.completedAt`) gets an 8 pt `progressLight` dot. Today has a 1.5 pt `accentText` ring. Other days get a `hairline` dot. Day initials in `caption` `ink3`; today's in `ink`.
     - Then the streak line, only when the streak is 1 or more: `caption` `ink3`, "4 days running. One lesson or chat a day keeps it going." With no streak there's no line (never a zero).
     - The whole card is a button that opens Progress, with hover.
   - **Think it through** (lit card, button):
     - eyebrow "Think it through · {mode}" with `questionmark.bubble`;
     - one prompt from `ModePromptProvider` for the chat's **current** mode, picked by day of the year, in `keep` 18 `ink`, in quotes;
     - `callout` `ink2`: that mode's `ModeDescription.purpose`;
     - a trailing `arrow.right` in `accentText`.
     - Clicking it opens a new chat in the current mode with the prompt **in the composer, not sent**, and the composer focused. There's no mode switch and no network call until the student sends it.
4. **Recent chats** (lit card): as now (title, New Chat as a `NightSecondaryButton`, three rows with hover, the existing empty copy).
5. **The weekly-nudge offer**, when it shows: a lit row with the existing copy; "Remind Me" is a `NightSecondaryButton`, "Not Now" a `NightTextButton`. (The hero holds the screen's one prominent button.)

Above the fold at 1280 × 800: the header, the hero and the two-card row (they end about 590 pt down a 748 pt detail). Recent chats starts in view.

**700 × 600** (column 652, gutter 24):
- The hero's Merc column is 96 wide with Merc at 72.
- The two cards still sit side by side (318 pt each).
- Recent chats is below the fold. Nothing is cut; the page scrolls.

**Carries over from DesignLab:** `NightHomeScreen`'s header, hero card (eyebrow, title, objective, meter, white button, lamp, stars), week card (ring, day dots), `questionCard` (as Think it through) and `NightEyebrow`. **Not carried:** the profile button (Settings is ⌘, and Progress ⌘4), "Later in Unit" (the sidebar shows the path), "about 6 min".

**Mouse and keyboard:** Return starts or continues the lesson. ⌘2 opens the Learning Path. Every card and row has hover and is a button (Full Keyboard Access reaches them; the main action needs only Return).

**Judges' fixes:** Merc anchored inside the layout; the curiosity card above the fold; the gradient once, here; the week's days spoken to VoiceOver; the date from a localised template.

**VoiceOver:**
- The hero: one element per button, plus a header for the title ("Lesson 3: Why AI sounds confident but can be wrong. Understand hallucination and the confidence-accuracy gap. 2 of 4 lessons done in Unit 1.").
- The week card: `state.weekAccessibilityLabel` plus "Lessons done on Tuesday and Thursday." (or "No lessons yet this week."), plus the streak line. It's a button: "Opens your progress."
- Think it through: "Think it through: {prompt}. Opens a new chat with this question ready to send."

### 5.2 Learning path (one unit's page)

Screen: `MacUnitPage`, new, in `AppFeature/Sources/Mac`. It replaces `CurriculumView` on the Mac. Same callbacks (`onStartLesson`, `onStartUnitTest`), same store. Toolbar: "Learning Path" / "Unit 1 of 8" and the Progress button.

**1280 × 800** (a 620 pt column, centred):

1. **Unit cover**: a lit card, **not** a gradient (§2.5). Radius `card`, padding 20.
   - Eyebrow: "Unit 01 · In progress" / "Not started" / "All lessons done" / "Mastered".
   - `title`: the unit's title.
   - `callout` `ink2`: `unit.summary`.
   - The meter: one 5 pt capsule per lesson in `progressLight` / `lumen` 40% for the current one / `hairline`, then a 10 pt diamond outline for the check.
   - `caption` `ink3`: "2 of 4 lessons · then the unit check".
   - Trailing: the unit number "01" in Lexend SemiBold 56, `accentText` at 18%, hidden from VoiceOver.
2. **The thread.** One row per lesson, then the unit check. A 40 pt node column with a 2 pt thread (`progressLight` between finished stops, `hairline` after), then the content.

   | Stop | Node | Content | Click |
   |---|---|---|---|
   | Done | 24 pt `progressLight` disc with a white check | `headline` `ink2` title, trailing `caption` `successText` "Done" | Opens the lesson to review (as today) |
   | Current: this unit's first lesson that is unlocked and not done (units aren't gated, so every unit has one) | 28 pt `surface` disc, 2.5 pt `accentText` ring, its number, the breathing halo (§2.6) | A lit card: eyebrow "Lesson 3 · You're here" when it's the student's frontier (`progress.frontierLessonId`), else "Lesson 1 · Next in this unit"; `title2` title; `callout` `ink2` objective; `NightPrimaryButton` "Start" or, when in progress, "Continue" (Return) | The button |
   | Ahead, locked | 24 pt `canvasTop` disc, 1.5 pt `ink3` ring, its number | `headline` `ink` title; `callout` `ink2` objective; trailing `caption` `ink3` "Opens after Lesson 3" | None. Help: "Opens after Lesson 3" |
   | Unit check | 20 pt rotated rounded square, `accentText` outline; filled `successText` seal when mastered | `headline` "Unit 1 check"; `callout` `ink2` "{n} questions, then one written answer Merc grades."; trailing `caption`: `accentText` "Opens after Lesson 4", or a `NightSecondaryButton` "Take the check" when unlocked, or `successText` "Mastered" | The button when unlocked |

3. **Next unit**: a quiet row: `caption` `ink3` "Next" and `headline` `accentText` "Unit 2 · Bias & Fairness →". It selects that unit in the sidebar. None on Unit 8.

**700 × 600:** the same column. The big numeral hides when the column is under 560 pt (not the case at 700 with the sidebar folded). Trailing metadata moves under the title when a row is narrower than 420 pt.

**Carries over:** `NightPathScreen`'s cover (not as a gradient), thread, nodes, current-lesson card, checkpoint row, the numbers instead of padlocks. **Not carried:** the later-units carousel (the sidebar is the unit list on a Mac), "Your path" (the toolbar says it), "About 6 min", "Every lesson is previewable", Merc beside the path.

**Mouse and keyboard:** Return = the current lesson. Rows have hover only when they can be clicked. Locked rows show no hover and no pointer change.

**Judges' fixes:**
- Path no longer repeats Home's gradient card.
- No green third hue on chrome: "Done" is `successText` text only.
- Numbers, not padlocks.
- An honest gating line (from the current unlock rule: a lesson opens when the one before it is done; the check opens when all lessons are done).

**VoiceOver:** each row is one element, e.g. "Lesson 1, done: What happens when you type a prompt." / "Lesson 3, you're here: …. {objective}" / "Lesson 4, opens after Lesson 3: …" / "Unit 1 check, opens after Lesson 4: 5 questions, then one written answer Merc grades." The cover's title is a header.

### 5.3 Lesson reader

Screen: `CurriculumLessonView`'s Mac branch, and Merc's replies through `NightReply` (§5.3.3). Toolbar: the title, "Unit 1 · Lesson 1 of 4", the back button / "Not now" (unchanged).

**1280 × 800:**
- The 620 pt reading column, centred, on the canvas (pool 1, no stars).
- Pinned at the column's top (a `safeAreaInset(edge: .top)`): the **part strip** (§5.3.2).
- Pinned at the bottom: the composer (§5.4) at column width, with the top and bottom scroll-edge fades (§2.8).

**700 × 600:** the same column (620 within 700). The part strip's name truncates at the tail (the full name is in its help tag and VoiceOver).

#### 5.3.1 The intro (before the lesson starts)

One centred group in the 600 pt gate box:
- `NightMercLamp(.wave, size: 96)`;
- eyebrow "Unit 1 · Lesson 1 of 4";
- `display` lesson title;
- `body` `ink2`: the existing line "Ready to dig in? I'll walk you through it — then check what landed.";
- `NightPrimaryButton` "Continue" (Return; the label and its accessibility label are unchanged).

The speech bubble and its tail go. "Not now" stays in the toolbar.

#### 5.3.2 Parts (the concept's "beats", made honest)

- **What a part is:** a section of Merc's replies in this lesson thread, split at Markdown thematic-break lines (`---` on its own line). A reply with no break is one part.
- **Counting:** parts are numbered from 1 across the whole lesson thread, in order, **counting only parts that exist so far.** A section counts once its first non-whitespace character has arrived. Whitespace-only sections don't count.
- **Naming:**
  - a section that contains a `[Q]` is named "Check";
  - otherwise it takes the first `**bold**` term in it, trimmed, if 32 characters or fewer;
  - otherwise it has no name ("Part 4").
  - "Hook" and every other invented name are gone.
- **Part marks:** between sections, instead of the hairline, a mark. `caption` SemiBold `accentText` "02", then a 28 × 2 pt `lumen` capsule fading to clear, then the name as an eyebrow in `ink3`. 10 pt above, 16 below. It's a header for VoiceOver ("Part 2, Tokenization"). The first part has no mark.
- **The part strip:** a floating-chrome capsule, 36 pt tall, full column width.
  - Leading: `calloutStrong` `ink` "Part 3" (`.monospacedDigit()`), then `callout` `ink2` " · Tokenization".
  - Trailing: one 18 × 4 pt capsule per part so far. Parts before the current one are `progressLight`, the current one `lumen`, later ones `hairline`. Then one **dashed** `hairline` capsule meaning "more may come"; it disappears once the lesson is complete.
  - **There is never a total.** No "of 6", no time left.
  - "Current" is the last part whose mark has scrolled above the top of the column (anchor preferences in the scroll view's coordinate space; this works on macOS 14), else part 1.
  - Clicking a segment scrolls its mark to the top (`layout`; instant under Reduce Motion).
  - VoiceOver: one element, "Lesson parts so far: 3. Now reading part 3, Tokenization." Adjustable: increment and decrement move between parts.
- Free chat doesn't get parts: there, `---` stays a plain hairline.

#### 5.3.3 Merc's reply

- **No bubble, no avatar, no "● Merc" presence line in a lesson.** Typography on the page: `body` (Lexend 15, line spacing 5) in `ink`, full column width (the reply measure is the column).
- The student's turns are the chat's student cards (§5.4).
- **[EX] example**: a lit card (radius `card`, padding 18).
  - Eyebrow "Example" with `scope`.
  - Then, **only when the recogniser matches**, a token line: the word in `machine` `ink`, an `arrow.right` in `ink3`, then one `NightTokenChip` per piece, in a `NightFlow`.
  - Then the example's own text, verbatim, `body` `ink2`.
  - **The recogniser:** in the example's text, a quoted word W (straight or curly quotes) followed in the same sentence by "token" or "tokens" and two or more quoted pieces whose concatenation is exactly W. The recorded lesson's "The word "unbelievable" might become three tokens: "un", "believ", "able"." matches. Anything else draws no chips. The chips are the model's own words; nothing is tokenised by the client.
  - VoiceOver for the token line: "unbelievable becomes 3 tokens: un, believ, able."
- **[KEY] key idea**: a lit card with the `lumen` wash.
  - Eyebrow "Key idea" with `key.fill`.
  - The text in `keep` 18 `ink`, line spacing 4.
  - **No "Saved to notebook"**, no bookmark glyph.
  - VoiceOver: "Key idea: …" (as now).
- **[CHECK] open question**: the Your turn card (§5.4) in `keep`. It's Merc's question to the student.
- **[Q] check** (inline, where it streamed; **no docked tray** on the Mac): a lit card, radius `card`, padding 18.
  - Eyebrow "Your turn first" with `circle.dashed`; after lock-in, "Answered" (fix pass: the strip and the part's mark already say "Check").
  - The stem in `title2` `ink`.
  - Answer rows, 8 pt apart:
    - min height 44; radius `row`; padding 14 × 10;
    - a 26 pt letter disc (13 pt Lexend SemiBold letter);
    - option text in `body`.
  - Row states:

    | State | Row | Disc |
    |---|---|---|
    | Rest | `surfaceRaised` fill | 1.5 pt `ink3` 55% ring, `ink2` letter |
    | Hover | the hover of §4.2 | |
    | Picked | `accent` 10% light / 20% dark over `surface`, 2 pt `accentText` stroke | `accent` fill, white letter |
    | After lock-in, the answer | `success` 14%, 2 pt `success` stroke | `success` disc with a white check, `successText` `checkmark.circle.fill` trailing |
    | After lock-in, the student's wrong pick | `error` 14%, 2 pt `error` stroke | `errorText` `xmark.circle.fill` trailing |
    | After lock-in, the others | `surfaceRaised` | text in `ink2` |

  - Under the rows, while there's a pick and no lock-in: `NightPrimaryButton` "Lock it in" with `lock` (Return while the card has focus).
  - **Lock it in** grades locally, posts the existing `ChatAnnouncement` and calls the existing `onSelect(index)`, which sends "I picked B) …" exactly as today. Merc's real follow-up then streams below as the next reply. No canned feedback and no "Next beat" button.
  - The card is answerable only when the existing `isEnabled` rule allows it: the last assistant message, complete, phase idle. It stays inert while the `[Q]` is still streaming.
  - While an answerable check is on screen, the composer's placeholder is "Or answer in your own words…": typing an answer still works, as today.
  - VoiceOver: the existing `optionAccessibility` labels and values; "Lock it in" reads "Lock in answer B".
- **[SOURCE: …] tags** become a source chip (§5.4), in lessons and chat alike.
- **Crisis guard:** a reply containing `988` or `741741` as a whole word (the server's own crisis-reply signal, `lib/crisisSignal.js`) renders as **plain reading text**: no Your turn card, no source chips, no serif, no wash. It still gets part marks, so the count stays true. Calm beats styled.
- **While streaming:** blocks render as they arrive (the `BlockParser` guarantees stay). Part marks appear as breaks arrive. The Your turn card applies only after the reply completes.
- Reading position, "Jump to latest" and the one type size stay as they are.

**Carries over:** `NightLessonScreen`'s full-width reader, beat marks (as part marks), meter (as the part strip, with no total), `exampleCard`, `keyCard`, `checkCard` and `optionRow` (inline), the "Or answer in your own words…" composer, `NightTokenChip`, `NightBeats.boldTerm`. **Not carried:** the docked tray, "Beat N of 6", "Saved to notebook", the notebook button, the hard-coded chips and beat names, "Next beat", the canned feedback.

**Mouse and keyboard:**
- Tab from the composer to the check card; A–D / 1–4 / ↑↓ pick; Return locks in.
- Escape leaves only when nothing would be lost (now also: not with a pick that isn't locked in).
- Click a part segment to jump.

**Judges' fixes:**
- The tray no longer covers the KEY it tests (there's no tray).
- "Part N, counting so far" instead of "Beat 2 of 6".
- Token chips only for a recognised pattern.
- Fixed-size letter discs, sized for the Mac's fixed type.

**VoiceOver:** listed with each block above. The reply reads block by block, as now.

### 5.4 Chat

Screen: `ChatView`'s Mac branch. Toolbar (unchanged in function): the mode switch, Explain More, New Chat; the Progress button replaces the streak chip (D8). Fix pass: below 860 pt of detail width the switch is a native pop-up menu ("Socratic ▾") and the "Chat" title steps aside (macOS 15+), so New Chat and Explain More never fall into the toolbar's overflow at the window's 700 pt minimum. The picker stays native: it's the Mac's own control, keyboard- and VoiceOver-correct, and sized by the system (the judges' 44 pt pill fix is about a phone's custom pills).

**1280 × 800:** the 620 pt column on the canvas (pool 1, no stars), the composer pinned at the bottom.

**700 × 600:** the same column. The picker stays; Explain More and New Chat go to » (as now).

- **Merc's replies:** typography on the page, as in §5.3.3.
  - Above each reply, a label line: `MercMascot(.idle, size: 20, presentation: .bust, emphasis: .badge, idleLife: false)` (hidden), "Merc" in `headline` `ink`, "AI tutor" in `caption` `ink3`. It doesn't name the mode (a thread's mode can change, and the label would be wrong for earlier replies).
  - VoiceOver: "Merc, AI tutor."
- **The student's turns:** trailing-aligned cards, at most 75% of the column (465 pt).
  - Fill `accent` 11% light / 24% dark; a `lumen` stroke 18% / 30%; radius 18 with a 6 pt bottom-trailing corner.
  - Text in `body` `ink`. Attached photos inside the card, as now.
  - VoiceOver: "You: …".
- **Source chip** (from `[SOURCE: …]`, in chat and lessons):
  - **Parsing** is a Mac-only pass over the reply's prose blocks and the text of its [KEY], [EX], [CHECK] cards and a check's question (`MessageBlock` and iOS untouched; a card's chips follow the card). It handles both server formats: `[SOURCE: Title — domain/path]` (server.js:1074) and `[SOURCE: brief label]` (server.js:478), with a Markdown link the model sometimes wraps around the tag (`[SOURCE: …](http://…)`, taken with it, its host filling in a missing domain, as `lib/sourceTags.js` does). The tag is removed from the prose; a tag used as a sentence's subject leaves its title in the sentence. Of PR #46's plain forms only the full shapes count: `(Source: label[, domain])`, and `Source: label (domain)` as a whole line or closing a line after a sentence. A label-only `Source: …` stays prose (its end can't be told from prose), and mid-stream a line's plain form waits for the line to end (fix pass).
  - **Look:** a lit row, radius `row`, padding 12: `doc.text.magnifyingglass` in `accentText` on a `lumen` 14% 32 pt square; the title in `headline` `ink`; under it, `caption` `ink3` "Cited by Merc · dl.acm.org" (or "Cited by Merc" with no domain).
  - **When it opens:** only when there's a domain and `https://<domain>` passes `ReplyLinkPolicy.allows`. The path the model wrote is never opened: the audit found invented deep links (AUD-38), and the server's rewrite drops it too (fix pass). Then it shows a trailing `arrow.up.right`, the pointing hand, and help "Merc picked this source. Open it and check that it says what Merc says." Otherwise it's an inert citation: no arrow, no hover.
  - **Never** a favicon or anything else fetched.
  - VoiceOver: "Source Merc cited: On the Dangers of Stochastic Parrots, dl.acm.org. Opens in your browser."
- **The Your turn card:** the latest reply only, once it has completed, when its last paragraph ends in "?" and is 400 characters or fewer (and the crisis guard doesn't apply). That paragraph moves out of the prose into a lit card with the `lumen` wash: eyebrow "Your turn" with `arrow.turn.down.right`, the question in `keep` 18 `ink`. Earlier replies keep their question as plain prose. VoiceOver: header, "Your turn: …".
- **The reply chips** under the latest reply: the real ones, "Explain more" and "Quiz me", as floating-chrome capsules (32 pt, `calloutStrong` `ink`, leading symbol), with hover. Their behaviour is unchanged.
- **The composer** (`ChatInputBar`'s Mac branch):
  - A floating-chrome capsule, min height 40.
  - Leading: the attach button, a 30 pt circle inside the field (`photo.badge.plus`, `ink2`, lumen under the pointer).
  - The field in `body` `ink`, placeholder in `ink3`.
  - Trailing: the send button, a 30 pt `prominent` circle with a white `arrow.up`. Disabled: a `hairline` fill with an `ink3` arrow. Stop: the same circle with `stop.fill`.
  - The boundary is `fieldStroke` (≥ 3:1, §2.3).
  - Focus: the field's own focus ring is off; the capsule draws `focusRing`.
  - Every key, drop and paste behaviour stays.
- **Jump to latest:** a floating-chrome pill, `calloutStrong` `accentText`, `arrow.down`.
- **The mode explainer sheet** (first time a mode is picked): a `surface` sheet; `title` heading; purpose, when to use it and the example in `body`; the button as `NightPrimaryButton`. The copy is unchanged.
- **Empty chat:**
  - "Hi, I'm Merc" in `title`;
  - the current mode's `ModeDescription.purpose` in `callout` `ink2`;
  - the four prompts of that mode as lit rows with hover and a trailing `arrow.up.right` in `ink3`;
  - the existing hint line in `caption` `ink3`.
  - Merc as `NightMercLamp(.idle, size: 72)` above "Hi, I'm Merc".

**Carries over:** `NightChatScreen`'s reply-as-type, `studentCard`, `sourceChip` (with honest copy), `questionCard` (as Your turn), chip styling, the composer, `NightReplyParts`' split. **Not carried:** the custom glass mode switcher (the native segmented picker is the Mac control), "Give me a hint" (no such feature; the real chips are Explain more and Quiz me), "pinned source", "Socratic · AI tutor" (the mode name), History in the header (the sidebar is the history).

**Mouse and keyboard:** unchanged (Return / Shift-Return, ⌥⌘1–3, ⌘N, ⌘R, ⇧⌘E, ⇧⌘A, right-click Copy / Report, drop and paste). The source chip is a link: pointing hand, and Return opens it when it's focused.

**Judges' fixes:**
- A source that doesn't look verified (educator).
- Bottom chrome is one layer: chips scroll with the reply; the composer is the only pinned chrome.
- No student turn half-dissolving under a header: the system toolbar's scroll edge handles it.
- The muddy 28 pt avatar is now a 20 pt badge beside type.

### 5.5 Unit check

Screen: `UnitTestView`'s Mac branch. Toolbar unchanged ("Unit 1 Check" / the unit's title / back). Restyle only: the questions, grading, the written defense, the 4-of-5 rule and the crisis branch don't change.

**1280 × 800 and 700 × 600:** the 620 pt column on the canvas (pool 1, no stars).

- **Instructions:** `body` `ink2`, the existing sentence. Then the existing keyboard line in `caption` `ink3`.
- **Each question:** a lit card (radius `card`, padding 18).
  - Eyebrow "Question 1".
  - The stem in `title2`.
  - The four rows exactly as the lesson check's rows (§5.3.3). This view already selects and then submits, so there's no Lock it in here.
  - After submit: the existing explanation in `body` `ink2`.
  - Focus: the card's own ring (§4.4) replaces the current overlay.
- **Submit:** `NightPrimaryButton` (⌘Return, as now).
- **Score line:** `title2` "You got 4 of 5 correct." (existing copy).
- **Written defense:**
  - eyebrow "Written answer" (was "WRITTEN DEFENSE");
  - the existing lead line in `body` `ink2`;
  - the defense prompt in `keep` 18 (Merc's question to the student);
  - the field as a lit well (`surfaceRaised`, `fieldStroke`, radius `row`, `body`), with the existing placeholder;
  - Submit as `NightPrimaryButton`.
  - "Grading your answer…" in `callout` `ink3`, with a small `ProgressView`.
- **Mastered:** a `successText` `checkmark.seal.fill` at 28 pt, then the existing sentence in `title2`, then `NightPrimaryButton` "Done". No ceremony (the unit-mastery ceremony is Quest's graft).
- **Not mastered / retry:** the existing copy and buttons as Night buttons.
- **Crisis** (`phase == .support`): the screen swaps to `CrisisSupportView` on a **flat** canvas (§5.9). The unit check's pool goes with it.
- **Unavailable:** "This unit test isn't available right now." with Done, centred in a lit card.

**Carries over:** `checkCard` / `optionRow` styling, `NightEyebrow`, `keep` for Merc's question. **Not carried:** a one-question-per-screen restyle (concept "next" item), any ceremony.
**Mouse and keyboard:** unchanged (A–D / 1–4, Tab / ↑ / ↓, ⌘Return, Escape when nothing is lost).
**Judges' fixes:** the shared row component; contrast pinned.
**VoiceOver:** unchanged labels; each card is a container with its stem as header.

### 5.6 Lesson complete

Screen: `LessonCompleteOverlay.macBody`. It stays a centred card over the dimmed lesson. Return takes the primary button. Escape (or a click on the backdrop) goes back to the lesson, as now.

New inputs, each with a default so the iOS call sites don't change:
- the lesson's `[KEY]` texts, in order, read by `CurriculumLessonView` from the lesson thread's assistant messages with `BlockParser`;
- `weekDone` and `weekGoal` after this completion, as plain `Int?`. `MacShellView` passes them in from the weekly plan, because ChatFeature can't import CurriculumFeature. Nil hides the week row.

**1280 × 800:**
- **Backdrop:** the lesson under a canvas-coloured scrim (`canvasBottom` at 70%; under Reduce Transparency, 92%).
- **The card:** 520 pt wide, at most the detail's height minus 48. It's a lit surface with radius `hero` and padding 24, on its own canvas: both pools and, in dark, stars, clipped to the card.
- **Top to bottom:**
  1. `NightMercLamp(.celebrate → .happy, size: 96)`, centred **inside** the card, with one bloom of `violet` / `accent` radial light behind him and no rings.
  2. Eyebrow "Unit 1 · Lesson 1 · Complete" with `checkmark.seal.fill`, centred.
  3. `display` "Lesson complete", centred.
  4. `body` `ink2`: the lesson title, centred.
  5. **Key ideas from this lesson** (only if there are any): a `headline` `ink2` label, then up to 3 rows: a `key.fill` in `accentText`, then the text in `keep` 16 `ink`. More than 3: the last 3, and "+1 more in the lesson" in `caption` `ink3`.
  6. **The week row** (a `surfaceRaised` well): `NightRhythmRing` 44 pt filling from the old count to the new one, `headline` "1 of 2 this week", and `callout` `ink2` "One more meets this week's goal. Or stop here for today." (at or past the goal: "Weekly goal met. Anything more is a bonus."). Shown only when `weekDone` and `weekGoal` are passed in.
  7. **Up next:** eyebrow `ink3` "Up next · Lesson 1.2" (the path's code, fix pass), then `headline` `ink` with the title. For a unit check: "Up next · Unit 1 check". At the end of the path the row isn't shown.
  8. **Buttons**, side by side: `NightSecondaryButton` "Done for now" (it does what "Back to lessons" does today: closes the lesson) and `NightPrimaryButton` "Start Lesson 1.2" (or "Take the Unit 1 Check" / "Back to your path"), Return.
  9. **Share** (the existing `LessonShareCard` path, unchanged) as a 30 pt chrome circle (`square.and.arrow.up`, label "Share") in the card's top-trailing corner.
- **The timeline:**
  - the card rises 12 pt and fades in (`milestone`);
  - +0.15 s, Merc celebrates and the bloom opens;
  - +0.25 s, the key rows fade in, 0.08 s apart;
  - +0.5 s, the ring fills over 0.6 s.
  - The buttons work from the first frame; nothing waits on the animation.
  - Reduce Motion: one crossfade to the final state.

**700 × 600:** the card is 520 × at most 500. Merc is 72. The content scrolls inside the card above a pinned button row (the two buttons, then Share in the corner as before). Nothing is truncated.

**Carries over:** `NightCompleteScreen`'s Merc-in-layout with bloom, eyebrow, display headline, key cards (as a list), week row with the stopping cue, Up next, the "Done for now" + "Start Lesson 2" pair, the reveal timeline. **Not carried:** "2 key ideas saved to your notebook", the notebook card stack, "You can now explain…", the concentric rings, "or call it a night" (time-of-day bound), the haptics.

**Mouse and keyboard:** Return = primary; Escape = keep reading; Tab reaches Done for now and Share.

**Judges' fixes:**
- Merc no longer collides with the header (he's inside the card).
- "Done for now" has equal weight.
- The headline is not "Nailed it!" in green.

**VoiceOver:**
- On appear, announce "Lesson complete. Up next: Lesson 2, Training data and where knowledge comes from."
- The key rows read "Key idea: …".
- The week row reads its sentence.
- The Share button reads "Share".

### 5.7 Onboarding and the consent gate

Screen: `OnboardingFlow` steps, in the shell's gate box (600 × at most 700, centred, as now). The sidebar stays hidden and disabled, and the menu stays off. **Nothing here may add a network call** (no remote images, no fetched fonts; Lexend is bundled). The wording, the order, the checkbox rule and `ConsentGate.currentVersion` don't change.

**1280 × 800:**
- The canvas with pool 1 and no stars.
- **Meet:** `NightMercLamp(.wave, size: 120)` above `display` "Meet Merc" and the existing line in `body` `ink2`, then `NightPrimaryButton` "Continue" (Return).
- **Age:** `display` title; the native pop-up (its bezel kept; step 02's fix); existing hints in `callout` `ink2`; `NightPrimaryButton` "Continue", disabled until an age is chosen.
- **Disclosure (consent):** `display` "Before you start"; the subline in `body` `ink2`; the three rows with `accentText` icons and `body` `ink` text; "Read the privacy policy" as a `NightTextButton` link; the native checkbox with its existing sentence on a lit row; `NightPrimaryButton` "Agree and continue" (disabled until ticked, Return when enabled); `NightTextButton` "Not now" in `ink2`.
- **Under 13, Paused, Limits, Your path:** the same treatment: `display` title, `body` text, Night buttons. Merc appears only where the step shows him today. The under-13 screen keeps its calm tone: no lamp, no light.

**700 × 600:** the box is 600 wide inside 700 and scrolls when a step is taller than 548 pt (the existing `GateStepContainer` behaviour), with the button directly under its step.

**Carries over:** type, palette, buttons, the Merc lamp. **Not carried:** stars, gradients.
**Mouse and keyboard:** Return = each step's button (existing); Tab reaches the checkbox and the pop-up.
**Judges' fixes:** none specific; contrast pinned.
**VoiceOver:** unchanged.

### 5.8 Settings window

Screen: `MacSettingsWindowView`. **Stays a native Mac settings window** (D10): the system toolbar tabs (General / Privacy / About), `Form` with `.formStyle(.grouped)`, system fonts, system backgrounds and controls.

- The only changes: `.tint(Night.prominent)` for controls, and whatever `BrandColor` text it uses now reads the Night values (§2.2).
- **Untouched:** "Delete My Data & Start Over…", its confirmation, failure alert and device-only reset sheet; Privacy Choices and withdrawing consent; the session ID's Copy rules; the main window's erase lock; `beforeSettingsErase` / `afterSettingsReset`.
- Light, dark, Increase Contrast and Reduce Transparency are the system's.

### 5.9 Crisis view (palette only)

Screen: `CrisisSupportView` and its Mac card `MacCrisisNumbers`, wherever they show (unit check, quiz, Help ▸ Get Help).

- **What changes:** only colour, through the `BrandColor` mapping (§2.2). The background is **flat** `canvasTop`: no gradient, no pools, no stars. The card is `surface` with a 1 pt `border` edge. Text is `ink` / `ink2`; links are `accentText`.
- **What doesn't:**
  - no Lexend display, no serif: the type stays `BrandFont` (system);
  - no lit edge, no shadow, no glow, no Merc, no motion, no hero, no glass;
  - the copy, the numbers, Copy, the FaceTime / Messages links and their note, and the Escape rule.
- The heart glyph keeps `BrandColor.accent`: decoration, already hidden from VoiceOver.
- It works the same under every accessibility setting. The HC palette applies; nothing else changes.

### 5.10 Error and empty states

| State | Spec |
|---|---|
| A send fails (chat or lesson) | Under the student's card: `exclamationmark.circle` in `errorText` and the existing reason in `body` `ink`, then a `NightSecondaryButton` "Retry" (⌘R). The existing per-platform network copy (`NetworkSwitchAdvice`) is unchanged. |
| Daily limit, server refusal, mode switch failed | Existing copy and alerts. Inline ones take the row above; system alerts stay system alerts. |
| No chats yet (Today) | The existing sentence in `body` `ink2` inside Recent chats. |
| Empty chat | §5.4. |
| Unit check unavailable | §5.5. |
| Whole path done (Today, unit page) | The existing `UpNext` copy ("You've finished every unit…") in the hero; the unit page's cover says "Mastered". |
| Progress with gamification off | Inherits the palette; never renders zeros (unchanged rule). |
| Loading (a lesson resuming, a reply starting) | The existing Merc presence, recoloured: three `lumen` dots that pulse; under Reduce Motion, still, with "Merc is writing…" in `caption` `ink3`. |

No sad Merc, no illustration, no colour wash on any error. An error is a line of text and a way forward.

---

## 6. Honest-copy register

Every line of new or changed UI text. "Kept" means existing product copy used as is.

| Concept said | The Mac says | Why |
|---|---|---|
| "Saved to notebook" (KEY card) | nothing | There is no notebook. |
| "2 key ideas saved to your notebook" | "Key ideas from this lesson" | The ideas are shown, not saved anywhere. |
| "4 days running. Rest days never reset your progress." | "4 days running. One lesson or chat a day keeps it going." (only when the streak is 1 or more) | The daily streak still exists and does reset. The second sentence is the Mac's existing streak copy. |
| "Beat 2 of 6 · Tokenization" | "Part 2 · Tokenization" | The total isn't known while a reply streams. Parts count so far. |
| "Hook" (first beat's name) | no name ("Part 1") | Invented label. |
| "about 6 min", "About 6 min", "6 min" | nothing | Not measured. |
| "Every lesson is previewable" | "Opens after Lesson 3" on locked rows | Lessons unlock in order (`isLessonUnlocked`). |
| "Unit 01 checkpoint · 5 questions, then defend your thinking in a few sentences." | "Unit 1 check · 5 questions, then one written answer Merc grades." | Kept from the Mac's `MacTodayView.upNext`; matches the real check. |
| "pinned source" | "Cited by Merc · {domain}" + help "Merc picked this source. Open it and check that it says what Merc says." | The model chooses the citation; it isn't verified. |
| "Merc · Socratic · AI tutor" | "Merc · AI tutor", over a thread's first reply only, as type (no bust) | The mode can change mid-thread; the bubble-less reply already says who speaks. The tutor is "Merc" on every Mac screen ("Ask Merc…", "Merc asks questions back…", "graded by Merc"); "Mercurius" is the app's name only. |
| "Give me a hint" | "Explain more", "Quiz me" (kept) | No hint feature exists. |
| "Continue lesson" | "Start Lesson 3 →" / "Continue Lesson 3 →" (kept) | |
| "Hi there." | `HomeState.opener` with "." ("Good evening.") | Kept wording, calmer punctuation. |
| (subline) | first lesson: "Your first lesson is ready when you are."; resuming or later: "Your next lesson is waiting."; goal met: "Your next lesson is there whenever you want it." (fix pass: the week card already says the goal is met); unit check next: "Unit 1's lessons are done. Ready for the check?"; path done: "You've finished the whole path. Chat with Merc any time to go deeper." | All from `HomeState.greeting`, minus its opener. The "keep your streak alive!" line is not used. |
| "Two lessons a week is the whole plan." | "Goal: 2 lessons a week." (kept `weekDetail`) | No new promise. |
| "Weekly goal met" / "1 of 2 lessons" | kept (`weekHeadline`) | |
| "Think it through · Socratic" + a recorded student question | "Think it through · {current mode}" + a prompt from `ModePromptProvider` + `ModeDescription.purpose` | Real prompts, real mode, no auto-send. |
| "Merc asks questions back. You do the reasoning." | `ModeDescription.purpose` (kept) | Existing copy. |
| "Your turn first" (was "Check · your turn first") / "Lock it in" / "Or answer in your own words…" | kept | All true of the Mac's check. |
| "Next beat" + canned feedback ("Exactly right — …") | nothing; Merc's real reply streams | The concept's feedback was a recording. |
| "Lesson complete" + "You can now explain tokenization and next-token prediction." | "Lesson complete" + the lesson's title | Asserted, not shown (educator). |
| "One more meets your weekly goal — or call it a night." | "One more meets this week's goal. Or stop here for today." | Same stopping cue, true at any hour. |
| "Nailed it!" (current Mac) | "Lesson complete" | Calmer; the eyebrow says what was completed. |
| "Back to lessons" (current Mac) | "Done for now" (same action) | A's stopping cue. |
| "WRITTEN DEFENSE" (current Mac) | "Written answer" | Plainer. |
| "Your path" (path title) | toolbar "Learning Path" (kept) | |
| Streak flame and count in the toolbar | "Progress" button | D8. |

A new string goes into the module's copy enum (§1.1) and §8.2's `NightCopyTests`.

---

## 7. Out of scope, and how each could come later

| Item | Why not now | How it could come later |
|---|---|---|
| **The meaning sky** (the concept's signature screen) | It needs authored, curated content and a teacher review. The educator found its control teaches the wrong model ("bank = money" is a dictionary lookup). | A separate project: write the Unit 1 Lesson 1 sequence with context chips as the control (SYNTHESIS B2), get a teacher review, build it as state-driven SwiftUI with VoiceOver summaries and a Reduce Motion fade, and decide where it sits in the lesson. The Night tokens here are its palette. |
| **The notebook** ("Saved to notebook", a Notebook destination, recall cards) | No store exists, and a store of a minor's learning needs a privacy decision (on-device only; erased by Delete my data). | Founder decision (SYNTHESIS §5 Q2). Then a `PersistenceKit` store, a sidebar row "Notebook", a bookmark on the KEY card, and "Delete my data" wiping it, with tests. Only then may the copy say "saved". |
| **The share card** ("I can explain…", Quest graft 9) | Another direction's graft. | The existing Share button stays. A new card would render through the existing `LessonShareCard` / `ImageRenderer` with no name and no score, opt-in. |
| **"Sure / Not sure" calibration** (Field Notes graft 1) | Graft. | Add a confidence step between pick and Lock it in in §5.3.3's check, with all four feedback paths written and reviewed. |
| **[KEY] collapsing while the check is open** (graft 2) | Graft. On the Mac the check is inline, so the KEY is above it in the scroll. | Collapse the lesson's last KEY card to its eyebrow while an answerable `[Q]` is on screen; restore it after lock-in. |
| **"AI tutor · can be wrong, so check its sources"**, numbered footnotes, "Go deeper" (graft 3) | Graft. The source chip here is the honest minimum for A's own chip. | Replace the chip with numbered footnotes and split "Sources" from "Go deeper". |
| **"In your words"** on lesson complete (graft 4) | Graft. | Pass the student's exercise answer to the complete card beside the key ideas. |
| **Hint ladder** ("Give me a nudge" / "Show an example", graft 13) | Graft, and it sends canned student turns (prompt-eval gate). | New chips that send fixed turns; `eval-pacing --runs 3` in both flag states. |
| **Unit-mastery ceremony** (graft 10), **unit emblems** (14), **hook questions** (12), **Merc's idea emotes** | Grafts, and they need authored content (24 skill lines, 8 emblems, 35 hooks). | After the content is written: a one-shot, state-driven reveal on `UnitTestView`'s mastered state, in the lamp language. |
| **"Part N of M", time left, `[TOK]` token chips on any example** | Needs a server outline marker: a three-client contract change (server, iOS, both widgets). | SYNTHESIS B4. The part strip's dashed "more" segment becomes real segments, and the recogniser gives way to `[TOK]`. |
| **Measured time estimates** | Not measured. | Compute median lesson durations from the usage ledger; show "About N min" only from that data. |
| **Retiring the daily streak** for a weekly rhythm | Founder decision; server and two iOS targets. | SYNTHESIS M5. The Today line then becomes the weekly count. |
| **Night Studio on iOS** | The hard rule for this branch. | The tokens and components here move out of `#if os(macOS)` with iOS sizes (`relativeTo:` text styles) and the iOS snapshot references re-recorded by the founder. |

---

## 8. Building it

### 8.1 Three engineers, in this order

| Engineer | Owns | Starts |
|---|---|---|
| **E1, foundations and chrome** | `DesignSystem/Sources/Night/*`, the `BrandColor` Mac mapping, `BrandButton` / `DuoButton` Mac branches, `.nightEnvironment()`, the DEBUG flags (§8.4), `NightContrastTests`, the window chrome and sidebar (§5.0), ⌘4, the Settings tint (§5.8), the crisis view check (§5.9), the gate (§5.7) | Day 1. Tokens and components first, so E2 and E3 can build on them. Until they land, E2 and E3 use this spec's values. |
| **E2, overview screens** | Today (§5.1), the unit page (§5.2), lesson complete (§5.6) | After E1's tokens |
| **E3, reading surfaces** | `NightReply` (§5.3.3: no bubble, blocks, token chips, source chips, Your turn, crisis guard), parts and the part strip (§5.3.2), the lesson intro (§5.3.1), Lock it in, the composer and chat (§5.4), the unit check (§5.5), errors and empty states (§5.10) | After E1's tokens |

### 8.2 Tests to add (all in `swift test`, all Mac-host)

| Suite | Pins |
|---|---|
| `NightContrastTests` | Every pair in §2.3, from `NightPalette`, all four variants |
| `NightPaletteMappingTests` | `BrandColor`'s Mac mapping table (§2.2) points at the right `NightPalette` entries; `BrandPalette` is unchanged |
| `NightPartsTests` | Counting across replies, whitespace sections, streaming (a section counts once its first character arrives), naming (Check, bold term, ≤ 32 characters, none), no total anywhere |
| `NightTokenChipTests` | The recorded example yields `un / believ / able`; a mismatch, a single piece, or no "token" word yields nothing; curly quotes |
| `NightSourceTests` | Both server formats; the tag leaves the prose; link-wrapped tags and tags in cards; prose that says "Source:" stays prose; the chip opens the domain only; `ReplyLinkPolicy` decides tappability; no domain → inert |
| `NightYourTurnTests` | Latest completed reply only; a "?" ending; 400 characters; the crisis guard (`988`, `741741`) turns it off |
| `NightCheckLockInTests` | A pick doesn't send; Lock it in sends "I picked B) …" once; letter keys pick only when the card has focus; Escape is refused with an uncommitted pick |
| `MacTodayTests` (extended) | The subline table (§6); the streak line never shows a zero; the week's day dots and their VoiceOver sentence |
| `MacUnitPageTests` | Each stop's state and its "Opens after Lesson N" from `isLessonUnlocked` |
| `NightCopyTests` | No string in the Night copy enums matches (case-insensitive) `notebook`, `saved to`, `rest day`, `\bof \d+\b` after "Part", `\b\d+\s?min`, `previewable`, `pinned`, `give me a hint`, `beat \d` |
| Existing Mac suites | Still pass: shell routing, gate, erase hooks, sidebar, shortcuts (add ⌘4 to the shortcut tables), composer keys, lesson chrome Escape (add the uncommitted-pick rule), harness options |

### 8.3 What must not move

- `swift test` passes in full, with `ArchitectureTests` (no new dependency edges: Night lives in DesignSystem, which every feature already imports).
- iOS: the snapshot comparison tests, recording **off**, show the same pass/fail set as `feat/mac-app-2026-10` (11 pass, 12 already stale), and the iOS `xcodebuild test` suite passes. That's the proof iOS is untouched.
- The consent gate still makes no request before consent (re-run step 04's logging-server check on the Night build).
- Delete my data, reset and withdraw still stop a running lesson first (the step-05 tests).

**Tooling from the parallel tooling step** (untracked in this worktree while this spec was written; use them once they're committed):
- `ios/scripts/ios-unchanged-check.sh`: the snapshot suite with recording off, against a committed baseline (`docs/mac-night-studio/ios-snapshot-baseline.txt`);
- `ios/scripts/ci-compat-lint.py`: trailing commas in argument lists, and macOS 26 / iOS 26 symbols outside `#if compiler(>=6.2)`;
- `ios/scripts/mac-copy-snapshots.sh`: §8.4's copy-and-photograph procedure in one script.

### 8.4 Verifying on the founder's Mac (without disturbing the founder)

- **Build** with derived data `/private/tmp/merc-mac-ns-dd` and SwiftPM scratch `/private/tmp/merc-mac-ns-spm`, after `xcodegen generate`. Delete untracked iCloud " 2" files first. Retry codesign xattr failures up to 3 times.
- **Never touch** the founder's running app or `/private/tmp/merc-mac-dd`.
- **Copy the app before running it:**
  1. copy the built `.app`;
  2. set `CFBundleIdentifier` to `com.mayoailiteracy.mercurius.native.macns<N>` with `PlistBuddy`;
  3. `codesign --force --deep -s - <copy>`;
  4. run `MAC_APP=<copy> scripts/mac-snapshots.sh <dir> <states…>`.

  Quit only that copy, by its PID.
- **New DEBUG flags**, each with a value:
  - `-NightContrast increased`;
  - `-NightReduceTransparency YES`;
  - `-NightReduceMotion YES`;
  - `-NightNoGlass YES` (the macOS 14–25 fallback on macOS 26);
  - `-NightCheckState picked|answered` (a lesson check with a pick, or locked in, from the replay).
- **Shots:**
  - every state in `mac-snapshots.sh`'s `ALL` list, light / dark / min;
  - plus `today`, `lesson`, `lesson-complete`, `chat-thread`, `unit-test`, `gate-consent` and `crisis` under each of the four flags above.
  - Look at every one. Glass shows dark or missing in PNGs; judge it on screen.
  - Pixel-check the contrast claims on a few shots with PIL (the hero under the lamp, `ink3` on the pooled canvas, the composer placeholder).
- **Snapshot record runs:** never.

### 8.5 Size

Rough, in engineer-days:

| Work | Days |
|---|---|
| Foundations, tests, chrome | 3 |
| Gate, crisis, Settings | 1 |
| Today | 1.5 |
| Unit page | 1.5 |
| Complete | 1 |
| Reply rendering | 3 |
| Parts and Lock it in | 2 |
| Chat and composer | 1.5 |
| Unit check | 1 |
| Errors | 0.5 |
| Accessibility pass and shots | 1.5 |
| **Total** | **≈ 17.5** |

That's about 6–7 working days for three engineers.

### 8.6 For the founder (defaults chosen, so nothing waits)

1. **The streak off the toolbar** (D8). Default: yes, as Night Studio does. Reverting is one toolbar item.
2. **Lock it in on the Mac only** (D9). The iPhone keeps tap-to-answer until iOS adopts Night Studio.
3. **Source chips on the Mac first.** They fix the raw `[SOURCE: …]` text that leaks on both platforms today. The iPhone still leaks until the parser moves to iOS (a quick win in SYNTHESIS Q2).
4. **The Mac and the iPhone will look different** until iOS adopts Night Studio. Students with both see the same content in two skins.
