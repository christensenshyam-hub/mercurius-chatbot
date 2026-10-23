import Foundation

/// The words every card's frame says, on both platforms. A card's own words
/// live in its `<Card>Copy` enum. Held to `InteractiveCopyRules` by
/// `CopyRulesTests`; the eyebrow and "Try it" are Lesson 1.1's
/// (ChatFeature checks they stay equal to `TokenizerCopy`'s).
public enum InteractiveShellCopy {
    public static let eyebrow = "Interactive"

    // The Mac's compact card (narrower than 440 pt)
    public static let tryIt = "Try it"
    public static let tryItHint = "Opens the interactive here, in the lesson"

    // Predict, then reveal
    public static let yourGuess = "Your guess"
    public static let youGuessed = "You guessed"
    public static let whatHappened = "What happened"
    public static let lockHint = "Locks in your guess. It can\u{2019}t be changed after."
    public static let lockedValue = "Your guess, locked in"
    public static let showMe = "Show me"
    public static let showMeHint = "Shows what happened, beside your guess"
    /// Said by VoiceOver on the explore control before a guess is locked.
    public static let guessFirst = "Make your guess first."

    // Step-through
    public static let next = "Next"
    public static let back = "Back"
    public static func stepPosition(_ number: Int, of count: Int) -> String { "Step \(number) of \(count)" }

    // Meters
    public static let equalSymbol = "="
    public static let notEqualSymbol = "\u{2260}"
    public static let equalSpoken = "about equal"
    public static let notEqualSpoken = "not equal"

    // The placeholder for a card that isn't built yet (DEBUG shows it only
    // through `-Interactive`/`-InteractiveGallery`; a dark card never
    // reaches a student).
    public static let placeholderTitle = "This interactive isn\u{2019}t ready yet"
    public static func placeholderBody(_ id: InteractiveID) -> String {
        "\(id.workingName) (\(id.slug)) has a place in this lesson, and nothing to show here yet."
    }

    /// Every line, for the register tests.
    public static var everyLine: [String] {
        [eyebrow, tryIt, tryItHint, yourGuess, youGuessed, whatHappened, lockHint, lockedValue, showMe, showMeHint,
         guessFirst, next, back, stepPosition(2, of: 6), equalSpoken, notEqualSpoken, placeholderTitle]
            + InteractiveID.allCases.map(placeholderBody)
    }
}

/// The labels every card puts on its canvas, never in a footnote (SLATE.md
/// "Labelled"): an authored "AI output" says it is an example written for
/// the lesson, a toy says so, made-up data says so, and a number we derived
/// says it is our arithmetic.
public struct InteractiveLabel: Equatable, Sendable {
    public enum Kind: CaseIterable, Sendable {
        /// "Example, written for this lesson."
        case example
        /// "A toy we built…"
        case toy
        /// "made-up" / "made up".
        case madeUp
        /// "our arithmetic".
        case ourArithmetic
        /// "illustrative".
        case illustrative

        /// What a line of this kind must say (case-insensitive).
        public var requiredPattern: String {
            switch self {
            case .example: return #"\bexample\b.*\bwritten for this lesson\b|\bwe wrote\b"#
            case .toy: return #"\ba toy we built\b"#
            case .madeUp: return #"\bmade[- ]up\b"#
            case .ourArithmetic: return #"\bour arithmetic\b"#
            case .illustrative: return #"\billustrative\b"#
            }
        }
    }

    public let kind: Kind
    public let text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    /// Whether `text` says what its kind requires.
    public var isWellFormed: Bool {
        text.range(of: kind.requiredPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// The register every card's words are held to (BUILD_PLAN.md §1.5). A
/// card's test runs `violations(in:card:predictionLines:)` over its Copy
/// enum's `everyLine`, and checks its labels with `InteractiveLabel`.
public enum InteractiveCopyRules {
    /// The honest-copy register: no line promises a notebook, a save, a
    /// time, a hint or a verification the app doesn't have. The same list
    /// as ChatFeature's `HonestCopy.banned` (a test keeps them equal).
    public static let honestCopyBanned: [String] = [
        "notebook", "saved to", "\\bsaved\\b", "rest day", #"part \d+ of \d+"#, #"beat \d"#,
        #"\b\d+\s?min\b"#, #"\bminutes?\b"#, "previewable", "pinned", "give me a hint", "hint",
        "never reset", "verified",
    ]

    /// Lines that give a model intent. Banned outside a card's listed
    /// prediction lines (a prediction may voice the misconception its
    /// reveal then refutes: "At which step did the model decide…?").
    public static let intentWords: [String] = [
        #"\bwants\b"#, #"\bcheats\b"#, #"\blies\b"#, #"\bknows\b"#, #"\bbelieves\b"#, #"\btricks\b"#,
        #"\blazy\b"#, #"\bdecided\b"#,
    ]

    /// Time promises the honest-copy register catches in other forms.
    public static let timeWords: [String] = [#"\b\d+\s?seconds?\b"#, #"\bseconds?\b"#]

    /// The documented per-card exceptions, all in one place: a pattern a
    /// card may use, and why.
    public static let exceptions: [InteractiveID: [String: String]] = [
        .predictTheExam: [
            "hint": "the study's tutor gave hints (Bastani et al. 2025); not an app feature",
        ],
    ]

    /// One broken rule: the line and the pattern it matched.
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public let line: String
        public let pattern: String
        public var description: String { "\"\(line)\" matches \(pattern)" }
    }

    /// Every rule `lines` break for `card`. `predictionLines` (the card's
    /// prediction prompt and choices, and the reveal line that refutes
    /// them) may use intent words.
    public static func violations(in lines: [String], card: InteractiveID?,
                                  predictionLines: [String] = []) -> [Violation] {
        let allowed = Set(card.flatMap { exceptions[$0]?.keys }.map(Array.init) ?? [])
        var found: [Violation] = []
        for line in lines {
            for pattern in honestCopyBanned + timeWords where !allowed.contains(pattern) && matches(pattern, line) {
                found.append(Violation(line: line, pattern: pattern))
            }
            guard !predictionLines.contains(line) else { continue }
            for pattern in intentWords where matches(pattern, line) {
                found.append(Violation(line: line, pattern: pattern))
            }
        }
        return found
    }

    /// The labels among `required` that no line carries.
    public static func missingLabels(_ required: [InteractiveLabel.Kind], in labels: [InteractiveLabel]) -> [InteractiveLabel.Kind] {
        required.filter { kind in !labels.contains { $0.kind == kind && $0.isWellFormed } }
    }

    static func matches(_ pattern: String, _ line: String) -> Bool {
        line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
