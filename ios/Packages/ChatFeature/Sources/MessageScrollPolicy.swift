import CoreGraphics

/// Where the message list stood at its last layout, in the list's own
/// coordinates: 0 is the top of the visible reading area.
struct MessageListGeometry: Equatable, Sendable {
    /// Top of the scrolled content: 0 at the top of the thread, negative once
    /// the student has scrolled down.
    var contentMinY: CGFloat = 0
    var contentHeight: CGFloat = 0
    /// Height of the visible reading area (it shrinks when the keyboard is up).
    var viewportHeight: CGFloat = 0
    /// Top of the latest message's row. `.infinity` until that row has been
    /// laid out — a value from an earlier message must never stand in for it.
    var latestMessageMinY: CGFloat = .infinity

    /// How far the end of the thread sits below the reading area.
    var distanceFromBottom: CGFloat {
        max(0, contentHeight + contentMinY - viewportHeight)
    }

    var isAtBottom: Bool { distanceFromBottom <= MessageScrollPolicy.bottomTolerance }
    var isAtTop: Bool { contentMinY >= -MessageScrollPolicy.bottomTolerance }
}

/// How the message list scrolls as the thread changes (AUD-09). Pure, so the
/// rules are unit-tested; `MessageListView` feeds it layout and performs what
/// it returns.
///
/// - A new latest message (the student's send with Merc's placeholder, a
///   lesson opener, Retry, Explain more, a loaded thread) goes to the bottom,
///   so the student sees what they sent and that Merc is working.
/// - A streaming reply is followed only while the student is at the bottom.
///   Once the reply's own top reaches the top of the reading area it is held
///   there — once per reply — so a long reply opens at its first line, not
///   its last, and the rest streams in below.
/// - Scrolling up stops the following at once; coming back to the bottom
///   resumes it. Elsewhere, a "Jump to latest" pill offers the way down.
/// - When the reading area changes height (the keyboard), a student who was
///   at the bottom stays at the bottom.
struct MessageScrollPolicy: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        case scrollToBottom(animated: Bool)
        /// Put the top of the latest message at the top of the reading area.
        case showLatestMessageTop
    }

    /// How close to the end still counts as being at the bottom.
    static let bottomTolerance: CGFloat = 36
    /// A followed reply is held at its top once its top edge rises to within
    /// this distance of the top of the reading area (about two lines), so the
    /// hold moves the text the same way following did, never back.
    static let holdThreshold: CGFloat = 56
    /// How far from the end the student must be before the pill shows.
    static let pillDistance: CGFloat = 120
    /// Below this reading height (an SE at accessibility sizes with the
    /// keyboard up has about 150 pt) the pill would cover much of the text,
    /// so it stays away.
    static let pillMinimumViewport: CGFloat = 180

    /// Whether new text is followed to the bottom.
    private(set) var isFollowing = true
    /// The platform reports when the student scrolls (iOS 18+). Then that,
    /// not offset changes, says who moved the list — a lazy stack shifts its
    /// own offset as it measures rows it had only estimated, and our own
    /// scrolls move it too.
    private(set) var knowsStudentScrolling: Bool

    init(knowsStudentScrolling: Bool = false) {
        self.knowsStudentScrolling = knowsStudentScrolling
    }
    /// The current reply has already been held at its top.
    private(set) var didHoldCurrentReply = false
    private(set) var geometry = MessageListGeometry()

    /// A new message became the latest. `isNewReply`: it is Merc's empty
    /// placeholder for a reply about to stream (animate the move); otherwise
    /// a thread was loaded (jump).
    mutating func latestMessageChanged(isNewReply: Bool) -> Action {
        isFollowing = true
        didHoldCurrentReply = false
        geometry.latestMessageMinY = .infinity
        return .scrollToBottom(animated: isNewReply)
    }

    /// The latest message's text changed (a streamed delta, or a reply that
    /// arrived whole). Uses the layout from before the change.
    mutating func latestMessageGrew() -> Action {
        guard isFollowing else { return .none }
        if !didHoldCurrentReply, geometry.latestMessageMinY <= Self.holdThreshold {
            didHoldCurrentReply = true
            isFollowing = false
            return .showLatestMessageTop
        }
        return .scrollToBottom(animated: false)
    }

    /// Something below the latest message appeared or went (the Retry or
    /// Explain more footer). Someone following keeps seeing the end.
    func footerChanged() -> Action {
        isFollowing ? .scrollToBottom(animated: true) : .none
    }

    /// The student tapped "Jump to latest".
    mutating func jumpToLatest() -> Action {
        isFollowing = true
        return .scrollToBottom(animated: true)
    }

    /// A new layout of the list arrived.
    mutating func geometryChanged(_ new: MessageListGeometry) -> Action {
        let old = geometry
        geometry = new
        if old.viewportHeight > 0, abs(new.viewportHeight - old.viewportHeight) > 0.5 {
            // The reading area changed height — the keyboard rose or fell.
            // The content keeps its offset, so without help the end of the
            // thread (the question being answered) slides under the composer.
            return old.isAtBottom ? .scrollToBottom(animated: false) : .none
        }
        guard !knowsStudentScrolling else { return .none }
        // iOS 17 has no scroll phases, so infer a drag from the offset: the
        // content moved down without getting shorter means the student
        // scrolled up, and following now would yank them back. The offset
        // can't say who moved the list down to the end (holding a reply does
        // too), so there following resumes only on a new turn or the pill.
        if new.contentMinY > old.contentMinY + 0.5, new.contentHeight >= old.contentHeight - 0.5 {
            isFollowing = false
        }
        return .none
    }

    /// The student started (`true`) or stopped (`false`) dragging or
    /// flinging the list — reported by the platform where it can (iOS 18+).
    /// A drag stops the following at once; letting go at the end of the
    /// thread resumes it.
    mutating func studentScrolling(_ scrolling: Bool) {
        knowsStudentScrolling = true
        isFollowing = scrolling ? false : isAtEndOfLongThread(geometry)
    }

    /// At the end of a thread longer than the screen — scrolled there, or
    /// never left. A thread that still fits is trivially "at the bottom";
    /// that must not undo a hold.
    private func isAtEndOfLongThread(_ geometry: MessageListGeometry) -> Bool {
        geometry.isAtBottom && geometry.contentHeight > geometry.viewportHeight + 0.5
    }

    /// The latest message's row was laid out at `minY`.
    mutating func latestMessageMoved(minY: CGFloat) {
        geometry.latestMessageMinY = minY
    }

    /// Whether the "Jump to latest" pill shows.
    var showsJumpPill: Bool {
        geometry.viewportHeight >= Self.pillMinimumViewport
            && geometry.distanceFromBottom > Self.pillDistance
    }
}

/// Whether the lesson's coach card stays in the list while the student
/// types (AUD-08). The card is the list's first row, so it scrolls away with
/// the lesson; while the composer is focused it also leaves when it is still
/// on screen, giving the reading area back (the row collapses to nothing).
/// It never collapses or returns where that would shift the text the student
/// is reading: a row changing height above the visible area moves everything
/// below it.
struct CoachCardPresence: Equatable, Sendable {
    private(set) var isHiddenForTyping = false

    /// Whether any of the card — the list's first row, `topInset` below the
    /// top of the content — is inside the reading area.
    static func isOnScreen(coachHeight: CGFloat, topInset: CGFloat,
                           geometry: MessageListGeometry) -> Bool {
        coachHeight > 0 && geometry.contentMinY + topInset + coachHeight > 0
    }

    /// The composer gained or lost focus. Returns true when the list should
    /// then scroll to the bottom to keep the student at the end.
    mutating func composerFocusChanged(
        focused: Bool,
        coachOnScreen: Bool,
        geometry: MessageListGeometry
    ) -> Bool {
        if focused {
            // Off screen it costs no reading space, and taking it out from
            // above the visible area would move the text being read.
            guard !isHiddenForTyping, coachOnScreen else { return false }
            isHiddenForTyping = true
            return geometry.isAtBottom
        }
        return restoreIfHarmless(geometry)
    }

    /// A new layout arrived while the card is out. It comes back once
    /// putting it back can't move what the student is reading.
    mutating func geometryChanged(composerFocused: Bool, geometry: MessageListGeometry) -> Bool {
        guard !composerFocused else { return false }
        return restoreIfHarmless(geometry)
    }

    private mutating func restoreIfHarmless(_ geometry: MessageListGeometry) -> Bool {
        guard isHiddenForTyping, geometry.isAtTop || geometry.isAtBottom else { return false }
        isHiddenForTyping = false
        return geometry.isAtBottom
    }
}
