import Foundation
import Observation

/// What the student has done with The Page with a Secret, for the open
/// lesson only: the step they are on (`StepThrough`, gated at the page),
/// their guess (`PredictReveal`) and the page's view (the one control).
/// Held by the lesson's `InteractiveStateStore`, so a reply's re-render
/// never resets it. Never `Codable`, never stored or sent.
///
///     step 1 Plan → 2 Act → 3 Observe (the page) ─guess─▶ ─switch─▶ 4 Plan → 5 Act → 6 Observe ⇒ reveal
///
/// - Next walks the run. It can't leave step 3 until a guess is locked AND
///   the page has been switched to what the agent reads at least once: the
///   hidden line is the evidence the reveal points to, so no student
///   reaches the reveal without having seen it.
/// - The toggle ("You see | The agent reads") isn't drawn until the guess
///   is locked (it would hint that the agent reads something else).
/// - Reaching step 6 reveals: the guess beside what happened.
/// - Spoiled mode (the tutor already named the idea): no guess; the card
///   opens at the page with the toggle on, and Next still waits for the
///   switch.
@Observable
@MainActor
public final class PageWithASecretState {
    public typealias Content = PageWithASecretContent

    public private(set) var machine: PredictReveal<Content.Guess>
    public private(set) var steps: StepThrough
    public private(set) var view: Content.PageView = .youSee
    /// The student has switched to the agent's view at least once.
    public private(set) var hasReadAgentView = false

    /// - Parameters:
    ///   - spoiled: open in the spoiled mode (`InteractiveCardContext.spoiled`).
    ///   - debug: DEBUG `-InteractiveState`, reached through the card's real
    ///     transitions (so it is a state a student can reach).
    public init(spoiled: Bool, debug: InteractiveDebugState? = InteractiveLaunchOptions.current.state) {
        let isSpoiled = spoiled || debug == .spoiled
        let count = Content.steps.count
        machine = PredictReveal(choices: Content.Guess.allCases, showMeAfter: 1, spoiled: isSpoiled)
        steps = StepThrough(count: count, start: isSpoiled ? Content.gate : 0, gate: Content.gate)
        apply(debug)
    }

    // MARK: What the view reads

    /// The prediction is on screen: at the page, with no guess yet.
    public var asksNow: Bool { machine.canLock && steps.index == Content.gate }

    /// The toggle is drawn and works (and VoiceOver says the hidden line):
    /// once a guess is locked, or from the start in spoiled mode.
    public var canSwitchView: Bool { machine.canExplore }

    /// The page still has to be switched to what the agent reads before
    /// Next can leave it: the card says so under the chips (or as the
    /// spoiled lead) and in its summary.
    public var mustSwitch: Bool { canSwitchView && !hasReadAgentView }

    public var revealLines: InteractiveRevealLines {
        machine.revealLines(guessText: PageWithASecretCopy.choice, result: PageWithASecretCopy.result)
    }

    public var progress: PageWithASecretProgress {
        PageWithASecretProgress(step: steps.index, view: view, guess: machine.spoiled ? nil : machine.guess,
                                canLock: machine.canLock, revealed: machine.isRevealed,
                                mustSwitch: mustSwitch && steps.index == Content.gate)
    }

    /// What VoiceOver says for the step just reached ("Step 4 of 6: Plan.
    /// New line: …").
    public var stepAnnouncement: String {
        steps.announcement(PageWithASecretCopy.stepSpoken[steps.index])
    }

    // MARK: What the student does

    /// Locks the guess and draws the toggle (Next still waits for the
    /// switch). False once a guess is locked, in spoiled mode, or before the
    /// page.
    @discardableResult
    public func lock(_ guess: Content.Guess) -> Bool {
        guard steps.index == Content.gate, machine.lock(guess) else { return false }
        return true
    }

    /// The next step. Past the page it counts as exploring; the last step
    /// reveals.
    @discardableResult
    public func next() -> Bool {
        guard steps.next() else { return false }
        if steps.index > Content.gate { machine.recordMove() }
        if steps.isLast { machine.reveal() }
        return true
    }

    @discardableResult
    public func back() -> Bool {
        steps.back()
    }

    /// Switches the page's view. False (and nothing changes) before a guess
    /// is locked. The first switch to what the agent reads opens the gate.
    @discardableResult
    public func show(_ newView: Content.PageView) -> Bool {
        guard canSwitchView, newView != view else { return false }
        view = newView
        if newView == .agentReads {
            hasReadAgentView = true
            steps.openGate()
        }
        machine.recordMove()
        return true
    }

    // MARK: DEBUG states (shots)

    private func apply(_ debug: InteractiveDebugState?) {
        guard let debug, debug != .hook, debug != .spoiled else { return }
        while steps.index < Content.gate { next() }
        lock(Content.Guess.allCases[0])
        guard debug != .predicted else { return }
        show(.agentReads)
        next()
        guard debug == .revealed else { return }
        while !steps.isLast { next() }
    }
}
