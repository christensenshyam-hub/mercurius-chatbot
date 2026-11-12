import Foundation

/// A learner decision or original response, with its answer key or rubric and
/// its answer-specific feedback.
public struct Activity: Sendable, Equatable {
    /// The question or instruction (aim: 15–35 words).
    public let prompt: String
    /// A scenario or claim the activity is about.
    public let scenario: Material?
    /// Evidence to weigh against the scenario (claim-vs-evidence activities).
    public let evidence: Material?
    public let kind: ActivityKind
    /// Hints, revealed one at a time after a wrong answer or on request.
    public let hints: [String]

    public init(
        prompt: String,
        scenario: Material? = nil,
        evidence: Material? = nil,
        kind: ActivityKind,
        hints: [String] = []
    ) {
        self.prompt = prompt
        self.scenario = scenario
        self.evidence = evidence
        self.kind = kind
        self.hints = hints
    }

    /// Graded on the device, instantly, with no model call.
    public var isDeterministic: Bool {
        if case .shortResponse = kind { return false }
        return true
    }
}

public enum ActivityKind: Sendable, Equatable {
    /// Single choice, multi-select, or a claim weighed against evidence (the
    /// same renderer; `ChoiceActivity.presentation` says which).
    case choice(ChoiceActivity)
    /// Pick claims or phrases out of an authored passage, by stable id. The
    /// player also offers them as a plain list (the accessible alternative).
    case claimSelection(ClaimSelectionActivity)
    /// A short original answer, evaluated against an explicit rubric by the
    /// server (the only model-graded kind).
    case shortResponse(ShortResponseActivity)
}

// MARK: - Choice

public struct ChoiceActivity: Sendable, Equatable {
    public enum Selection: Sendable, Equatable { case single, multiple }
    public enum Presentation: Sendable, Equatable {
        case standard
        /// The scenario is a claim and `Activity.evidence` the evidence; the
        /// options are verdicts about the claim given that evidence.
        case claimVersusEvidence
    }

    public let options: [ChoiceOption]
    public let selection: Selection
    public let presentation: Presentation
    /// The correct option ids: exactly one for `.single`.
    public let correct: Set<String>
    /// Feedback when the answer is right (aim: 15–35 words).
    public let correctFeedback: String
    /// Multi-select only: shown when some but not all right options are chosen.
    public let partialFeedback: String?

    public init(
        options: [ChoiceOption],
        selection: Selection = .single,
        presentation: Presentation = .standard,
        correct: Set<String>,
        correctFeedback: String,
        partialFeedback: String? = nil
    ) {
        self.options = options
        self.selection = selection
        self.presentation = presentation
        self.correct = correct
        self.correctFeedback = correctFeedback
        self.partialFeedback = partialFeedback
    }
}

public struct ChoiceOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    /// Shown when this option is chosen and the answer is wrong: names the
    /// misconception the distractor stands for. Empty for a correct option.
    public let feedback: String

    public init(id: String, text: String, feedback: String = "") {
        self.id = id
        self.text = text
        self.feedback = feedback
    }
}

// MARK: - Claim selection

public struct ClaimSelectionActivity: Sendable, Equatable {
    /// The passage, in order. Selectable spans carry a claim id.
    public let passage: [PassageSegment]
    /// The claim ids that answer the prompt.
    public let correct: Set<String>
    public let selection: ChoiceActivity.Selection
    public let correctFeedback: String
    /// Feedback per wrong claim id (why that span isn't the answer).
    public let claimFeedback: [String: String]

    public init(
        passage: [PassageSegment],
        correct: Set<String>,
        selection: ChoiceActivity.Selection = .single,
        correctFeedback: String,
        claimFeedback: [String: String]
    ) {
        self.passage = passage
        self.correct = correct
        self.selection = selection
        self.correctFeedback = correctFeedback
        self.claimFeedback = claimFeedback
    }

    public var claims: [PassageSegment] { passage.filter { $0.claimId != nil } }
}

public struct PassageSegment: Sendable, Equatable {
    public let text: String
    /// Set for a selectable claim or phrase; nil for connecting text.
    public let claimId: String?
    public init(_ text: String, claimId: String? = nil) {
        self.text = text
        self.claimId = claimId
    }
}

// MARK: - Short response

public struct ShortResponseActivity: Sendable, Equatable {
    /// The id the server grades against (`lib/lessonPlayerRubrics.js`): the
    /// rubric lives on the server so the endpoint can't grade an arbitrary
    /// task. Shown here for reference and tests only.
    public let rubricId: String
    /// The rubric in words, mirrored from the server registry for the reviewer
    /// and the validator (never sent as instructions).
    public let rubric: Rubric
    public let placeholder: String
    public let maxCharacters: Int
    /// Reviewed guidance shown when the response can't be graded right now
    /// (offline, timeout, invalid result). It never says the answer was right.
    public let fallbackGuidance: String
    /// A model answer shown after two "not yet" results, so a learner who is
    /// stuck can see what a sound response looks like before writing their own.
    public let exemplar: String

    public init(
        rubricId: String,
        rubric: Rubric,
        placeholder: String,
        maxCharacters: Int = 400,
        fallbackGuidance: String,
        exemplar: String
    ) {
        self.rubricId = rubricId
        self.rubric = rubric
        self.placeholder = placeholder
        self.maxCharacters = maxCharacters
        self.fallbackGuidance = fallbackGuidance
        self.exemplar = exemplar
    }
}

public struct Rubric: Sendable, Equatable {
    /// Must be present for "meets".
    public let core: [String]
    /// Credited in feedback, not required.
    public let rewarded: [String]
    /// Misconceptions to name if expressed (each with a stable flag id the
    /// server may return).
    public let flags: [RubricFlag]
    public init(core: [String], rewarded: [String] = [], flags: [RubricFlag] = []) {
        self.core = core
        self.rewarded = rewarded
        self.flags = flags
    }
}

public struct RubricFlag: Sendable, Equatable {
    public let id: String
    public let description: String
    /// The reviewed correction the player shows when the server returns this flag.
    public let correction: String
    public init(id: String, description: String, correction: String) {
        self.id = id
        self.description = description
        self.correction = correction
    }
}
