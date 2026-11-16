import SwiftUI

/// The shared motion tokens for the lesson player and the learning path.
///
/// Every duration, spring and stagger a lesson-player or path animation uses
/// comes from here, so timing changes in one place. (The Mac's Night Studio
/// design keeps its own `Night.Motion`; `resolved(_:reduceMotion:)` has the
/// same shape there, so the two can merge without rewriting call sites.)
public enum Motion {

    // MARK: Durations

    public enum Duration {
        /// Small state changes: a selection settling, a tint.
        public static let fast: TimeInterval = 0.15
        /// Most transitions: a step changing, a scroll to feedback.
        public static let standard: TimeInterval = 0.25
        /// Larger arrivals: a card or screen settling into place.
        public static let slow: TimeInterval = 0.4
    }

    // MARK: Springs

    /// Taps: quick, with a little life, settles fast.
    public static let snappy = Animation.spring(duration: Duration.standard, bounce: 0.15)
    /// Layout: things moving to make room. No overshoot.
    public static let gentle = Animation.spring(duration: Duration.slow, bounce: 0)

    // MARK: Stagger

    /// The gap between items that arrive one after another (options, cards).
    public static let staggerInterval: TimeInterval = 0.06

    /// The delay for the item at `index` in a staggered group.
    public static func staggerDelay(_ index: Int) -> TimeInterval {
        Double(max(index, 0)) * staggerInterval
    }

    // MARK: Ambient loops (the learning path)

    /// The halo that pulses outward from the current lesson's node.
    public static let ambientPulse = Animation.easeOut(duration: 1.4).repeatForever(autoreverses: false)
    /// The START callout's bob above the current node.
    public static let ambientBob = Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)

    // MARK: Reduce Motion

    /// What an animation becomes under Reduce Motion.
    public enum ReduceMotionFallback: Sendable {
        /// A plain 0.2 s opacity crossfade (`Motion.fade`).
        case fade
        /// No animation: the change happens at once.
        case none
    }

    /// The Reduce Motion crossfade: movement and scale become a plain fade.
    public static let fade = Animation.easeInOut(duration: 0.2)

    /// Each half of a sequential Reduce Motion fade (out, then in): together
    /// they take `fade`'s 0.2 s.
    public static let fadeHalfDuration: TimeInterval = 0.1
    public static let fadeHalf = Animation.easeInOut(duration: fadeHalfDuration)

    /// `animation`, or the crossfade under Reduce Motion.
    /// Same shape as `Night.Motion.resolved(_:reduceMotion:)`.
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// `animation`, or the call site's chosen fallback under Reduce Motion
    /// (`nil` for `.none`, which `withAnimation` and `.animation` treat as
    /// no animation).
    public static func resolved(_ animation: Animation, reduceMotion: Bool, fallback: ReduceMotionFallback) -> Animation? {
        guard reduceMotion else { return animation }
        switch fallback {
        case .fade: return fade
        case .none: return nil
        }
    }

    /// `transition`, or a plain opacity transition under Reduce Motion. With
    /// `.none` the opacity transition still applies, but the change it rides
    /// on is unanimated (pair it with a `.none` animation), so it's instant.
    public static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}
