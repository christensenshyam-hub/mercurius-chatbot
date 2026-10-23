#if os(macOS)
import Foundation
import CoreGraphics

// Lesson 1.1's interactive on the Mac, "How a model reads “bank”": what is
// the Mac's own. The content, the map's geometry, the card's state, where it
// sits in the lesson and every line it says are shared with the iPhone
// (Tokenizer/TokenizerInteractive.swift, Tokenizer/LessonInteractive.swift);
// the Mac's card is NightTokenizerCard.swift.

/// When the card starts compact: a "Try it" card that opens in place.
enum NightTokenizerLayout {
    /// The card is narrower than this (a 700 pt window with the sidebar
    /// open leaves a 390 pt reading measure): it starts compact.
    static let compactBelowWidth: CGFloat = 440

    /// `-NightTokenizerCompact YES` (shots only): compact at any width.
    static let debugForcesCompact: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "NightTokenizerCompact")
        #else
        return false
        #endif
    }()

    /// `width` 0 is "not measured yet": the full card.
    static func isCompact(width: CGFloat, expanded: Bool, forced: Bool = false) -> Bool {
        guard !expanded else { return false }
        return forced || (width > 0 && width < compactBelowWidth)
    }
}
#endif
