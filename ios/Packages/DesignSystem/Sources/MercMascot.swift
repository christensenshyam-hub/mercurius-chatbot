import SwiftUI

/// Semantic mood for the mascot — a disposition the host can set. Mood is
/// expressed through SUBTLE NATIVE MOTION ONLY (a slight lean, head-cock, or
/// pop); it never changes the procedural artwork or the explicit `state`
/// expression. Mapping mood → richer expression is a deliberate later step.
public enum MercMood: Equatable {
    case neutral
    case happy
    case thinking
    case listening
    case confused
    case celebrating
    case serious
    case encouraging
}

/// What the mascot is *doing* right now — the temporal/animation axis. Drives a
/// subtle motion overlay and takes precedence over `mood` when active.
public enum MercActivity: Equatable {
    case idle
    case userTyping
    case aiThinking
    case aiSpeaking
    case success
    case error
}

/// **MercMascot** — the one reusable way to place the Merc mascot.
///
/// Merc himself is the procedural character art (`Merc(state:size:)`). MercMascot
/// is a thin wrapper that adds, without ever touching the artwork:
/// - **placement** (`.free` / `.peek` / `.clippedHead`) — the framing each
///   surface needs, so call sites stop re-coding frame/clip/tap modifiers.
/// - **emphasis** (`.none` / `.softGlow` / `.badge`) — an optional readability
///   backing for the dark theme.
/// - **mood** + **activity** — subtle native-SwiftUI motion that differentiates
///   states (idle breathe/bob/blink, a thinking tilt+pulse, a listening lean, a
///   speaking bounce, a celebrate/success pop, an error shake). All motion is a
///   transform on the whole view — no new art, no pose surgery — and is disabled
///   under Reduce Motion.
/// - **idleAntics** + **pokeable** — the "Duo energy" layer: an opted-in hero
///   Merc plays a brief random micro-antic every few seconds of true idle
///   (reusing the existing pose art), and reacts with a happy pop / wave /
///   confetti burst when tapped. Antics are off under Reduce Motion and start
///   several seconds after appear, so snapshot first-frames never change.
///
/// Every new axis defaults to its no-op value, so existing call sites are
/// unchanged unless they explicitly opt in.
public struct MercMascot: View {
    public enum Placement: Equatable {
        case free
        case peek
        case clippedHead(visibleHeight: CGFloat)
    }

    public enum Emphasis: Equatable {
        case none
        case softGlow
        case badge
    }

    /// How much of the character the frame shows.
    public enum Presentation: Equatable {
        /// The full 160×180 character, as drawn. The default everywhere.
        case fullBody
        /// A circular head-and-shoulders crop for avatar sizes (~30–44pt):
        /// the artwork is zoomed and re-centered on the face/visor so Merc
        /// stays readable next to a message bubble, then clipped to a circle.
        /// Non-destructive — pure frame math over the same procedural art.
        /// Designed for `.free` placement (typically with `.badge` emphasis).
        case bust
    }

    private let state: MercState
    private let size: CGFloat
    private let placement: Placement
    private let presentation: Presentation
    private let emphasis: Emphasis
    private let mood: MercMood
    private let activity: MercActivity
    private let idleLife: Bool
    private let idleAntics: Bool
    private let pokeable: Bool
    private let onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Transient poses layered over the host's `state`. Ownership is split so
    /// the two never clear each other's reaction: `anticState` is written ONLY
    /// by the antics loop, `pokeState` ONLY by `poke()` (and a poke wins
    /// visually). Both always settle back to `nil`; the host's state is the
    /// truth. The antics loop also clears any stale `anticState` on (re)start,
    /// so a cancellation mid-antic (scroll-out in a lazy stack, tab switch)
    /// can never leave Merc frozen in an antic pose.
    @State private var anticState: MercState?
    @State private var pokeState: MercState?
    @State private var pokeTask: Task<Void, Never>?
    @State private var pokeCount = 0

    public init(
        _ state: MercState = .idle,
        size: CGFloat = 120,
        placement: Placement = .free,
        presentation: Presentation = .fullBody,
        emphasis: Emphasis = .none,
        mood: MercMood = .neutral,
        activity: MercActivity = .idle,
        idleLife: Bool = true,
        idleAntics: Bool = false,
        pokeable: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.state = state
        self.size = size
        self.placement = placement
        self.presentation = presentation
        self.emphasis = emphasis
        self.mood = mood
        self.activity = activity
        self.idleLife = idleLife
        self.idleAntics = idleAntics
        self.pokeable = pokeable
        self.onTap = onTap
    }

    public var body: some View {
        emphasized
            .modifier(MercMotion(mood: mood, activity: activity))
            .modifier(TapAffordance(onTap: tapHandler))
            .task(id: anticsActive) { await runAntics() }
            .sensoryFeedback(.impact(weight: .light), trigger: pokeCount)
    }

    /// The pose actually rendered: a poke reaction wins, then a running antic,
    /// otherwise the host-supplied state.
    private var effectiveState: MercState { pokeState ?? anticState ?? state }

    private var merc: Merc {
        Merc(state: effectiveState, size: size, ambient: idleLife)
    }

    // MARK: - Idle antics ("Duo energy")

    /// Antics only play when the mascot is genuinely at rest: the host isn't
    /// posing him (`state == .idle`), nothing live is happening (`activity` /
    /// `mood` neutral), the surface opted in, and Reduce Motion is off.
    private var anticsActive: Bool {
        idleAntics && !reduceMotion
            && state == .idle && activity == .idle && mood == .neutral
    }

    /// The life director: every few seconds of true idle, play one brief
    /// random micro-antic (a wave hello, a happy bounce, a pensive glance),
    /// then settle back. The first antic fires several seconds after appear,
    /// so a synchronously rendered first frame (snapshots) is unchanged.
    private func runAntics() async {
        // A task (re)start — first appear, reappear after a lazy-container
        // scroll-out, or a gate flip — invalidates any stale antic pose, so a
        // cancellation that landed mid-antic can't leave the pose stuck.
        anticState = nil
        guard anticsActive else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 5.5...9.5)))
            guard !Task.isCancelled, anticsActive else { return }
            guard pokeState == nil else { continue }   // don't talk over a poke
            let pick: MercState = [.wave, .happy, .thinking].randomElement() ?? .wave
            withAnimation(.easeOut(duration: 0.25)) { anticState = pick }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.3...1.9)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { anticState = nil }
        }
    }

    // MARK: - Poke reaction

    /// Tap handler: a pokeable Merc always reacts to a tap (then forwards to
    /// `onTap` if the host wants the event too); otherwise taps behave exactly
    /// as before — a gesture only when the host supplied one.
    private var tapHandler: (() -> Void)? {
        guard pokeable else { return onTap }
        return {
            poke()
            onTap?()
        }
    }

    private func poke() {
        pokeCount += 1
        pokeTask?.cancel()
        let pick: MercState = [.happy, .wave, .celebrate].randomElement() ?? .happy
        withAnimation(.easeOut(duration: 0.2)) { pokeState = pick }
        pokeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { pokeState = nil }
        }
    }

    private var mercHeight: CGFloat { size }
    private var mercWidth: CGFloat { size * 160.0 / 180.0 }

    // Bust crop tuning (art space is 160×180):
    /// How far the artwork is zoomed inside the bust circle. 1.6 puts the
    /// head + visor at ~55% of the circle with the wing tips peeking in at
    /// the edges — recognizably Merc, readable at 30pt — while leaving
    /// headroom above the helmet dome (static top y≈17) for the per-state
    /// body bob (.happy peaks at −12, .celebrate at −18, plus the ~3-unit
    /// breathing lift), so no state flattens the helmet against the clip.
    private static let bustZoom: CGFloat = 1.6
    /// The art-space y (as a fraction of the 180pt art height) the crop
    /// centers on — the visor stripe (y≈45–55), so the visible band runs
    /// from just above the helmet dome to the toga's shoulder.
    private static let bustFocusY: CGFloat = 52.0 / 180.0

    /// The character at the requested presentation: the plain full-body art,
    /// or the zoomed circular head-and-shoulders crop.
    @ViewBuilder private var portrait: some View {
        switch presentation {
        case .fullBody:
            merc
        case .bust:
            // Render the same procedural art larger, slide it down so the
            // face sits at the frame's center, and clip to a circle. The
            // ambient bob/blink keep running inside the crop, so the avatar
            // reads as "alive in a porthole" rather than a static icon.
            Merc(state: effectiveState, size: size * Self.bustZoom, ambient: idleLife)
                .offset(y: (0.5 - Self.bustFocusY) * size * Self.bustZoom)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    @ViewBuilder private var placed: some View {
        switch placement {
        case .free:
            portrait
        case .peek:
            portrait
                .padding(.top, BrandSpacing.xs)
                .padding(.bottom, BrandSpacing.xxs)
                .frame(maxWidth: .infinity)
        case .clippedHead(let visibleHeight):
            portrait
                .frame(height: visibleHeight, alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Emphasis

    @ViewBuilder private var emphasized: some View {
        switch emphasis {
        case .none:
            placed
        case .softGlow:
            placed.background(alignment: .center) { softGlow }
        case .badge:
            placed
                .frame(width: mercHeight, height: mercHeight)
                .padding(mercHeight * 0.10)
                .background(badge)
        }
    }

    private var softGlow: some View {
        let diameter = mercHeight * 1.4
        return RadialGradient(
            colors: [
                BrandColor.accentLight.opacity(0.34),
                BrandColor.accent.opacity(0.14),
                .clear,
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private var badge: some View {
        let diameter = mercHeight * 1.2
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BrandColor.mercViolet.opacity(0.22),
                        BrandColor.surfaceElevated,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .overlay(Circle().strokeBorder(BrandColor.mercViolet.opacity(0.32), lineWidth: 1))
            .brandShadow(.card)
            .allowsHitTesting(false)
    }
}

// MARK: - Motion layer (mood + activity)

/// Resolves (mood, activity) to ONE subtle motion and applies it as a transform
/// over the whole mascot. Activity (the live thing the mascot is doing) wins;
/// mood supplies a resting disposition when the activity is idle. Fully disabled
/// under Reduce Motion.
private struct MercMotion: ViewModifier {
    let mood: MercMood
    let activity: MercActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loopOn = false       // repeating: pulse / bounce / tilt
    @State private var popScale: CGFloat = 1 // one-shot: celebrate / success
    @State private var shakeX: CGFloat = 0   // one-shot: error

    private enum Behavior { case none, lean, tilt, pulse, bounce, pop, shake }

    private var behavior: Behavior {
        if reduceMotion { return .none }
        switch activity {
        case .error:      return .shake
        case .success:    return .pop
        case .aiSpeaking: return .bounce
        case .aiThinking: return .pulse
        case .userTyping: return .lean
        case .idle:
            switch mood {
            case .celebrating:           return .pop
            case .thinking, .confused:   return .tilt
            case .listening, .encouraging: return .lean
            case .neutral, .happy, .serious: return .none
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleAmount, anchor: .bottom)
            .rotationEffect(.degrees(rotationDegrees), anchor: .bottom)
            .offset(x: shakeX, y: offsetY)
            .animation(repeatAnimation, value: loopOn)
            .animation(.easeOut(duration: 0.35), value: rotationDegrees)
            .onAppear { restart() }
            .onChange(of: activity) { _, _ in restart() }
            .onChange(of: mood) { _, _ in restart() }
    }

    // Resolved transform values for the current behavior.
    private var rotationDegrees: Double {
        switch behavior {
        case .lean: return 3.5     // lean slightly forward
        case .tilt: return -5      // head cocked (thinking / confused)
        default:    return 0
        }
    }

    private var scaleAmount: CGFloat {
        switch behavior {
        case .pulse: return loopOn ? 1.03 : 1.0
        case .tilt:  return loopOn ? 1.02 : 1.0
        case .pop:   return popScale
        default:     return 1.0
        }
    }

    private var offsetY: CGFloat {
        behavior == .bounce ? (loopOn ? -3 : 0) : 0
    }

    private var repeatAnimation: Animation? {
        switch behavior {
        case .pulse, .tilt: return .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
        case .bounce:       return .easeInOut(duration: 0.32).repeatForever(autoreverses: true)
        default:            return nil
        }
    }

    /// (Re)arm whatever the current behavior needs. Resets transient drivers so
    /// switching behaviors never leaves a stuck transform.
    private func restart() {
        popScale = 1
        shakeX = 0
        loopOn = false

        switch behavior {
        case .pulse, .tilt, .bounce:
            // Toggle on the next runloop tick so the false→true change animates.
            DispatchQueue.main.async { loopOn = true }
        case .pop:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.45)) { popScale = 1.14 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { popScale = 1.0 }
            }
        case .shake:
            let steps: [CGFloat] = [-7, 6, -5, 4, -2, 0]
            for (i, dx) in steps.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.055) {
                    withAnimation(.easeInOut(duration: 0.055)) { shakeX = dx }
                }
            }
        case .lean, .none:
            break
        }
    }
}

/// Adds a rectangular tap area + handler only when a tap closure is supplied, so
/// the no-tap case leaves hit-testing exactly as the bare mascot has it.
private struct TapAffordance: ViewModifier {
    let onTap: (() -> Void)?

    @ViewBuilder func body(content: Content) -> some View {
        if let onTap {
            content.contentShape(Rectangle()).onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("MercMascot — placements + emphasis") {
    ScrollView {
        VStack(spacing: 28) {
            MercMascot(.idle, size: 120, placement: .free)
            MercMascot(.wave, size: 72, placement: .peek)
            MercMascot(.happy, size: 128, placement: .clippedHead(visibleHeight: 84))

            Divider()

            HStack(spacing: 24) {
                MercMascot(.idle, size: 120, emphasis: .softGlow)
                MercMascot(.happy, size: 120, emphasis: .badge)
            }
            HStack(spacing: 16) {
                MercMascot(.wave, size: 36, emphasis: .badge)
                MercMascot(.idle, size: 56, emphasis: .badge)
                MercMascot(.happy, size: 80, emphasis: .badge)
            }

            Divider()

            // Full-body vs bust at avatar sizes — the readability comparison.
            HStack(spacing: 16) {
                MercMascot(.idle, size: 30, emphasis: .badge)
                MercMascot(.idle, size: 30, presentation: .bust, emphasis: .badge)
                MercMascot(.idle, size: 44, presentation: .bust, emphasis: .badge)
                MercMascot(.happy, size: 44, presentation: .bust, emphasis: .badge)
            }
        }
        .padding(40)
    }
    .background(BrandColor.background)
    .preferredColorScheme(.dark)
}
#endif
