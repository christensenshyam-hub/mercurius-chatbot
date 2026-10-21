import Foundation

/// A state a card can be opened in for screenshots (`-InteractiveState`).
public enum InteractiveDebugState: String, CaseIterable, Sendable {
    /// Untouched: the hook, nothing picked.
    case hook
    /// A prediction locked in (the card's first choice), nothing explored.
    case predicted
    /// Locked in and explored (as many moves as "Show me" needs), not yet
    /// revealed.
    case explored
    /// Locked in, explored and revealed.
    case revealed
    /// The spoiled mode (as if the tutor had said a spoiler term first).
    case spoiled
}

/// Where the lesson's list scrolls once a reply settles (`-InteractiveScroll`).
public enum InteractiveScrollTarget: String, CaseIterable, Sendable {
    /// The card's top edge, under the end of the text before it.
    case top
    /// The card's reveal (`InteractiveScrollID.reveal`).
    case reveal
    /// The card's bottom edge, with what follows it.
    case after
}

/// The scroll ids a lesson's list knows the card by. A card marks its
/// reveal with `.id(InteractiveScrollID.reveal)`; the host marks the rest.
public enum InteractiveScrollID {
    public static let card = "lesson-interactive-card"
    public static let top = "lesson-interactive-card-top"
    public static let reveal = "lesson-interactive-card-reveal"
    public static let after = "lesson-interactive-card-after"

    public static func id(for target: InteractiveScrollTarget) -> String {
        switch target {
        case .top: return top
        case .reveal: return reveal
        case .after: return after
        }
    }
}

/// The DEBUG launch arguments for the interactives (shots and UI tests
/// only; a Release build reads none of them, `current` is empty there):
///
/// - `-Interactive <slug>`: open the card's lesson (implies `-LessonPreview
///   -LessonSkipIntro -LessonReplay`) with Lesson 1.1's recorded replies or,
///   for any other lesson, authored stub replies that say they are stubs.
///   The card shows even while it ships dark. A stub replay answers its own
///   checks until the card's reply has arrived (`repliesToReach`).
/// - `-InteractiveGallery <slug>`: the card alone on the lesson's
///   background, with no lesson, server or replay.
/// - `-InteractiveState hook|predicted|explored|revealed|spoiled`: the card
///   opens in that state (`PredictReveal.debugStarting`).
/// - `-InteractiveScroll top|reveal|after`: once a reply settles, the
///   lesson scrolls the card's top, its reveal or its end into view.
/// - `-InteractiveStubSpoiled YES`: the stub reply names the card's first
///   spoiler term above the card, so the real spoiler path runs.
/// - `-InteractiveReduceMotion YES`, `-InteractiveReduceTransparency YES`,
///   `-InteractiveIncreaseContrast YES`: the iPhone card draws as under
///   that setting (simctl can set Increase Contrast only). The tokenizer's
///   `-NightTokenizer…` flags count too; on the Mac, Night's own `-Night…`
///   flags apply.
/// - `-InteractiveCompact YES`: the Mac's card starts as its compact "Try
///   it" card at any width.
///
/// Combine with `-UIPreferredContentSizeCategoryName
/// UICTContentSizeCategoryAccessibilityXXXL` (AX5) for the text sizes.
public struct InteractiveLaunchOptions: Equatable, Sendable {
    public var card: InteractiveID?
    public var gallery: InteractiveID?
    public var state: InteractiveDebugState?
    public var scroll: InteractiveScrollTarget?
    public var stubSpoiled = false
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    /// `-InteractiveCompact YES` (or Lesson 1.1's `-NightTokenizerCompact
    /// YES`): the Mac's card starts compact at any width.
    public var macCompact = false

    public init() {}

    /// The options in a launch's arguments (pure, for the tests).
    public init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value
        }
        func flag(_ name: String) -> Bool {
            guard let raw = value(name)?.lowercased() else { return false }
            return raw == "yes" || raw == "true" || raw == "1"
        }
        card = value("-Interactive").flatMap(InteractiveID.init(slug:))
        gallery = value("-InteractiveGallery").flatMap(InteractiveID.init(slug:))
        state = value("-InteractiveState").flatMap { InteractiveDebugState(rawValue: $0.lowercased()) }
        scroll = value("-InteractiveScroll").flatMap { InteractiveScrollTarget(rawValue: $0.lowercased()) }
        stubSpoiled = flag("-InteractiveStubSpoiled")
        reduceMotion = flag("-InteractiveReduceMotion") || flag("-NightTokenizerReduceMotion")
        reduceTransparency = flag("-InteractiveReduceTransparency") || flag("-NightTokenizerReduceTransparency")
        increaseContrast = flag("-InteractiveIncreaseContrast") || flag("-NightTokenizerIncreaseContrast")
        macCompact = flag("-InteractiveCompact") || flag("-NightTokenizerCompact")
    }

    /// This launch's options: DEBUG builds only. A Release build (which a
    /// Mac App Store user can launch with arguments) reads none.
    public static let current: InteractiveLaunchOptions = {
        #if DEBUG
        return InteractiveLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
        return InteractiveLaunchOptions()
        #endif
    }()
}
