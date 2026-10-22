import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

// MARK: - What a Basics lesson needs from its host

/// How a Basics lesson differs from a Deep-dive one (BEGINNER_GUIDE §2.2–2.6).
/// ChatFeature can't see the curriculum, so the host hands these over as
/// plain values; `CurriculumLessonView(basics: nil)` is the Deep dive,
/// unchanged.
public struct BasicsLessonOptions {
    /// The learner's Basics reading size (a floor the host applies).
    public var readingSize: ReadingSize
    /// Show the one-time "Want the words bigger?" offer (iPhone only; the
    /// Mac has no Dynamic Type).
    public var offersReadingSize: Bool
    public var onChooseReadingSize: (ReadingSize) -> Void
    public var onDismissReadingSizeOffer: () -> Void
    /// What the completion shows under "Try this today".
    public var wrapUp: BasicsWrapUp?

    public init(
        readingSize: ReadingSize = .standard,
        offersReadingSize: Bool = false,
        onChooseReadingSize: @escaping (ReadingSize) -> Void = { _ in },
        onDismissReadingSizeOffer: @escaping () -> Void = {},
        wrapUp: BasicsWrapUp? = nil
    ) {
        self.readingSize = readingSize
        self.offersReadingSize = offersReadingSize
        self.onChooseReadingSize = onChooseReadingSize
        self.onDismissReadingSizeOffer = onDismissReadingSizeOffer
        self.wrapUp = wrapUp
    }
}

/// "What to try next" after a Basics lesson: one real-life task, and the
/// message inside it ready to copy when the task quotes one.
public struct BasicsWrapUp: Equatable, Sendable {
    public let tryThisToday: String
    public let message: String?

    public init(tryThisToday: String, message: String? = nil) {
        self.tryThisToday = tryThisToday
        self.message = message
    }
}

/// The words Basics screens use (held plain: no "just", "simply", "easy",
/// no urgency; BEGINNER_GUIDE §1.2–1.4).
enum BasicsCopy {
    static let back = "Lessons"
    static let backAccessibility = "Back to lessons. Your place is saved."
    static let introLine = "One small step at a time. You can stop whenever you like, and I'll save your place."
    static let start = "Start"
    static let startAccessibility = "Start the lesson."
    static let placeholder = "Type your message here"
    static let compactPlaceholder = "Type here"

    // Practice chip
    static func chipAccessibility(_ line: String) -> String {
        "Put “\(line)” in the message box. You can change it before you send."
    }
    #if os(macOS)
    static let chipHint = "Click to put it in the box"
    #else
    static let chipHint = "Tap to put it in the box"
    #endif

    // Completion
    static let headline = "Lesson complete"
    static let tryThisToday = "Try this today"
    static let copy = "Copy the message"
    static let copied = "Copied. Paste it into any chatbot."
    static func next(_ title: String) -> String { "Next: \(title)" }
    static let backToLessons = "Back to lessons"
    static let enough = "That's enough for today"
    static let placeSaved = "Your place is saved."
}

// MARK: - The practice line

/// The practice line at the end of a Basics reply — `Try asking me: "…"`, or
/// `Now try: "…"` for a follow-up (SERVER.md: "a practice line is always its
/// own last paragraph … 12 words or fewer"). The lesson turns it into a chip
/// that fills the message box without sending, so the learner can still
/// change the words and tap the arrow themselves.
enum PracticeLine {
    static let leads = ["Try asking me:", "Now try:", "Try asking me", "Now try"]

    /// The quoted message in `reply`'s last paragraph, if that paragraph is
    /// a practice line. Straight and curly double quotes both count.
    static func extract(from reply: String) -> String? {
        let paragraphs = reply
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = paragraphs.last else { return nil }
        // Only a plain line: never a card, a list or a quiz.
        guard !last.hasPrefix("["), !last.contains("\n") else { return nil }
        guard let lead = leads.first(where: { last.range(of: $0, options: [.caseInsensitive]) != nil }),
              let leadRange = last.range(of: lead, options: [.caseInsensitive])
        else { return nil }
        let rest = last[leadRange.upperBound...]
        let opens: Set<Character> = ["\"", "\u{201C}"]
        let closes: Set<Character> = ["\"", "\u{201D}"]
        guard let open = rest.firstIndex(where: { opens.contains($0) }) else { return nil }
        let body = rest[rest.index(after: open)...]
        guard let close = body.firstIndex(where: { closes.contains($0) }) else { return nil }
        let message = body[..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 160 else { return nil }
        return message
    }

    /// The chip for the thread as it stands: the latest reply's practice
    /// line, while nothing is coming in and the box is empty.
    static func chip(messages: [ChatMessage], isIdle: Bool, draft: String) -> String? {
        guard isIdle, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let last = messages.last, last.role == .assistant
        else { return nil }
        return extract(from: last.content)
    }
}

/// A tappable practice line above the message box.
struct PracticeChip: View {
    let line: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                Image(systemName: "text.cursor")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(line)”")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BasicsCopy.chipHint)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .strokeBorder(BrandColor.accent.opacity(0.35), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BasicsCopy.chipAccessibility(line))
        .accessibilityIdentifier("basics.practiceChip")
    }
}

// MARK: - Copy on Merc's replies

private struct LessonOffersCopyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Merc's replies offer Copy in their press-and-hold menu (Basics: its
    /// lessons write notes and emails meant to leave the app, and b4_l1
    /// teaches "press and hold, tap Copy"). The Mac always offers it.
    var lessonOffersCopy: Bool {
        get { self[LessonOffersCopyKey.self] }
        set { self[LessonOffersCopyKey.self] = newValue }
    }
}

@MainActor
enum LessonPasteboard {
    /// Put `text` on the pasteboard.
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        MacPasteboard.copy(text)
        #endif
    }
}
