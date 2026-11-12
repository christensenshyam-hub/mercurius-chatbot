import Foundation
@testable import LessonPlayer

/// A small, valid lesson using every activity kind, for the core tests.
enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static let choice = ChoiceActivity(
        options: [
            ChoiceOption(id: "a", text: "Supported", feedback: "Nothing backs it up yet: a statement on its own is not evidence, however precise it sounds."),
            ChoiceOption(id: "b", text: "Unverified"),
            ChoiceOption(id: "c", text: "Contradicted", feedback: "Nothing contradicts it either. With no evidence either way, the claim is simply not checked yet."),
        ],
        correct: ["b"],
        correctFeedback: "Right: nothing has been offered to support it or contradict it, so it stays unverified until you check."
    )

    static let multi = ChoiceActivity(
        options: [
            ChoiceOption(id: "x", text: "Open the original study"),
            ChoiceOption(id: "y", text: "Check what it measured"),
            ChoiceOption(id: "z", text: "Count sites that repeat it", feedback: "Repetition is not evidence: many sites can copy one unchecked number from each other."),
        ],
        selection: .multiple,
        correct: ["x", "y"],
        correctFeedback: "Both: find the source, then check that what it measured matches the claim being made.",
        partialFeedback: "One more: finding the source is half of it; check what it measured, too."
    )

    static let claims = ClaimSelectionActivity(
        passage: [
            PassageSegment("Studies agree that "),
            PassageSegment("green rooms improve memory by 34%", claimId: "stat"),
            PassageSegment(", and "),
            PassageSegment("many schools now use them", claimId: "schools"),
            PassageSegment("."),
        ],
        correct: ["stat"],
        correctFeedback: "Yes: 34% is a precise, testable number you could look for in the original study.",
        claimFeedback: ["schools": "That's a claim, but a vague one: there's no number in it to test against a source."]
    )

    static let rubric = Rubric(
        core: ["Holds off relying on the claim and looks for relevant, verifiable evidence."],
        rewarded: ["Checks whether the evidence actually supports the claim."],
        flags: [RubricFlag(id: "missing_citation_proves_false", description: "Says a missing citation proves the claim false.",
                           correction: "A citation you can't find leaves the claim unverified, not disproven.")]
    )

    static let short = ShortResponseActivity(
        rubricId: "fixture.short",
        rubric: rubric,
        placeholder: "One sentence",
        maxCharacters: 200,
        fallbackGuidance: "We couldn't check your answer right now. A sound next step holds off on the claim and looks for the original study.",
        exemplar: "I wouldn't rely on the 22% yet; I'd search for the original study and see if it measured test scores."
    )

    static func lesson(version: Int = 1, mustBeAnswered: [String] = [], mustBeCorrect: [String]? = nil) -> LessonContent {
        let correct = mustBeCorrect ?? ["s1", "s3", "s4", "s5", "s6"].filter { !mustBeAnswered.contains($0) }
        return LessonContent(
            lessonId: "u9_l9",
            contentVersion: version,
            title: "Fixture lesson",
            objective: "Tell confident presentation apart from evidence.",
            prerequisites: ["u9_l8"],
            steps: [
                LessonStep(id: "s1", kind: .activity(Activity(
                    prompt: "Based on the statement alone, is this claim supported, unverified, or contradicted by evidence you have been shown?",
                    scenario: Material(text: "Green study rooms improve memory by 34%.", origin: .fictional),
                    kind: .choice(choice),
                    hints: ["Has anyone shown you a source?"]
                ))),
                LessonStep(id: "s2", kind: .teach(TeachContent(
                    heading: "Sounding sure isn't evidence",
                    body: "AI can write confident text without reliable evidence behind it. A precise number or a realistic citation can be produced the same way as any other text, so neither one shows that a claim is accurate until you check it.",
                    keyIdea: "Precision and confidence are not evidence."
                )), depth: [
                    DepthItem(id: "why", kind: .why, title: "Why?", body: "The model predicts likely words."),
                    DepthItem(id: "deep1", kind: .stage(1), title: "Stage 1", body: "Calibration."),
                    DepthItem(id: "deep2", kind: .stage(2), title: "Stage 2", body: "Fake citations."),
                ]),
                LessonStep(id: "s3", kind: .activity(Activity(
                    prompt: "Tap the claim in this AI answer that you could test against a source, because it states a specific number.",
                    scenario: Material(text: "An AI answer.", origin: .fictional),
                    kind: .claimSelection(claims)
                ))),
                LessonStep(id: "s4", kind: .activity(Activity(
                    prompt: "Which two actions together give you the strongest evidence about whether this claim is accurate? Choose both.",
                    kind: .choice(multi)
                ))),
                LessonStep(id: "s5", kind: .activity(Activity(
                    prompt: "Does this excerpt from the study support the claim that green rooms improve memory by 34 percent?",
                    scenario: Material(text: "Green study rooms improve memory by 34%.", origin: .fictional),
                    evidence: Material(text: "Participants rated green rooms as calmer. The study did not measure memory.", origin: .fictional),
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(id: "sup", text: "Yes, it supports the claim", feedback: "Calmer isn't better memory: the study measured how rooms felt, not what people remembered."),
                            ChoiceOption(id: "unv", text: "No, the claim is still unverified"),
                            ChoiceOption(id: "con", text: "No, it proves the claim false", feedback: "It doesn't disprove it either: memory wasn't measured at all, so the claim is untested here."),
                        ],
                        presentation: .claimVersusEvidence,
                        correct: ["unv"],
                        correctFeedback: "Right: the study measured calm, not memory, so this excerpt can't support the memory claim."
                    ))
                ))),
                LessonStep(id: "s6", kind: .activity(Activity(
                    prompt: "AI says rain sounds improve test scores by 22%, and you can't find its citation. What do you do next?",
                    kind: .shortResponse(short)
                ))),
                LessonStep(id: "s7", kind: .finish(FinishContent(
                    heading: "Done for now",
                    practiced: "You sorted claims into supported, unverified and contradicted.",
                    next: "Next: the unit review."
                ))),
            ],
            completion: CompletionRule(mustBeCorrect: correct, mustBeAnswered: mustBeAnswered)
        )
    }

    static func machine(_ lesson: LessonContent = lesson()) -> LessonMachine {
        LessonMachine(content: lesson, attempt: LessonAttempt(lesson: lesson, attemptId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, now: t0))!
    }
}

extension LessonMachine {
    /// Answers the current objective step correctly and advances.
    mutating func passCurrent() {
        guard let activity = currentStep.activity else { _ = send(.advance(from: currentStep.id)); return }
        switch activity.kind {
        case .choice(let c):
            for id in c.correct.sorted() { _ = send(.choose(id)) }
        case .claimSelection(let s):
            for id in s.correct.sorted() { _ = send(.toggleClaim(id)) }
        case .shortResponse:
            _ = send(.editText("I'd hold off and look for the original study."))
            let token = send(.submit).effects.compactMap { e -> Int? in
                if case .requestEvaluation(_, let t, _) = e { return t }; return nil
            }.first!
            _ = send(.evaluationArrived(token: token, ResponseEvaluation(status: .meets, feedback: "That's the move.")))
        }
        if activity.isDeterministic { _ = send(.submit) }
        _ = send(.advance(from: currentStep.id))
    }
}
