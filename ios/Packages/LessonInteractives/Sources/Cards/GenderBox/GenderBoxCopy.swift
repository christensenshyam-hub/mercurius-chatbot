import Foundation

/// The prediction's choices: will the résumé with "women's" still score
/// lower once the gender box is deleted?
public enum GenderBoxGuess: String, CaseIterable, Sendable, Hashable {
    case stillLower
    case higher
    case tie
}

/// Every line Delete the Gender Box shows or speaks, on both platforms
/// (docs/interactives/delete-the-gender-box/CONTENT.md lists them). Every
/// number in them comes from `GenderBoxContent`, which computes it from the
/// authored rows; `GenderBoxTests` holds the words to the register and the
/// numbers to the slate's.
public enum GenderBoxCopy {
    public static let title = "Delete the Gender Box"

    /// The Mac's compact card (narrower than 440 pt).
    public static let compactLine = "A toy r\u{E9}sum\u{E9} scorer: delete its gender box, and see what \u{201C}women\u{2019}s\u{201D} does."

    // MARK: The hook (the audit role)

    public static var hook: String {
        let c = GenderBoxContent.self
        return "You\u{2019}re checking a r\u{E9}sum\u{E9} scorer: a toy we built, not Amazon\u{2019}s. It learned from "
            + "\(c.resumes.count) made-up past r\u{E9}sum\u{E9}s and who got hired: \(c.menHired) of \(c.men.count) men, "
            + "\(c.womenHired) of \(c.women.count) women."
    }

    // MARK: Labels (on the canvas)

    /// The slate's on-card label.
    public static let toyLabel = InteractiveLabel(
        .toy,
        "A toy we built from made-up r\u{E9}sum\u{E9}s. Amazon\u{2019}s real tool was never published, and this isn\u{2019}t how it worked."
    )
    /// Under the weights: the numbers are the toy's real fit, and real tools
    /// learn from far more (the slate's accuracy note).
    public static var arithmeticLabel: InteractiveLabel {
        InteractiveLabel(.ourArithmetic, "Weights and scores: our arithmetic, from fitting the toy to these "
                         + "\(GenderBoxContent.resumes.count) r\u{E9}sum\u{E9}s. Real scorers learn from far more.")
    }

    public static var labels: [InteractiveLabel] { [toyLabel, arithmeticLabel] }

    // MARK: The past résumés

    public static var pastHeading: String { "The \(GenderBoxContent.resumes.count) past r\u{E9}sum\u{E9}s" }

    /// The résumés' summary: under the heading at the accessibility sizes
    /// (the list is folded there), and read with the heading elsewhere.
    public static var pastSummary: String {
        let c = GenderBoxContent.self
        return "\(c.men.count) men, \(c.menHired) hired. \(c.women.count) women, \(c.womenHired) hired."
    }

    /// The heading for VoiceOver where the table shows (the summary is
    /// read with it): "The 12 past résumés: 8 men, 6 hired. 4 women, 1 hired."
    public static var pastHeadingSpoken: String { "\(pastHeading): \(pastSummary)" }

    public static let genderColumn = "Gender box"
    public static let clubsColumn = "Clubs"
    public static let hiredColumn = "Hired?"
    public static let man = "man"
    public static let woman = "woman"
    public static let hired = "Hired"
    public static let notHired = "Not hired"
    public static let noClubs = "No clubs listed"

    public static func gender(_ profile: GenderBoxProfile) -> String { profile.woman ? woman : man }

    public static func club(_ club: GenderBoxClub) -> String {
        switch club {
        case .chessCaptain: return "chess club captain"
        case .womensChessCaptain: return "women\u{2019}s chess club captain"
        case .womensChess: return "women\u{2019}s chess club"
        case .coding: return "coding club"
        }
    }

    /// The résumé's clubs in one line ("No clubs listed" when none).
    public static func clubs(_ profile: GenderBoxProfile) -> String {
        let lines = profile.clubs.map(club)
        return lines.isEmpty ? noClubs : lines.joined(separator: ", ")
    }

    public static func outcome(_ hired: Bool) -> String { hired ? Self.hired : notHired }

    /// The accessibility sizes: the list opens behind this.
    public static var showAll: String { "Show all \(GenderBoxContent.resumes.count)" }
    public static let hideAll = "Hide the list"
    public static let showAllHelp = "Shows each past r\u{E9}sum\u{E9} as text"
    /// A row's title in the accessibility-size list ("Résumé 9").
    public static func rowTitle(_ resume: GenderBoxResume) -> String {
        "R\u{E9}sum\u{E9} \(resume.id)"
    }

    /// One past résumé for VoiceOver.
    public static func resumeSpoken(_ resume: GenderBoxResume, _ box: GenderBox) -> String {
        let gender = box == .kept
            ? "gender box: \(Self.gender(resume.profile))"
            : "gender box deleted (it said \(Self.gender(resume.profile)))"
        return "R\u{E9}sum\u{E9} \(resume.id), \(gender). \(sentenceCase(clubs(resume.profile))). \(outcome(resume.hired))."
    }

    /// `text` with its first letter capitalised (a club list starting a sentence).
    static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: What it learned

    public static let learnedHeading = "What it learned"
    public static let learnedIntro = "It reads the gender box and three words. Each weight pushes a score up or down."

    public static func featureName(_ feature: GenderBoxFeature) -> String {
        switch feature {
        case .woman: return "gender: woman"
        case .womens: return "women\u{2019}s"
        case .captain: return "captain"
        case .coding: return "coding"
        }
    }

    public static func effect(_ effect: GenderBoxEffect) -> String {
        switch effect {
        case .up: return "pushes up"
        case .upALittle: return "pushes up a little"
        case .down: return "pushes down"
        case .downALittle: return "pushes down a little"
        }
    }

    static func effectSpoken(_ effect: GenderBoxEffect) -> String {
        switch effect {
        case .up: return "pushes the score up"
        case .upALittle: return "pushes the score up a little"
        case .down: return "pushes the score down"
        case .downALittle: return "pushes the score down a little"
        }
    }

    /// The toy's word as it appears in a club line (nil: the gender box,
    /// which isn't a word on the résumé).
    public static func featureWord(_ feature: GenderBoxFeature) -> String? {
        feature == .woman ? nil : featureName(feature)
    }

    public static let deletedTag = "deleted"
    /// The weight before the gender box went: "was −1.21".
    public static func was(_ weight: Double) -> String { "was \(GenderBoxContent.signed(weight))" }
    /// Under the bars.
    public static let axisDown = "\u{2190} down"
    public static let axisUp = "up \u{2192}"

    /// The weight's earlier value, when deleting the gender box changed it
    /// (to the two decimals shown).
    public static func earlier(_ feature: GenderBoxFeature, _ box: GenderBox) -> Double? {
        guard box == .deleted, let now = GenderBoxContent.weight(feature, .deleted),
              let before = GenderBoxContent.weight(feature, .kept), before != now else { return nil }
        return before
    }

    /// A weight's row in words, at the accessibility sizes: "−1.53,
    /// pushes down (was −1.21)" or "deleted".
    public static func weightText(_ feature: GenderBoxFeature, _ box: GenderBox) -> String {
        guard let weight = GenderBoxContent.weight(feature, box) else { return deletedTag }
        var line = "\(GenderBoxContent.signed(weight)), \(effect(GenderBoxContent.effect(weight)))"
        if let before = earlier(feature, box) { line += " (\(was(before)))" }
        return line
    }

    /// A weight's row for VoiceOver: "women's: minus 1.53, pushes the score
    /// down. It was minus 1.21."
    public static func weightSpoken(_ feature: GenderBoxFeature, _ box: GenderBox) -> String {
        guard let weight = GenderBoxContent.weight(feature, box) else {
            return "\(featureName(feature)): deleted. The toy no longer reads it."
        }
        var line = "\(featureName(feature)): \(GenderBoxContent.spokenSigned(weight)), "
            + "\(effectSpoken(GenderBoxContent.effect(weight)))."
        if let before = earlier(feature, box) { line += " It was \(GenderBoxContent.spokenSigned(before))." }
        return line
    }

    // MARK: The two new résumés

    public static let testHeading = "Two new r\u{E9}sum\u{E9}s"
    public static let testIntro = "Both are women who code. One line is different."
    public static let testWithTitle = "With \u{201C}women\u{2019}s\u{201D}"
    public static let testWithoutTitle = "Without it"
    public static func genderLine(_ profile: GenderBoxProfile) -> String { "Gender box: \(gender(profile))" }
    public static let scoreCaption = "out of 100"

    /// A test résumé for VoiceOver.
    public static func testSpoken(_ profile: GenderBoxProfile, _ box: GenderBox) -> String {
        let title = profile == GenderBoxContent.testWith ? "with women\u{2019}s" : "without women\u{2019}s"
        let gender = box == .kept ? "gender box: \(Self.gender(profile))" : "gender box deleted"
        return "New r\u{E9}sum\u{E9} \(title): \(gender), \(clubs(profile)). "
            + "Score: \(GenderBoxContent.score(profile, box)) out of 100."
    }

    // MARK: Predict

    public static let predictPrompt = "Delete the gender box and train the toy again. Will the r\u{E9}sum\u{E9} with "
        + "\u{201C}women\u{2019}s\u{201D} still score lower?"

    public static func guessTitle(_ guess: GenderBoxGuess) -> String {
        switch guess {
        case .stillLower: return "Yes, still lower"
        case .higher: return "No, it\u{2019}ll score higher"
        case .tie: return "They\u{2019}ll tie"
        }
    }

    /// The prompt and its choices: the only lines that may use intent
    /// words (they use none).
    public static var predictionLines: [String] {
        [predictPrompt] + GenderBoxGuess.allCases.map(guessTitle)
    }

    // MARK: The control

    public static let controlName = "Gender box"
    /// The control's visible name, before its two options.
    public static var controlLabel: String { "\(controlName):" }
    public static func boxTitle(_ box: GenderBox) -> String { box == .kept ? "kept" : "deleted" }
    public static func boxAccessibility(_ box: GenderBox) -> String { "\(controlName): \(boxTitle(box))" }
    public static func boxHelp(_ box: GenderBox) -> String {
        box == .kept ? "Puts the gender box back, as the toy first learned"
                     : "Deletes the gender box and fits the toy again on the same r\u{E9}sum\u{E9}s"
    }

    // MARK: Reveal

    /// "Still lower" when the deleted fit still scores "women's" lower.
    public static var resultWord: String {
        let pair = GenderBoxContent.scores(.deleted)
        if pair.with < pair.without { return "Still lower" }
        return pair.with == pair.without ? "A tie" : "Higher"
    }

    public static var revealResult: String {
        let pair = GenderBoxContent.scores(.deleted)
        let before = GenderBoxContent.weight(.womens, .kept) ?? 0
        let after = GenderBoxContent.weight(.womens, .deleted) ?? 0
        return "\(resultWord): \(pair.with) vs \(pair.without). With the gender box gone, \u{201C}women\u{2019}s\u{201D} "
            + "carried more of the weight (from \(GenderBoxContent.signed(before)) to \(GenderBoxContent.signed(after)))."
    }

    /// The honest nuance, kept small (both women gained; the gap grew).
    public static var nuance: String {
        let kept = GenderBoxContent.scores(.kept)
        let deleted = GenderBoxContent.scores(.deleted)
        return "Both scores rose (\(kept.with) to \(deleted.with), and \(kept.without) to \(deleted.without)), "
            + "and the gap grew."
    }

    public static let takeaway = "It learned from past decisions. Delete one column, and other words carry the same "
        + "pattern. Reuters reported that Amazon\u{2019}s scorer downgraded r\u{E9}sum\u{E9}s containing "
        + "\u{201C}women\u{2019}s\u{201D} (2018)."

    // MARK: VoiceOver

    /// Said when the student flips the gender box (after the first reveal,
    /// which says the reveal instead): the weights and both scores.
    public static func announcement(_ box: GenderBox) -> String {
        let weights = GenderBoxContent.features(box).compactMap { feature -> String? in
            GenderBoxContent.weight(feature, box).map { "\(featureName(feature)) \(GenderBoxContent.spokenSigned($0))" }
        }
        let pair = GenderBoxContent.scores(box)
        var line = "Gender box \(boxTitle(box)). Weights: \(weights.joined(separator: ", ")). "
            + "Women\u{2019}s chess club captain: \(pair.with). Chess club captain: \(pair.without)."
        if box == .deleted { line += " \(resultWord)." }
        return line
    }

    /// The card's state in one sentence or two, read after its title.
    public static func accessibilitySummary(box: GenderBox, asksForGuess: Bool) -> String {
        let pair = GenderBoxContent.scores(box)
        var line = "Gender box \(boxTitle(box)). The new r\u{E9}sum\u{E9} with women\u{2019}s scores \(pair.with); "
            + "the one without scores \(pair.without)."
        if box == .deleted, let now = GenderBoxContent.weight(.womens, .deleted),
           let before = GenderBoxContent.weight(.womens, .kept) {
            line += " Women\u{2019}s now weighs \(GenderBoxContent.spokenSigned(now)); "
                + "it was \(GenderBoxContent.spokenSigned(before))."
        }
        if asksForGuess { line += " Guess what deleting the gender box does." }
        return line
    }

    // MARK: Every line

    /// Every line the card shows or speaks, in every state.
    public static var everyLine: [String] {
        var lines: [String] = [
            title, compactLine, hook, pastHeading, pastSummary, pastHeadingSpoken, genderColumn, clubsColumn,
            hiredColumn, man, woman, hired, notHired, noClubs, showAll, hideAll, showAllHelp, learnedHeading, learnedIntro, deletedTag,
            axisDown, axisUp, testHeading, testIntro, testWithTitle, testWithoutTitle, scoreCaption, predictPrompt,
            controlName, controlLabel, resultWord, revealResult, nuance, takeaway,
        ]
        lines += labels.map(\.text)
        lines += GenderBoxClub.allCases.map(club)
        lines += GenderBoxGuess.allCases.map(guessTitle)
        lines += [GenderBoxEffect.up, .upALittle, .down, .downALittle].flatMap { [effect($0), effectSpoken($0)] }
        for box in GenderBox.allCases {
            lines += [boxTitle(box), boxAccessibility(box), boxHelp(box), announcement(box),
                      accessibilitySummary(box: box, asksForGuess: true),
                      accessibilitySummary(box: box, asksForGuess: false)]
            lines += GenderBoxContent.resumes.flatMap { [resumeSpoken($0, box), rowTitle($0), clubs($0.profile)] }
            lines += GenderBoxFeature.allCases.flatMap { [featureName($0), weightText($0, box), weightSpoken($0, box)] }
            lines += [GenderBoxContent.testWith, GenderBoxContent.testWithout].flatMap {
                [testSpoken($0, box), genderLine($0)]
            }
        }
        return lines
    }
}
