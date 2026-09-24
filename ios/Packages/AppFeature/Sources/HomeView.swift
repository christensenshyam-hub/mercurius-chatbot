import SwiftUI
import DesignSystem
import CurriculumFeature
import SettingsFeature

/// The first screen a user sees after the app finishes bootstrapping —
/// reimagined as a **Merc welcome moment** (the Duolingo pattern: the mascot
/// IS the front door, not a logo card).
///
/// On appear, a large Merc pops in with a spring, waves hello, and "speaks" a
/// greeting through a typewriter speech bubble that knows where the student
/// is (streak, this week, the next stop). He then keeps living — idle antics
/// every few seconds, a poke reaction on tap — while two chunky CTAs guide
/// the user into the two halves of the app:
///
/// - **The next stop** ("Start Lesson 1", "Continue · Lesson 3: …", "Take the
///   Unit 1 check") — opens it directly, over the learning path.
/// - **Chat with Merc** — opens the free Discussion chat (Chat tab).
///
/// Above them, "This week · 1 of 2" tracks the weekly goal. Installs that
/// finished onboarding before the weekly nudges existed get a one-time card
/// offering them.
///
/// Motion is fully gated on Reduce Motion (everything renders settled, full
/// greeting shown instantly). At accessibility type sizes Merc shrinks so the
/// scaled text and CTAs keep the room. VoiceOver reads the complete greeting
/// immediately — never the mid-typewriter fragment.
struct HomeView: View {

    // MARK: - Inputs

    private let state: HomeState
    private let onStartNext: () -> Void
    private let onStartChat: () -> Void
    private let showsReminderCard: Bool
    private let onAcceptReminders: () -> Void
    private let onDismissReminderCard: () -> Void

    init(
        state: HomeState,
        onStartNext: @escaping () -> Void,
        onStartChat: @escaping () -> Void,
        showsReminderCard: Bool = false,
        onAcceptReminders: @escaping () -> Void = {},
        onDismissReminderCard: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onStartNext = onStartNext
        self.onStartChat = onStartChat
        self.showsReminderCard = showsReminderCard
        self.onAcceptReminders = onAcceptReminders
        self.onDismissReminderCard = onDismissReminderCard
    }

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Entrance pop: Merc scales/slides in on appear (Reduce Motion: settled).
    @State private var entered = false
    /// The wave-hello that follows the entrance, settling to idle (antics then
    /// take over inside MercMascot).
    @State private var mercState: MercState = .idle
    /// Speech bubble visibility + typewriter progress.
    @State private var showBubble = false
    @State private var typedCount = 0
    @State private var greeting = ""
    @State private var typeTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColor.background
                    .ignoresSafeArea()

                content
            }
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .tint(BrandColor.accent)
    }

    // MARK: - Layout

    private var content: some View {
        // GeometryReader lets the hero composition fill the WHOLE screen at
        // normal type sizes (Merc centered, CTAs down by the thumb) while
        // accessibility sizes fall back to a natural scroll.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    brandRow
                        .padding(.top, BrandSpacing.md)

                    if showsReminderCard {
                        reminderCard
                            .padding(.top, BrandSpacing.lg)
                            .transition(.opacity)
                    }

                    Spacer(minLength: BrandSpacing.xl)

                    speechBubble
                        .padding(.bottom, BrandSpacing.sm)

                    mercHero

                    Spacer(minLength: BrandSpacing.xxl)

                    ctaSection

                    Spacer(minLength: BrandSpacing.lg)
                }
                .padding(.horizontal, BrandSpacing.xl)
                .frame(maxWidth: .infinity)
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear(perform: enter)
        .onDisappear { typeTask?.cancel() }
    }

    // MARK: - Pieces

    /// Compact brand identity up top — just the wordmark; Merc below carries
    /// the personality (and the monogram circle read as clutter next to him).
    private var brandRow: some View {
        Text("Mercurius AI")
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .foregroundStyle(BrandColor.text)
            .accessibilityAddTraits(.isHeader)
    }

    /// Merc's speech bubble with a typewriter reveal and a tail pointing down
    /// at him. The FULL greeting is the layout copy (rendered clear) with the
    /// typed prefix painted over it — both leading-aligned at the same wrap
    /// width, so glyphs land in their final positions from the first
    /// character and the bubble never reflows or shifts Merc/CTAs mid-type.
    private var speechBubble: some View {
        VStack(spacing: -1) {
            ZStack(alignment: .topLeading) {
                bubbleText(greeting)
                    .foregroundStyle(.clear)      // sizes the bubble; never visible
                bubbleText(typedGreeting)
                    .foregroundStyle(BrandColor.text)
            }
            .padding(.vertical, BrandSpacing.sm)
            .padding(.horizontal, BrandSpacing.md)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .fill(BrandColor.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                            .strokeBorder(BrandColor.border, lineWidth: 1)
                    )
                    .brandShadow(.card)
            )

            BubbleTail()
                .fill(BrandColor.surfaceElevated)
                .overlay(BubbleTailEdges().stroke(BrandColor.border, lineWidth: 1))
                .frame(width: 18, height: 9)
        }
        .opacity(showBubble ? 1 : 0)
        .scaleEffect(showBubble ? 1 : 0.9, anchor: .bottom)
        .accessibilityLabel(greeting)   // VoiceOver hears the whole line at once
    }

    private func bubbleText(_ string: String) -> Text {
        Text(string)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
    }

    private var typedGreeting: String {
        String(greeting.prefix(typedCount))
    }

    /// The star of the screen. Pops in with a spring, waves, then lives —
    /// idle antics + poke reaction come from MercMascot itself.
    private var mercHero: some View {
        MercMascot(mercState, size: mercSize, emphasis: .softGlow,
                   idleAntics: true, pokeable: true)
            .scaleEffect(entered ? 1 : 0.4, anchor: .bottom)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 36)
            .accessibilityHidden(true)
    }

    private var mercSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : 216
    }

    /// The week ring over two chunky Duolingo-style CTAs: the next stop first
    /// (the growth loop), chat second.
    private var ctaSection: some View {
        VStack(spacing: BrandSpacing.md) {
            if state.next != nil {
                weekRow
            }

            DuoButton(state.primaryActionTitle, style: .primary, action: onStartNext)
                .accessibilityHint(state.primaryActionHint)
                .accessibilityIdentifier("home.nextStop")

            DuoButton("Chat with Merc", style: .secondary, action: onStartChat)
                .accessibilityHint("Opens a free-form conversation with the tutor")
        }
        // Cap the CTA width on larger devices (iPad) so the buttons
        // don't stretch across the entire screen.
        .frame(maxWidth: 420)
        // Pin to ideal height: inside the screen-filling VStack the spare
        // vertical space must go to the Spacers — without this, DuoButton's
        // flexible 3D shadow plate absorbs it and stretches into a slab.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "This week · 1 of 2" with a small progress ring (the GamifiedTopBar
    /// level-ring pattern).
    private var weekRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(BrandColor.surfaceElevated, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: state.weekProgress)
                    .stroke(BrandGradient.mercHorizontal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)

            Text(state.weekLabel)
                .font(BrandFont.roundedCaption)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.weekAccessibilityLabel)
    }

    /// The one-time weekly-nudge offer. Compact, above Merc, so it never
    /// pushes the CTAs out of reach.
    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Want Merc to remind you twice a week?")
                        .font(BrandFont.roundedBodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Wednesday at 7 PM and Sunday at 6 PM. You can change this in Progress.")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let buttons = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: BrandSpacing.xs))
                : AnyLayout(HStackLayout(spacing: BrandSpacing.sm))
            buttons {
                BrandButton("Remind me", style: .primary, action: onAcceptReminders)
                    .accessibilityIdentifier("home.reminderCard.accept")
                BrandButton("Not now", style: .ghost, action: onDismissReminderCard)
                    .accessibilityIdentifier("home.reminderCard.dismiss")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .fill(BrandColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(BrandColor.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Entrance choreography

    private func enter() {
        greeting = state.greeting(hour: Calendar.current.component(.hour, from: Date()))
        guard !reduceMotion else {
            // Reduce Motion: no pop, no wave, no typewriter — everything
            // renders settled with the full greeting.
            entered = true
            showBubble = true
            typedCount = greeting.count
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            entered = true
        }
        mercState = .wave
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            mercState = .idle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showBubble = true
            }
            startTyping()
        }
    }

    private func startTyping() {
        typeTask?.cancel()
        typedCount = 0
        typeTask = Task { @MainActor in
            for i in 1...max(greeting.count, 1) {
                try? await Task.sleep(for: .seconds(0.024))
                guard !Task.isCancelled else { return }
                typedCount = i
            }
        }
    }

}

/// The little downward triangle hanging off the speech bubble (filled; its
/// top edge tucks 1pt under the bubble to hide the seam).
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Just the tail's two slanted edges, for the border stroke — stroking the
/// closed triangle would redraw its top edge straight across the bubble
/// seam and make the tail read as a separate pasted-on shape.
private struct BubbleTailEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewState(streak: Int = 0) -> HomeState {
    let suite = "preview.home.\(streak)"
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    let progress = CurriculumProgressStore(
        preferences: UserDefaultsPreferenceStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    )
    return HomeState.build(streak: streak, progress: progress)
}

#Preview("Light") {
    HomeView(state: previewState(), onStartNext: {}, onStartChat: {}, showsReminderCard: true)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(state: previewState(streak: 5), onStartNext: {}, onStartChat: {})
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    HomeView(state: previewState(), onStartNext: {}, onStartChat: {}, showsReminderCard: true)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
