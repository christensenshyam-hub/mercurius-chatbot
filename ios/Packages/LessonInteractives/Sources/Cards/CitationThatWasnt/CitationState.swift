import Foundation
import Observation

/// What the student has done with The Citation That Wasn't, for the open
/// lesson only: the walk through the five slots, the step guess and its
/// reveal, and whether "Write it again" was pressed. Owned by the lesson's
/// `InteractiveStateStore`, so a reply's re-render never resets it. In
/// memory only: nothing here can be encoded, stored or sent.
///
/// The order differs from the cards that predict before they explore: here
/// the walk comes first, and each slot's tap is itself a prediction (a
/// guess, then the model's draw: SLATE.md "Predict, then reveal"). The step
/// question is the card's committed guess; the reveal and "Write it again"
/// wait for it.
@Observable
@MainActor
public final class CitationState {
    public private(set) var walk: CitationWalk
    /// The step question ("At which step did the model decide…?").
    public private(set) var machine: PredictReveal<CitationStepGuess>
    /// "Write it again" was pressed: the second path is shown.
    public private(set) var rewritten = false
    /// How many of the second reference's pieces are written so far (the
    /// view writes them one after another, or all at once under Reduce
    /// Motion). Kept here so a re-render doesn't start them again.
    public var rewriteShown = 0

    /// - Parameters:
    ///   - spoiled: the tutor's text gave the answer away: no step question,
    ///     and the reveal follows the walk.
    ///   - debug: DEBUG's `-InteractiveState` (the shots). For this card
    ///     `explored` is the walk paused at the year, its draw shown (the
    ///     walk is this card's exploring); `predicted` and `revealed` have
    ///     the walk done (the top bar guessed each time) and "The author"
    ///     guessed.
    ///   - rewritten: DEBUG's `-CitationRewritten YES`: done, revealed and
    ///     written again.
    public init(spoiled: Bool, debug: InteractiveDebugState?, rewritten: Bool) {
        let isSpoiled = spoiled || debug == .spoiled
        let choices = CitationStepGuess.allCases
        if rewritten {
            walk = .walked(through: .volumeAndPages, finished: true)
            var machine = PredictReveal.debugStarting(isSpoiled ? .spoiled : .revealed, choices: choices,
                                                      showMeAfter: 0, guess: .author)
            machine.reveal()
            self.machine = machine
            self.rewritten = true
            rewriteShown = CitationContent.slotCount
            return
        }
        switch debug {
        case .explored:
            walk = .walked(through: .year)
            machine = PredictReveal(choices: choices, showMeAfter: 0, spoiled: isSpoiled)
        case .predicted, .revealed:
            walk = .walked(through: .volumeAndPages, finished: true)
            machine = .debugStarting(debug, choices: choices, showMeAfter: 0, spoiled: isSpoiled, guess: .author)
        case .hook, .spoiled, nil:
            walk = CitationWalk()
            machine = PredictReveal(choices: choices, showMeAfter: 0, spoiled: isSpoiled)
        }
    }

    /// The card in a lesson: DEBUG's launch arguments (none in Release).
    public convenience init(spoiled: Bool) {
        self.init(spoiled: spoiled, debug: InteractiveLaunchOptions.current.state,
                  rewritten: CitationDebug.current.rewritten)
    }

    // MARK: What the view asks

    /// The step question shows once the walk is done (never in spoiled
    /// mode).
    public var asksStepQuestion: Bool { walk.finished && machine.asksForPrediction }

    /// "Show me" shows once the step guess is locked, until the reveal.
    public var showsShowMe: Bool { walk.finished && machine.showsShowMe }

    /// The reveal is on screen.
    public var isRevealed: Bool { walk.finished && machine.isRevealed }

    /// "Write it again" works only after the reveal, once.
    public var canRewrite: Bool { isRevealed && !rewritten }

    /// The reveal's lines: the guess (none in spoiled mode) and what
    /// happened.
    public var revealLines: InteractiveRevealLines {
        machine.revealLines(guessText: CitationCopy.choiceTitle, result: CitationCopy.revealResult)
    }

    public var summary: String {
        CitationCopy.accessibilitySummary(walk: walk, guess: machine.guess, revealed: isRevealed,
                                          spoiled: machine.spoiled, rewritten: rewritten)
    }

    // MARK: What the student does

    /// Guesses candidate `index` at the slot on screen; the model's pick is
    /// drawn. Returns what VoiceOver should hear (nil: nothing changed).
    @discardableResult
    public func guess(_ index: Int) -> String? {
        let slot = walk.slot
        guard walk.guess(index) else { return nil }
        return CitationCopy.drawAnnouncement(walk, slot: slot)
    }

    /// "Next piece", or after the fifth "See the finished reference". In
    /// spoiled mode the reveal comes with the finished reference. Returns
    /// what VoiceOver should hear.
    @discardableResult
    public func advance() -> String? {
        guard walk.advance() else { return nil }
        guard walk.finished else { return CitationCopy.stepHeading(walk) }
        if machine.spoiled {
            machine.reveal()
            return CitationCopy.finishedAnnouncement(path: walk.path) + " " + CitationCopy.revealAnnouncement
        }
        return CitationCopy.finishedAnnouncement(path: walk.path)
    }

    /// Locks the step guess (once, after the walk).
    @discardableResult
    public func lock(_ choice: CitationStepGuess) -> Bool {
        guard walk.finished else { return false }
        return machine.lock(choice)
    }

    /// "Show me": the reveal. Returns what VoiceOver should hear.
    @discardableResult
    public func reveal() -> String? {
        guard walk.finished, machine.reveal() else { return nil }
        guard let guess = machine.guess, !machine.spoiled else { return CitationCopy.revealAnnouncement }
        return "\(InteractiveShellCopy.youGuessed) \(CitationCopy.choiceTitle(guess)). \(CitationCopy.revealAnnouncement)"
    }

    /// "Write it again": the second path. Returns what VoiceOver should hear.
    @discardableResult
    public func rewrite() -> String? {
        guard canRewrite else { return nil }
        rewritten = true
        machine.recordMove()
        return CitationCopy.rewriteAnnouncement()
    }
}

/// This card's own DEBUG launch arguments (shots only; a Release build
/// reads none):
///
/// - `-CitationRewritten YES`: the walk done, the reveal shown and "Write
///   it again" pressed (with `-InteractiveState spoiled`, in spoiled mode).
/// - `-CitationAutoplay YES`: from whatever state the card opens in, its
///   next actions play by themselves, about 1.5 s apart (for the reveal
///   clip: `-InteractiveState predicted` then "Show me", then "Write it
///   again"). Never under Reduce Motion.
/// - `-CitationScroll walk|finished|reveal|end`: a moment after the card
///   appears, the list (the lesson's, or the gallery's) scrolls that part
///   of the card into view: the slot being written, the five drawn pieces
///   (with the question and the reveal under them), the reveal, or the
///   card's end.
public struct CitationDebug: Equatable, Sendable {
    public enum Scroll: String, CaseIterable, Sendable {
        case walk, finished, reveal, end
    }

    public var rewritten = false
    public var autoplay = false
    public var scroll: Scroll?

    public init() {}

    /// The options in a launch's arguments (pure, for the tests).
    public init(arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            let raw = arguments[index + 1]
            return raw.hasPrefix("-") ? nil : raw.lowercased()
        }
        func flag(_ name: String) -> Bool {
            guard let raw = value(name) else { return false }
            return raw == "yes" || raw == "true" || raw == "1"
        }
        rewritten = flag("-CitationRewritten")
        autoplay = flag("-CitationAutoplay")
        scroll = value("-CitationScroll").flatMap(Scroll.init(rawValue:))
    }

    public static let current: CitationDebug = {
        #if DEBUG
        return CitationDebug(arguments: ProcessInfo.processInfo.arguments)
        #else
        return CitationDebug()
        #endif
    }()
}
