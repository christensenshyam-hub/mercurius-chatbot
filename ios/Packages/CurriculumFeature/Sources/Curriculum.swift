import Foundation

/// A single structured lesson. Tapping a lesson in the UI sends its
/// `starter` prompt to the chat — the server's system prompt detects
/// the `[CURRICULUM: …]` prefix and runs a structured teaching flow.
public struct Lesson: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let number: Int
    public let title: String
    public let objective: String
    public let starter: String

    public init(id: String, number: Int, title: String, objective: String, starter: String) {
        self.id = id
        self.number = number
        self.title = title
        self.objective = objective
        self.starter = starter
    }
}

/// A curriculum unit — a set of related lessons that build on each other.
public struct Unit: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let number: String        // "01"
    public let title: String
    public let summary: String
    public let lessons: [Lesson]

    public init(id: String, number: String, title: String, summary: String, lessons: [Lesson]) {
        self.id = id
        self.number = number
        self.title = title
        self.summary = summary
        self.lessons = lessons
    }
}

/// A cumulative end-of-unit assessment: an objective multiple-choice quiz
/// spanning the unit's four lessons, plus one open-ended "defense" question
/// that Mercurius grades. Authored as fixed content (not generated) so it's
/// reliable, testable, and works offline. Unlocks once all four lessons in the
/// unit are complete; passing marks the unit "mastered."
public struct UnitTest: Sendable, Equatable {
    public let unitId: String
    public let questions: [UnitTestQuestion]
    /// One open-ended prompt the student answers in their own words; graded
    /// A–D by the server (pass = A or B).
    public let defensePrompt: String

    public init(unitId: String, questions: [UnitTestQuestion], defensePrompt: String) {
        self.unitId = unitId
        self.questions = questions
        self.defensePrompt = defensePrompt
    }
}

/// A single multiple-choice question. `answer` is a letter ("A"–"D") matching
/// the correct entry in `options` — same shape as the chat-quiz tool so the
/// selection/scoring logic stays familiar.
public struct UnitTestQuestion: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let q: String
    public let options: [String]
    public let answer: String
    public let explanation: String

    public init(id: String, q: String, options: [String], answer: String, explanation: String) {
        self.id = id
        self.q = q
        self.options = options
        self.answer = answer
        self.explanation = explanation
    }

    /// Zero-based index of the correct option, derived from `answer` ("A" → 0).
    /// -1 if `answer` isn't a single A–Z letter.
    public var answerIndex: Int {
        guard let scalar = answer.uppercased().unicodeScalars.first,
              answer.count == 1, scalar.value >= 65, scalar.value <= 90
        else { return -1 }
        return Int(scalar.value) - 65
    }

    /// The correct option text indexes a real entry and there are at least two
    /// options. Used by tests to catch authoring slips.
    public var isWellFormed: Bool {
        options.count >= 2 && (0..<options.count).contains(answerIndex)
    }
}

/// The full Mercurius curriculum — 8 units of structured lessons + cumulative unit tests.
/// Content mirrors the server's CURRICULUM_PROMPT + web widget, so the
/// iOS experience stays consistent with the web.
public enum MercuriusCurriculum {
    public static let units: [Unit] = [
        Unit(
            id: "unit_1",
            number: "01",
            title: "How AI Actually Works",
            summary: "LLMs, training data, next-token prediction, and why AI can sound confident but still be wrong.",
            lessons: [
                Lesson(
                    id: "u1_l1", number: 1,
                    title: "What happens when you type a prompt",
                    objective: "Understand tokenization and next-token prediction.",
                    starter: "[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise."
                ),
                Lesson(
                    id: "u1_l2", number: 2,
                    title: "Training data and where knowledge comes from",
                    objective: "Understand how LLMs are trained and what their knowledge actually is.",
                    starter: "[CURRICULUM: Unit 1, Lesson 2] Explain where an LLM's knowledge comes from — training data, RLHF, and fine-tuning. After the explanation, give me an exercise to test my understanding."
                ),
                Lesson(
                    id: "u1_l3", number: 3,
                    title: "Why AI sounds confident but can be wrong",
                    objective: "Understand hallucination and the confidence-accuracy gap.",
                    starter: "[CURRICULUM: Unit 1, Lesson 3] Teach me about AI hallucination and why LLMs can sound confident even when wrong. Give a concrete example, then an exercise where I have to identify a potential hallucination."
                ),
                Lesson(
                    id: "u1_l4", number: 4,
                    title: "Unit review and application",
                    objective: "Apply everything from Unit 1 to a real scenario.",
                    starter: "[CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive exercise that tests everything from Unit 1: tokenization, training data, and hallucination. Then grade my performance and tell me what to revisit."
                ),
            ]
        ),
        Unit(
            id: "unit_2",
            number: "02",
            title: "Bias & Fairness",
            summary: "Where AI bias comes from, real cases like COMPAS and facial recognition, and why \"objective algorithm\" is a myth.",
            lessons: [
                Lesson(
                    id: "u2_l1", number: 1,
                    title: "Where bias enters AI systems",
                    objective: "Understand the pipeline of bias: data, design, deployment.",
                    starter: "[CURRICULUM: Unit 2, Lesson 1] Walk me through how bias enters AI systems at each stage — data collection, model design, and deployment. After explaining, give me an exercise."
                ),
                Lesson(
                    id: "u2_l2", number: 2,
                    title: "Case study: COMPAS and criminal justice",
                    objective: "Analyze a real-world case of algorithmic bias.",
                    starter: "[CURRICULUM: Unit 2, Lesson 2] Teach me about the COMPAS algorithm and what went wrong. Present the case, then give me an exercise where I analyze the tradeoffs involved."
                ),
                Lesson(
                    id: "u2_l3", number: 3,
                    title: "Facial recognition and representation",
                    objective: "Understand bias in computer vision systems.",
                    starter: "[CURRICULUM: Unit 2, Lesson 3] Explain the bias problems in facial recognition systems — the Gender Shades study and Joy Buolamwini's work. Then give me an exercise."
                ),
                Lesson(
                    id: "u2_l4", number: 4,
                    title: "Building a bias audit",
                    objective: "Apply bias analysis to a new scenario.",
                    starter: "[CURRICULUM: Unit 2, Lesson 4 - Review] Give me a scenario where an AI system is being deployed and have me conduct a bias audit. Grade my analysis and provide detailed feedback."
                ),
            ]
        ),
        Unit(
            id: "unit_3",
            number: "03",
            title: "AI in Society",
            summary: "AI in hiring, healthcare, criminal justice, and education — who benefits, who gets harmed, and what the stakes are.",
            lessons: [
                Lesson(
                    id: "u3_l1", number: 1,
                    title: "AI in hiring and employment",
                    objective: "Understand automated hiring tools and their consequences.",
                    starter: "[CURRICULUM: Unit 3, Lesson 1] Teach me how AI is used in hiring — resume screening, video interviews, personality analysis. What are the benefits and what can go wrong? Then give me an exercise."
                ),
                Lesson(
                    id: "u3_l2", number: 2,
                    title: "AI in healthcare",
                    objective: "Evaluate AI applications in medical contexts.",
                    starter: "[CURRICULUM: Unit 3, Lesson 2] Walk me through how AI is used in healthcare — diagnostics, drug discovery, triage. What are the stakes when it fails? Give me an exercise after."
                ),
                Lesson(
                    id: "u3_l3", number: 3,
                    title: "AI in education",
                    objective: "Think critically about AI tools in learning.",
                    starter: "[CURRICULUM: Unit 3, Lesson 3] How is AI changing education — tutoring, grading, plagiarism detection? What should students and teachers be aware of? Give me an exercise."
                ),
                Lesson(
                    id: "u3_l4", number: 4,
                    title: "Stakeholder analysis",
                    objective: "Map who benefits and who is harmed by an AI system.",
                    starter: "[CURRICULUM: Unit 3, Lesson 4 - Review] Present me with a real AI deployment scenario and have me do a full stakeholder analysis: who benefits, who is harmed, what are the power dynamics. Grade my work."
                ),
            ]
        ),
        Unit(
            id: "unit_4",
            number: "04",
            title: "Prompt Engineering",
            summary: "How framing changes outputs, few-shot prompting, and how to use AI critically rather than passively.",
            lessons: [
                Lesson(
                    id: "u4_l1", number: 1,
                    title: "How framing changes everything",
                    objective: "Learn how different phrasings produce different outputs.",
                    starter: "[CURRICULUM: Unit 4, Lesson 1] Show me how the way I phrase a prompt completely changes the output. Give me examples of the same question asked 3 different ways with different results. Then give me a practice exercise."
                ),
                Lesson(
                    id: "u4_l2", number: 2,
                    title: "Few-shot prompting and chain-of-thought",
                    objective: "Master intermediate prompting techniques.",
                    starter: "[CURRICULUM: Unit 4, Lesson 2] Teach me few-shot prompting and chain-of-thought techniques. Explain each with examples, then give me exercises where I practice both."
                ),
                Lesson(
                    id: "u4_l3", number: 3,
                    title: "Critical prompting: getting AI to admit uncertainty",
                    objective: "Learn how to prompt for honesty, not just answers.",
                    starter: "[CURRICULUM: Unit 4, Lesson 3] Teach me how to prompt AI to be more honest — asking for confidence levels, requesting counterarguments, forcing nuance. Give me exercises to practice."
                ),
                Lesson(
                    id: "u4_l4", number: 4,
                    title: "Prompt challenge",
                    objective: "Solve a real problem using advanced prompting.",
                    starter: "[CURRICULUM: Unit 4, Lesson 4 - Review] Give me a challenging real-world task and have me write the best prompt I can for it. Then critique my prompt and suggest improvements. Grade my technique."
                ),
            ]
        ),
        Unit(
            id: "unit_5",
            number: "05",
            title: "Ethics & Alignment",
            summary: "The hardest problems: alignment, autonomous weapons, corporate responsibility, and what happens when AI fails.",
            lessons: [
                Lesson(
                    id: "u5_l1", number: 1,
                    title: "The alignment problem",
                    objective: "Understand why aligning AI with human values is hard.",
                    starter: "[CURRICULUM: Unit 5, Lesson 1] Explain the alignment problem in AI — what it is, why it is hard, and what the stakes are. Use concrete examples. Then give me an exercise."
                ),
                Lesson(
                    id: "u5_l2", number: 2,
                    title: "Autonomous weapons and lethal AI",
                    objective: "Grapple with the ethics of autonomous weapons systems.",
                    starter: "[CURRICULUM: Unit 5, Lesson 2] Teach me about autonomous weapons and the debate around lethal AI decision-making. Present both sides, then give me a scenario-based exercise."
                ),
                Lesson(
                    id: "u5_l3", number: 3,
                    title: "Corporate responsibility and open vs. closed AI",
                    objective: "Understand who controls AI and why it matters.",
                    starter: "[CURRICULUM: Unit 5, Lesson 3] Walk me through the debate about open vs. closed AI models and corporate responsibility. Who should control AI development? Exercise after."
                ),
                Lesson(
                    id: "u5_l4", number: 4,
                    title: "Build your AI ethics framework",
                    objective: "Build a personal ethical framework for AI.",
                    starter: "[CURRICULUM: Unit 5, Lesson 4 - Final Review] Have me build my own AI ethics framework from everything I have learned across all 5 units. Ask me hard questions, challenge my reasoning, and grade the result."
                ),
            ]
        ),
        Unit(
            id: "unit_6",
            number: "06",
            title: "Spotting AI: Deepfakes & Synthetic Media",
            summary: "How AI generates images, voice, and video — and how to tell what's real, from detection tricks to deepfake scams and the 'liar's dividend.'",
            lessons: [
                Lesson(
                    id: "u6_l1", number: 1,
                    title: "How AI makes images, voice, and video",
                    objective: "Understand how generative models create synthetic media.",
                    starter: "[CURRICULUM: Unit 6, Lesson 1] Teach me how AI actually generates images, voice, and video — diffusion models and voice cloning, in plain terms, with real tools as examples. Then give me a hands-on exercise."
                ),
                Lesson(
                    id: "u6_l2", number: 2,
                    title: "Spotting AI-generated content",
                    objective: "Learn practical techniques to detect synthetic media.",
                    starter: "[CURRICULUM: Unit 6, Lesson 2] Teach me how to tell if an image, video, or audio clip was AI-generated — the real tells, provenance signals like C2PA / Content Credentials, and reverse search. Then give me an exercise."
                ),
                Lesson(
                    id: "u6_l3", number: 3,
                    title: "Deepfakes, scams, and consent",
                    objective: "Understand the real harms of deepfakes and how to respond.",
                    starter: "[CURRICULUM: Unit 6, Lesson 3] Teach me about deepfakes and voice-clone scams — real cases, the consent and harassment problems, and how to protect myself. Then give me a scenario-based exercise."
                ),
                Lesson(
                    id: "u6_l4", number: 4,
                    title: "Misinformation and the liar's dividend",
                    objective: "Understand how synthetic media distorts truth and trust.",
                    starter: "[CURRICULUM: Unit 6, Lesson 4] Teach me how AI-generated media fuels misinformation, and explain the 'liar's dividend' — how the mere existence of fakes lets people deny real things. Then give me an exercise."
                ),
                Lesson(
                    id: "u6_l5", number: 5,
                    title: "Unit review: verify a viral claim",
                    objective: "Apply detection and verification skills end-to-end.",
                    starter: "[CURRICULUM: Unit 6, Lesson 5 - Review] Give me a realistic viral media claim and have me verify it end-to-end — is it real, AI-generated, or genuine but miscaptioned? Then grade my process A–D and tell me what to revisit."
                ),
            ]
        ),
        Unit(
            id: "unit_7",
            number: "07",
            title: "Using AI Well",
            summary: "The practical literacy: using AI to learn instead of avoid learning, researching and writing with it honestly, and protecting your data.",
            lessons: [
                Lesson(
                    id: "u7_l1", number: 1,
                    title: "Thinking partner, not a crutch",
                    objective: "Use AI to learn more, not to skip the thinking.",
                    starter: "[CURRICULUM: Unit 7, Lesson 1] Teach me the difference between using AI to actually learn versus to avoid thinking — the cognitive-offloading trap, and how to use it as a tutor instead of an answer machine. Then give me an exercise."
                ),
                Lesson(
                    id: "u7_l2", number: 2,
                    title: "Research and fact-finding with AI",
                    objective: "Use AI for research without getting burned by its traps.",
                    starter: "[CURRICULUM: Unit 7, Lesson 2] Teach me how to use AI for research well — and its traps: hallucinated sources, sycophancy, and stale knowledge. Show me a verification workflow, then give me an exercise."
                ),
                Lesson(
                    id: "u7_l3", number: 3,
                    title: "Writing with AI honestly",
                    objective: "Use AI in your writing with integrity and your own voice.",
                    starter: "[CURRICULUM: Unit 7, Lesson 3] Teach me how to use AI in my writing honestly — disclosure, keeping my own voice, and where the line sits between help and cheating. Use real school-policy examples, then give me an exercise."
                ),
                Lesson(
                    id: "u7_l4", number: 4,
                    title: "Your data and privacy",
                    objective: "Understand what you reveal to AI and how to protect it.",
                    starter: "[CURRICULUM: Unit 7, Lesson 4] Teach me what really happens to the things I type into AI chatbots — training on your data, what gets stored, and what I should never share. Then give me an exercise."
                ),
                Lesson(
                    id: "u7_l5", number: 5,
                    title: "Unit review: your AI-use policy",
                    objective: "Design and defend your own rules for using AI.",
                    starter: "[CURRICULUM: Unit 7, Lesson 5 - Review] Have me write my own personal AI-use policy — when I will and won't use AI for schoolwork, and why — then challenge my reasoning and grade it A–D."
                ),
            ]
        ),
        Unit(
            id: "unit_8",
            number: "08",
            title: "The Frontier: Agents & What's Next",
            summary: "Where AI is heading now — from chatbots to tool-using agents, multimodal models, what AI still can't do, and how to evaluate new claims without hype or fear.",
            lessons: [
                Lesson(
                    id: "u8_l1", number: 1,
                    title: "From chatbots to agents",
                    objective: "Understand what AI agents are and why they matter.",
                    starter: "[CURRICULUM: Unit 8, Lesson 1] Teach me the difference between a chatbot and an AI 'agent' that can use tools and take actions — what it unlocks and what new risks it creates. Use real examples, then give me an exercise."
                ),
                Lesson(
                    id: "u8_l2", number: 2,
                    title: "Multimodal AI",
                    objective: "Understand AI that sees, hears, and speaks.",
                    starter: "[CURRICULUM: Unit 8, Lesson 2] Teach me what multimodal AI is — models that handle images, audio, and video, not just text — what it enables and the new failure modes it brings. Then give me an exercise."
                ),
                Lesson(
                    id: "u8_l3", number: 3,
                    title: "What AI still can't do",
                    objective: "Understand the real limits of today's AI.",
                    starter: "[CURRICULUM: Unit 8, Lesson 3] Teach me what current AI still genuinely struggles with — reasoning reliability, the 'jagged frontier,' and why it fails in surprising ways. Use concrete examples, then give me an exercise."
                ),
                Lesson(
                    id: "u8_l4", number: 4,
                    title: "Keeping up and staying critical",
                    objective: "Build habits to evaluate new AI claims and tools.",
                    starter: "[CURRICULUM: Unit 8, Lesson 4] Teach me how to evaluate new AI products and bold claims without falling for hype or fear — what questions to ask and what evidence to demand. Then give me an exercise."
                ),
                Lesson(
                    id: "u8_l5", number: 5,
                    title: "Unit review: evaluate a real AI product",
                    objective: "Apply critical evaluation to a real AI tool.",
                    starter: "[CURRICULUM: Unit 8, Lesson 5 - Review] Give me a real AI product or agent and have me evaluate it — capabilities, limits, risks, and whether I'd trust it and why. Then grade me A–D."
                ),
            ]
        ),
    ]

    public static func unit(withId id: String) -> Unit? {
        units.first { $0.id == id }
    }

    public static var allLessons: [Lesson] {
        units.flatMap { $0.lessons }
    }

    /// The unit that contains the lesson with `lessonId`, or nil if unknown.
    public static func unit(containingLesson lessonId: String) -> Unit? {
        units.first { unit in unit.lessons.contains { $0.id == lessonId } }
    }

    /// The next lesson after `lessonId` **within the same unit**, or nil if it's
    /// the unit's last lesson (or the id is unknown). Sequential unlock gating is
    /// per-unit, so "next" is too — finishing a unit's last lesson returns nil
    /// (the student moves on via the unit test / the next unit).
    public static func lesson(after lessonId: String) -> Lesson? {
        for unit in units {
            if let idx = unit.lessons.firstIndex(where: { $0.id == lessonId }) {
                let next = idx + 1
                return next < unit.lessons.count ? unit.lessons[next] : nil
            }
        }
        return nil
    }

    // MARK: - Versioning + migrations
    //
    // The curriculum is hand-authored static data; any time we rename or
    // reorder lesson ids (e.g. "u1_l1" → "u1_intro") we bump `version` and
    // add an entry to `migrations(from:to:)` below. `CurriculumProgressStore`
    // stores the curriculum version alongside the completed-id set, and
    // on load it runs every migration from the stored version up to the
    // current one — so a user's hard-won lesson completions survive
    // curriculum reshuffles rather than orphaning to dead ids.

    /// Monotonic version stamp for the curriculum content. Bump whenever
    /// a lesson id is renamed, reordered, or removed — i.e. anything that
    /// would orphan existing stored progress.
    public static let version: Int = 1

    /// Per-step migration map: returns the set of `oldId → newId`
    /// rewrites that should apply when moving from `from` to `from + 1`.
    /// Missing keys = no change for that id.
    ///
    /// Example for a future bump:
    /// ```
    /// case 1:
    ///     return ["u1_l1": "u1_intro", "u1_l2": "u1_tokens"]
    /// ```
    public static func migrations(stepFrom from: Int) -> [String: String] {
        switch from {
        // No migrations yet — v1 is the only shipped curriculum version.
        default:
            return [:]
        }
    }
}

// MARK: - Unit tests (cumulative end-of-unit assessments)

extension MercuriusCurriculum {

    /// The cumulative test for a unit, or nil if the id is unknown.
    public static func unitTest(for unitId: String) -> UnitTest? {
        unitTests.first { $0.unitId == unitId }
    }

    /// One authored `UnitTest` per unit. Questions span all four lessons; the
    /// `defensePrompt` is graded A–D by the server (pass = A/B). Carried under
    /// the same `version` stamp as the lessons.
    static let unitTests: [UnitTest] = [
        UnitTest(
            unitId: "unit_1",
            questions: [
                UnitTestQuestion(
                    id: "ut1_q1",
                    q: "When you type a prompt into an LLM, what is the first thing that happens to your text?",
                    options: [
                        "It is searched against a database of stored answers",
                        "It is broken into tokens and converted to numbers",
                        "It is sent to a human reviewer",
                        "It is translated into a programming language",
                    ],
                    answer: "B",
                    explanation: "LLMs tokenize text into chunks and map them to numeric IDs the model can process — they don't look answers up in a database."
                ),
                UnitTestQuestion(
                    id: "ut1_q2",
                    q: "At its core, what is an LLM doing when it generates a response?",
                    options: [
                        "Retrieving the correct answer from its training data",
                        "Predicting the next token, one at a time, by probability",
                        "Reasoning through formal logic rules",
                        "Querying the live internet",
                    ],
                    answer: "B",
                    explanation: "An LLM repeatedly predicts the most likely next token given everything so far — it generates text, it doesn't retrieve stored answers."
                ),
                UnitTestQuestion(
                    id: "ut1_q3",
                    q: "Where does an LLM's 'knowledge' actually come from?",
                    options: [
                        "A real-time connection to the web",
                        "Statistical patterns learned from a large body of training text",
                        "A hand-written rulebook of facts",
                        "Only the user's previous messages",
                    ],
                    answer: "B",
                    explanation: "Knowledge is encoded as patterns learned during training — not a live lookup, a fact database, or just your chat history."
                ),
                UnitTestQuestion(
                    id: "ut1_q4",
                    q: "An LLM gives a confident, detailed citation for a study that doesn't exist. This is best described as:",
                    options: [
                        "A database error",
                        "A network timeout",
                        "A hallucination — fluent output not grounded in fact",
                        "A deliberate lie",
                    ],
                    answer: "C",
                    explanation: "Hallucination is plausible-sounding output that isn't grounded in real facts. It isn't intent ('lie') or a system error."
                ),
                UnitTestQuestion(
                    id: "ut1_q5",
                    q: "Why can an LLM sound equally confident whether it's right or wrong?",
                    options: [
                        "It always knows when it's wrong but hides it",
                        "Its fluency reflects language patterns, not a check on truth",
                        "It fact-checks every sentence before sending",
                        "It only sounds confident when it's correct",
                    ],
                    answer: "B",
                    explanation: "Confidence in tone comes from language modeling; there's no built-in truth meter, so fluency never guarantees accuracy."
                ),
            ],
            defensePrompt: "In your own words, explain why an LLM can produce a confident, well-written answer that is still factually wrong. Reference how it generates text and where its knowledge comes from, and describe one habit you'd use to catch such errors."
        ),
        UnitTest(
            unitId: "unit_2",
            questions: [
                UnitTestQuestion(
                    id: "ut2_q1",
                    q: "A facial-recognition tool trained mostly on light-skinned faces performs worse on dark-skinned faces. Where did bias primarily enter?",
                    options: [
                        "Data collection (unrepresentative training data)",
                        "The user interface",
                        "The server hardware",
                        "The programming language",
                    ],
                    answer: "A",
                    explanation: "Skewed, unrepresentative training data is a classic source of biased outcomes — the model learned from faces that didn't represent everyone."
                ),
                UnitTestQuestion(
                    id: "ut2_q2",
                    q: "The COMPAS recidivism algorithm was criticized mainly because it:",
                    options: [
                        "Was too slow to run",
                        "Produced different error rates across racial groups",
                        "Required an internet connection",
                        "Was released as open source",
                    ],
                    answer: "B",
                    explanation: "Investigations found it mislabeled risk at different rates across racial groups — a fairness problem, not a performance one."
                ),
                UnitTestQuestion(
                    id: "ut2_q3",
                    q: "The COMPAS debate showed some fairness definitions can't all be satisfied at once. This means:",
                    options: [
                        "Fairness is easy to define mathematically",
                        "There can be genuine tradeoffs between competing notions of fairness",
                        "Bias is always intentional",
                        "Algorithms are inherently objective",
                    ],
                    answer: "B",
                    explanation: "Different fairness criteria can be mathematically incompatible, forcing value-laden tradeoffs — there's no single 'fair.'"
                ),
                UnitTestQuestion(
                    id: "ut2_q4",
                    q: "Joy Buolamwini's Gender Shades study found that commercial facial-analysis systems:",
                    options: [
                        "Worked equally well for everyone",
                        "Could not detect any faces",
                        "Had much higher error rates for darker-skinned women",
                        "Were illegal to sell",
                    ],
                    answer: "C",
                    explanation: "Error rates were dramatically higher for darker-skinned women than lighter-skinned men, exposing representation bias."
                ),
                UnitTestQuestion(
                    id: "ut2_q5",
                    q: "Why is calling an algorithm 'objective' often misleading?",
                    options: [
                        "Algorithms can't do arithmetic",
                        "They encode the assumptions and biases of their data and designers",
                        "They behave completely randomly",
                        "They never make mistakes",
                    ],
                    answer: "B",
                    explanation: "Algorithms reflect human choices and the data they learn from; 'objective' can disguise embedded bias."
                ),
            ],
            defensePrompt: "A city wants to use an AI tool to screen job applicants. Name two specific ways bias could enter this system (at different stages) and one concrete safeguard you'd require before it goes live. Justify each."
        ),
        UnitTest(
            unitId: "unit_3",
            questions: [
                UnitTestQuestion(
                    id: "ut3_q1",
                    q: "An AI résumé screener is trained on a company's past hires. A key risk is that it may:",
                    options: [
                        "Run too slowly to be useful",
                        "Reproduce and amplify historical hiring biases",
                        "Refuse to read PDF files",
                        "Always pick the strongest candidate",
                    ],
                    answer: "B",
                    explanation: "Learning from past hires can bake in and scale up whatever bias those past decisions contained."
                ),
                UnitTestQuestion(
                    id: "ut3_q2",
                    q: "Compared with an AI movie recommender, why are the stakes higher for an AI medical-diagnosis tool?",
                    options: [
                        "Medical models have more parameters",
                        "Errors can directly harm health or lives",
                        "Movies are harder to model than medicine",
                        "There are no real stakes in either",
                    ],
                    answer: "B",
                    explanation: "In high-stakes domains, a wrong output can cause real physical harm — that raises the bar for reliability and oversight."
                ),
                UnitTestQuestion(
                    id: "ut3_q3",
                    q: "An AI plagiarism detector sometimes flags innocent students. The key literacy lesson is:",
                    options: [
                        "Always trust the tool's verdict",
                        "Treat AI outputs as fallible evidence, not final verdicts",
                        "Ban student writing entirely",
                        "Detectors are essentially never wrong",
                    ],
                    answer: "B",
                    explanation: "These tools have false positives; their output should inform human judgment, not replace it."
                ),
                UnitTestQuestion(
                    id: "ut3_q4",
                    q: "In a stakeholder analysis of an AI deployment, you primarily map:",
                    options: [
                        "Only the company's expected profit",
                        "Who benefits, who is harmed, and the power dynamics",
                        "The model's parameter count",
                        "Where the servers are located",
                    ],
                    answer: "B",
                    explanation: "Stakeholder analysis surfaces winners, losers, and imbalances of power around a system."
                ),
                UnitTestQuestion(
                    id: "ut3_q5",
                    q: "An AI triage system speeds up an ER but deprioritizes a group whose symptoms it underweights. This shows AI benefits and harms are often:",
                    options: [
                        "Shared equally by everyone",
                        "Distributed unevenly across different groups",
                        "Always entirely negative",
                        "Impossible to anticipate",
                    ],
                    answer: "B",
                    explanation: "Benefits and harms usually fall on different groups — which is exactly what stakeholder thinking is meant to reveal."
                ),
            ],
            defensePrompt: "Pick one domain — hiring, healthcare, or education. Describe a realistic AI deployment in it, then name who benefits most, who bears the greatest risk, and one policy you'd put in place to protect the people at risk. Defend your reasoning."
        ),
        UnitTest(
            unitId: "unit_4",
            questions: [
                UnitTestQuestion(
                    id: "ut4_q1",
                    q: "Asking 'List the benefits of X' versus 'List the benefits AND risks of X' shows that:",
                    options: [
                        "Prompt wording has no real effect",
                        "Framing shapes what the model includes or leaves out",
                        "The model ignores how you phrase things",
                        "Only spelling matters",
                    ],
                    answer: "B",
                    explanation: "How you frame a request steers the scope and slant of the answer — a core prompt-engineering insight."
                ),
                UnitTestQuestion(
                    id: "ut4_q2",
                    q: "'Few-shot' prompting means:",
                    options: [
                        "Giving the model a few worked examples of the task",
                        "Using as few words as possible",
                        "Running the model only a few times",
                        "Limiting the reply to a few tokens",
                    ],
                    answer: "A",
                    explanation: "Few-shot = showing a handful of input→output examples so the model infers the pattern you want."
                ),
                UnitTestQuestion(
                    id: "ut4_q3",
                    q: "Asking the model to 'think step by step' (chain-of-thought) helps most with:",
                    options: [
                        "Multi-step reasoning problems",
                        "Making the model run faster",
                        "Forcing every answer to be shorter",
                        "Changing what the model was trained on",
                    ],
                    answer: "A",
                    explanation: "Eliciting intermediate steps improves performance on reasoning-heavy tasks."
                ),
                UnitTestQuestion(
                    id: "ut4_q4",
                    q: "Which prompt is most likely to surface the model's uncertainty?",
                    options: [
                        "'Just give me the answer.'",
                        "'How confident are you, and what might make this wrong?'",
                        "'Answer in one word.'",
                        "'You are always right.'",
                    ],
                    answer: "B",
                    explanation: "Explicitly asking for a confidence level and possible failure modes prompts more honest, hedged answers."
                ),
                UnitTestQuestion(
                    id: "ut4_q5",
                    q: "Using AI critically rather than passively includes:",
                    options: [
                        "Accepting the first answer as final",
                        "Requesting counterarguments and checkable sources",
                        "Telling the model never to hedge",
                        "Only ever asking yes/no questions",
                    ],
                    answer: "B",
                    explanation: "Asking for counterarguments and sources you can verify keeps you in control instead of trusting blindly."
                ),
            ],
            defensePrompt: "You want an AI to help plan a fair class debate on a controversial topic. Write the prompt you'd use, then name two specific techniques you applied (e.g., role framing, few-shot examples, asking for counterarguments) and explain why each improves the result."
        ),
        UnitTest(
            unitId: "unit_5",
            questions: [
                UnitTestQuestion(
                    id: "ut5_q1",
                    q: "The 'alignment problem' refers to the difficulty of:",
                    options: [
                        "Running AI on specially aligned hardware",
                        "Getting AI systems to reliably pursue what humans actually intend",
                        "Aligning text neatly on the screen",
                        "Training AI models more quickly",
                    ],
                    answer: "B",
                    explanation: "Alignment is about AI reliably doing what we mean and value — not just what we literally specify."
                ),
                UnitTestQuestion(
                    id: "ut5_q2",
                    q: "An AI told to 'maximize a score' finds a loophole that boosts the score without achieving the real goal. This illustrates:",
                    options: [
                        "That AI always understands human intent",
                        "Reward hacking / specification gaming",
                        "A hardware failure",
                        "Perfect alignment",
                    ],
                    answer: "B",
                    explanation: "Optimizing the literal metric instead of the intended goal is classic specification gaming — a core alignment worry."
                ),
                UnitTestQuestion(
                    id: "ut5_q3",
                    q: "A central ethical objection to lethal autonomous weapons is that:",
                    options: [
                        "They are too expensive to build",
                        "Delegating kill decisions to machines erodes human accountability",
                        "They operate too slowly",
                        "They consume too much electricity",
                    ],
                    answer: "B",
                    explanation: "Removing meaningful human control over lethal force raises deep accountability and moral-responsibility concerns."
                ),
                UnitTestQuestion(
                    id: "ut5_q4",
                    q: "A genuine tradeoff of releasing powerful AI models openly is that it:",
                    options: [
                        "Has no real downsides",
                        "Increases transparency and access but can also ease misuse",
                        "Guarantees misuse is prevented",
                        "Is identical to a closed release",
                    ],
                    answer: "B",
                    explanation: "Openness aids scrutiny and broad access, but can lower barriers to misuse — a real tension, not a free win."
                ),
                UnitTestQuestion(
                    id: "ut5_q5",
                    q: "When a few companies control frontier AI, a key AI-literacy concern is:",
                    options: [
                        "Concentrated power over a society-shaping technology",
                        "That the models become too cheap",
                        "That the code becomes unreadable",
                        "Nothing — who controls AI doesn't matter",
                    ],
                    answer: "A",
                    explanation: "Concentrated control over an influential technology raises questions about accountability and how power is distributed."
                ),
            ],
            defensePrompt: "State one principle that should guide how powerful AI is built or governed. Give the strongest objection to your principle, then respond to that objection. Show you can hold the tension honestly rather than dismissing the other side."
        ),
        UnitTest(
            unitId: "unit_6",
            questions: [
                UnitTestQuestion(
                    id: "ut6_q1",
                    q: "Most modern AI image generators create an image by:",
                    options: [
                        "Copying and pasting pieces of existing photos",
                        "Starting from random noise and refining it toward your prompt (diffusion)",
                        "Searching the web for a matching photo",
                        "Asking a human artist to draw it",
                    ],
                    answer: "B",
                    explanation: "Diffusion models begin with random noise and iteratively denoise it toward the prompt — they generate new pixels, they don't copy or retrieve a photo."
                ),
                UnitTestQuestion(
                    id: "ut6_q2",
                    q: "Content Credentials (the C2PA standard) help you judge a piece of media by:",
                    options: [
                        "Blurring any AI-generated faces automatically",
                        "Attaching tamper-evident metadata about how a file was created and edited",
                        "Scanning only for a hidden pixel watermark",
                        "Deleting fake images from your device",
                    ],
                    answer: "B",
                    explanation: "C2PA / Content Credentials attach signed provenance metadata recording where an asset came from and how it was edited."
                ),
                UnitTestQuestion(
                    id: "ut6_q3",
                    q: "Which is the LEAST reliable way to decide an image is AI-generated in 2026?",
                    options: [
                        "Checking its provenance / Content Credentials",
                        "Reverse image searching for an original source",
                        "Assuming any image with one small visual glitch must be fake",
                        "Tracing it to an authoritative original publisher",
                    ],
                    answer: "C",
                    explanation: "Glitches (hands, garbled text) are getting rarer and real photos have artifacts too — a single glitch is weak evidence. Provenance and sourcing are far stronger."
                ),
                UnitTestQuestion(
                    id: "ut6_q4",
                    q: "You get a call in your friend's exact voice urgently asking you to send money. The safest move is:",
                    options: [
                        "Send it — the voice proves it's really them",
                        "Hang up and verify through a separate, known channel before doing anything",
                        "Keep them talking until you feel sure",
                        "Reply with your bank details to confirm who you are",
                    ],
                    answer: "B",
                    explanation: "A voice can be cloned from seconds of audio. Verify urgent money requests out-of-band through a channel you already trust."
                ),
                UnitTestQuestion(
                    id: "ut6_q5",
                    q: "The 'liar's dividend' describes how widespread deepfakes:",
                    options: [
                        "Make it easier to prove something is real",
                        "Let people dismiss genuine evidence by claiming 'it's probably fake'",
                        "Pay the creators who make the fakes",
                        "Have no real effect on public trust",
                    ],
                    answer: "B",
                    explanation: "Once anything could be fake, bad actors can wave away real, inconvenient footage as 'just a deepfake' — that benefit to liars is the liar's dividend."
                ),
            ],
            defensePrompt: "A shocking video of a public figure is spreading fast online. Walk through exactly how you'd decide whether it's real, AI-generated, or genuine-but-miscaptioned — name at least three concrete checks and what would make you trust or doubt it."
        ),
        UnitTest(
            unitId: "unit_7",
            questions: [
                UnitTestQuestion(
                    id: "ut7_q1",
                    q: "Using AI to actually LEARN a hard concept (rather than avoid it) looks like:",
                    options: [
                        "Pasting the question and copying the answer down",
                        "Having it explain, then re-explaining it back in your own words and quizzing yourself",
                        "Asking it to write the whole assignment",
                        "Turning in its output unchanged",
                    ],
                    answer: "B",
                    explanation: "Learning requires doing the thinking yourself — use AI to explain and test you, then retrieve and apply it on your own."
                ),
                UnitTestQuestion(
                    id: "ut7_q2",
                    q: "An AI hands you three perfect-looking citations for a paper. Before using them you should:",
                    options: [
                        "Trust them — they include page numbers",
                        "Check that each source actually exists and really says what's claimed",
                        "Ask the AI to add a few more citations",
                        "Assume they're fine if they're formatted correctly",
                    ],
                    answer: "B",
                    explanation: "LLMs routinely fabricate plausible-looking citations. Always confirm each source exists and supports the claim before citing it."
                ),
                UnitTestQuestion(
                    id: "ut7_q3",
                    q: "AI chatbots often agree with whatever you propose. The right lesson is:",
                    options: [
                        "Its agreement proves you're right",
                        "You can't treat its agreement as independent confirmation — ask it to argue the other side",
                        "You should always phrase things as leading questions",
                        "It is incapable of disagreeing",
                    ],
                    answer: "B",
                    explanation: "Sycophancy means models tend to validate the user, so agreement isn't real evidence. Ask it to make the strongest opposing case."
                ),
                UnitTestQuestion(
                    id: "ut7_q4",
                    q: "Under a typical school AI policy, which use is most likely to count as cheating?",
                    options: [
                        "Asking AI to explain a concept you're stuck on",
                        "Using AI to quiz yourself before a test",
                        "Submitting an AI-written essay as your own work",
                        "Asking AI for counterarguments to your own draft",
                    ],
                    answer: "C",
                    explanation: "Passing off AI-generated work as your own is the classic integrity violation. Using AI to learn, quiz, or critique is usually fine — though disclosure rules vary."
                ),
                UnitTestQuestion(
                    id: "ut7_q5",
                    q: "What's the safest assumption about sensitive info (passwords, others' private details) you type into a chatbot?",
                    options: [
                        "It disappears the moment you close the chat",
                        "It may be stored and could be used to improve models unless you've opted out",
                        "It's end-to-end encrypted and unreadable by anyone",
                        "It's automatically deleted after 24 hours",
                    ],
                    answer: "B",
                    explanation: "Many services retain conversations and may train on them by default — don't paste secrets or other people's private data."
                ),
            ],
            defensePrompt: "Name one task you'd use AI for and one you deliberately wouldn't. For each, justify your choice in terms of learning, honesty, and verification — and name the safeguard you'd apply."
        ),
        UnitTest(
            unitId: "unit_8",
            questions: [
                UnitTestQuestion(
                    id: "ut8_q1",
                    q: "What mainly separates an AI 'agent' from a regular chatbot?",
                    options: [
                        "It runs on a bigger model",
                        "It can take actions and use tools — browse, run code, call apps — to pursue a goal, not just chat",
                        "It only ever replies in JSON",
                        "It never makes mistakes",
                    ],
                    answer: "B",
                    explanation: "Agents plan and act using tools to accomplish multi-step goals — powerful, but it raises new oversight and safety risks a chatbot doesn't."
                ),
                UnitTestQuestion(
                    id: "ut8_q2",
                    q: "A key NEW risk when an AI agent can take real actions is that:",
                    options: [
                        "It types more slowly",
                        "A mistake or a manipulated instruction can cause real-world consequences, not just a wrong sentence",
                        "It can never be switched off",
                        "It uses no electricity",
                    ],
                    answer: "B",
                    explanation: "When an agent actually sends, buys, or deletes things, errors and prompt-injection have real consequences — meaningful human oversight matters more."
                ),
                UnitTestQuestion(
                    id: "ut8_q3",
                    q: "'Multimodal' AI means a model that can:",
                    options: [
                        "Run on several phones at once",
                        "Work across more than one kind of input or output — e.g. text, images, audio, video",
                        "Only translate between languages",
                        "Manage multiple passwords",
                    ],
                    answer: "B",
                    explanation: "Multimodal models handle several modalities — seeing an image, hearing audio, reading text — rather than text alone."
                ),
                UnitTestQuestion(
                    id: "ut8_q4",
                    q: "The 'jagged frontier' of AI capability describes how today's models:",
                    options: [
                        "Are equally good at everything",
                        "Can ace a genuinely hard task yet fail a task that looks easier, unpredictably",
                        "Improve on a fixed monthly schedule",
                        "Only work on weekends",
                    ],
                    answer: "B",
                    explanation: "Capability is uneven — strong on some surprisingly hard tasks, weak on some surprisingly easy ones — so 'it did X, so it can do easier Y' doesn't hold."
                ),
                UnitTestQuestion(
                    id: "ut8_q5",
                    q: "An ad claims a new AI is '99% accurate.' The best first question is:",
                    options: [
                        "'Where can I buy it?'",
                        "'Accurate at what task, measured how, and on whose data?'",
                        "'Is it the biggest model available?'",
                        "'Does it have a mobile app?'",
                    ],
                    answer: "B",
                    explanation: "A bare accuracy number is meaningless without the task, the benchmark, and the conditions — demand the specifics behind any bold claim."
                ),
            ],
            defensePrompt: "Pick a real AI tool or agent you've seen. Name one genuinely impressive thing it can do and one real limit or risk it has, then say whether you'd rely on it for something that matters — and what would have to be true for you to trust it."
        ),
    ]
}
