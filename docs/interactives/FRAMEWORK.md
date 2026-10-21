# Lesson interactives: the framework

**What this is:** the shared framework the slate's cards are built on (`SLATE.md`, `BUILD_PLAN.md` §1 in `.claude/worktrees/interactives-shared/`): a registry keyed by lesson id, the placement rules, the predict-then-reveal machine, the shared blocks and views with iPhone and Mac styling hooks, and the DEBUG launch paths for screenshots. Lesson 1.1's tokenizer is registered through it, and its behaviour is unchanged.
**Branch:** `feat/interactives-wave1` (from `feat/ios-tokenizer`). **Status:** framework built; every new card ships dark (`enabled: false`) until its review is signed off. Nothing merges without the founder's explicit OK.

---

## 1. How to add a card (the steps)

Do these in order. `<Card>` is the card's type name (`DoubtDial`), `<slug>` its slate slug (`doubt-dial`), `<id>` its `InteractiveID` case (`.doubtDial`). The id, the registry row and a placeholder view already exist for all 11 cards.

1. **Read the card's brief.** Read its entry in `SLATE.md` and `slate.json`, and its sketch in `sketches/<slug>.svg`. Get its numbers from `tools/check_slate_numbers.py`.
2. **Content and logic.** Write `LessonInteractives/Sources/Cards/<Card>/<Card>Content.swift`.
   - It holds the authored data and the pure logic, and nothing in it is a view.
   - Re-derive every number the card shows from the authored data, so the test can check it.
   - If the card needs a block of its own (ToyFit, RoutePlanner, IconArray, FrameScrubber), put the block's pure logic in `Sources/Blocks/<Block>.swift`, with its own tests.
3. **Copy.** Write `Cards/<Card>/<Card>Copy.swift` as an enum that holds every visible and spoken line.
   - `static var everyLine: [String]`: every line the card shows or speaks.
   - `static let labels: [InteractiveLabel]`: the card's on-canvas labels, each with a kind (`.example`, `.toy`, `.madeUp`, `.ourArithmetic`, `.illustrative`).
   - `static func accessibilitySummary(_ state:) -> String`: the card's state in one sentence.
   - `static let predictionLines: [String]`: the prediction prompt and its choices, plus a reveal line that refutes them. Only these lines may use intent words.
   - Lesson 1.1's tokenizer still writes its own title; for a new card, the title's VoiceOver label defaults to "Interactive: <title>".
4. **State.** Write `Cards/<Card>/<Card>State.swift`, an `@Observable @MainActor final class` that is never `Codable`.
   - It holds a `PredictReveal<Choice>` (`.debugStarting(InteractiveLaunchOptions.current.state, …)` in its init) and the card's control state.
   - The view gets it with `context.state { <Card>State(spoiled: $0.spoiled) }`.
5. **iPhone view.** Write `Views/Phone/<Card>PhoneCard.swift`, inside `#if os(iOS)`.
   - Wrap it in `InteractiveCardShell(id:title:summary:compactLine:)`.
   - Build it from the shared blocks (§4) and use only `@Environment(\.interactiveTheme)` roles and `.interactiveText(_:)`.
   - Check it at Dynamic Type up to AX5 on an SE. `theme.usesTables` swaps charts for `InteractiveTextTable`, and decoration goes, never content.
6. **Mac view.** Write `Views/Mac/Night<Card>Card.swift`, inside `#if os(macOS)`.
   - Use the same shell. It draws Night Studio and the compact "Try it" card below 440 pt.
   - Use the shared controls: they put themselves in the Tab loop and hold Return from the check.
   - Arrows: ←/→ only, while the control has focus. ↑/↓ belong to the lesson's check while it waits.
7. **Wire it in** (`Sources/Views/InteractiveCardViews.swift`, the only shared lines a card edits).
   - Replace the card's `InteractivePlaceholderCard(context)` line in `phone(_:)` with `<Card>PhoneCard(context)`.
   - Replace its line in `mac(_:)` with `Night<Card>Card(context)`.
   - Add `<id>` to `built`. Each card's lines are separated by blank lines, so parallel card branches merge cleanly.
8. **Tests.** Copy the template in §6 to `LessonInteractives/Tests/<Card>Tests.swift`. Add a UI test from `MercuriusUITests/InteractiveLaunchUITests.swift` (§6.3).
9. **Verify** with the commands in §5: `swift test`, the CI lint, an iOS build with `xcodebuild test`, the snapshot check, a Mac Debug build, then shots from the gallery and in the lesson on iPhone 16 Pro Max, iPhone SE at AX5 and Mac. Store the key shots under `docs/interactives/<slug>/shots/`.
10. **Content doc.** Write `docs/interactives/<slug>/CONTENT.md` in the tokenizer's shape (`docs/mac-night-studio/tokenizer/CONTENT.md`). It holds:
    - the numbered claims with their sources and status;
    - "what this card does NOT say";
    - the VoiceOver walk-through script;
    - the invented-name searches (date and result);
    - the teacher checklist (`BUILD_PLAN.md` §4.5).
11. **Ship dark.** Leave `enabled: false` in `InteractiveRegistry.all`. Turning the card on is its own last commit, made after the teacher's sign-off is recorded in CONTENT.md, and it needs the founder's explicit OK.

Don't edit: the wire, the prompt, `server.js`, the placement code (§3), other cards' files, or `project.yml` (the module is a package target).

---

## 2. File layout

```
ios/Packages/LessonInteractives/            (DesignSystem only: no network, no storage)
  Sources/
    Core/
      InteractiveID.swift          every card: slug, working name
      InteractiveSpec.swift        InteractiveSpec, InteractiveAnchorRule, InteractiveTerms (spoiler/mention matching)
      InteractiveRegistry.swift    the table: lesson → card, anchor, spoilers, wave, enabled
      InteractiveLaunchOptions.swift   DEBUG launch arguments; InteractiveScrollID
      PredictReveal.swift          the predict → reveal machine; InteractiveRevealLines
      InteractiveCopy.swift        InteractiveShellCopy, InteractiveLabel, InteractiveCopyRules
      InteractiveLayout.swift      InteractiveLayout, InteractiveMotion, InteractiveAccessibility
      InteractiveStateStore.swift  per-lesson state store; InteractiveCardContext
    Blocks/
      ThresholdCounters.swift      stops over scored items, counted meters; MeterComparison; InteractiveRates
      StepThrough.swift            Next/Back steps with a gate and VoiceOver lines
      (ToyFit, RoutePlanner, IconArray, FrameScrubber: added by their first card)
    Views/
      InteractiveCardViews.swift   the id → view switch per platform; `built`; the placeholder card
      Shared/
        InteractiveTheme.swift     the styling hooks: InteractiveTheme roles, .interactiveText(_:)
        InteractiveCardShell.swift the frame: iPhone night-sky island / Mac lit card + compact "Try it"
        InteractiveControls.swift  InteractiveChip, InteractiveActionButton, the Mac keyboard contract, key routing
        PredictChips.swift         PredictChips, RevealBox, LabelLine, InteractiveTextTable
        CounterTiles.swift         CounterTiles (+ the "=/≠" comparison)
        StopControl.swift          StopControl, InteractiveSegmented, StepControls
      Phone/                       <Card>PhoneCard.swift (one per card)
      Mac/                         Night<Card>Card.swift (one per card)
    Cards/<Card>/                  <Card>Content.swift, <Card>Copy.swift, <Card>State.swift
  Tests/                           Registry, PredictReveal, Blocks, CopyRules, NoIO (+ state store),
                                   LaunchAndLayout; one <Card>Tests.swift per card

ios/Packages/ChatFeature/Sources/  (everything that reads the thread)
  Lesson/LessonInteractive.swift      the anchor rules, spoiler scan, once-per-thread index, iPhone bubble split
  Lesson/LessonInteractiveCardView.swift  the host (routes the tokenizer to its own views), scroll marks,
                                      the DEBUG gallery (InteractiveGalleryView)
  Lesson/InteractiveStubReplies.swift DEBUG stub replies for lessons with no recording
  LessonReplay.swift                  per-lesson replay; auto-answers stub checks for later-reply cards
  Tokenizer/, Mac/NightTokenizer*     Lesson 1.1's card, unmoved
  ChatView.swift, MessageBubbleView.swift, Mac/NightReplyViews.swift   card-agnostic mounting
ios/Packages/ChatFeature/Tests/InteractivePlacementTests.swift   every rule, spoilers, stubs, the tokenizer via the registry
ios/Packages/AppFeature/Sources/RootView.swift, Mac/MacShellView.swift  -Interactive / -InteractiveGallery routing
ios/Packages/AppFeature/Tests/InteractiveCurriculumTests.swift   registry vs Curriculum.swift
ios/Packages/ArchitectureTests/                                  LessonInteractives may depend on DesignSystem only
ios/MercuriusUITests/InteractiveLaunchUITests.swift              the launch paths, end to end
docs/interactives/<slug>/CONTENT.md, shots/                      per card
```

---

## 3. The registry and the placement API

### 3.1 The registry (`InteractiveRegistry`, LessonInteractives)

```swift
public enum InteractiveID: String, CaseIterable { case tokenizer, citationThatWasnt, … }   // .slug, init?(slug:)
public enum InteractiveAnchorRule { case firstExample, teachReply(Int), firstReplyMentioning([String], fallback: Int) }
public struct InteractiveSpec { id, lessonID, anchor, spoilers, wave, enabled }
InteractiveRegistry.all                      // one row per card (BUILD_PLAN.md §1.2's table)
InteractiveRegistry.spec(for: .doubtDial)    // a card's row
InteractiveRegistry.spec(forLesson: "u6_l4") // the lesson's ENABLED card, or in DEBUG the -Interactive card
```

The rules are enforced by tests:
- one card per lesson, and none in a Review lesson;
- every lesson id exists in `Curriculum.swift`;
- every unit has 1 or 2 cards;
- only cards in `InteractiveCardViews.built` may be enabled. Today only the tokenizer is enabled.

### 3.2 Placement (`LessonInteractiveAnchor`, ChatFeature)

```swift
LessonInteractiveAnchor.placement(spec:messages:crisisReplies:sections:) -> LessonInteractivePlacement?
LessonInteractiveAnchor.placement(lessonID:messages:crisisReplies:sections:)  // the registry's card; the tokenizer's old call
LessonInteractiveIndex().placement(spec: | lessonID: …)   // cached per thread change, kept per thread (LessonInteractiveMemory)
struct LessonInteractivePlacement { messageID, position (section, afterBlock), card: InteractiveID, spoiled: Bool }
```

**Which reply** (the anchor rule):
- `.firstExample`: the first reply with an [EX] example, or the first complete reply when none has one. This is Lesson 1.1's rule, unchanged.
- `.teachReply(n)`: the nth reply that carries a [Q] check. A reply counts once its check has begun arriving. If that reply can't hold the card (its check is its very first block), the next teach reply does.
- `.firstReplyMentioning(terms, fallback: n)`: the first reply whose text contains a term, matched case- and diacritic-insensitively from the start of a word. A reply that is still arriving without a term is waited for. If no reply has a term by teach reply n, teach reply n holds the card.

**Where in that reply** (the same for every rule):
- at the end of the part its first [EX] is in, before any check;
- with no example, at the reply's end before its check.

**Always:**
- The card is never placed mid-stream: it waits until the example's part has ended (a later part or a check has begun, or the reply is complete).
- Cut and failed replies are passed over.
- A "complete" reply counts as proof only when it is the thread's last message (AUD-29).
- A thread that carried a crisis line (988 or 741741) has no card.
- The card appears once per thread, and in the same place when the lesson is reopened in the same run.
- Nothing is sent or stored, and the wire and the prompt are unchanged.

**Spoilers.** The scan covers every earlier reply in full, plus the anchor reply's text above the card. It runs once, when the place is found, and the flag is kept with the placement, so it never flips while the lesson is open.
- The spec's spoiler terms use the same matching as the mention rule. "12%" doesn't match "112%", and "impossib" does match "impossibility".
- A spoiled card gets `context.spoiled == true`, and its `PredictReveal(spoiled: true)` skips the prediction. The reveal then has no "You guessed".

**Drawing.** `ChatView`'s list passes `interactiveAfter` (the position) and `interactiveCard` (`LessonInteractiveCardRef(id, spoiled)`) to each row. The iPhone bubble (`MessageBubbleView`) and the Mac reply (`NightMessageRow`) then branch:
- the tokenizer is drawn by `LessonTokenizerCard` / `NightInteractiveCard`, exactly as before;
- every other card is drawn by `LessonInteractiveCardView`, which calls `InteractiveCardViews.card(InteractiveCardContext(spec, spoiled, store))`. The store is the lesson list's `InteractiveStateStore`, which lives only in memory and starts fresh on a new lesson screen.
- The card carries the scroll ids `InteractiveScrollID.card` / `.top` / `.after`, and the card marks `.reveal` itself.

---

## 4. The building blocks and styling hooks

### 4.1 Pure logic (tested in `LessonInteractivesTests`)

| Block | Use |
|---|---|
| `PredictReveal<Choice>` | `hook → locked → exploring → revealed`; `lock(_:)` once (`canLock`); `canExplore` gates the one control; `recordMove()`; `showsShowMe` after `showMeAfter` moves; `reveal()`; spoiled mode; `revealLines(guessText:result:)` → `InteractiveRevealLines` (`.spoken` for VoiceOver); `debugStarting(_:choices:…)` for `-InteractiveState` |
| `ThresholdCounters<Item>` | items with a score, a `Rule` (`.atMost` / `.atLeast`), `Stop`s with limits, `Meter`s that count (item, in?) pairs; `counts(atStop:)`, `table`, `smallestTotal`, `itemsIn(atStop:)`. It reproduces the Doubt Dial's table in `BlocksTests` |
| `MeterComparison` | "=" / "≠" within a tolerance, with `spoken` words ("about equal" / "not equal") |
| `InteractiveRates.percent` | whole percents (our arithmetic: label it) |
| `StepThrough` | `count`, `next()` / `back()`, `furthest`, a `gate` step that Next can't leave until `openGate()`, `position` ("Step 4 of 6") and `announcement(_:)` |
| `InteractiveTerms` | the anchor's and the spoiler scan's term matching |
| `InteractiveCopyRules` | `violations(in:card:predictionLines:)`: the honest-copy register (the same list as ChatFeature's `HonestCopy`, kept equal by a test), time words, and intent words outside the prediction lines. Per-card exceptions live in one table (Predict the Exam: "hint"). `missingLabels(_:in:)` |
| `InteractiveLayout` / `InteractiveMotion` / `InteractiveAccessibility` | `usesTables` (AX1 and up), the Mac's compact rule (440 pt), 44/36 pt targets, SE widths (343 → 311 pt content), `fitsInOneRow`; `animation(_:reduceMotion:)` (a crossfade), `transition`, `autoplays`; `announce(_:)`, `numbersMissing(_:from:)` |

### 4.2 Views (`Views/Shared`, both platforms)

| View | What it gives a card |
|---|---|
| `InteractiveCardShell(id:title:accessibilityTitle:summary:compactLine:content:)` | the eyebrow and title (a header whose value is `summary`), the frame, the theme. On the iPhone, Lesson 1.1's night-sky island; on the Mac, Night's lit card and the compact "Try it" below 440 pt (VoiceOver goes to the title, the keyboard to the first control) |
| `PredictChips(prompt, machine:, title:, onLock:)` | the question (a header) and 2–4 chips; one tap locks the guess; a selection haptic |
| `RevealBox(lines, takeaway:)` | "You guessed / What happened", one VoiceOver element. Mark it `.id(InteractiveScrollID.reveal)` and announce `lines.spoken` |
| `CounterTiles(tiles, comparison:)` | printed counts and "=/≠"; a text table at AX sizes; `CounterTiles.summary(_:)` is the sentence to announce |
| `StopControl(name, stops:, selection:, isEnabled:, value:, decreaseLabel:, increaseLabel:, onSelect:)` | a stops track (44 pt marks), or two step buttons at AX sizes; one adjustable VoiceOver element; ←/→ on the Mac while focused; a haptic |
| `InteractiveSegmented(name, options:, selection:, title:, onSelect:)` | a 2–3-way toggle (←/→ on the Mac) |
| `StepControls(steps, nextTitle:, onBack:, onNext:)` | Back / Next with "Step n of m" (→/← on the Mac) |
| `InteractiveChip`, `InteractiveActionButton` | a single choice or action, with the platform's target, ring and keys |
| `LabelLine(InteractiveLabel)` | an on-canvas label (never a footnote) |
| `InteractiveTextTable(rows)` | label-over-value rows for the accessibility sizes |

### 4.3 Styling hooks

`@Environment(\.interactiveTheme) var theme`, set by the shell, gives:
- colour roles: `ink`, `ink2`, `ink3`, `accentText`, `surface`, `raised`, `prominent` (white on it), `hairline`, `edge`, `lumen`, `focusRing`, `wash(_:)`, `wellEdge`;
- metrics: `minTarget` (44 on the iPhone, 36 on the Mac), `sectionSpacing`, `rowSpacing`, `chipSpacing`, `padding`;
- settings: `increasedContrast`, `reduceTransparency`, `reduceMotion`, `usesTables`, `lit`;
- motion: `animation(_:)`, `transition(edge:)`.

`.interactiveText(.title | .heading | .body | .callout | .calloutStrong | .caption | .eyebrow | .number | .machine)` sets the type: iPhone Dynamic Type styles, or the Mac's Night ramp.

On the iPhone the roles come from `NightSkyCard` (the same in light and dark, the HC values under Increase Contrast, solid under Reduce Transparency); on the Mac, from `Night`. Every text role reads at 4.5:1 or better on `surface` and `raised`. Use only these roles. If a card needs a new colour, add a role here instead.

### 4.4 The contracts every card keeps (checked by the card's tests and shots)

- **Predict first, one control.** The control is `isEnabled: machine.canExplore`. Its VoiceOver value says `InteractiveShellCopy.guessFirst` until a guess is locked.
- **iPhone:** targets of 44 pt or more, and a selection haptic on each pick or stop (the shared controls do both). AX5 on an SE drops decoration but keeps every word. The card never scrolls sideways.
- **Mac:** every control is in the Tab loop whatever the Full Keyboard Access setting. Space and Return activate. A focused control holds Return, so the lesson's check never locks in from it. A–D, 1–4 and ↑/↓ still answer the check. A check pick takes focus back. A click doesn't keep the keyboard.
- **Reduce Motion:** crossfades only, and nothing autoplays (`InteractiveMotion.autoplays`).
- **Increase Contrast and Reduce Transparency:** `theme.lit` is false (no glows or stars), and edges are solid.
- **No state by colour alone:** use a glyph and words.
- **VoiceOver:** the title and the steps are headers, and the card's state is one sentence (`summary`). Announce what the student caused.
- **Minors:** no real faces or voices, synthetic people only, and no real person accused of anything. Name real companies only as the slate allows.

---

## 5. DEBUG launch arguments, the gallery and verification

| Argument | Effect |
|---|---|
| `-Interactive <slug>` | Opens the card's lesson. It implies `-LessonPreview -LessonSkipIntro -LessonReplay`. Lesson 1.1 replays its recording; every other lesson streams **stub replies that say they are stubs** ("**Debug stub, reply 1 of 2.**"), shaped for the card's anchor. The card is shown even while it ships dark. For a card in a later reply (`teachReply`, `firstReplyMentioning`), the replay answers its own stub checks ("I picked A) …") until the card's reply arrives. On the Mac it opens in the shell's detail column |
| `-InteractiveGallery <slug>` | The card alone on the lesson's background (Night's canvas on the Mac), with no lesson, server or replay |
| `-InteractiveState hook\|predicted\|explored\|revealed\|spoiled` | The card opens in that state (`PredictReveal.debugStarting`; `spoiled` also forces the spoiled mode) |
| `-InteractiveScroll top\|reveal\|after` | Once a reply settles, the list scrolls the card's top, its reveal or its end into view |
| `-InteractiveStubSpoiled YES` | The stub reply names the card's first spoiler term above the card, so the real spoiler scan sets the spoiled mode |
| `-InteractiveReduceMotion YES`, `-InteractiveReduceTransparency YES`, `-InteractiveIncreaseContrast YES` | The iPhone card draws as under that setting (the tokenizer's `-NightTokenizer…` flags count too). On the Mac use `-NightReduceMotion YES`, `-NightReduceTransparency YES` or `-NightContrast increased` |
| `-InteractiveCompact YES` | The Mac card starts compact at any width |

Give every flag a value: on the Mac, a bare word after a value-less flag opens as a document. Text sizes on the iPhone use `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` (AX5).

**iPhone shots** (your own simulator and your own derived data):
```bash
cd ios && xcodegen generate
xcodebuild build -project Mercurius.xcodeproj -scheme Mercurius \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath /private/tmp/merc-ia-<key>-dd
APP=/private/tmp/merc-ia-<key>-dd/Build/Products/Debug-iphonesimulator/Mercurius.app
xcrun simctl install <udid> "$APP"
xcrun simctl launch <udid> com.mayoailiteracy.mercurius.native -UITests YES -consentVersion 1 -hasSeenOnboarding YES \
  -hasSeenChatInputHint YES -InteractiveGallery doubt-dial -InteractiveState revealed
xcrun simctl io <udid> screenshot /path/shot.png
# in its lesson:  … -Interactive doubt-dial -InteractiveScroll reveal
```

**Mac shots.** Only through a renamed copy, while the founder keeps using the real app. Never `pkill` or `killall` Mercurius, and never touch `/private/tmp/merc-mac-tok-dd` or `/private/tmp/merc-mac-ns-dd`.
```bash
xcodebuild build -project Mercurius.xcodeproj -scheme MercuriusMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/merc-ia-<key>-mac-dd
SRC_APP=/private/tmp/merc-ia-<key>-mac-dd/Build/Products/Debug/Mercurius.app COPY_DIR=/private/tmp/merc-ia-<key>-copies \
  N=ia<n> VARIANTS="light dark min" INTERACTIVE_ARGS="-InteractiveState revealed" \
  scripts/mac-copy-snapshots.sh <out-dir> gallery-doubt-dial interactive-doubt-dial
```
`scripts/mac-snapshots.sh` has two generic shot names:
- `interactive-<slug>`: the card in its lesson, scrolled to its top;
- `gallery-<slug>`: the card alone.

`INTERACTIVE_ARGS` adds state arguments, and `INTERACTIVE_DELAY` sets the settle time (14 s by default). `min` is the 700×600 window, where the card is compact.

**The verification set** (CI is Xcode 16.2 / Swift 6.0.3 on macOS 14):
1. `cd ios/Packages && swift test`
2. `python3 ios/scripts/ci-compat-lint.py`. CI also rejects these, and the lint doesn't catch them all:
   - a trailing comma in an argument list;
   - `#require` on an optional chain ending in a collection;
   - a Double·CGFloat mix inside `sin`/`cos`;
   - an API newer than iOS 17 / macOS 14 without a guard.
3. The iOS build, then `xcodebuild test` on your simulator, with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never`.
4. `SIM=<udid> DD=/private/tmp/merc-ia-<key>-dd ios/scripts/ios-unchanged-check.sh <out>`. It must keep the same 23 results (11 pass, 12 already stale). **Never run a record run.**
5. A Mac Debug build into your own derived data.

---

## 6. The test template

### 6.1 `LessonInteractives/Tests/<Card>Tests.swift`

```swift
import Foundation
import Testing
@testable import LessonInteractives

/// <Card name> (<lesson>): content, copy, state and VoiceOver. Every number
/// the card shows is re-derived here from its authored data
/// (tools/check_slate_numbers.py is the cross-check).
@Suite("<Card name>: content")
struct <Card>ContentTests {
    @Test("Every displayed number is re-derived from the authored data")
    func numbers() {
        // e.g. the dial's table, the fit's weights to 2 dp, the planner's unique optimum
        #expect(<Card>Content.table == [[5, 0], [3, 1], [2, 2], [0, 4], [0, 5]])
    }
}

@Suite("<Card name>: words")
struct <Card>CopyTests {
    @Test("Every line keeps the register; intent words only in the prediction lines")
    func register() {
        let found = InteractiveCopyRules.violations(in: <Card>Copy.everyLine, card: .<id>,
                                                    predictionLines: <Card>Copy.predictionLines)
        #expect(found.isEmpty, "\(found)")
    }

    @Test("The slate's labels are on the canvas")
    func labels() {
        #expect(InteractiveCopyRules.missingLabels([.madeUp], in: <Card>Copy.labels).isEmpty)
        // and the slate's exact on-card label text, e.g.:
        #expect(<Card>Copy.labels.contains { $0.text.hasPrefix("A made-up feed.") })
    }

    @Test("A summary for every state, saying every number it shows")
    func summaries() {
        for stop in 0..<5 {
            let line = <Card>Copy.accessibilitySummary(stop: stop)
            #expect(InteractiveAccessibility.numbersMissing(<Card>Content.table[stop], from: line).isEmpty)
        }
    }
}

@Suite("<Card name>: predict, then reveal")
@MainActor
struct <Card>StateTests {
    @Test("The control is off until a guess is locked; spoiled mode skips the guess")
    func gate() {
        let state = <Card>State(spoiled: false)
        #expect(!state.machine.canExplore)
        state.lock(.doubtEverything)
        #expect(state.machine.canExplore)
        #expect(<Card>State(spoiled: true).machine.canExplore)
    }

    @Test("The reveal pairs every guess with the result")
    func reveal() { /* for each choice: lock, explore, reveal; check revealLines.spoken */ }

    @Test("Nothing it holds can be encoded")
    func notCodable() { #expect(!((<Card>State(spoiled: false) as Any) is any Encodable)) }
}

#if os(macOS)
// Mac keys: the NightTokenizerTests pattern (ChatFeature) for the card's own key routing.
#endif
```

### 6.2 Placement

Placement needs no new test per card. `InteractivePlacementTests` already runs every card's real stub thread through its rule, and covers spoilers for every card that has spoiler terms. Add a test there only if the card's anchor or spoiler terms change.

### 6.3 A UI test (`MercuriusUITests/<Card>UITests.swift`)

Start from `InteractiveLaunchUITests` and follow `LessonInteractiveUITests`:
1. Launch with `-Interactive <slug>`.
2. Wait for the card's header (`label BEGINSWITH "Interactive: "`).
3. Tap a prediction chip and check that it is `isSelected`.
4. Use the control, then reach the reveal.
5. Answer the lesson's check by tap (on a stub lesson that is option A). It still sends "I picked …".

Find elements by accessibility label or identifier. Keep the "Debate" pill and the Settings button accessible.

### 6.4 iPhone layout (optional, recommended for dense cards)

Copy `MercuriusTests/TokenizerCardLayoutTests.swift`. It renders the card with `ImageRenderer` at 343 and 408 pt, at `.large` / `.xxxLarge` / `.accessibility3` / `.accessibility5`, and asserts that nothing leaves the card. Inject a store: `.environment(InteractiveStateStore())`.

---

## 7. Where this differs from BUILD_PLAN.md, and why

| Plan | Built | Why |
|---|---|---|
| `resources: [.process("Resources")]` on the new target | No resources yet | SwiftPM refuses a resource path that doesn't exist. Grown from Static (wave 2) adds the folder and the line with its first frame |
| An `InteractiveCardFactory` | `InteractiveCardViews` (LessonInteractives) + `LessonInteractiveCardView` (ChatFeature host) | Card views live in the module, so the switch is there. The host in ChatFeature routes the tokenizer, whose views stay in ChatFeature |
| `placement(spec:messages:crisisReplies:sections:)` replaces the tokenizer check | Added, and `placement(lessonID:…)` kept as a wrapper over the registry | The tokenizer's existing tests and `TokenizerCardLayoutTests` run unchanged (one of the plan's P0 conditions) |
| "The anchor reply's text is scanned for spoilers" | Every earlier reply in full, plus the anchor reply **above the card** | The flag comes out the same whether the place is found mid-stream or on reopen, and text after the card isn't read before it |
| Case-insensitive terms | Case- and diacritic-insensitive, **from the start of a word**, any ending | "12%" mustn't match "112%"; "impossib" must match "impossibility". "Guardian" also matches "guardian" (a parent or guardian): the Page card's builder should consider "The Guardian" |
| `LessonInteractive.swift` in `Sources/Tokenizer/` | Moved to `Sources/Lesson/` (types unchanged) | It is no longer the tokenizer's |
| Architecture: an infra-level module | A new "content module" rule: LessonInteractives may depend on DesignSystem only; features may depend on it | Infra modules are required in AppFeature by rule. AppFeature does depend on it (for the DEBUG paths), but the rule that matters is the leaf allowlist |
| DEBUG hooks read through UserDefaults | Parsed from the launch arguments, DEBUG only (`InteractiveLaunchOptions`) | The module then needs no UserDefaults at all (NoIOTests), and the parsing is unit-tested |
| `-Interactive <slug>` opens "with a canned thread" | Stub replies stream through the real replay client and the real placement; the replay answers stub checks itself | Lesson replays exist only for u1_l1. Answering keeps `teachReply`/mention cards reachable without taps (simctl can't tap) |
| Blocks: StepThrough, ThresholdCounters, PredictReveal, IconArray, ToyFit, RoutePlanner, FrameScrubber | PredictReveal, ThresholdCounters (+ MeterComparison, rates), StepThrough and the shared views | These three are shared within wave 1. ToyFit and RoutePlanner have one card each and are built by it (★4, ★5); IconArray and FrameScrubber are wave 2 |
| Mac chip groups: arrows between candidates | `InteractiveSegmented`, `StopControl` and `StepControls` take ←/→; `PredictChips` moves by Tab | Arrows inside a chip group need one shared focus value per group. A card that wants them (the Citation's candidates) can hold its own `FocusState<Choice?>`, as `NightOpeningChip` does |

---

## 8. Known limits

- The placeholder card (`InteractivePlaceholderCard`) is what a dark, unbuilt card shows under `-Interactive` and the gallery. A student never sees it: dark cards aren't placed outside DEBUG, and only built cards may be enabled.
- `teachReply` assumes exercise replies carry no [Q] block. Confirm this on eval transcripts before enabling a wave-2 `teachReply` card (BUILD_PLAN.md §1.3).
- The placement eval (`scripts/eval-interactive-placement.mjs`, §3.6) and D1's marker are not part of this framework.
- Snapshot test states for cards: add them to the iOS snapshot suite only as new tests, never as record runs. The founder records references.

---

## 9. Verified on this branch (2026-10-21)

- **`swift test`** (ios/Packages): 1,287 tests pass. That includes the 45 in `LessonInteractivesTests`, the new placement, spoiler and stub tests in ChatFeature, the registry-against-curriculum tests in AppFeature, and ArchitectureTests with the new content-module rule. Lesson 1.1's own tests (`TokenizerInteractiveTests`, `NightTokenizerTests`) pass **unchanged**.
- **CI lint:** `ios/scripts/ci-compat-lint.py` finds 0 issues.
- **iOS build and tests on a simulator** (iPhone 16 Pro Max, iOS 26.4): `xcodebuild test`, with snapshot recording forced off and the snapshot suite run separately (below).
  - Unit tests: 6 of 6 pass, including `TokenizerCardLayoutTests`.
  - UI tests: 34 of 34 pass, including the four new `InteractiveLaunchUITests` and Lesson 1.1's `LessonInteractiveUITests`.
  - Seven free-chat UI tests timed out first, under machine load (testmanagerd snapshot and launch timeouts). Alone, all seven passed in 67 s. On a busy machine, re-run failures like these before suspecting the code.
- **Snapshots:** `ios-unchanged-check.sh` gives the same 23 results as the baseline (11 pass, 12 already stale), with the same pixels for every stale render.
- **Mac:** the Debug build succeeds. Shots taken through a renamed copy (`gallery-doubt-dial`, `interactive-doubt-dial`, light and 700×600 dark) show Night's lit card alone and in the u6_l4 stub lesson after the example's part.
- **iPhone shots:**
  - `-InteractiveGallery doubt-dial` on the 16 Pro Max and on an SE at AX5: the card wraps inside its width, with no sideways overflow.
  - `-Interactive two-tests-one-line -InteractiveStubSpoiled YES`: the replay answered its own check, the card landed in reply 2 (`teachReply(2)`), and the real spoiler scan turned on the spoiled mode.
