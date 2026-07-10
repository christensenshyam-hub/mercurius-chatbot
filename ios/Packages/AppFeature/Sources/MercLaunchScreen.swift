import SwiftUI
import DesignSystem

/// The Duolingo-style branded launch moment shown while `RootView` bootstraps
/// (session resolve + SwiftData spin-up): Merc hovers mid-screen under the
/// wordmark while an indeterminate bar sweeps and a rotating AI-literacy tip
/// gives the wait a purpose. `RootView` holds this screen for a minimum beat
/// even when bootstrap is instant, so it reads as an intentional welcome
/// rather than a flash.
///
/// Motion (the hover, the sweep) is fully disabled under Reduce Motion — the
/// screen renders settled with a static track. VoiceOver reads one combined
/// "Loading Mercurius" element plus the tip.
struct MercLaunchScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the gentle hover float (autoreversing).
    @State private var float = false
    /// Drives the indeterminate sweep across the progress track.
    @State private var sweep = false
    /// One tip per launch — picked on appear so it rotates across opens.
    @State private var tip = ""

    private static let tips = [
        "Tip: AI can sound confident and still be wrong — verify big claims.",
        "Tip: The better your question, the better the answer.",
        "Tip: LLMs predict words. Understanding them is your job.",
        "Tip: Ask AI to show its reasoning, not just its answer.",
        "Did you know? Merc is named for Mercury, the messenger god.",
    ]

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Merc hovers on his wings — the launch mascot beat. Under
                // Reduce Motion the offset is 0 (a neutral rest pose), never
                // the +8 bottom extreme of the (disabled) hover arc.
                MercMascot(.idle, size: 170, emphasis: .softGlow)
                    .offset(y: reduceMotion ? 0 : (float ? -10 : 8))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                        value: float
                    )
                    .accessibilityHidden(true)

                Text("Mercurius AI")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(BrandColor.text)
                    .padding(.top, BrandSpacing.lg)

                Spacer()

                VStack(spacing: BrandSpacing.md) {
                    progressTrack

                    Text(tip)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, BrandSpacing.xl)
                }
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
        // .combine: one focusable element whose label VoiceOver reliably
        // reads (a .contain container's label is only unreliable group
        // context, and would double-speak the tip).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Mercurius. \(tip)")
        .onAppear {
            tip = Self.tips.randomElement() ?? Self.tips[0]
            guard !reduceMotion else { return }
            float = true
            // Scope the repeatForever to THIS state change. A persistent
            // `.animation(value:)` modifier on the capsule lets ancestor
            // layout shifts (the launch zoom settling, the crossfade to
            // Home) ride the repeat curve too — the capsule visibly tears
            // out of the track and glides back ("spills out of the bar").
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }

    /// A thin indeterminate loader: a gradient segment sweeping across a
    /// muted track. Static (partial fill) under Reduce Motion so the screen
    /// still reads as "loading" without the motion.
    private var progressTrack: some View {
        GeometryReader { geo in
            let segment = geo.size.width * 0.35
            ZStack(alignment: .leading) {
                Capsule().fill(BrandColor.surfaceElevated)
                Capsule()
                    .fill(BrandGradient.mercHorizontal)
                    .frame(width: segment)
                    .offset(x: sweep ? geo.size.width - segment : 0)
                    // Animated via `withAnimation` at onAppear — see there
                    // for why a persistent .animation modifier is wrong.
            }
        }
        .frame(width: 200, height: 6)
        .clipShape(Capsule())
        // Isolate the subtree's geometry: outer movement is applied to the
        // finished track as a unit, so in-flight sweep frames can never be
        // composed against a moved ancestor.
        .geometryGroup()
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Launch — light") {
    MercLaunchScreen().preferredColorScheme(.light)
}

#Preview("Launch — dark") {
    MercLaunchScreen().preferredColorScheme(.dark)
}
#endif
