import Foundation

/// Every line Patch the Reward shows or speaks, on both platforms
/// (docs/interactives/patch-the-reward/CONTENT.md §1 lists them). Numbers
/// in the lines come from the planned runs (`PatchTheRewardContent`), never
/// typed in. The words keep the slate's rule: the boat does what a rule
/// pays for; it never "wants", "cheats" or "tricks".
public enum PatchTheRewardCopy {
    public static let title = "Patch the Reward"
    /// The Mac's compact card.
    public static let compactLine = "Write the rule that pays a toy boat, then see what it does to score."

    // MARK: The hook

    public static let hook = "You\u{2019}re training a boat to win a race. You can only tell it one thing: what earns points."
    /// The lagoon's speed is here as well as in the toy label: rule B's
    /// guess is a fair one only if the student has read it.
    public static let trackLine = "A race is 3 laps of the loop, past gates 1, 2 and 3. Off to the side is a lagoon: open water, where the boat goes fastest, and 3 star targets that come back after they\u{2019}re hit."

    // MARK: Labels (on the canvas)

    /// The slate's label, then the toy's speeds (rule B depends on them).
    public static let toyLabel = InteractiveLabel(
        .toy,
        "A toy we built, not the real game. The boat takes the best-scoring route for your rule, which a computer worked out ahead of time. The 2016 agent learned its loop by trial and error. In the toy, the boat is fastest on the lagoon\u{2019}s open water."
    )
    /// After the reveal: A and B's loopholes are ours, of a documented kind.
    public static let madeUpLabel = InteractiveLabel(
        .madeUp,
        "Loopholes A and B are made up for this toy. DeepMind researchers keep a public list of dozens of real cases of the same kind."
    )
    public static let labels: [InteractiveLabel] = [toyLabel, madeUpLabel]

    // MARK: The 2016 rule

    /// Stands on its own: the tutor's first example may be another case.
    public static let replayRule = "First, a rule like the one a game-playing AI got in 2016: +10 points per target hit."
    public static let playReplay = "Play it"
    public static let playReplayHint = "Runs the boat under this rule"
    public static let replayCaption = "Like the real 2016 CoastRunners agent: lots of points, no finish."

    // MARK: The patches

    public static let goal = "Patch the rule so the boat finishes the race."
    public static let predictPrompt = "Will it finish now?"
    public static let skip = "Skip to the result"
    public static let skipHint = "Shows where the run ends"
    public static let playAgain = "Play it again"
    public static let pickHint = "Shows this rule on the track"
    public static let pickFirst = "Play the 2016 rule first."
    public static let scoring = "It isn\u{2019}t cheating. It\u{2019}s scoring."
    /// Why C worked (it paid for the race itself, which a lap spells out
    /// exactly), and why that doesn't carry over to values: a rule for them
    /// pays for a stand-in, as A and B did. Not "a lap is easy to count":
    /// crossings and metres are as easy to count, and those rules failed.
    public static let takeaway = "Nothing was broken: the boat did exactly what each rule paid for. Rule C worked here because a lap can be spelled out exactly, so the rule could pay for the race itself. \u{201C}Be helpful\u{201D} or \u{201C}be honest\u{201D} can\u{2019}t be spelled out like that, so a rule for them pays for a stand-in, as A and B did, and stand-ins leave gaps."

    // Counters
    public static let pointsTile = "Points"
    public static let lapsTile = "Laps"
    public static func lapsValue(_ laps: Int) -> String { "\(laps) of \(PatchTrack.laps)" }

    /// The rule as written on its chip: "A · +100 every time it crosses
    /// the finish line".
    public static func rule(_ rule: PatchRule) -> String {
        switch rule {
        case .targets: return "+10 per target hit"
        case .finishLine: return "+100 every time it crosses the finish line"
        case .metres: return "+1 for every metre it moves"
        case .orderedLaps: return "+100 for each full lap through gates 1, 2, 3 in order"
        }
    }

    /// "2016" or the patch's letter.
    public static func name(_ rule: PatchRule) -> String {
        rule.letter ?? "2016"
    }

    /// A chip's words: the rule's name and its text.
    public static func chip(_ rule: PatchRule) -> String {
        "\(name(rule)) \u{00B7} \(self.rule(rule))"
    }

    /// The rule for VoiceOver: "Rule A: plus 100 per finish-line crossing".
    public static func spokenRule(_ rule: PatchRule) -> String {
        switch rule {
        case .targets: return "The 2016-style rule: plus 10 per target hit"
        case .finishLine: return "Rule A: plus 100 per finish-line crossing"
        case .metres: return "Rule B: plus 1 per metre moved"
        case .orderedLaps: return "Rule C: plus 100 per full lap through gates 1, 2 and 3 in order"
        }
    }

    /// A chip's VoiceOver label: the rule, and once tried, how it ended.
    public static func chipAccessibility(_ rule: PatchRule, tried: Bool) -> String {
        let run = PatchTheRewardContent.run(rule)
        guard tried else { return spokenRule(rule) + "." }
        return "\(spokenRule(rule)). Tried: \(run.laps) laps."
    }

    /// The chip's words once tried: how it ended ("0 laps", "3 laps").
    public static func chipStatus(_ rule: PatchRule) -> String {
        "\(PatchTheRewardContent.run(rule).laps) laps"
    }

    // MARK: The guesses

    public static func guessChoice(_ guess: PatchGuess) -> String {
        switch guess {
        case .finishes: return "Yes"
        case .doesNotFinish: return "No"
        }
    }

    /// The guess beside the result ("You guessed: It finishes"; the
    /// reveal adds the full stop when it says it).
    public static func guessText(_ guess: PatchGuess) -> String {
        switch guess {
        case .finishes: return "It finishes"
        case .doesNotFinish: return "It won\u{2019}t finish"
        }
    }

    // MARK: Results

    /// What the boat did under `rule`, with the run's own numbers.
    public static func result(_ rule: PatchRule) -> String {
        let run = PatchTheRewardContent.run(rule)
        switch rule {
        case .targets:
            return "It hit \(run.targetsHit) targets, circling the stars, and finished \(run.laps) laps."
        case .finishLine:
            return "It crossed the line \(run.lineCrossings) times, back and forth, and finished \(run.laps) laps."
        case .metres:
            return "It moved \(grouped(run.metres)) metres, round and round the open lagoon where it\u{2019}s fastest, and finished \(run.laps) laps."
        case .orderedLaps:
            return "It went through gates 1, 2 and 3 in order and finished \(run.laps) laps."
        }
    }

    /// The line under a run's result.
    public static func caption(_ rule: PatchRule) -> String {
        switch rule {
        case .targets: return replayCaption
        case .finishLine: return "Crossing the line isn\u{2019}t finishing a lap. " + scoring
        case .metres: return "Moving isn\u{2019}t racing. " + scoring
        case .orderedLaps: return "It finished once the rule spelled out what a lap is. " + shortcutGap
        }
    }

    /// C's second line: "careful once" doesn't close every gap.
    public static let shortcutGap = "Add a shortcut between the gates, and even this rule would have a gap."

    /// A run in one sentence for VoiceOver (the slate's form): "Rule A:
    /// plus 100 per finish-line crossing. The boat crossed the line 30
    /// times, back and forth, and finished 0 laps. 3000 points."
    public static func spokenRun(_ rule: PatchRule) -> String {
        let run = PatchTheRewardContent.run(rule)
        let did: String
        switch rule {
        case .targets:
            did = "The boat hit \(run.targetsHit) targets, circling the stars in the lagoon, and finished \(run.laps) laps."
        case .finishLine:
            did = "The boat crossed the line \(run.lineCrossings) times, back and forth, and finished \(run.laps) laps."
        case .metres:
            did = "The boat moved \(run.metres) metres, round and round the lagoon\u{2019}s open water, where it\u{2019}s fastest, and finished \(run.laps) laps."
        case .orderedLaps:
            did = "The boat went through gates 1, 2 and 3 in order and finished \(run.laps) laps."
        }
        return "\(spokenRule(rule)). \(did) \(run.points) points."
    }

    // MARK: The picture

    /// The track, once, in words (VoiceOver; the picture's label).
    public static let trackDescription = "The toy track, seen from above: a loop with a finish line and gates 1, 2 and 3, and off to the side a lagoon with open water, where the boat goes fastest, and 3 star targets."

    /// The route drawn on the track, in words.
    public static func route(_ rule: PatchRule?) -> String {
        guard let rule else { return "The boat waits on the start line." }
        switch rule {
        case .targets: return "Its route: past gates 1 and 2 into the lagoon, then round and round the 3 stars."
        case .finishLine:
            return "Its route: back and forth over the finish line, \(PatchTheRewardContent.run(.finishLine).lineCrossings) times."
        case .metres: return "Its route: past gates 1 and 2 into the lagoon, then round and round its open water."
        case .orderedLaps: return "Its route: 3 laps, through gates 1, 2 and 3 in order each time."
        }
    }

    /// "The boat is running rule A." (or "the 2016-style rule").
    public static func running(_ rule: PatchRule) -> String {
        "The boat is running \(rule == .targets ? "the 2016-style rule" : "rule \(name(rule))")."
    }

    /// What the picture shows, in words: the run playing, or the route
    /// drawn (the boat on the start line before any run). Written under
    /// the picture at the accessibility text sizes.
    public static func trackCaption(_ rule: PatchRule?, playing: Bool) -> String {
        guard let rule else { return route(nil) }
        return playing ? running(rule) : route(rule)
    }

    /// The picture's VoiceOver label: the track, then the route on it.
    public static func pictureAccessibility(_ rule: PatchRule?, playing: Bool) -> String {
        "\(trackDescription) \(trackCaption(rule, playing: playing))"
    }

    /// "The finish line" under the picture's chequered line; the gates'
    /// numbers are drawn in their discs.
    public static let finishMark = "finish"

    /// The tags on a route's two legs (a still): the way in, then the loop
    /// it repeats. Words, not numbers: the gates are numbered.
    public static let legIn = "in"
    public static let legLoop = "loop"

    /// Beside the double-headed arrow on rule A's still: how many times the
    /// run crossed the line ("\u{00D7}30").
    public static func shuttleTag(_ run: PatchRun) -> String {
        "\u{00D7}\(run.lineCrossings)"
    }

    /// The points a move earned, popped where it earned them while a run
    /// plays ("+100" at the line, "+10" at a star).
    public static func pop(_ points: Int) -> String {
        "+\(points)"
    }

    // MARK: The reveal

    /// "It would finish for 2 of the 3 rules" (no full stop: the reveal adds it).
    public static func overallGuess(_ count: Int) -> String {
        let total = PatchRule.patches.count
        switch count {
        case 0: return "It would finish for none of the \(total) rules"
        case total: return "It would finish for all \(total) rules"
        default: return "It would finish for \(count) of the \(total) rules"
        }
    }

    /// "It finished for 1 of them: rule C." (spoiled: "…for 1 of the 3 rules…")
    public static func overallResult(spoiled: Bool) -> String {
        let finishing = PatchTheRewardContent.finishingPatches
        let names = finishing.map { "rule \(name($0))" }.joined(separator: " and ")
        let of = spoiled ? "of the \(PatchRule.patches.count) rules" : "of them"
        return "It finished for \(finishing.count) \(of): \(names)."
    }

    // MARK: VoiceOver

    /// The card's state in one sentence (the title's value).
    public static func accessibilitySummary(_ state: PatchSummaryState) -> String {
        switch state {
        case .untouched:
            return "Nothing has run yet. First, the 2016-style rule, plus 10 per target hit. Press \(playReplay)."
        case .playing(let rule):
            return "The boat is running. \(spokenRule(rule))."
        case .awaitingGuess(let rule):
            return "\(spokenRule(rule)). \(predictPrompt) Make your guess."
        case .ran(let rule, let tried):
            let left = PatchRule.patches.count - tried
            let more = rule == .targets ? " Now patch the rule: pick A, B or C." : " \(left) of 3 patches left to try."
            return spokenRun(rule) + more
        case .revealed(let guesses, let spoiled):
            let finished = PatchTheRewardContent.finishingPatches.count
            let total = PatchRule.patches.count
            let lead = spoiled ? "" : "You predicted it would finish for \(guesses) of \(total) rules. "
            return lead + "It finished for \(finished) of \(total): \(PatchTheRewardContent.finishingPatches.map { "rule \(name($0))" }.joined(separator: " and "))."
        }
    }

    // MARK: The register

    /// The prediction lines (the only ones that may voice the
    /// misconception; these don't need to).
    public static var predictionLines: [String] {
        [predictPrompt] + PatchGuess.allCases.map(guessChoice) + PatchGuess.allCases.map(guessText) + [scoring]
    }

    /// Every line the card shows or speaks.
    public static var everyLine: [String] {
        var lines = [title, compactLine, hook, trackLine, replayRule, playReplay, playReplayHint, replayCaption, goal,
                     predictPrompt, skip, skipHint, playAgain, pickHint, pickFirst, scoring, takeaway, pointsTile,
                     lapsTile, trackDescription, finishMark, legIn, legLoop, shortcutGap,
                     shuttleTag(PatchTheRewardContent.run(.finishLine)), overallResult(spoiled: false),
                     overallResult(spoiled: true)]
        lines += PatchRule.allCases.flatMap { PatchTheRewardContent.run($0).pops.map { pop($0.points) } }
        lines += labels.map(\.text)
        lines += (0...PatchRule.patches.count).map(overallGuess)
        lines += (0...PatchTrack.laps).map(lapsValue)
        lines += PatchGuess.allCases.flatMap { [guessChoice($0), guessText($0)] }
        lines += [route(nil)]
        for rule in PatchRule.allCases {
            lines += [self.rule(rule), name(rule), chip(rule), spokenRule(rule), chipStatus(rule), result(rule), running(rule),
                      caption(rule), spokenRun(rule), route(rule), chipAccessibility(rule, tried: false),
                      chipAccessibility(rule, tried: true), pictureAccessibility(rule, playing: true),
                      pictureAccessibility(rule, playing: false)]
        }
        lines += PatchSummaryState.examples.map(accessibilitySummary)
        return lines
    }

    /// `number` with a comma every three digits ("1,114"), the same on
    /// every device.
    public static func grouped(_ number: Int) -> String {
        let digits = String(abs(number))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (number < 0 ? "-" : "") + out
    }
}

/// The guess for each patch: will the boat finish the race now?
public enum PatchGuess: String, CaseIterable, Sendable, Hashable {
    case finishes
    case doesNotFinish
}

/// The card's state as its one VoiceOver sentence sees it.
public enum PatchSummaryState: Equatable, Sendable {
    /// Nothing has run.
    case untouched
    /// A run is playing.
    case playing(PatchRule)
    /// A patch is picked; its guess is still to make.
    case awaitingGuess(PatchRule)
    /// The picked rule has run (`tried`: patches run so far).
    case ran(PatchRule, tried: Int)
    /// All three patches have run (`guesses`: how many were guessed to finish).
    case revealed(guesses: Int, spoiled: Bool)

    /// One of each, for the register tests.
    public static var examples: [PatchSummaryState] {
        var all: [PatchSummaryState] = [.untouched, .revealed(guesses: 2, spoiled: false), .revealed(guesses: 0, spoiled: true)]
        for rule in PatchRule.allCases {
            all += [.playing(rule), .awaitingGuess(rule), .ran(rule, tried: 1)]
        }
        return all
    }
}
