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

    /// The slate's on-canvas label, word for word.
    public static let feedLabel = InteractiveLabel(
        .madeUp, "A made-up feed. Here the dial judges by how surprising a post looks. Real checking is messier."
    )
    /// Under "Check first": the findings are authored too.
    public static let checkLabel = InteractiveLabel(.madeUp, "These checks are made up too, like the feed.")

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
    /// The five stops, least doubt first.
    public static let stops = ["Believe everything", "Believe most", "Unsure", "Doubt most", "Doubt everything"]
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

    /// What happened, beside the guess.
    public static func result(for guess: DoubtDialGuess) -> String {
        let posts = DoubtDialContent.postCount
        switch guess {
        case .believeEverything:
            let tally = DoubtDialContent.tally(atStop: DoubtDialContent.stops(for: .believeEverything)[0])
            return "It shared \(fakesPhrase(tally.fakesShared)), and waved away \(realPhrase(tally.realWavedAway)). "
                + "No setting got below \(DoubtDialContent.fewestMistakes) mistakes out of \(posts)."
        case .middle:
            let middle = DoubtDialContent.stops(for: .middle).map { DoubtDialContent.mistakesByStop[$0] }
            let fewest = middle.min() ?? 0
            let made = Set(middle).count == 1 ? "\(fewest)" : "at least \(fewest)"
            return "Every setting in the middle still made \(made) mistakes out of \(posts). "
                + "Turning the dial only moved your mistakes around."
        case .doubtEverything:
            let tally = DoubtDialContent.tally(atStop: DoubtDialContent.stops(for: .doubtEverything)[0])
            return "It shared \(fakesPhrase(tally.fakesShared)), and waved away \(realPhrase(tally.realWavedAway)). "
                + "That\u{2019}s exactly what someone hiding a real story would want."
        }
    }

    /// What happened, with no guess (the spoiled mode).
    public static var spoiledResult: String {
        let tally = DoubtDialContent.tally(atStop: DoubtDialContent.stops(for: .doubtEverything)[0])
        return "No setting got below \(DoubtDialContent.fewestMistakes) mistakes out of \(DoubtDialContent.postCount). "
            + "Doubt everything shared \(fakesPhrase(tally.fakesShared)), "
            + "and waved away \(realPhrase(tally.realWavedAway))."
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

    public static let takeaway = "Doubt alone can\u{2019}t sort them. Checking can, and \u{201C}not sure yet\u{201D} is an honest answer."

    // MARK: The feed

    public static let feedTitle = "The feed"
    public static let feedOrder = "Least surprising first."
    public static let sharedColumn = "Shared"
    public static let wavedAwayColumn = "Waved away"
    public static let notSharedColumn = "Not shared"
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
                     feedOrder, sharedColumn, wavedAwayColumn, notSharedColumn, emptyColumn, realTag, fakeTag, whatChecking,
                     mistakeTag, mistakeSpoken]
        lines += labels.map(\.text)
        lines += DoubtDialGuess.allCases.flatMap { [guessTitle($0), result(for: $0)] }
        lines += stops
        lines += stopIndices.flatMap { [rule(atStop: $0), dialValue(atStop: $0), mistakesLine(atStop: $0)] }
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
        let checked = DoubtDialContent.sharedCount(atStop: 0, checking: true)
        columns += [(sharedColumn, checked), (notSharedColumn, total - checked)]
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
