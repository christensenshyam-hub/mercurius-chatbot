import SwiftUI
import DesignSystem

/// The "lesson passed" celebration — a clouded backdrop, an animated check, and
/// a clear path forward. This is what the student sees the moment a lesson is
/// completed, in place of the raw `[…]` marker that used to leak into the
/// transcript. Presented as a full-screen layer inside `CurriculumLessonView`.
public struct LessonCompleteOverlay: View {
    /// Where the primary button leads. ChatFeature can't see the curriculum, so
    /// the host hands over plain values.
    public enum NextStop: Equatable, Sendable {
        case lesson(number: Int, title: String)
        /// The unit's check, offered once its last lesson is done. `unitNumber`
        /// is spelled as the curriculum spells it ("01").
        case unitTest(unitNumber: String, unitTitle: String)
    }

    /// The lesson just completed (shown as a subtitle).
    let lessonTitle: String
    /// Nil = nothing to go on to from here; "Back to lessons" becomes primary.
    let nextStop: NextStop?
    /// The lesson header's unit label ("UNIT 01") and lesson number, for the
    /// share card.
    let unitLabel: String?
    let lessonNumber: Int?
    let reduceMotion: Bool
    let exits: LessonCompleteExits

    @State private var sheetOffset: CGFloat = 800
    @State private var mercScale: CGFloat = 0.6
    @State private var share: ShareState = .rendering
    @State private var dismissalReported = false

    private enum ShareState {
        case rendering
        case ready(LessonShareImage, preview: Image)
        case unavailable
    }

    /// `nextLessonNumber`/`nextLessonTitle` are the pre-`NextStop` spelling and
    /// map to `.lesson`; an explicit `nextStop` wins.
    init(
        lessonTitle: String,
        nextLessonNumber: Int? = nil,
        nextLessonTitle: String? = nil,
        nextStop: NextStop? = nil,
        unitLabel: String? = nil,
        lessonNumber: Int? = nil,
        reduceMotion: Bool,
        onNext: @escaping () -> Void,
        onBackToLessons: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onCelebrationDismissed: (() -> Void)? = nil
    ) {
        self.lessonTitle = lessonTitle
        self.nextStop = nextStop ?? Self.nextStop(lessonNumber: nextLessonNumber, lessonTitle: nextLessonTitle)
        self.unitLabel = unitLabel
        self.lessonNumber = lessonNumber
        self.reduceMotion = reduceMotion
        self.exits = LessonCompleteExits(
            onNext: onNext,
            onBackToLessons: onBackToLessons,
            onDismiss: onDismiss,
            onCelebrationDismissed: onCelebrationDismissed
        )
    }

    static func nextStop(lessonNumber: Int?, lessonTitle: String?) -> NextStop? {
        guard let lessonNumber, let lessonTitle else { return nil }
        return .lesson(number: lessonNumber, title: lessonTitle)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dimmed scrim. Tapping it keeps the celebration out of the way
                // so the student can re-read the final feedback.
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { exit(.dismiss) }
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Keep reading the lesson")

                sheet
                    // Cap the sheet so a long title at large Dynamic Type scrolls
                    // instead of pushing the primary button off-screen.
                    .frame(maxHeight: geo.size.height * 0.86)
                    .offset(y: sheetOffset)
            }
        }
        .onAppear(perform: animateIn)
        .task { await renderShareCard() }
    }

    /// A bottom sheet with Merc (celebrating) bursting out over its top edge.
    private var sheet: some View {
        contentCard
            .overlay(alignment: .top) {
                MercMascot(.celebrate, size: 148)
                    .scaleEffect(mercScale)
                    .offset(y: -80)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
    }

    private var contentCard: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Color.clear.frame(height: 56)   // room for the bursting Merc

                VStack(spacing: BrandSpacing.xs) {
                    Text("Nailed it!")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(BrandColor.success)
                        .multilineTextAlignment(.center)
                    Text("Lesson complete · \(lessonTitle)")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary)

                if let upNextLabel { upNext(upNextLabel) }
                buttons
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 34, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous
            )
            .fill(BrandColor.surface)
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.3), radius: 28, y: -8)
        )
    }

    private func upNext(_ label: String) -> some View {
        VStack(spacing: 2) {
            Text("UP NEXT")
                .font(BrandFont.caption)
                .tracking(1.5)
                .foregroundStyle(BrandColor.accent)
            Text(label)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BrandSpacing.xs)
    }

    var upNextLabel: String? {
        switch nextStop {
        case .lesson(let number, let title):
            return "Lesson \(number) · \(title)"
        case .unitTest(let unitNumber, let unitTitle):
            return "Unit \(Self.displayUnitNumber(unitNumber)) check · \(unitTitle)"
        case nil:
            return nil
        }
    }

    /// Nil when there is no next stop.
    var primaryActionTitle: String? {
        switch nextStop {
        case .lesson:
            return "Next lesson"
        case .unitTest(let unitNumber, _):
            return "Take the Unit \(Self.displayUnitNumber(unitNumber)) check"
        case nil:
            return nil
        }
    }

    /// "01" reads as "Unit 1" in a sentence.
    private static func displayUnitNumber(_ unitNumber: String) -> String {
        Int(unitNumber).map(String.init) ?? unitNumber
    }

    private var buttons: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let primaryActionTitle {
                BrandButton(primaryActionTitle, style: .primary) { exit(.next) }
                shareButton
                BrandButton("Back to lessons", style: .ghost) { exit(.backToLessons) }
            } else {
                BrandButton("Back to lessons", style: .primary) { exit(.backToLessons) }
                shareButton
            }
        }
        .padding(.top, BrandSpacing.xs)
    }

    @ViewBuilder
    private var shareButton: some View {
        switch share {
        case .ready(let item, let preview):
            ShareLink(
                item: item,
                preview: SharePreview("Lesson complete · \(lessonTitle)", image: preview)
            ) {
                shareLabel
            }
            .buttonStyle(GhostLinkStyle())
            .accessibilityHint("Shares a picture of this finished lesson")
        case .rendering:
            // Holds the button's place so the sheet doesn't jump when the
            // image is ready.
            shareLabel
                .foregroundStyle(BrandColor.accent)
                .opacity(0.5)
                .accessibilityHidden(true)
        case .unavailable:
            EmptyView()
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(BrandFont.bodyEmphasized)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, BrandSpacing.lg)
    }

    private var accessibilitySummary: String {
        switch nextStop {
        case .lesson(let number, let title):
            return "Lesson complete: \(lessonTitle). Up next, lesson \(number): \(title)."
        case .unitTest(let unitNumber, let unitTitle):
            return "Lesson complete: \(lessonTitle). You finished this unit's lessons. "
                + "Up next, the Unit \(Self.displayUnitNumber(unitNumber)) check: \(unitTitle)."
        case nil:
            return "Lesson complete: \(lessonTitle). You finished this unit's lessons."
        }
    }

    private func exit(_ path: LessonCompleteExits.Path) {
        // The scrim stays tappable while the overlay fades out, so a second
        // tap can arrive; the host hears about the dismissal once.
        exits.take(path, reportDismissal: !dismissalReported)
        dismissalReported = true
    }

    private func animateIn() {
        guard !reduceMotion else { sheetOffset = 0; mercScale = 1; return }
        withAnimation(.timingCurve(0.2, 0.9, 0.3, 1.1, duration: 0.45)) { sheetOffset = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.12)) { mercScale = 1 }
    }

    private func renderShareCard() async {
        // Rendering is synchronous main-actor work; let the sheet land first
        // so it can't hitch the entrance.
        if !reduceMotion { try? await Task.sleep(for: .milliseconds(650)) }
        guard !Task.isCancelled else { return }
        let card = LessonShareCard(lessonTitle: lessonTitle, unitLabel: unitLabel, lessonNumber: lessonNumber)
        if let rendered = card.renderShareable() {
            share = .ready(rendered.item, preview: rendered.preview)
        } else {
            share = .unavailable
        }
    }
}

/// The overlay's three ways out. Each runs its own action and then tells the
/// host the celebration is gone (the review prompt waits on that), so no path
/// can skip the report.
struct LessonCompleteExits {
    enum Path: CaseIterable {
        case next, backToLessons, dismiss
    }

    let onNext: () -> Void
    let onBackToLessons: () -> Void
    let onDismiss: () -> Void
    let onCelebrationDismissed: (() -> Void)?

    func take(_ path: Path, reportDismissal: Bool = true) {
        switch path {
        case .next: onNext()
        case .backToLessons: onBackToLessons()
        case .dismiss: onDismiss()
        }
        if reportDismissal { onCelebrationDismissed?() }
    }
}

/// `BrandButton`'s ghost look for a control `BrandButton` can't wrap (a
/// `ShareLink`).
private struct GhostLinkStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BrandColor.accent)
            .background(configuration.isPressed ? BrandColor.accent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("With next lesson") {
    LessonCompleteOverlay(
        lessonTitle: "The alignment problem",
        nextStop: .lesson(number: 2, title: "Reward hacking & specification gaming"),
        unitLabel: "UNIT 05",
        lessonNumber: 1,
        reduceMotion: false,
        onNext: {}, onBackToLessons: {}, onDismiss: {}
    )
}

#Preview("Unit check next") {
    LessonCompleteOverlay(
        lessonTitle: "Review: ethics & alignment",
        nextStop: .unitTest(unitNumber: "05", unitTitle: "Ethics & Alignment"),
        unitLabel: "UNIT 05",
        lessonNumber: 4,
        reduceMotion: false,
        onNext: {}, onBackToLessons: {}, onDismiss: {}
    )
}

#Preview("Nothing next") {
    LessonCompleteOverlay(
        lessonTitle: "Review: ethics & alignment",
        reduceMotion: false,
        onNext: {}, onBackToLessons: {}, onDismiss: {}
    )
}
#endif
