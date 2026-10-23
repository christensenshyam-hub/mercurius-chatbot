import SwiftUI

/// Asks the lesson's list to bring part of a card into view: the host's
/// `ScrollViewReader` (ChatFeature's lesson list, on both platforms).
///
/// A card marks the part with one of `InteractiveScrollID`'s ids (the
/// card's stage, its panel, its reveal) and calls this when something the
/// student set off would otherwise happen out of sight: a run playing on a
/// stage they scrolled past to reach the controls, a question opening above
/// the chip they tapped. The host scrolls the least that shows the whole
/// part (nothing when it already shows), and counts the move as the
/// student's own, so the list stops following a streaming reply. `animated`
/// is the card's: false under Reduce Motion.
///
/// - The host scrolls on the next turn of the main queue, once the update
///   that asked has been laid out, so a card may call this from `onChange`
///   in the same update that resizes the part.
/// - Mark a part that fits the reading area. For one taller than it,
///   `scrollTo(_:anchor: nil)` doesn't define which edge shows, so it can
///   differ between iOS versions: mark the piece of it the student needs
///   (the Citation scrolls to its draw's button, not the whole draw).
///
/// Outside a lesson (the gallery, previews, tests) it does nothing. Two
/// actions with the same `key` are equal, so a host that hands a new one
/// down on every render doesn't redraw the card for it.
public struct InteractiveScrollAction: Equatable {
    private let key: String
    private let handler: @MainActor (_ id: String, _ animated: Bool) -> Void

    public init(key: String, _ handler: @escaping @MainActor (_ id: String, _ animated: Bool) -> Void) {
        self.key = key
        self.handler = handler
    }

    /// Brings the part marked `id` into view.
    @MainActor
    public func callAsFunction(_ id: String, animated: Bool) {
        handler(id, animated)
    }

    /// Does nothing (no lesson list around the card).
    public static let none = InteractiveScrollAction(key: "none") { _, _ in }

    public static func == (lhs: InteractiveScrollAction, rhs: InteractiveScrollAction) -> Bool {
        lhs.key == rhs.key
    }
}

private struct InteractiveScrollActionKey: EnvironmentKey {
    static let defaultValue = InteractiveScrollAction.none
}

extension EnvironmentValues {
    /// The lesson list's "bring this part of the card into view"
    /// (`InteractiveScrollAction`); does nothing outside a lesson.
    public var interactiveScrollIntoView: InteractiveScrollAction {
        get { self[InteractiveScrollActionKey.self] }
        set { self[InteractiveScrollActionKey.self] = newValue }
    }
}

extension View {
    /// Marks this part of a card for `InteractiveScrollAction` (and the
    /// DEBUG `-InteractiveScroll`), with a little room above and below it,
    /// so the list shows it clear of the reading area's edges (the Mac's
    /// top and bottom fades; on the iPhone, a breath under the header).
    public func interactiveScrollMark(_ id: String) -> some View {
        modifier(InteractiveScrollMark(id: id))
    }
}

private struct InteractiveScrollMark: ViewModifier {
    let id: String
    @Environment(\.interactiveTheme) private var theme

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .id(id)
                .padding(.vertical, theme.platform == .mac ? -24 : -12)
                .accessibilityHidden(true)
        }
    }
}
