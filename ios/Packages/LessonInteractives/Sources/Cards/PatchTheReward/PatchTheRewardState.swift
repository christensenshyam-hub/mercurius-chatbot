import Foundation
import Observation

/// A run playing on the track: which rule, and when it started.
public struct PatchPlayback: Equatable, Sendable {
    public let rule: PatchRule
    public let started: Date
    let id: Int
    /// DEBUG shots (`-PatchRewardFreezeTick`): the run holds at this tick.
    let frozenTick: Double?

    /// The race clock's tick at `date`.
    public func tick(at date: Date) -> Double {
        if let frozenTick { return frozenTick }
        return PatchTheRewardContent.tick(afterPlaying: date.timeIntervalSince(started))
    }
}

/// What the student has done with Patch the Reward, for the open lesson
/// (kept in the lesson's `InteractiveStateStore`, in memory only, never
/// `Codable`): whether the 2016-style rule has run, which rule is picked,
/// each patch's guess and run (one `PredictReveal` per patch), and the run
/// playing now.
///
/// The flow (SLATE.md §5): the 2016-style rule plays first; then each patch
/// asks "Will it finish now?" before it runs (spoiled mode: no guess, it
/// runs at once); once all three have run, the reveal sets the guesses
/// beside what happened.
@Observable
@MainActor
public final class PatchTheRewardState {
    public let spoiled: Bool
    /// The 2016-style rule has run (the patches open after it).
    public private(set) var replayed = false
    /// The rule whose chip is picked.
    public private(set) var selected: PatchRule = .targets
    /// Each patch's guess and run.
    public private(set) var machines: [PatchRule: PredictReveal<PatchGuess>]
    /// The run playing now (nil when none is, and always under Reduce Motion).
    public private(set) var playing: PatchPlayback?
    /// Bumped each time a run ends (played out, skipped, or shown at once):
    /// a view announces the result on it.
    public private(set) var finishedRuns = 0
    /// The rule whose run ended last.
    public private(set) var lastFinished: PatchRule?
    /// The run (`finishedRuns`) that brought the reveal: a view says the
    /// reveal with that run's result, and not again on a replay.
    public private(set) var revealedOnRun: Int?

    @ObservationIgnored private var playID = 0
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(spoiled: Bool, debug: InteractiveDebugState? = InteractiveLaunchOptions.current.state) {
        let isSpoiled = spoiled || debug == .spoiled
        self.spoiled = isSpoiled
        var machines: [PatchRule: PredictReveal<PatchGuess>] = [:]
        for rule in PatchRule.patches {
            machines[rule] = PredictReveal(choices: PatchGuess.allCases, showMeAfter: 1, spoiled: isSpoiled)
        }
        self.machines = machines
        if let debug { start(at: debug) }
    }

    // MARK: Reading

    /// A patch's guess and run (nil for the 2016-style rule, which has no guess).
    public func machine(_ rule: PatchRule) -> PredictReveal<PatchGuess>? { machines[rule] }

    /// Whether `rule`'s run has ended at least once.
    public func hasRun(_ rule: PatchRule) -> Bool {
        rule == .targets ? replayed : (machines[rule]?.isRevealed ?? false)
    }

    /// The 2016-style rule always takes a pick; a patch once that rule has run.
    public func canPick(_ rule: PatchRule) -> Bool { rule == .targets || replayed }

    /// How many patches have run.
    public var triedCount: Int { PatchRule.patches.filter(hasRun).count }

    /// All three patches have run: the reveal shows.
    public var isRevealed: Bool { triedCount == PatchRule.patches.count }

    /// How many patches the student guessed would finish.
    public var guessesFinish: Int { PatchRule.patches.filter { machines[$0]?.guess == .finishes }.count }

    /// The rule on the track: the one playing, else the picked one once it
    /// has run (nil: the boat waits on the start line).
    public var shownRule: PatchRule? { playing?.rule ?? (hasRun(selected) ? selected : nil) }

    /// The picked patch waits for its guess.
    public var awaitsGuess: Bool {
        selected != .targets && playing == nil && (machines[selected]?.canLock ?? false)
    }

    /// The patches' rules on the reveal: the guess (nil in spoiled mode)
    /// beside what happened.
    public func revealLines(_ rule: PatchRule) -> InteractiveRevealLines {
        let result = PatchTheRewardCopy.result(rule)
        guard let machine = machines[rule] else { return InteractiveRevealLines(guess: nil, result: result) }
        return machine.revealLines(guessText: PatchTheRewardCopy.guessText, result: result)
    }

    /// The overall reveal, once all three patches have run.
    public var overallReveal: InteractiveRevealLines? {
        guard isRevealed else { return nil }
        return InteractiveRevealLines(guess: spoiled ? nil : PatchTheRewardCopy.overallGuess(guessesFinish),
                                      result: PatchTheRewardCopy.overallResult(spoiled: spoiled))
    }

    /// The card's state, for its one VoiceOver sentence.
    public var summaryState: PatchSummaryState {
        if let playing { return .playing(playing.rule) }
        if isRevealed { return .revealed(guesses: guessesFinish, spoiled: spoiled) }
        if awaitsGuess { return .awaitingGuess(selected) }
        if hasRun(selected) { return .ran(selected, tried: triedCount) }
        return .untouched
    }

    // MARK: Acting

    /// A rule's chip. Picking another rule shows it (a patch not yet run
    /// asks for its guess, or in spoiled mode runs at once; the 2016-style
    /// rule runs if it hasn't). The picked rule, picked again, plays again.
    /// A run still playing ends first (its own chip only ends it).
    public func pick(_ rule: PatchRule, animated: Bool) {
        guard canPick(rule) else { return }
        if let playing {
            skip()
            if playing.rule == rule { return }
        }
        if rule == selected {
            if hasRun(rule) || rule == .targets || spoiled { play(rule, animated: animated) }
            return
        }
        selected = rule
        if !hasRun(rule) && (rule == .targets || spoiled) { play(rule, animated: animated) }
    }

    /// The Mac's ←/→ on a rule's chip: the rule before or after `rule` that
    /// takes a pick (nil at either end). The arrow picks it, as a click does.
    public func neighbour(of rule: PatchRule, _ arrow: InteractiveArrow) -> PatchRule? {
        let all = PatchRule.allCases
        guard let index = all.firstIndex(of: rule) else { return nil }
        let next = index + (arrow == .next ? 1 : -1)
        guard all.indices.contains(next), canPick(all[next]) else { return nil }
        return all[next]
    }

    /// The picked patch's guess: locks it in, then runs the patch.
    public func lock(_ guess: PatchGuess, animated: Bool) {
        guard selected != .targets, var machine = machines[selected], machine.lock(guess) else { return }
        machines[selected] = machine
        play(selected, animated: animated)
    }

    /// Runs `rule`: plays it on the track (`animated`), or shows where it
    /// ends at once (Reduce Motion, or a test). A patch runs only once its
    /// guess is in (or in spoiled mode).
    public func play(_ rule: PatchRule, animated: Bool, frozenAt frozenTick: Double? = nil) {
        if rule != .targets {
            guard var machine = machines[rule], machine.recordMove() else { return }
            machines[rule] = machine
        }
        if playing != nil { skip() }
        selected = rule
        playID += 1
        guard animated else {
            end(rule)
            return
        }
        let id = playID
        playing = PatchPlayback(rule: rule, started: Date(), id: id, frozenTick: frozenTick)
        timer?.cancel()
        guard frozenTick == nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PatchTheRewardContent.playDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.endPlaying(id)
        }
    }

    /// Ends the run playing now: its result shows at once.
    public func skip() {
        guard let playing else { return }
        endPlaying(playing.id)
    }

    private func endPlaying(_ id: Int) {
        guard let playing, playing.id == id else { return }
        timer?.cancel()
        timer = nil
        self.playing = nil
        end(playing.rule)
    }

    private func end(_ rule: PatchRule) {
        if rule == .targets {
            replayed = true
        } else if var machine = machines[rule] {
            machine.reveal()
            machines[rule] = machine
        }
        lastFinished = rule
        finishedRuns += 1
        if revealedOnRun == nil && isRevealed { revealedOnRun = finishedRuns }
    }

    // MARK: DEBUG shots

    /// The state `-InteractiveState` asks for, reached through the real
    /// actions (each run shown at once): `predicted` has the 2016-style rule
    /// run and A picked, its guess waiting; `explored` has A ("It
    /// finishes.") and B ("It won't finish.") run; `revealed` adds C ("It
    /// finishes."), so the reveal reads "2 of the 3 rules"; `spoiled` is
    /// untouched in spoiled mode.
    private func start(at debug: InteractiveDebugState) {
        guard debug != .hook && debug != .spoiled else { return }
        play(.targets, animated: false)
        pick(.finishLine, animated: false)
        guard debug != .predicted else { return }
        lock(.finishes, animated: false)
        pick(.metres, animated: false)
        lock(.doesNotFinish, animated: false)
        guard debug == .revealed else { return }
        pick(.orderedLaps, animated: false)
        lock(.finishes, animated: false)
    }

    #if DEBUG
    /// `-PatchRewardAutoRun 2016|a|b|c` (+ `-PatchRewardAutoRunDelay <s>`,
    /// default 1.5): a while after the card appears, run that rule once as a
    /// tap would (a patch with the guess "It finishes."), for the motion
    /// clip; simctl can't tap. `-PatchRewardFreezeTick <n>` holds the run at
    /// that tick, for a still of the boat and its wake.
    public func debugAutoRun(animated: Bool) async {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard !Self.debugAutoRunDone, let raw = value("-PatchRewardAutoRun")?.lowercased() else { return }
        let rules: [String: PatchRule] = ["2016": .targets, "a": .finishLine, "b": .metres, "c": .orderedLaps]
        guard let rule = rules[raw] else { return }
        Self.debugAutoRunDone = true
        let freeze = value("-PatchRewardFreezeTick").flatMap(Double.init)
        let delay = value("-PatchRewardAutoRunDelay").flatMap(Double.init) ?? (freeze == nil ? 1.5 : 0)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if rule == .targets && !replayed {
            play(.targets, animated: animated, frozenAt: freeze)
            return
        }
        if !replayed { play(.targets, animated: false) }
        if selected != rule { pick(rule, animated: false) }
        if var machine = machines[rule], machine.lock(.finishes) {
            machines[rule] = machine
        }
        play(rule, animated: animated, frozenAt: freeze)
    }

    private static var debugAutoRunDone = false
    #endif
}
