import Foundation

/// The result of Check answer on an option step (choice or claim picker),
/// played as a short sequence instead of appearing in one frame:
///
///     0.00 s  the chosen option takes its result colour
///             (correct: the checkmark pops in and the row pulses once;
///              wrong: the row shakes)
///     0.15 s  the feedback panel fades in and rises; the scroll follows it
///     0.25 s  wrong, on a step that reveals the answer: the right option
///             turns green, so the eye moves from the mistake to the answer
///     0.60 s  settled: the options take taps again
///
/// The view runs the timers; this decides the beats and what each one shows.
enum FeedbackChoreography {
    enum Outcome: Equatable {
        case correct
        /// `revealsAnswer`: the step shows the right answer after this miss
        /// (not on a Try again step).
        case wrong(revealsAnswer: Bool)

        init(verdict: Verdict, revealed: Bool) {
            self = verdict == .correct ? .correct : .wrong(revealsAnswer: revealed)
        }
    }

    enum Beat: Equatable {
        case result, panel, revealAnswer, settled
    }

    static let panelDelay: TimeInterval = 0.15
    static let answerDelay: TimeInterval = 0.25
    /// Long enough for the last beat's animation (the panel's gentle spring,
    /// the shake, the revealed answer's colour) to finish.
    static let settleTime: TimeInterval = 0.6
    /// The wrong answer's shake: 3 oscillations of 6 pt.
    static let shakeDuration: TimeInterval = 0.35
    static let shakeDistance: CGFloat = 6
    static let shakeOscillations = 3
    /// The correct answer's pulse and checkmark pop.
    static let pulseScale: CGFloat = 1.03
    static let checkmarkStartScale: CGFloat = 0.5
    /// How far the panel rises as it fades in.
    static let panelRise: CGFloat = 16

    static func beats(for outcome: Outcome) -> [(at: TimeInterval, beat: Beat)] {
        var beats: [(TimeInterval, Beat)] = [(0, .result), (panelDelay, .panel)]
        if case .wrong(revealsAnswer: true) = outcome { beats.append((answerDelay, .revealAnswer)) }
        beats.append((settleTime, .settled))
        return beats
    }
}

/// What an option step shows of its latest result while the choreography
/// plays. Settled (nil playback) shows everything the record says.
struct FeedbackReveal: Equatable {
    var result = false
    var panel = false
    var answer = false

    static let settled = FeedbackReveal(result: true, panel: true, answer: true)

    mutating func apply(_ beat: FeedbackChoreography.Beat) {
        switch beat {
        case .result: result = true
        case .panel: panel = true
        case .revealAnswer: answer = true
        case .settled: self = .settled
        }
    }

    /// What to show for `record`, given the submission whose result has
    /// fully played (`settledIndex`) and the one playing now, if any. A new
    /// result that hasn't started playing yet shows nothing of itself, so
    /// it never flashes in its final state for a frame.
    static func display(record: StepRecord, settledIndex: Int?, playing: (index: Int, reveal: FeedbackReveal)?) -> FeedbackReveal {
        guard record.phase == .feedback || record.phase == .done, let last = record.lastSubmission,
              last.index != settledIndex else { return .settled }
        if let playing, playing.index == last.index { return playing.reveal }
        return FeedbackReveal()
    }
}
