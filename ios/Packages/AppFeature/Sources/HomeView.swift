import SwiftUI
import DesignSystem

/// The first screen a user sees after the app finishes bootstrapping —
/// reimagined as a **Merc welcome moment** (the Duolingo pattern: the mascot
/// IS the front door, not a logo card).
///
/// On appear, a large Merc pops in with a spring, waves hello, and "speaks" a
/// contextual greeting through a typewriter speech bubble (streak-aware when
/// the learner has one going). He then keeps living — idle antics every few
/// seconds, a poke reaction on tap — while two chunky CTAs guide the user
/// into the two halves of the app:
///
/// - **Start learning** — jumps into the learning path (Curriculum tab).
/// - **Chat with Merc** — opens the free Discussion chat (Chat tab).
/// - **How it works** — the subdued explainer link, unchanged.
///
/// Motion is fully gated on Reduce Motion (everything renders settled, full
/// greeting shown instantly). At accessibility type sizes Merc shrinks so the
/// scaled text and CTAs keep the room. VoiceOver reads the complete greeting
/// immediately — never the mid-typewriter fragment.
public struct HomeView: View {

    // MARK: - Inputs

    private let onStartChat: () -> Void
    private let onStartLearning: () -> Void
    private let onHowItWorks: () -> Void
    /// Current streak (days). > 1 flavors the greeting Duolingo-style.
    private let streak: Int

    public init(
        onStartChat: @escaping () -> Void,
        onStartLearning: @escaping () -> Void,
        onHowItWorks: @escaping () -> Void,
        streak: Int = 0
    ) {
        self.onStartChat = onStartChat
        self.onStartLearning = onStartLearning
        self.onHowItWorks = onHowItWorks
        self.streak = streak
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

    public var body: some View {
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

    /// Two chunky Duolingo-style CTAs: lessons first (the growth loop), chat
    /// second, and the subdued explainer link last.
    private var ctaSection: some View {
        VStack(spacing: BrandSpacing.md) {
            DuoButton("Start learning", style: .primary, action: onStartLearning)
                .accessibilityHint("Opens your learning path of lessons")

            DuoButton("Chat with Merc", style: .secondary, action: onStartChat)
                .accessibilityHint("Opens a free-form conversation with the tutor")

            Button(action: onHowItWorks) {
                Text("How it works")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a short explanation of how Mercurius teaches")
        }
        // Cap the CTA width on larger devices (iPad) so the buttons
        // don't stretch across the entire screen.
        .frame(maxWidth: 420)
        // Pin to ideal height: inside the screen-filling VStack the spare
        // vertical space must go to the Spacers — without this, DuoButton's
        // flexible 3D shadow plate absorbs it and stretches into a slab.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Entrance choreography

    private func enter() {
        greeting = makeGreeting()
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

    /// A short, contextual line: streak-aware when one is alive, otherwise a
    /// time-of-day opener with a rotating invitation.
    private func makeGreeting() -> String {
        if streak > 1 {
            return "Day \(streak) — let's keep your streak alive!"
        }
        let hour = Calendar.current.component(.hour, from: Date())
        let opener: String
        switch hour {
        case 5..<12:  opener = "Good morning!"
        case 12..<17: opener = "Good afternoon!"
        case 17..<22: opener = "Good evening!"
        default:      opener = "Up late? Perfect time to learn."
        }
        let invitations = [
            "Ready to sharpen your AI skills?",
            "Let's learn something new today.",
            "Your next lesson is waiting.",
        ]
        return opener + " " + (invitations.randomElement() ?? invitations[0])
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

#Preview("Light") {
    HomeView(
        onStartChat: { print("Chat") },
        onStartLearning: { print("Learn") },
        onHowItWorks: { print("How it works") }
    )
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(
        onStartChat: { print("Chat") },
        onStartLearning: { print("Learn") },
        onHowItWorks: { print("How it works") },
        streak: 5
    )
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    HomeView(
        onStartChat: { print("Chat") },
        onStartLearning: { print("Learn") },
        onHowItWorks: { print("How it works") }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
