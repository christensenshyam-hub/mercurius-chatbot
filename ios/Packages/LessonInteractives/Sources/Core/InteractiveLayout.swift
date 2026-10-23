import SwiftUI

/// The layout rules every card follows, as numbers the tests can hold.
public enum InteractiveLayout {
    /// The Mac: a card narrower than this (a 700 pt window with the sidebar
    /// open leaves a 390 pt reading measure) starts as a compact "Try it"
    /// card that opens in place. Lesson 1.1's `NightTokenizerLayout` value.
    public static let macCompactBelowWidth: CGFloat = 440

    /// `width` 0 is "not measured yet": the full card.
    public static func isMacCompact(width: CGFloat, expanded: Bool, forced: Bool = false) -> Bool {
        guard !expanded else { return false }
        return forced || (width > 0 && width < macCompactBelowWidth)
    }

    /// The iPhone's smallest touch target, and the Mac's control height.
    public static let phoneMinTarget: CGFloat = 44
    public static let macMinTarget: CGFloat = 36

    /// The card widths the iPhone is checked at: an SE's row (375 pt less
    /// its 16 pt margins) and a 16 Pro Max's (440 pt less them).
    public static let phoneCardWidths: [CGFloat] = [343, 408]
    /// The iPhone card's inner padding (`BrandSpacing.lg`), so its content
    /// is 311 pt wide on an SE.
    public static let phonePadding: CGFloat = 16
    /// The iPhone card's widest (the lesson bubble's cap).
    public static let phoneMaxWidth: CGFloat = 560
    /// The Mac card's inner padding (`Night.Space.card`).
    public static let macPadding: CGFloat = 20

    /// The room a card's content has inside a card `cardWidth` wide.
    public static func contentWidth(cardWidth: CGFloat, padding: CGFloat = phonePadding) -> CGFloat {
        max(cardWidth - 2 * padding, 0)
    }

    /// At the accessibility text sizes every chart, grid and array is drawn
    /// as text or a table instead (decoration goes, content stays).
    public static func usesTables(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }

    /// Whether items `widths` wide fit side by side in `available`, with
    /// `spacing` between them: when they don't, a card stacks them (no card
    /// scrolls sideways).
    public static func fitsInOneRow(_ widths: [CGFloat], spacing: CGFloat, in available: CGFloat) -> Bool {
        guard !widths.isEmpty else { return true }
        let total = widths.reduce(0, +) + spacing * CGFloat(widths.count - 1)
        return total <= available + 0.5
    }
}

/// How cards move. Under Reduce Motion everything crossfades in place and
/// nothing plays by itself.
public enum InteractiveMotion {
    /// The crossfade that replaces a move.
    public static let crossfade = Animation.easeInOut(duration: 0.25)
    /// A control's state change (a pick, a stop).
    public static let change = Animation.smooth(duration: 0.35)

    /// `animation`, or the crossfade under Reduce Motion.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfade : animation
    }

    /// How a piece arrives: from `edge` with a fade, or only a fade under
    /// Reduce Motion.
    public static func transition(reduceMotion: Bool, edge: Edge = .bottom) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: edge))
    }

    /// Whether a card may play anything without a tap (a replay, a run).
    public static func autoplays(reduceMotion: Bool) -> Bool { !reduceMotion }
}

/// VoiceOver for cards: each card's state is one sentence in its Copy enum
/// (`accessibilitySummary`), headings name the card and its steps, and a
/// change the student caused is announced.
public enum InteractiveAccessibility {
    /// Says `line` wherever VoiceOver's focus is.
    @MainActor
    public static func announce(_ line: String) {
        AccessibilityNotification.Announcement(line).post()
    }

    /// The numbers in `numbers` that `summary` doesn't say ("every chart's
    /// numbers appear in its summary"). A number counts when it appears
    /// as a whole number in the text.
    public static func numbersMissing(_ numbers: [Int], from summary: String) -> [Int] {
        let said = Set(summary.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) })
        return numbers.filter { !said.contains($0) }
    }
}
