import Foundation

/// Predict, then reveal (RESEARCH.md §1.1, BUILD_PLAN.md §1.5): every card
/// asks for one committed guess before it shows what happens, keeps the
/// guess beside the result, and never scores it.
///
///     hook ──lock(choice)──▶ locked ──move──▶ exploring ──reveal──▶ revealed
///
/// - The explore control stays off until a guess is locked: `canExplore`.
///   A locked guess can't be changed (the guess is the hook, not a grade).
/// - "Show me" appears after the card's set number of moves
///   (`showMeAfter`; 0 shows it as soon as the guess is locked).
/// - Spoiled mode (the tutor already gave the answer): no prediction, the
///   control is on from the start, and the reveal has no "You guessed".
/// - Nothing here outlives the lesson: the card's state object holds it in
///   memory, and it is never `Codable`.
public struct PredictReveal<Choice: Hashable & Sendable>: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Untouched (spoiled mode starts ready to explore instead).
        case hook
        /// A guess is locked; nothing explored yet.
        case locked
        /// The student has used the control at least once.
        case exploring
        /// The result is shown beside the guess.
        case revealed
    }

    /// The prediction's options, in the order they are shown.
    public let choices: [Choice]
    /// Moves before "Show me" appears.
    public let showMeAfter: Int
    /// The tutor's text already gave the answer away.
    public let spoiled: Bool

    public private(set) var guess: Choice?
    public private(set) var moves = 0
    public private(set) var phase: Phase = .hook

    public init(choices: [Choice], showMeAfter: Int = 1, spoiled: Bool = false) {
        self.choices = choices
        self.showMeAfter = max(showMeAfter, 0)
        self.spoiled = spoiled
    }

    /// Whether the card asks for a guess at all.
    public var asksForPrediction: Bool { !spoiled }

    /// Whether the prediction chips still take a pick.
    public var canLock: Bool { !spoiled && guess == nil && phase == .hook }

    /// Whether the card's one control works yet: once a guess is locked, or
    /// from the start in spoiled mode.
    public var canExplore: Bool { spoiled || guess != nil }

    /// Whether "Show me" is offered.
    public var showsShowMe: Bool { canExplore && phase != .revealed && moves >= showMeAfter }

    public var isRevealed: Bool { phase == .revealed }

    /// Locks in `choice`. False (and no change) if a guess is already
    /// locked, the card is spoiled, or `choice` isn't one of the options.
    @discardableResult
    public mutating func lock(_ choice: Choice) -> Bool {
        guard canLock, choices.contains(choice) else { return false }
        guess = choice
        phase = .locked
        return true
    }

    /// The student used the control. False (and nothing counted) before a
    /// guess is locked. Moves after the reveal still count, and the reveal
    /// stays.
    @discardableResult
    public mutating func recordMove() -> Bool {
        guard canExplore else { return false }
        moves += 1
        if phase == .hook || phase == .locked { phase = .exploring }
        return true
    }

    /// Shows the result. False before a guess is locked (outside spoiled
    /// mode).
    @discardableResult
    public mutating func reveal() -> Bool {
        guard canExplore else { return false }
        phase = .revealed
        return true
    }

    /// The reveal's lines: the guess (nil in spoiled mode) and the result.
    public func revealLines(guessText: (Choice) -> String, result: String) -> InteractiveRevealLines {
        InteractiveRevealLines(guess: spoiled ? nil : guess.map(guessText), result: result)
    }

    /// The state a DEBUG `-InteractiveState` asks for, reached through the
    /// real transitions (so it can't be one the student couldn't reach).
    /// `.predicted` and later lock `guess` (default: the first choice).
    public static func debugStarting(_ state: InteractiveDebugState?, choices: [Choice],
                                     showMeAfter: Int = 1, spoiled: Bool = false,
                                     guess: Choice? = nil) -> PredictReveal {
        let isSpoiled = spoiled || state == .spoiled
        var machine = PredictReveal(choices: choices, showMeAfter: showMeAfter, spoiled: isSpoiled)
        guard let state, state != .hook, state != .spoiled else { return machine }
        if let pick = guess ?? choices.first { machine.lock(pick) }
        guard state != .predicted else { return machine }
        for _ in 0..<max(showMeAfter, 1) { machine.recordMove() }
        if state == .revealed { machine.reveal() }
        return machine
    }
}

/// What a reveal says: the guess beside the result ("You guessed: Doubt
/// everything." then what happened). No score, no "wrong".
public struct InteractiveRevealLines: Equatable, Sendable {
    /// The guess as the student picked it; nil in spoiled mode.
    public let guess: String?
    /// What happened, in one or two sentences.
    public let result: String

    public init(guess: String?, result: String) {
        self.guess = guess
        self.result = result
    }

    /// The reveal as one sentence for VoiceOver: "You guessed Doubt
    /// everything. It shared no fakes…".
    public var spoken: String {
        guard let guess else { return result }
        return "\(InteractiveShellCopy.youGuessed) \(guess). \(result)"
    }
}
