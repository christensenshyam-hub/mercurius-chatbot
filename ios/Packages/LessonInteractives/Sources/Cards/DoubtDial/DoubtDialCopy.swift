import Foundation

/// Every line The Doubt Dial shows or speaks, on the iPhone and the Mac
/// (docs/interactives/doubt-dial/CONTENT.md lists them for review). Every
/// number in a line is counted from `DoubtDialContent`, never typed in, so
/// `DoubtDialTests` can hold each one to the authored data. The card never
/// says "liar's dividend": the tutor names it in the next reply.
public enum DoubtDialCopy {
    public static let title = "The Doubt Dial"

    /// The Mac's compact "Try it" card.
    public static let compactLine = "Turn a dial from believing everything to doubting everything, and count the mistakes in a made-up feed."

    // MARK: The hook and the labels

    public static var hook: String {
        "\(spelled(DoubtDialContent.postCount)) posts about the made-up town of \(DoubtDialContent.town): "
            + "\(DoubtDialContent.realCount) are real and \(DoubtDialContent.fakeCount) are fake. "
            + "We wrote them all, so we know which."
    }

    public static var dotsLine: String {
        "The dots show how surprising each post looks, from 1 to \(DoubtDialContent.maxSurprise)."
    }

    /// The slate's on-canvas label, reworded after review (CONTENT.md
    /// "Departures from the slate"): the feed is made up and half fake on
    /// purpose, and the dial judges only by surprise. Saying "real checking
    /// is messier" here, before checking is shown, made the dial read as a
    /// simple kind of checking; that caveat now sits under "Check first".
    public static let feedLabel = InteractiveLabel(
        .madeUp, "A made-up feed. Real feeds aren\u{2019}t half fake. The dial judges only by how surprising a post looks."
    )
    /// Under "Check first": the findings are authored too, and real
    /// checking is messier.
    public static let checkLabel = InteractiveLabel(
        .madeUp, "These checks are made up too, like the feed. Real checking is messier."
    )

    public static let labels: [InteractiveLabel] = [feedLabel, checkLabel]

    // MARK: Predict

    public static let predictPrompt = "Which setting will fool you least?"

    public static func guessTitle(_ guess: DoubtDialGuess) -> String {
        switch guess {
        case .believeEverything: return "Believe everything"
        case .middle: return "Somewhere in the middle"
        case .doubtEverything: return "Doubt everything"
        }
    }

    // MARK: The dial

    /// The dial's visible name.
    public static let dialName = "How much doubt?"
    /// What VoiceOver calls the dial.
    public static let dialAccessibilityName = "Doubt dial"
    /// The five stops, least doubt first. The centre stop is "In the
    /// middle" (the slate's "Unsure"): it makes firm calls like every stop,
    /// and "not sure yet" belongs to checking alone.
    public static let stops = ["Believe everything", "Believe most", "In the middle", "Doubt most", "Doubt everything"]
    /// The step buttons at the accessibility sizes.
    public static let lessDoubt = "Less doubt"
    public static let moreDoubt = "More doubt"
    /// After the guess, before "Show me".
    public static let turnPrompt = "Turn the dial and watch both counters."

    /// What the stop does, from its limit: "Shares posts with up to 3 dots.
    /// Waves away the rest."
    public static func rule(atStop stop: Int) -> String {
        let limit = DoubtDialContent.stopLimits[DoubtDialContent.clamped(stop)]
        if limit >= DoubtDialContent.maxSurprise { return "Shares every post." }
        if limit <= 0 { return "Waves away every post." }
        if limit == 1 { return "Shares only posts with 1 dot. Waves away the rest." }
        return "Shares posts with up to \(limit) dots. Waves away the rest."
    }

    /// What VoiceOver says at a stop: "Doubt everything. You'd share 0
    /// fakes and wave away 5 real stories."
    public static func dialValue(atStop stop: Int) -> String {
        let tally = DoubtDialContent.tally(atStop: stop)
        return "\(stopName(stop)). You\u{2019}d share \(count(tally.fakesShared, "fake", "fakes")) "
            + "and wave away \(count(tally.realWavedAway, "real story", "real stories"))."
    }

    public static func stopName(_ stop: Int) -> String { stops[DoubtDialContent.clamped(stop)] }

    // MARK: The counters

    public static let fakesSharedLabel = "Fakes you\u{2019}d share"
    public static let realWavedAwayLabel = "Real stories you\u{2019}d wave away"
    /// After "Check first".
    public static let checkedFakesLabel = "Fakes shared"
    public static let checkedRealLabel = "Real stories waved away"
    public static let notSureYetLabel = "Not sure yet"

    /// Under the counters: "4 mistakes out of 10 at this setting."
    public static func mistakesLine(atStop stop: Int) -> String {
        "\(count(DoubtDialContent.tally(atStop: stop).mistakes, "mistake", "mistakes")) out of "
            + "\(DoubtDialContent.postCount) at this setting."
    }

    // MARK: The reveal

    /// What happened, beside the guess. "Show me" turns the dial to the
    /// setting it names (`DoubtDialContent.revealStop`), so the counters
    /// beside it agree; each line names its setting rather than "it", so
    /// it stays true if the student turns the dial on.
    public static func result(for guess: DoubtDialGuess) -> String {
        switch guess {
        case .believeEverything:
            return "\(endLine(.believeEverything)) \(floorLine)"
        case .middle:
            let made = DoubtDialContent.middleMistakes.map { "\($0)" }
                ?? "at least \(DoubtDialContent.fewestMistakes)"
            let verdict = DoubtDialContent.middleBeatsTheEnds
                ? "You\u{2019}re right: the middle fooled you least. But even there"
                : "The middle didn\u{2019}t do better than the ends. Even there"
            let within = DoubtDialContent.middleMistakes == nil ? ""
                : ", and moving within the middle only swapped one kind of mistake for the other"
            return "\(verdict) it made \(made) mistakes out of \(DoubtDialContent.postCount)\(within)."
        case .doubtEverything:
            return "\(endLine(.doubtEverything)) "
                + "That\u{2019}s just what someone caught in a real story would want: everyone calling it fake. "
                + floorLine
        }
    }

    /// What happened, with no guess (the spoiled mode; "Show me" turns the
    /// dial to Doubt everything, the setting it names).
    public static var spoiledResult: String {
        "\(endLine(.doubtEverything)) \(floorLine)"
    }

    /// One end of the dial, its mistakes counted and set beside the other
    /// end's: "Doubt everything never shared a fake, but it waved away all
    /// 5 real stories: 5 mistakes, the same as believing everything."
    static func endLine(_ end: DoubtDialGuess) -> String {
        // The two ends (a middle guess has no end line; it reads as doubt).
        let stop = end == .believeEverything ? 0 : DoubtDialContent.stopLimits.count - 1
        let tally = DoubtDialContent.tally(atStop: stop)
        let mistakes = count(tally.mistakes, "mistake", "mistakes")
        let tie = DoubtDialContent.endMistakes == nil ? "" : (end == .believeEverything
            ? ", the same as doubting everything" : ", the same as believing everything")
        if end == .believeEverything {
            let real = tally.realWavedAway == 0 ? "never waved away a real story"
                : "waved away \(realPhrase(tally.realWavedAway))"
            return "\(stopName(stop)) \(real), but it shared \(fakesPhrase(tally.fakesShared)): \(mistakes)\(tie)."
        }
        let fakes = tally.fakesShared == 0 ? "never shared a fake" : "shared \(fakesPhrase(tally.fakesShared))"
        return "\(stopName(stop)) \(fakes), but it waved away \(realPhrase(tally.realWavedAway)): \(mistakes)\(tie)."
    }

    /// "The middle did a little better, but no setting got below 4
    /// mistakes out of 10."
    static var floorLine: String {
        let better = DoubtDialContent.middleBeatsTheEnds ? "The middle did a little better, but no" : "No"
        return "\(better) setting got below \(DoubtDialContent.fewestMistakes) mistakes out of \(DoubtDialContent.postCount)."
    }

    /// The row under the dial once revealed.
    public static var mistakesRowTitle: String { "Mistakes out of \(DoubtDialContent.postCount) at each setting" }

    /// The row in one sentence (VoiceOver, and the accessibility sizes'
    /// text): "Believe everything: 5 mistakes. Believe most: 4 mistakes. …"
    public static var mistakesRowSpoken: String {
        "\(mistakesRowTitle). "
            + DoubtDialContent.mistakesByStop.enumerated()
            .map { "\(stopName($0.offset)): \(mistakesCell($0.element))" }
            .joined(separator: ". ") + "."
    }

    public static func mistakesCell(_ mistakes: Int) -> String { count(mistakes, "mistake", "mistakes") }

    // MARK: Check first

    public static let checkIntro = "The dial only looks at how surprising a post seems. "
        + "Checking looks at where it came from, and who else reports it."
    public static let checkFirst = "Check first"
    public static let checkHint = "Shows what checking found for each post"
    public static let backToDial = "Back to the dial"
    public static let backHint = "Shows what the dial does with each post again"

    /// "0 fakes shared, 0 real stories waved away, 2 not sure yet."
    public static var checkTallyLine: String {
        let tally = DoubtDialContent.checkTally
        return "\(count(tally.fakesShared, "fake", "fakes")) shared, "
            + "\(count(tally.realWavedAway, "real story", "real stories")) waved away, "
            + "\(tally.notSureYet) not sure yet."
    }

    /// What checking did, reported rather than ruled: "Checking sorted 8 of
    /// 10, and was honest about the other 2: not sure yet." (The general
    /// rule is the lesson's exercise for the student to state.)
    public static var takeaway: String {
        "Checking sorted \(DoubtDialContent.checkSettled) of \(DoubtDialContent.postCount), "
            + "and was honest about the other \(DoubtDialContent.checkTally.notSureYet): not sure yet."
    }

    // MARK: The feed

    public static let feedTitle = "The feed"
    public static let feedOrder = "Least surprising first."
    public static let sharedColumn = "Shared"
    public static let wavedAwayColumn = "Waved away"
    public static let notSharedColumn = "Not shared"
    /// The Mac's checking group for the posts held back.
    public static let notSureYetColumn = "Not sure yet"
    /// A Mac column with nothing in it at this setting.
    public static let emptyColumn = "No posts at this setting."
    public static let realTag = "Real"
    public static let fakeTag = "Fake"
    public static let whatChecking = "What checking found"
    /// Beside a post the setting got wrong (a fake shared, a real story
    /// waved away): the counters' posts, marked one by one.
    public static let mistakeTag = "Mistake"
    public static let mistakeSpoken = "A mistake"

    public static func tag(_ post: DoubtDialPost) -> String { post.isReal ? realTag : fakeTag }

    // MARK: The strip under the dial

    /// A post's letter in the strip: R (real) or F (fake).
    public static func stripLetter(_ post: DoubtDialPost) -> String { post.isReal ? "R" : "F" }
    /// The strip's key, drawn with the glyphs between: "R real · F fake ·
    /// ↗ shared · ⊘ waved away · ✕ a mistake".
    public static let stripKeyLetters = "R real \u{00B7} F fake"
    public static let stripKeyShared = "shared"
    public static let stripKeyWavedAway = "waved away"
    public static let stripKeyMistake = "a mistake"

    /// The strip in words (its VoiceOver line, and its text form at the
    /// accessibility sizes): "Mistakes at this setting: School board, Water
    /// tower (fakes shared); Seal, Bridge (real stories waved away)."
    public static func mistakesHere(atStop stop: Int) -> String {
        let wrong = DoubtDialContent.mistakes(atStop: stop, checking: false)
        let fakes = wrong.filter { !$0.isReal }.map(\.shortName)
        let real = wrong.filter(\.isReal).map(\.shortName)
        var groups: [String] = []
        if !fakes.isEmpty {
            groups.append("\(fakes.joined(separator: ", ")) (\(fakes.count == 1 ? "fake shared" : "fakes shared"))")
        }
        if !real.isEmpty {
            groups.append("\(real.joined(separator: ", ")) "
                          + "(\(real.count == 1 ? "real story waved away" : "real stories waved away"))")
        }
        return groups.isEmpty ? "No mistakes at this setting." : "Mistakes at this setting: \(groups.joined(separator: "; "))."
    }

    /// The Mac's header for one of checking's groups.
    public static func checkColumn(_ verdict: DoubtDialVerdict) -> String {
        switch verdict {
        case .shared: return sharedColumn
        case .notSureYet: return notSureYetColumn
        case .notShared, .wavedAway: return notSharedColumn
        }
    }

    /// A column's header with its count: "Shared · 7".
    public static func column(_ name: String, count: Int) -> String { "\(name) \u{00B7} \(count)" }
    public static func columnSpoken(_ name: String, count: Int) -> String {
        "\(name): \(self.count(count, "post", "posts"))"
    }

    /// The word beside a post's glyph.
    public static func verdictWord(_ verdict: DoubtDialVerdict) -> String {
        switch verdict {
        case .shared: return "Shared"
        case .wavedAway: return "Waved away"
        case .notShared: return "Not shared"
        case .notSureYet: return "Not sure yet"
        }
    }

    /// The verdict as VoiceOver says it.
    public static func verdictSpoken(_ verdict: DoubtDialVerdict) -> String {
        verdict == .notSureYet ? "Not sure yet, so don\u{2019}t share yet" : verdictWord(verdict)
    }

    public static func surpriseSpoken(_ surprise: Int) -> String {
        "Surprise \(surprise) of \(DoubtDialContent.maxSurprise)"
    }

    /// A post at the accessibility sizes, under its title: "Real ·
    /// surprise 4 of 5 · Waved away · Mistake".
    public static func postTextLine(_ post: DoubtDialPost, verdict: DoubtDialVerdict?) -> String {
        var parts = [tag(post), surpriseSpoken(post.surprise).lowercased()]
        if let verdict {
            parts.append(verdictWord(verdict))
            if DoubtDialContent.isMistake(post, verdict) { parts.append(mistakeTag) }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// A post for VoiceOver: "A seal naps on the ferry dock, and the ferry
    /// waits. Real. Surprise 4 of 5. Waved away. A mistake."
    public static func postAccessibility(_ post: DoubtDialPost, verdict: DoubtDialVerdict?, checking: Bool) -> String {
        var parts = [post.title, tag(post), surpriseSpoken(post.surprise)]
        if let verdict {
            parts.append(verdictSpoken(verdict))
            if DoubtDialContent.isMistake(post, verdict) { parts.append(mistakeSpoken) }
        }
        if checking { parts.append("\(whatChecking): \(post.checkLine)") }
        return parts.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: ". ") + "."
    }

    // MARK: VoiceOver

    /// The card's state in one sentence (the title's value).
    public enum Mode: Equatable, Sendable {
        /// No guess yet: the dial is off.
        case hook
        /// The dial at a stop.
        case dial(Int)
        /// After "Check first".
        case checked
    }

    public static func accessibilitySummary(_ mode: Mode) -> String {
        switch mode {
        case .hook:
            return "\(spelled(DoubtDialContent.postCount)) made-up posts, \(DoubtDialContent.realCount) real and "
                + "\(DoubtDialContent.fakeCount) fake. Make your guess, then turn the dial."
        case .dial(let stop):
            return dialValue(atStop: stop)
        case .checked:
            return "\(checkFirst): \(checkTallyLine)"
        }
    }

    // MARK: Every line

    /// The prediction and its choices (the only lines that may voice a
    /// misconception; none uses an intent word).
    public static var predictionLines: [String] {
        [predictPrompt] + DoubtDialGuess.allCases.map(guessTitle)
    }

    /// Every line the card shows or speaks, for the register tests.
    public static var everyLine: [String] {
        let stopIndices = Array(stops.indices)
        let posts = DoubtDialContent.posts
        let verdicts: [DoubtDialVerdict?] = [nil, .shared, .wavedAway, .notShared, .notSureYet]
        var lines = [title, compactLine, hook, dotsLine, predictPrompt, dialName, dialAccessibilityName,
                     lessDoubt, moreDoubt, turnPrompt, fakesSharedLabel, realWavedAwayLabel, checkedFakesLabel,
                     checkedRealLabel, notSureYetLabel, spoiledResult, mistakesRowTitle, mistakesRowSpoken,
                     checkIntro, checkFirst, checkHint, backToDial, backHint, checkTallyLine, takeaway, feedTitle,
                     feedOrder, sharedColumn, wavedAwayColumn, notSharedColumn, notSureYetColumn, emptyColumn, realTag,
                     fakeTag, whatChecking, mistakeTag, mistakeSpoken, stripKeyLetters, stripKeyShared, stripKeyWavedAway,
                     stripKeyMistake, "R", "F"]
        lines += labels.map(\.text)
        lines += DoubtDialGuess.allCases.flatMap { [guessTitle($0), result(for: $0)] }
        lines += stops
        lines += stopIndices.flatMap {
            [rule(atStop: $0), dialValue(atStop: $0), mistakesLine(atStop: $0), mistakesHere(atStop: $0)]
        }
        lines += DoubtDialContent.mistakesByStop.map(mistakesCell)
        lines += [Mode.hook, .checked].map(accessibilitySummary) + stopIndices.map { accessibilitySummary(.dial($0)) }
        lines += [DoubtDialVerdict.shared, .wavedAway, .notShared, .notSureYet].flatMap { [verdictWord($0), verdictSpoken($0)] }
        for post in posts {
            lines += [post.title, post.checkLine, surpriseSpoken(post.surprise)]
            for verdict in verdicts {
                lines.append(postTextLine(post, verdict: verdict))
                lines.append(postAccessibility(post, verdict: verdict, checking: false))
                lines.append(postAccessibility(post, verdict: verdict, checking: true))
            }
        }
        // The Mac's column headers, with the counts they can show.
        let total = DoubtDialContent.postCount
        var columns = stopIndices.flatMap { stop -> [(String, Int)] in
            let shared = DoubtDialContent.sharedCount(atStop: stop, checking: false)
            return [(sharedColumn, shared), (wavedAwayColumn, total - shared)]
        }
        columns += DoubtDialContent.checkGroups.map { (checkColumn($0.verdict), $0.posts.count) }
        lines += columns.flatMap { [column($0.0, count: $0.1), columnSpoken($0.0, count: $0.1)] }
        return lines
    }

    // MARK: Words for counts

    /// A count that starts a sentence, in words ("Ten"); digits past ten.
    static func spelled(_ number: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        return words.indices.contains(number) ? words[number] : "\(number)"
    }

    /// "1 fake", "3 fakes".
    static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    /// "no fakes", "all 5 fakes", "3 fakes".
    static func fakesPhrase(_ number: Int) -> String {
        if number == 0 { return "no fakes" }
        if number == DoubtDialContent.fakeCount { return "all \(number) fakes" }
        return count(number, "fake", "fakes")
    }

    /// "no real stories", "all 5 real stories", "1 real story".
    static func realPhrase(_ number: Int) -> String {
        if number == 0 { return "no real stories" }
        if number == DoubtDialContent.realCount { return "all \(number) real stories" }
        return count(number, "real story", "real stories")
    }
}
