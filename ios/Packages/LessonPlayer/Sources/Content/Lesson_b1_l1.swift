import Foundation

// Basics, Unit 1, Lesson 1, "What is an AI chatbot?", as an interactive
// lesson. DRAFT COPY FOR THE FOUNDER'S REVIEW (HANDOFF.md lists it).
//
// The first lesson a new learner who picks "I'm new to AI" enters. Its real
// objective (BasicsCurriculum.swift): "You'll send your first message to a
// chatbot." Its assessment (lib/basicsGuide.js, COMPLETION): at least one
// practice message that Merc answered, and the lesson's check answered (a
// wrong pick still completes: this is not a safety lesson). The content
// follows the server guide's lesson entry: the reassurance and how-to-type
// lines, Idea 1 (a program you talk to; no one is typing back), the practice
// "Are you a real person?", Idea 2 (it guesses word by word what fits; not a
// person, not a search engine; many chatbots, Merc is one), the check, the
// postcard rule, "Try this today". No statistics (the guide's note).
//
// Basics voice: plain words, short sentences, no jargon, no grade.

public extension LessonCatalog {
    static let b1_l1_v1 = LessonContent(
        lessonId: "b1_l1",
        contentVersion: 1,
        title: "What is an AI chatbot?",
        objective: "You’ll send your first message to a chatbot, and know who, or what, writes back.",
        prerequisites: [],
        steps: [
            // 1. A decision on the first screen.
            LessonStep(
                id: "who-wrote-it",
                kind: .activity(Activity(
                    prompt: "You type a question into a chatbot, and an answer appears a few seconds later. Who wrote that answer?",
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(
                                id: "person",
                                text: "A person at the company, typing fast",
                                feedback: "It feels like a person, because the words are friendly and quick. But no one is typing back. A computer program wrote it."
                            ),
                            ChoiceOption(
                                id: "website",
                                text: "It was copied from one website",
                                feedback: "Good guess, but it doesn’t copy a page. A computer program writes a new answer each time you ask."
                            ),
                            ChoiceOption(id: "program", text: "A computer program, word by word"),
                        ],
                        correct: ["program"],
                        correctFeedback: "Yes. A computer program wrote it, one word after another. No one is typing back to you."
                    ))
                )),
                depth: [
                    DepthItem(
                        id: "who-wrote-it.why",
                        kind: .why,
                        title: "Why?",
                        body: "An AI chatbot is a computer program you talk to by typing or speaking. It writes back in everyday words, so it can feel like a person. It isn’t one."
                    ),
                ]
            ),

            // 2. Idea 1, with the reassurance and how to type.
            LessonStep(
                id: "what-it-is",
                kind: .teach(TeachContent(
                    heading: "You can’t break anything here",
                    body: "An AI chatbot is a computer program you talk to by typing or speaking. There are no silly questions. Type in the box, or tap the microphone on your keyboard and talk. Then tap Send.",
                    keyIdea: "A chatbot is a computer program you talk to. No one is typing back."
                ))
            ),

            // 3. The objective: a real first message, and a real reply.
            LessonStep(
                id: "first-message",
                kind: .activity(Activity(
                    prompt: "Now send your first message to a chatbot. Ask Merc whether it’s a real person, or ask in your own words.",
                    kind: .practice(PracticeActivity(
                        suggestion: "Are you a real person?",
                        placeholder: "Type your message to Merc",
                        maxCharacters: 300,
                        fallbackGuidance: "Your message couldn’t reach Merc right now, so it’s saved here. Check that you’re online, then tap Retry. You haven’t done anything wrong.",
                        notice: "That’s it: you sent a message, and a computer program wrote back in everyday words. You just used a chatbot."
                    ))
                ))
            ),

            // 4. Idea 2.
            LessonStep(
                id: "how-it-writes",
                kind: .teach(TeachContent(
                    heading: "How it writes",
                    body: "A chatbot learned from a huge amount of writing. It makes each answer by guessing, word by word, what fits best. It isn’t a person, and it isn’t a search engine. ChatGPT, Claude, Gemini and Copilot are chatbots. Merc is one too.",
                    keyIdea: "It writes by guessing what words fit best."
                )),
                depth: [
                    DepthItem(
                        id: "how-it-writes.example",
                        kind: .example,
                        title: "Show an example",
                        body: "If you type “The cat sat on the…”, a chatbot is very likely to guess “mat” or “chair” next. It writes whole answers the same way, one guess at a time."
                    ),
                ]
            ),

            // 5. A new application: the postcard rule.
            LessonStep(
                id: "postcard",
                kind: .activity(Activity(
                    prompt: "Here’s a safety rule: if you wouldn’t write it on a postcard, don’t type it into a chatbot. Which message follows it?",
                    scenario: Material(
                        title: "Three messages someone might type",
                        text: "The card number and password below are made up for practice.",
                        origin: .fictional
                    ),
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(id: "soup", text: "What’s a good soup for a cold day?"),
                            ChoiceOption(
                                id: "card",
                                text: "My card number is 4000 1234 5678 9010",
                                feedback: "Never type a card number into a chatbot, even to ask about a charge. You can get good help without it."
                            ),
                            ChoiceOption(
                                id: "password",
                                text: "My password is Rover2024. Is it good?",
                                feedback: "Keep passwords to yourself, even to check them. You can ask “What makes a strong password?” instead."
                            ),
                        ],
                        correct: ["soup"],
                        correctFeedback: "Yes. A soup question is fine on a postcard. Card numbers and passwords never are, and you can get help without them."
                    ))
                ))
            ),

            // 6. The lesson's check.
            LessonStep(
                id: "check",
                kind: .activity(Activity(
                    prompt: "Last one, and there’s no grade. Which is the best description of an AI chatbot?",
                    kind: .choice(ChoiceActivity(
                        options: [
                            ChoiceOption(
                                id: "person",
                                text: "A person at the company typing answers to you",
                                feedback: "It can sound like one, but no person is typing. A computer program writes each answer."
                            ),
                            ChoiceOption(id: "program", text: "A program that writes by guessing what words fit"),
                            ChoiceOption(
                                id: "library",
                                text: "A big library that looks up the right answer",
                                feedback: "It doesn’t look answers up, and it can be wrong. It writes by guessing what words fit best."
                            ),
                        ],
                        correct: ["program"],
                        correctFeedback: "That’s it. A chatbot is a computer program that writes answers by guessing what words fit best."
                    ))
                ))
            ),

            // 7. The finish.
            LessonStep(
                id: "finish",
                kind: .finish(FinishContent(
                    heading: "You did it",
                    practiced: "You sent your first message to a chatbot, saw that a computer program writes back, and learned the postcard rule.",
                    next: "Try this today: ask a chatbot one thing you’ve wondered about this week. Next lesson: what chatbots are good at."
                ))
            ),
        ],
        // Basics' completion: a practice message Merc answered, and the check
        // answered. A wrong pick still completes (not a safety lesson): the
        // right answer is shown kindly, and success is recorded as "not
        // demonstrated" rather than graded correct.
        completion: CompletionRule(
            mustBeCorrect: [],
            mustBeAnswered: ["who-wrote-it", "first-message", "postcard", "check"]
        )
    )
}
