import Foundation

/// The two-phase step change: the step on screen trails `model.step`, so the
/// outgoing step fades out completely before the incoming one is inserted.
/// Only one step is ever in the view hierarchy, so the two never overlap and
/// a change in step height can't jump the layout.
///
///     shown(A) ──step→B──▶ leaving(A, target B) ──leave done──▶ shown(B)
///
/// The view runs the animations; this holds the state and decides what
/// happens when the step changes again mid-transition:
/// - while leaving, a newer step just becomes the target, so the swap lands
///   on the latest step;
/// - while leaving, a return to the step on screen fades it back in;
/// - a step change while the incoming step is still animating in starts a
///   new leave from wherever the animation is.
/// Each leave carries a generation; a finished leave that's been superseded
/// is ignored, and the one that superseded it finishes on its own, so the
/// player can't be left at zero opacity.
struct StepTransition: Equatable {
    enum Phase: Equatable {
        /// The displayed step is fully visible (or animating in).
        case shown
        /// The displayed step is fading out; `targetStepId` comes next.
        case leaving
    }

    enum Effect: Equatable {
        /// Nothing to animate.
        case none
        /// Animate the displayed step out, then call `leaveFinished` with this
        /// generation.
        case startLeaving(generation: Int)
        /// A leave was cancelled by a return to the displayed step: animate it
        /// back in.
        case returnToShown
    }

    /// The step in the view hierarchy.
    private(set) var displayedStepId: String
    /// The model's current step: where the transition is heading.
    private(set) var targetStepId: String
    private(set) var phase: Phase = .shown
    private(set) var generation = 0

    init(stepId: String) {
        displayedStepId = stepId
        targetStepId = stepId
    }

    /// The model's step changed to `stepId`.
    mutating func stepChanged(to stepId: String) -> Effect {
        targetStepId = stepId
        switch phase {
        case .shown:
            guard stepId != displayedStepId else { return .none }
            phase = .leaving
            generation += 1
            return .startLeaving(generation: generation)
        case .leaving:
            guard stepId == displayedStepId else { return .none }
            phase = .shown
            generation += 1
            return .returnToShown
        }
    }

    /// The leave started with `generation` has run its time. Returns the step
    /// to insert, or nil when that leave was superseded.
    mutating func leaveFinished(generation finished: Int) -> String? {
        guard phase == .leaving, finished == generation else { return nil }
        displayedStepId = targetStepId
        phase = .shown
        return displayedStepId
    }
}
