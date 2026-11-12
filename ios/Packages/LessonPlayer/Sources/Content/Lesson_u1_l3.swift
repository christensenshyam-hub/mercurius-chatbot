import Foundation

// Unit 1, Lesson 3, "Why AI sounds confident but can be wrong", as an
// interactive lesson (SPEC.md, "Lesson 3 script").
//
// Objective (pilot): distinguish confident presentation from evidential
// support, and choose a sound verification action. It keeps the legacy
// lesson's objective (hallucination and the confidence-accuracy gap: steps
// 2 and its Go deeper stages) and its assessment (identify a claim to check,
// what to check, how to verify: steps 3, 4, 5, transfer in step 6).
//
// Facts: only the server guide's checked facts (server.js, Unit 1 Lesson 3:
// Mata v. Avianca, the GPT-4 Technical Report on calibration). Every other
// claim, number, source and excerpt is invented practice material and is
// labelled so on screen.
//
// Three states run through the lesson: supported (evidence backs the claim),
// contradicted (evidence goes against it), unverified (no evidence either
// way yet). An unlocated citation is unverified, not disproven, and a real
// source still has to say what the claim says.

public extension LessonCatalog {
    static let u1_l3_v1 = LessonContent(
        lessonId: "u1_l3",
        contentVersion: 1,
        title: "Why AI sounds confident but can be wrong",
        objective: "Tell confident-sounding claims apart from claims backed by evidence, and choose a sound way to check one.",
        prerequisites: ["u1_l2"],
        steps: [
            // 1. A decision on the first screen.
            LessonStep(
                id: "claim-state",
                kind: .activity(Activity(
                    prompt: "Judging only by this statement, is the claim supported, unverified, or contradicted?",
                    scenario: Material(
                        title: "An AI tells you",
                        text: "“Green study rooms improve memory by 34%.”",
                        origin: .fictional
                    ),
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(
                                id: "supported",
                                text: "Supported",
                                feedback: "A precise number sounds measured, but nothing here backs it up. Supported means a source shows it, and none has been given."
                            ),
                            ChoiceOption(id: "unverified", text: "Unverified"),
                            ChoiceOption(
                                id: "contradicted",
                                text: "Contradicted",
                                feedback: "Nothing here says it’s false either. Contradicted means evidence points the other way, and you haven’t seen any evidence yet."
                            ),
                        ],
                        correct: ["unverified"],
                        correctFeedback: "Right. No evidence has been supplied, for or against. The exact number makes it sound checked, but nothing shows that it was."
                    )),
                    hints: ["Ask yourself: has anyone shown you evidence, for it or against it?"]
                )),
                depth: [
                    DepthItem(
                        id: "claim-state.why",
                        kind: .why,
                        title: "Why?",
                        body: "A claim is supported when evidence backs it, contradicted when evidence goes against it, and unverified when you haven’t seen evidence either way. Most claims start out unverified, however confident they sound."
                    ),
                ]
            ),

            // 2. The principle, briefly; the technical detail is optional depth.
            LessonStep(
                id: "principle",
                kind: .teach(TeachContent(
                    heading: "Sounding sure isn’t evidence",
                    body: "AI writes by predicting likely words, not by checking facts. So it can produce confident text with nothing reliable behind it. A precise number like 34%, or a citation with a real-looking author and journal, comes out the same way as any other sentence.",
                    keyIdea: "Confidence, exact numbers and realistic citations aren’t evidence. A source that actually says it is."
                )),
                depth: [
                    DepthItem(
                        id: "principle.why",
                        kind: .why,
                        title: "Why?",
                        body: "A language model picks each next word by how likely it is, given the words so far. A citation has a familiar shape: names, a year, a journal. The model can fill that shape fluently whether or not the paper exists."
                    ),
                    DepthItem(
                        id: "principle.example",
                        kind: .example,
                        title: "Show an example",
                        body: "“Henderson & Ortiz (2019), Journal of Applied Cognition” looks like a real citation. The shape is all it takes to sound credible, and an AI can produce it without any paper behind it.",
                        origin: .fictional
                    ),
                    DepthItem(
                        id: "principle.deep1",
                        kind: .stage(1),
                        title: "A real case",
                        body: "In Mata v. Avianca (2023), lawyers filed a court brief citing cases that ChatGPT had invented. A federal judge fined them and their firm $5,000.",
                        origin: .real(SourceInfo(citation: "Mata v. Avianca, Inc. (S.D.N.Y. 2023)", year: 2023))
                    ),
                    DepthItem(
                        id: "principle.deep2",
                        kind: .stage(2),
                        title: "Why polish can hide doubt",
                        body: "OpenAI’s GPT-4 Technical Report (2023) found the pre-trained model’s confidence matched its accuracy well, and that post-training, including RLHF, made that calibration worse. A polished assistant can sound sure when it isn’t.",
                        origin: .real(SourceInfo(citation: "OpenAI, GPT-4 Technical Report (2023)", year: 2023))
                    ),
                    DepthItem(
                        id: "principle.deep3",
                        kind: .stage(3),
                        title: "Real source, wrong claim",
                        body: "Finding a real paper isn’t the end. An AI can attach a real source to a claim it never makes. Checking means reading what the source measured and what it found, and comparing that with the claim."
                    ),
                ]
            ),

            // 3. Select the testable numerical claim.
            LessonStep(
                id: "testable-claim",
                kind: .activity(Activity(
                    prompt: "Tap the claim in this AI answer that gives a specific number you could check against the original study.",
                    scenario: Material(
                        title: "An AI answer",
                        text: "Studies show green study rooms can boost memory. In one experiment, students in green rooms remembered 34% more words than students in white rooms. Many teachers now recommend them, and the color is thought to feel calming.",
                        origin: .fictional
                    ),
                    kind: .claimSelection(ClaimSelectionActivity(
                        passage: [
                            PassageSegment("Studies show ", claimId: nil),
                            PassageSegment("green study rooms can boost memory", claimId: "boost"),
                            PassageSegment(". In one experiment, "),
                            PassageSegment("students in green rooms remembered 34% more words than students in white rooms", claimId: "34-percent"),
                            PassageSegment(". "),
                            PassageSegment("Many teachers now recommend them", claimId: "teachers"),
                            PassageSegment(", and "),
                            PassageSegment("the color is thought to feel calming", claimId: "calming"),
                            PassageSegment("."),
                        ],
                        correct: ["34-percent"],
                        correctFeedback: "Yes: 34% more words, green rooms against white. A figure that precise should appear in the original study if it’s real, so it’s what to check.",
                        claimFeedback: [
                            "boost": "That’s a claim, but a broad one. “Can boost” gives no number or measure, so there’s nothing exact to match against a study.",
                            "teachers": "Maybe true, but there’s no number to test: which teachers, and how many? Look for the sentence with an exact figure.",
                            "calming": "“Is thought to” is hedged, and there’s no measure to check. Look for the sentence with an exact figure.",
                        ]
                    )),
                    hints: ["Look for a percentage."]
                ))
            ),

            // 4. Which action gives the strongest evidence?
            LessonStep(
                id: "best-check",
                kind: .activity(Activity(
                    prompt: "You want to know whether the 34% figure is accurate. Which action gives you the strongest evidence?",
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(
                                id: "journal-exists",
                                text: "Confirm the journal it cites really exists",
                                feedback: "A real journal doesn’t show the paper is real, or that it found 34%. The journal existing says nothing about this claim."
                            ),
                            ChoiceOption(
                                id: "ask-again",
                                text: "Ask the AI whether it’s sure about the number",
                                feedback: "It can sound just as sure the second time. Asking again tests its confidence, not the evidence behind the number."
                            ),
                            ChoiceOption(id: "original-study", text: "Find the original study and read what it found"),
                            ChoiceOption(
                                id: "repeat-sites",
                                text: "Find several websites that repeat the 34% figure",
                                feedback: "Repetition isn’t evidence. Many sites can copy one unchecked number from each other, or from the same AI answer."
                            ),
                        ],
                        correct: ["original-study"],
                        correctFeedback: "Right. Only the original study can show what was measured and found. A real journal or a dozen repeating sites can’t."
                    )),
                    hints: ["Which option lets you see what was actually measured?"]
                ))
            ),

            // 5. A claim against evidence.
            LessonStep(
                id: "excerpt",
                kind: .activity(Activity(
                    prompt: "Here’s an excerpt from the study the AI cited. Does it support the claim that green rooms improve memory by 34%?",
                    scenario: Material(title: "The claim", text: "“Green study rooms improve memory by 34%.”", origin: .fictional),
                    evidence: Material(
                        title: "From the study",
                        text: "“Participants rated green rooms as calmer. The study did not measure memory performance.”",
                        origin: .fictional
                    ),
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(id: "still-unverified", text: "No. The claim is still unverified"),
                            ChoiceOption(
                                id: "supports",
                                text: "Yes. It shows green rooms help",
                                feedback: "Calmer isn’t better memory. The excerpt reports how the rooms felt, and says memory wasn’t measured at all."
                            ),
                            ChoiceOption(
                                id: "disproves",
                                text: "No. It proves the claim false",
                                feedback: "It doesn’t disprove it either. Memory wasn’t measured, so this excerpt says nothing about the 34%, one way or the other."
                            ),
                        ],
                        presentation: .claimVersusEvidence,
                        correct: ["still-unverified"],
                        correctFeedback: "Right. The study measured calm, not memory. What it measured doesn’t match the claim, so the 34% stays unverified."
                    )),
                    hints: ["Compare what the study measured with what the claim says."]
                ))
            ),

            // 6. Transfer: a new scenario, in the learner's own words.
            LessonStep(
                id: "transfer",
                kind: .activity(Activity(
                    prompt: "In one sentence, what would you do next, and why?",
                    scenario: Material(
                        title: "A new claim",
                        text: "An AI tells you: “Listening to rain sounds improves test scores by 22%.” It cites a study, but you can’t find that study anywhere.",
                        origin: .fictional
                    ),
                    kind: .shortResponse(ShortResponseActivity(
                        rubricId: "u1_l3.transfer.v1",
                        rubric: Rubric(
                            core: ["Holds off on relying on the claim, and looks for relevant evidence that can be checked."],
                            rewarded: ["Checks whether the evidence actually supports the claim (what was measured, and the 22%)."],
                            flags: [
                                RubricFlag(
                                    id: "missing_citation_proves_false",
                                    description: "Says a citation that can't be found proves the claim is false or made up.",
                                    correction: "One thing to fix: a study you can’t find leaves the claim unverified, not false. It might exist but be hard to find, or be cited wrongly."
                                ),
                            ]
                        ),
                        placeholder: "One sentence: what you’d do next, and why",
                        maxCharacters: 400,
                        fallbackGuidance: "We couldn’t check your answer right now, so it isn’t graded yet. Your answer is saved. A sound next step holds off on the 22% and looks for a source that measured test scores. Tap Retry, or finish for now and come back.",
                        exemplar: "I wouldn’t rely on the 22% yet. I’d keep looking for the original study, or other research that measured test scores, and check whether it actually found that."
                    )),
                    hints: ["Should you trust the 22% yet? And where could real evidence come from?"]
                ))
            ),

            // 7. The finish.
            LessonStep(
                id: "finish",
                kind: .finish(FinishContent(
                    heading: "Lesson complete",
                    practiced: "You sorted a claim into supported, unverified or contradicted, picked out a number you could test, chose the strongest check, and saw that evidence has to match the claim.",
                    next: "Next is Lesson 4, the Unit 1 review: one research scenario that uses tokens, training data and today’s checking skills."
                ))
            ),
        ],
        completion: CompletionRule(mustBeCorrect: ["claim-state", "testable-claim", "best-check", "excerpt", "transfer"])
    )
}
