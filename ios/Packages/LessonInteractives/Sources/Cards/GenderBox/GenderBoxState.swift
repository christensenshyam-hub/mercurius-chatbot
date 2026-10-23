import Foundation
import Observation

/// What the student has done with Delete the Gender Box, for the open
/// lesson only: the guess (locked once), the gender box kept or deleted, and
/// the accessibility sizes' "Show all 12". Held by the lesson's
/// `InteractiveStateStore`; never `Codable`, never stored or sent.
///
///     hook ──guess──▶ locked ──delete the box──▶ revealed (the box flips freely after)
///
/// The first time the box is deleted the reveal shows: the control is the
/// reveal here (the new scores are the answer), so there is no "Show me".
/// Spoiled mode (none of this card's anchors has spoiler terms today, but
/// `-InteractiveState spoiled` reaches it) skips the guess.
@Observable
@MainActor
public final class GenderBoxState {
    public private(set) var machine: PredictReveal<GenderBoxGuess>
    public private(set) var box: GenderBox = .kept
    /// The accessibility sizes: the 12 résumés as a list of text, behind
    /// "Show all 12" (the summary line stays above it).
    public var showsAllResumes = false

    /// - Parameter debug: a DEBUG `-InteractiveState` (shots and UI tests
    ///   only). `.predicted` and later lock "Shrink" (the misconception's
    ///   answer, so the shots show the surprise). `.explored` and
    ///   `.revealed` both open with the box deleted and the reveal shown,
    ///   because deleting it is what reveals.
    public init(spoiled: Bool, debug: InteractiveDebugState? = InteractiveLaunchOptions.current.state) {
        var machine = PredictReveal.debugStarting(debug, choices: GenderBoxGuess.allCases, showMeAfter: 1,
                                                  spoiled: spoiled, guess: .shrink)
        if machine.phase == .exploring || machine.phase == .revealed {
            box = .deleted
            machine.reveal()
        }
        self.machine = machine
        #if DEBUG
        showsAllResumes = Self.debugShowsAll(ProcessInfo.processInfo.arguments)
        #endif
    }

    public var asksForGuess: Bool { machine.asksForPrediction && machine.guess == nil }

    /// Locks the guess in. False if one is already locked (or spoiled).
    @discardableResult
    public func lock(_ guess: GenderBoxGuess) -> Bool {
        machine.lock(guess)
    }

    /// The one control. Returns what VoiceOver should hear (nil: nothing
    /// changed, or no guess yet): the reveal the first time the box is
    /// deleted, the new weights and scores after that.
    @discardableResult
    public func set(_ newBox: GenderBox) -> String? {
        guard machine.canExplore, newBox != box else { return nil }
        machine.recordMove()
        box = newBox
        if newBox == .deleted && !machine.isRevealed {
            machine.reveal()
            return "\(revealLines.spoken) \(GenderBoxCopy.nuance)"
        }
        return GenderBoxCopy.announcement(newBox)
    }

    /// The other position (the Mac's arrows, a second tap).
    @discardableResult
    public func flip() -> String? {
        set(box == .kept ? .deleted : .kept)
    }

    public var revealLines: InteractiveRevealLines {
        machine.revealLines(guessText: GenderBoxCopy.guessTitle, result: GenderBoxCopy.revealResult)
    }

    /// The card's state in a sentence or two, for the title's VoiceOver value.
    public var summary: String {
        GenderBoxCopy.accessibilitySummary(box: box, asksForGuess: asksForGuess)
    }

    #if DEBUG
    /// `-GenderBoxShowAll YES`: the accessibility sizes' list starts open
    /// (shots of the list at AX5).
    nonisolated static func debugShowsAll(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-GenderBoxShowAll"), arguments.indices.contains(index + 1)
        else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    /// `-GenderBoxAutoplayAt <seconds since 1970>`: at that moment the card
    /// locks "Shrink", and 1.6 s later deletes the gender box (the
    /// reveal clip: simctl can't tap, so a clock both sides share times it).
    nonisolated static func debugAutoplayAt(_ arguments: [String]) -> Date? {
        guard let index = arguments.firstIndex(of: "-GenderBoxAutoplayAt"), arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Plays the guess and the deletion at `-GenderBoxAutoplayAt`'s moment.
    func debugAutoplay() async {
        guard let start = Self.debugAutoplayAt(ProcessInfo.processInfo.arguments) else { return }
        let wait = start.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        guard !Task.isCancelled else { return }
        lock(.shrink)
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        guard !Task.isCancelled else { return }
        if let line = set(.deleted) { InteractiveAccessibility.announce(line) }
    }
    #endif
}
