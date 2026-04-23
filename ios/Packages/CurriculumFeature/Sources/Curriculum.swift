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

/// The full Mercurius curriculum — 5 units × 4 lessons = 20 lessons.
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
    ]

    public static func unit(withId id: String) -> Unit? {
        units.first { $0.id == id }
    }

    public static var allLessons: [Lesson] {
        units.flatMap { $0.lessons }
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
