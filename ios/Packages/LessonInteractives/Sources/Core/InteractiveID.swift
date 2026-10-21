import Foundation

// The lesson interactives' framework (docs/interactives/FRAMEWORK.md): every
// card on the slate (SLATE.md), keyed by lesson in `InteractiveRegistry`,
// placed in its lesson's thread by ChatFeature's `LessonInteractiveAnchor`,
// and drawn on the iPhone and the Mac from one module that can't reach the
// network or storage (it depends on DesignSystem only).

/// Every lesson interactive on the slate, Lesson 1.1's tokenizer included.
/// A card that isn't built yet still has an id, a spec and a placeholder
/// view, so adding one changes only its own files, its registry row's
/// `enabled` (after its review) and its line in `InteractiveCardViews`.
public enum InteractiveID: String, CaseIterable, Sendable, Hashable {
    /// U1L1, "How a model reads “bank”" (ChatFeature/Sources/Tokenizer).
    case tokenizer
    /// U1L3, The Citation That Wasn't.
    case citationThatWasnt
    /// U2L2, Two Tests, One Line.
    case twoTestsOneLine
    /// U2L3, Who's in the Test?
    case whosInTheTest
    /// U3L1, Delete the Gender Box.
    case deleteTheGenderBox
    /// U3L2, The Ward of 1,000.
    case wardOf1000
    /// U4L1, Read My Mind.
    case readMyMind
    /// U5L1, Patch the Reward.
    case patchTheReward
    /// U6L1, Grown from Static.
    case grownFromStatic
    /// U6L4, The Doubt Dial.
    case doubtDial
    /// U7L1, Predict the Exam.
    case predictTheExam
    /// U8L1, The Page with a Secret.
    case pageWithASecret

    /// The slate's slug ("doubt-dial"): `sketches/<slug>.svg`,
    /// `docs/interactives/<slug>/` and the launch arguments
    /// (`-Interactive <slug>`, `-InteractiveGallery <slug>`).
    public var slug: String {
        switch self {
        case .tokenizer: return "tokenizer"
        case .citationThatWasnt: return "citation-that-wasnt"
        case .twoTestsOneLine: return "two-tests-one-line"
        case .whosInTheTest: return "whos-in-the-test"
        case .deleteTheGenderBox: return "delete-the-gender-box"
        case .wardOf1000: return "ward-of-1000"
        case .readMyMind: return "read-my-mind"
        case .patchTheReward: return "patch-the-reward"
        case .grownFromStatic: return "grown-from-static"
        case .doubtDial: return "doubt-dial"
        case .predictTheExam: return "predict-the-exam"
        case .pageWithASecret: return "page-with-a-secret"
        }
    }

    /// The slate's working name, for DEBUG screens and docs. A card's
    /// on-screen title is its Copy enum's, never this.
    public var workingName: String {
        switch self {
        case .tokenizer: return "How a model reads \u{201C}bank\u{201D}"
        case .citationThatWasnt: return "The Citation That Wasn\u{2019}t"
        case .twoTestsOneLine: return "Two Tests, One Line"
        case .whosInTheTest: return "Who\u{2019}s in the Test?"
        case .deleteTheGenderBox: return "Delete the Gender Box"
        case .wardOf1000: return "The Ward of 1,000"
        case .readMyMind: return "Read My Mind"
        case .patchTheReward: return "Patch the Reward"
        case .grownFromStatic: return "Grown from Static"
        case .doubtDial: return "The Doubt Dial"
        case .predictTheExam: return "Predict the Exam"
        case .pageWithASecret: return "The Page with a Secret"
        }
    }

    /// The card a slug or a raw value names ("doubt-dial", "doubtDial"),
    /// ignoring case.
    public init?(slug: String) {
        let wanted = slug.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.allCases.first(where: { $0.slug == wanted || $0.rawValue.lowercased() == wanted })
        else { return nil }
        self = match
    }
}
