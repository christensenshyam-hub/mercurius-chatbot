import Foundation
import Observation

/// What the student has done with The Doubt Dial in the open lesson: the
/// guess (in the predict-then-reveal machine), the dial's stop, and whether
/// "Check first" is showing. Owned by the lesson's `InteractiveStateStore`,
/// so a reply's re-render never resets it; in memory only (never encoded,
/// stored or sent), and a new lesson screen starts fresh.
@Observable
@MainActor
public final class DoubtDialState {
    /// Dial moves before "Show me" appears: at least two settings tried.
    public static let showMeAfter = 2

    public private(set) var machine: PredictReveal<DoubtDialGuess>
    /// The dial's stop, 0 (believe everything) to 4 (doubt everything).
    public private(set) var stop: Int
    /// "Check first" is showing: the feed shows what checking found.
    public private(set) var checking = false

    /// - Parameters:
    ///   - spoiled: the tutor's text gave the answer away (this card has no
    ///     spoiler terms, so only DEBUG's `-InteractiveState spoiled`).
    ///   - launch / debug: DEBUG shots only (`-InteractiveState`,
    ///     `-DoubtDialGuess`, `-DoubtDialCheckFirst`); empty in Release.
    public init(spoiled: Bool, launch: InteractiveLaunchOptions = .current, debug: DoubtDialDebug = .current) {
        let guess = debug.guess ?? .doubtEverything
        let machine = PredictReveal.debugStarting(launch.state, choices: DoubtDialGuess.allCases,
                                                  showMeAfter: Self.showMeAfter, spoiled: spoiled, guess: guess)
        self.machine = machine
        switch launch.state {
        case .explored?:
            stop = machine.spoiled ? DoubtDialContent.startStop : DoubtDialContent.representativeStop(for: guess)
        case .revealed?:
            // Where "Show me" leaves the dial on the real path.
            stop = DoubtDialContent.revealStop(for: machine.spoiled ? nil : machine.guess,
                                               current: DoubtDialContent.representativeStop(for: guess))
        default:
            stop = DoubtDialContent.startStop
        }
        checking = debug.checkFirst && machine.isRevealed
    }

    // MARK: What the card shows

    /// The card's state, for its one-sentence VoiceOver summary.
    public var mode: DoubtDialCopy.Mode {
        if checking { return .checked }
        return machine.canExplore ? .dial(stop) : .hook
    }

    public var summary: String { DoubtDialCopy.accessibilitySummary(mode) }

    /// The dial's two counters at its stop. (Checking's three are
    /// `DoubtDialContent.checkTally`: the card shows both side by side.)
    public var dialTally: DoubtDialTally { DoubtDialContent.tally(atStop: stop) }

    /// What a post shows: nothing before the guess, the dial's verdict
    /// after it, or what checking found.
    public func verdict(for post: DoubtDialPost) -> DoubtDialVerdict? {
        if checking { return DoubtDialContent.checkVerdict(post) }
        return machine.canExplore ? DoubtDialContent.verdict(post, atStop: stop) : nil
    }

    /// The guess beside what happened.
    public var revealLines: InteractiveRevealLines {
        let result = machine.spoiled ? DoubtDialCopy.spoiledResult
            : (machine.guess.map(DoubtDialCopy.result(for:)) ?? DoubtDialCopy.spoiledResult)
        return machine.revealLines(guessText: DoubtDialCopy.guessTitle, result: result)
    }

    /// "Check first" is offered once the result is shown.
    public var canCheck: Bool { machine.isRevealed }

    // MARK: What the student does

    /// Locks the guess in (once).
    @discardableResult
    public func lock(_ guess: DoubtDialGuess) -> Bool {
        machine.lock(guess)
    }

    /// Turns the dial to `newStop`. False (and nothing changes) before a
    /// guess is locked, or at the same stop. Turning it leaves "Check
    /// first": the feed shows the dial's verdicts again.
    @discardableResult
    public func turn(to newStop: Int) -> Bool {
        let target = DoubtDialContent.clamped(newStop)
        guard machine.canExplore, target != stop else { return false }
        stop = target
        machine.recordMove()
        checking = false
        return true
    }

    /// "Show me": the result beside the guess, and the dial turned to the
    /// setting the result names (the guess's end; a middle stop for "in the
    /// middle", the one the student is on if it is one; Doubt everything in
    /// spoiled mode), so the counters, the lit mistakes cell and the feed
    /// agree with the sentence beside them. Not a move: "Show me" is gone.
    @discardableResult
    public func showMe() -> Bool {
        guard machine.showsShowMe, machine.reveal() else { return false }
        stop = DoubtDialContent.revealStop(for: machine.spoiled ? nil : machine.guess, current: stop)
        checking = false
        return true
    }

    /// "Check first": the feed shows what checking found.
    @discardableResult
    public func checkFirst() -> Bool {
        guard canCheck, !checking else { return false }
        checking = true
        return true
    }

    /// "Back to the dial".
    @discardableResult
    public func backToDial() -> Bool {
        guard checking else { return false }
        checking = false
        return true
    }
}

/// The card's own DEBUG shot arguments, beside the framework's
/// `-InteractiveState`: `-DoubtDialGuess believe|middle|doubt` (the guess
/// a `predicted`/`explored`/`revealed` state locks; default doubt),
/// `-DoubtDialCheckFirst YES` ("Check first" showing, once revealed) and
/// `-DoubtDialScrollFeed YES` (the reveal's scroll mark moves to the feed's
/// heading, so `-InteractiveScroll reveal` brings the feed and its column
/// headers to the top). Read from the launch in DEBUG builds only.
public struct DoubtDialDebug: Equatable, Sendable {
    public var guess: DoubtDialGuess?
    public var checkFirst = false
    public var scrollToFeed = false

    public init(guess: DoubtDialGuess? = nil, checkFirst: Bool = false, scrollToFeed: Bool = false) {
        self.guess = guess
        self.checkFirst = checkFirst
        self.scrollToFeed = scrollToFeed
    }

    /// The options in a launch's arguments (pure, for the tests).
    public init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value.lowercased()
        }
        switch value("-DoubtDialGuess") {
        case "believe", "believeeverything": guess = .believeEverything
        case "middle": guess = .middle
        case "doubt", "doubteverything": guess = .doubtEverything
        default: guess = nil
        }
        func isOn(_ flag: String) -> Bool {
            let raw = value(flag)
            return raw == "yes" || raw == "true" || raw == "1"
        }
        checkFirst = isOn("-DoubtDialCheckFirst")
        scrollToFeed = isOn("-DoubtDialScrollFeed")
    }

    public static let current: DoubtDialDebug = {
        #if DEBUG
        return DoubtDialDebug(arguments: ProcessInfo.processInfo.arguments)
        #else
        return DoubtDialDebug()
        #endif
    }()
}
