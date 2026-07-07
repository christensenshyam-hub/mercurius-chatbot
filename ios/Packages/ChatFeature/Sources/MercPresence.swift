import SwiftUI
import DesignSystem

/// Drives the **ephemeral Merc** mascot's expression + on-screen presence from
/// chat lifecycle events.
///
/// Merc is not a permanent fixture: he pops in with a wave when a conversation
/// starts, reacts while it's active, dozes after a stretch of inactivity, and
/// then fades out entirely (the chat reclaims the space) until the next message
/// brings him back. This controller owns that lifecycle — two timers
/// (idle→sleep, then sleep→hide) plus brief reaction "flashes" that settle back
/// to `.idle`. It only flips state; the *view* layer owns the actual
/// animations and honors reduce-motion.
@MainActor
@Observable
public final class MercPresenceController {
    /// The expression to render. Drives `Merc(state:)`.
    public private(set) var state: MercState = .idle
    /// Whether Merc is on screen at all. When false the zone collapses to zero
    /// height and the conversation reclaims the space.
    public private(set) var isVisible: Bool = false

    // Tunables (seconds) — exposed internally for tests + future tuning.
    var idleToSleep: Double = 50
    var sleepToHide: Double = 15
    var introHold: Double = 0.9
    var reactionHold: Double = 1.4
    /// When true (the lesson hero), Merc dozes in place after the idle delay and
    /// stays on screen until woken — he never auto-hides. When false (the free
    /// chat peek), he fades out after `sleepToHide` and returns on the next msg.
    var persistent: Bool = false

    private var idleTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var didIntro = false
    /// Set when `thinkingBegan` arrives during the entrance wave: the wave plays
    /// out, then resumes into `.thinking` instead of settling to `.idle`.
    private var pendingThinkAfterWave = false

    public init() {}

    // MARK: - Lifecycle events (called from the view's .onChange handlers)

    /// The conversation became active (a fresh thread started) or was resumed.
    /// `greet` plays the one-time wave intro; a resumed/loaded thread passes
    /// `false` and skips to idle. Never overrides an in-flight `.thinking` (a
    /// resumed thread may already be streaming — thinking owns the entrance
    /// then).
    public func chatStarted(greet: Bool) {
        isVisible = true
        guard state != .thinking else { return }
        if greet && !didIntro {
            didIntro = true
            flashWave()
        } else if state == .sleep {
            state = .idle
        }
        armIdleTimer()
    }

    /// The assistant began producing a turn → think. Suspends the idle timer so
    /// Merc never dozes mid-response. If an entrance wave is still playing, the
    /// wave finishes first and then resumes into thinking.
    public func thinkingBegan() {
        wake()
        if state == .wave {
            pendingThinkAfterWave = true
            idleTask?.cancel(); idleTask = nil
            return
        }
        reactionTask?.cancel(); reactionTask = nil
        state = .thinking
        idleTask?.cancel(); idleTask = nil
    }

    /// The assistant finished a turn. A successful, non-empty reply earns a
    /// brief happy nod; a failed/empty turn just settles to idle. If the
    /// entrance wave is still playing, let it settle on its own.
    public func thinkingEnded(positive: Bool) {
        wake()
        pendingThinkAfterWave = false
        if state == .wave {
            armIdleTimer()
            return
        }
        if positive { flash(.happy) } else { state = .idle }
        armIdleTimer()
    }

    /// A celebratory beat (e.g. unit mastery). Not wired to ordinary lesson
    /// completion — that's owned by the full-screen LessonCompleteOverlay — but
    /// available for callers that want a prominent Merc moment.
    public func celebrate() {
        wake()
        flash(.celebrate)
        armIdleTimer()
    }

    /// Generic activity (a new message arrived, the user is typing): keep Merc
    /// awake and restart the idle countdown — but never while he's mid-thought
    /// (that would let a racing signal re-arm a timer that could doze him).
    public func activity() {
        wake()
        guard state != .thinking else { return }
        armIdleTimer()
    }

    /// The thread was cleared/replaced — reset so the next conversation gets a
    /// fresh greeting.
    public func reset() {
        didIntro = false
        pendingThinkAfterWave = false
        idleTask?.cancel(); idleTask = nil
        reactionTask?.cancel(); reactionTask = nil
        state = .idle
        isVisible = false
    }

    // MARK: - Internals

    private func wake() {
        if !isVisible { isVisible = true }
        if state == .sleep { state = .idle }
    }

    private func flashWave() {
        state = .wave
        reactionTask?.cancel()
        reactionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.introHold ?? 0.9))
            guard let self, !Task.isCancelled else { return }
            if self.state == .wave {
                self.state = self.pendingThinkAfterWave ? .thinking : .idle
            }
            self.pendingThinkAfterWave = false
        }
    }

    private func flash(_ s: MercState) {
        reactionTask?.cancel()
        state = s
        reactionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.reactionHold ?? 1.4))
            guard let self, !Task.isCancelled else { return }
            if self.state == s { self.state = .idle }
        }
    }

    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.idleToSleep ?? 50))
            guard let self, !Task.isCancelled, self.state != .thinking else { return }
            self.state = .sleep
            if self.persistent { return }   // hero dozes in place — never auto-hides
            try? await Task.sleep(for: .seconds(self.sleepToHide))
            guard !Task.isCancelled else { return }
            self.isVisible = false
        }
    }
}

/// An ephemeral Merc that sits at the top of a conversation and reacts to it.
/// Self-contained: owns its `MercPresenceController`, reads reduce-motion +
/// Dynamic Type itself, and translates the shared `ChatViewModel`'s observable
/// signals (`phase`, `messages`, `draft`) into Merc's expression + presence.
/// Drop it in as a `VStack(spacing: 0)` sibling between the header divider and
/// the message list — when Merc fades out the zone collapses with no residual
/// gap.
/// NOTE: currently UNWIRED. The free chat now expresses Merc through the top
/// intro coach (`EmptyChatView`) + per-message avatars driven by
/// `MercMascotState` / `focalMercState`, and lessons use `MercCoachCard`. This
/// ephemeral-presence zone has no production callers anymore; its
/// `MercPresenceController` state machine is kept (and unit-tested) in case a
/// future surface wants the doze→sleep→hide behavior again.
public struct MercChatZone: View {
    /// `peek` — the free-chat ephemeral strip (small, fades out on idle).
    /// `hero` — a large, haloed, persistent centerpiece (dozes in place, wakes
    /// on tap, never disappears).
    /// `anchor` — a persistent buddy that peeks up from behind the composer,
    /// clipped to head/torso; same lifecycle as `hero`, different framing.
    public enum Style { case peek, hero, anchor }

    private let model: ChatViewModel
    private let style: Style

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var controller: MercPresenceController

    public init(model: ChatViewModel, style: Style = .peek) {
        self.model = model
        self.style = style
        let c = MercPresenceController()
        if style == .hero || style == .anchor {
            c.persistent = true
            c.idleToSleep = 60   // README: Merc dozes after ~60s of inactivity
        }
        _controller = State(initialValue: c)
    }

    private var mercSize: CGFloat {
        switch style {
        case .hero: return 140
        case .anchor: return 128
        case .peek: return 72
        }
    }

    public var body: some View {
        Group {
            if isShown {
                zoneContent.transition(transition)
            }
        }
        // Only the pop-in / collapse is animated here. Merc owns all of its own
        // per-state motion internally, so we deliberately do NOT animate on
        // `controller.state` (its eye/mouth/arm swaps are meant to snap).
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.74),
                   value: controller.isVisible)
        .onAppear {
            switch style {
            case .hero, .anchor:
                controller.chatStarted(greet: true)    // lesson opens → wave Merc in
            case .peek:
                if !model.messages.isEmpty { controller.chatStarted(greet: false) }
            }
        }
        // messages.count is observed BEFORE phase so that on a genuine first
        // send (0→2 in one transaction) the wave is established before the
        // streaming-phase signal arrives.
        .onChange(of: model.messages.count) { old, new in
            if new == 0 {
                controller.reset()
            } else if old == 0 {
                // A small opening burst (a fresh send / lesson opener) greets;
                // a bulk hydrate (resuming an archived thread) just appears.
                controller.chatStarted(greet: new <= 2)
            } else {
                controller.activity()
            }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .sending, .streaming:
                controller.thinkingBegan()
            case .idle:
                controller.thinkingEnded(positive: lastReplyWasAssistant)
            case .failed:
                controller.activity()   // stay present + neutral; no happy on failure
            }
        }
        .onChange(of: model.draft) { _, _ in
            // Typing keeps a visible Merc awake, but doesn't summon him back if
            // he's already faded out (he returns on the next *message*).
            if controller.isVisible { controller.activity() }
        }
    }

    private var isShown: Bool {
        switch style {
        case .hero, .anchor: return controller.isVisible   // persistent
        case .peek: return controller.isVisible && !dynamicTypeSize.isAccessibilitySize
        }
    }

    @ViewBuilder private var zoneContent: some View {
        switch style {
        case .peek:
            MercMascot(controller.state, size: mercSize, placement: .peek)
        case .hero:
            ZStack {
                RadialGradient(colors: [BrandColor.mercViolet.opacity(0.16), .clear],
                               center: .center, startRadius: 2, endRadius: 105)
                    .frame(width: 210, height: 150)
                MercMascot(controller.state, size: mercSize, placement: .free)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { controller.activity() }   // tap to wake (README wiring)
        case .anchor:
            // Peeks up from behind the composer: show head/torso, crop the legs.
            MercMascot(controller.state, size: mercSize,
                       placement: .clippedHead(visibleHeight: mercSize * 0.66),
                       onTap: { controller.activity() })   // tap to wake
        }
    }

    private var lastReplyWasAssistant: Bool {
        guard let last = model.messages.last, last.role == .assistant else { return false }
        if case .failed = last.status { return false }
        // An empty (but not failed) reply shouldn't earn a happy nod.
        return !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        switch style {
        case .peek:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.5, anchor: .bottom)),
                removal: .opacity.combined(with: .scale(scale: 0.7, anchor: .bottom)))
        case .hero:
            return .opacity.combined(with: .scale(scale: 0.85, anchor: .center))
        case .anchor:
            return .opacity.combined(with: .move(edge: .bottom))
        }
    }
}
