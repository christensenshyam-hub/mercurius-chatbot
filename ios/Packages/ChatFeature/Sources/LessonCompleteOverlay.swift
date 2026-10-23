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
    /// A Basics lesson's completion (BEGINNER_GUIDE §2.6): "Try this today",
    /// the next lesson, and "That's enough for today". No share card and no
    /// week ring. nil is the Deep dive's celebration, unchanged.
    let basics: BasicsWrapUp?
    @State private var copiedMessage = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// What this completion unlocked, under the headline (the host's slot).
    @Environment(\.lessonCompleteAccessory) private var accessory

    #if os(macOS)
    /// The Mac's card rises a little as it fades in, rather than sliding up
    /// from the bottom of the screen like the iPhone's sheet.
    @State private var sheetOffset: CGFloat = 40
    @State private var cardShown = false
    #else
    @State private var sheetOffset: CGFloat = 800
    #endif
    @State private var mercScale: CGFloat = 0.6
    @State private var share: ShareState = .rendering
    @State private var dismissalReported = false
    @ScaledMetric(relativeTo: .title) private var headlineSize: CGFloat = 27
    // The Mac's body size (`MacTypeRamp`): the Mac has no Dynamic Type.
    #if os(macOS)
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = MacTypeRamp.body
    #else
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 13.5
    #endif

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
        onCelebrationDismissed: (() -> Void)? = nil,
        basicsWrapUp: BasicsWrapUp? = nil
    ) {
        self.lessonTitle = lessonTitle
        self.nextStop = nextStop ?? Self.nextStop(lessonNumber: nextLessonNumber, lessonTitle: nextLessonTitle)
        self.unitLabel = unitLabel
        self.lessonNumber = lessonNumber
        self.reduceMotion = reduceMotion
        self.basics = basicsWrapUp
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
        #if os(macOS)
        // Night Studio's card (SPEC.md §5.6): the credential, the lesson's
        // key ideas, the week and the next stop, with "Done for now".
        NightLessonComplete(lessonTitle: lessonTitle, nextStop: nextStop, unitLabel: unitLabel,
                            lessonNumber: lessonNumber, reduceMotion: reduceMotion, exits: exits,
                            basics: basics)
        #else
        phoneBody
        #endif
    }

    private var phoneBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dimmed scrim. Tapping it keeps the celebration out of the way
                // so the student can re-read the final feedback. Not while the
                // sheet holds what this completion unlocked (AI Basics'
                // certificate): the celebration doesn't come back, so a stray
                // tap would take the card for good. Its buttons still close it.
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if accessory == nil { exit(.dismiss) } }
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Keep reading the lesson")
                    .accessibilityHidden(accessory != nil)

                sheet
                    // Cap the sheet so a long title at large Dynamic Type scrolls
                    // instead of pushing the primary button off-screen. Bottom-
                    // aligned: a sheet shorter than the cap (Basics' sized-to-
                    // fit card) sits on the bottom edge, not in the middle.
                    .frame(maxHeight: geo.size.height * 0.86, alignment: .bottom)
                    .offset(y: sheetOffset)
            }
        }
        .onAppear(perform: animateIn)
        .task { if basics == nil { await renderShareCard() } }
    }

    /// Merc bursts out over the sheet's top edge, except on a Basics sheet
    /// at accessibility sizes: there the sheet is tall and Merc would sit on
    /// the text (review 2026-10-22). The Deep dive's sheet is unchanged.
    private var showsMerc: Bool {
        basics == nil || !dynamicTypeSize.isAccessibilitySize
    }

    /// A bottom sheet with Merc (celebrating) bursting out over its top edge.
    private var sheet: some View {
        contentCard
            .overlay(alignment: .top) {
                if showsMerc {
                    MercMascot(.celebrate, size: 148)
                        .scaleEffect(mercScale)
                        .offset(y: -80)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var contentCard: some View {
        if let basics {
            basicsCard(basics)
                .background(cardBackground)
        } else {
            ScrollView {
                deepDiveContent
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(cardBackground)
        }
    }

    private var deepDiveContent: some View {
            VStack(spacing: BrandSpacing.lg) {
                Color.clear.frame(height: 56)   // room for the bursting Merc

                VStack(spacing: BrandSpacing.xs) {
                    Text("Nailed it!")
                        .font(.system(size: headlineSize, weight: .black, design: .rounded))
                        .foregroundStyle(BrandColor.successText)
                        .multilineTextAlignment(.center)
                    Text("Lesson complete · \(lessonTitle)")
                        .font(.system(size: subtitleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary)

                if let accessory { accessory }
                if let upNextLabel { upNext(upNextLabel) }
                buttons
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Basics

    /// Basics' completion: a calm headline, "Try this today" (with Copy when
    /// it quotes a message), then the next lesson and a way to stop.
    ///
    /// When it all fits, one column, as before. When it doesn't (the larger
    /// text sizes older adults use), the two choices and "Your place is
    /// saved." are pinned to the bottom of the sheet, the way "Your path"
    /// pins its buttons, and only the headline and "Try this today" scroll
    /// above them, so "Next" and "That's enough for today" are never below
    /// the fold (review 2026-10-22).
    private func basicsCard(_ wrapUp: BasicsWrapUp) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: BrandSpacing.lg) {
                basicsSummary(wrapUp)
                basicsChoices
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                ScrollView {
                    basicsSummary(wrapUp)
                        .padding(.horizontal, BrandSpacing.xl)
                        .padding(.top, BrandSpacing.lg)
                        .padding(.bottom, BrandSpacing.md)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
                // A line running under the pinned choices fades out rather
                // than being cut mid-line, so it reads as "there's more" (as
                // on the Mac's card).
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [BrandColor.surface.opacity(0), BrandColor.surface],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Divider()
                basicsChoices
                    .padding(.horizontal, BrandSpacing.xl)
                    .padding(.top, BrandSpacing.md)
                    .padding(.bottom, BrandSpacing.xxl)
                    .frame(maxWidth: .infinity)
                    // Never squeezed: the scrolling part gives up the room,
                    // so the next lesson's whole title shows.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The headline, what the completion unlocked (the course's last lesson:
    /// "You finished AI Basics") and "Try this today".
    private func basicsSummary(_ wrapUp: BasicsWrapUp) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            // Room for Merc, when he shows.
            if showsMerc { Color.clear.frame(height: 56) }

            VStack(spacing: BrandSpacing.xs) {
                Text(BasicsCopy.headline)
                    .font(.system(size: headlineSize, weight: .black, design: .rounded))
                    .foregroundStyle(BrandColor.successText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lessonTitle)
                    .font(.system(size: subtitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(basicsAccessibilitySummary)

            if let accessory { accessory }
            if !wrapUp.tryThisToday.isEmpty {
                tryThisTodayCard(wrapUp)
            }
        }
    }

    /// The next lesson and a way to stop, then "Your place is saved."
    private var basicsChoices: some View {
        VStack(spacing: BrandSpacing.sm) {
            if case .lesson(_, let title) = nextStop {
                BrandButton(BasicsCopy.next(title), style: .primary) { exit(.next) }
                    .accessibilityIdentifier("basics.complete.next")
                BrandButton(BasicsCopy.enough, style: .ghost) { exit(.backToLessons) }
                    .accessibilityIdentifier("basics.complete.enough")
            } else {
                BrandButton(BasicsCopy.backToLessons, style: .primary) { exit(.backToLessons) }
            }
            Text(BasicsCopy.placeSaved)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BrandSpacing.xs)
    }

    private func tryThisTodayCard(_ wrapUp: BasicsWrapUp) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(BasicsCopy.tryThisToday.uppercased())
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.accentText)
                .accessibilityAddTraits(.isHeader)
            Text(wrapUp.tryThisToday)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let message = wrapUp.message {
                Button {
                    LessonPasteboard.copy(message)
                    copiedMessage = true
                } label: {
                    Label(copiedMessage ? BasicsCopy.copied : BasicsCopy.copy,
                          systemImage: copiedMessage ? "checkmark" : "doc.on.doc")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("basics.complete.copy")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.background, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .strokeBorder(BrandColor.border, lineWidth: 1)
        )
    }

    private var basicsAccessibilitySummary: String {
        if case .lesson(_, let title) = nextStop {
            return "Lesson complete: \(lessonTitle). Up next: \(title)."
        }
        return "Lesson complete: \(lessonTitle)."
    }

    @ViewBuilder private var cardBackground: some View {
        #if os(macOS)
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(BrandColor.surface)
            .shadow(color: .black.opacity(0.3), radius: 28, y: 10)
        #else
        UnevenRoundedRectangle(
            topLeadingRadius: 34, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous
        )
        .fill(BrandColor.surface)
        .ignoresSafeArea(edges: .bottom)
        // No shadow: the iPhone is dark only, and Night casts none in dark
        // (SPEC.md §2.6).
        #endif
    }

    private func upNext(_ label: String) -> some View {
        VStack(spacing: 2) {
            Text("UP NEXT")
                .font(BrandFont.caption)
                .tracking(1.5)
                .foregroundStyle(BrandColor.accentText)
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
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
                shareButton
                BrandButton("Back to lessons", style: .ghost) { exit(.backToLessons) }
            } else {
                BrandButton("Back to lessons", style: .primary) { exit(.backToLessons) }
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
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
                .foregroundStyle(BrandColor.accentText)
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
        #if os(macOS)
        guard !reduceMotion else { sheetOffset = 0; mercScale = 1; cardShown = true; return }
        withAnimation(.easeOut(duration: 0.25)) { cardShown = true }
        #else
        guard !reduceMotion else { sheetOffset = 0; mercScale = 1; return }
        #endif
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

private struct LessonCompleteAccessoryKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

public extension EnvironmentValues {
    /// Shown on a lesson's complete screen, under its headline (both
    /// platforms): the host's slot for what this completion unlocked
    /// (AppFeature puts the "You finished AI Basics" card here when the
    /// course's last lesson earned its certificate). ChatFeature can't see
    /// the certificates, so the host fills it, as a unit check's
    /// `unitMasteryAccessory` is filled.
    var lessonCompleteAccessory: AnyView? {
        get { self[LessonCompleteAccessoryKey.self] }
        set { self[LessonCompleteAccessoryKey.self] = newValue }
    }
}

/// `BrandButton`'s ghost look for a control `BrandButton` can't wrap (a
/// `ShareLink`).
private struct GhostLinkStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BrandColor.accentText)
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
