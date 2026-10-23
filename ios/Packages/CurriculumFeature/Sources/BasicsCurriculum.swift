import Foundation

/// The two courses the app teaches.
///
/// - **Basics**: a short, separate course for anyone new to AI chatbots
///   (5 units, 18 lessons, `b<unit>_l<lesson>` ids, `basics_<n>` units, no
///   unit checks). Written for any adult beginner; it works for teens too.
/// - **Deep dive**: the original 8-unit AI-literacy course
///   (`MercuriusCurriculum`, `u<unit>_l<lesson>` ids, `unit_<n>` units).
///   "Deep dive" is only its name where the two sit side by side.
///
/// Progress for both lives in the one `CurriculumProgressStore` and syncs
/// as one list: the ids never overlap, and every count is per track.
public enum CurriculumTrack: String, CaseIterable, Sendable, Codable, Hashable {
    case basics
    case deepDive

    /// The name on the switch, the sidebar and the onboarding cards.
    public var displayName: String {
        switch self {
        case .basics: return "Basics"
        case .deepDive: return "Deep dive"
        }
    }

    public var units: [Unit] {
        switch self {
        case .basics: return BasicsCurriculum.units
        case .deepDive: return MercuriusCurriculum.units
        }
    }

    public var allLessons: [Lesson] { units.flatMap(\.lessons) }

    /// Only the Deep dive has cumulative unit checks.
    public var hasUnitTests: Bool { self == .deepDive }

    public func unit(withId id: String) -> Unit? {
        units.first { $0.id == id }
    }

    public func unit(containingLesson lessonId: String) -> Unit? {
        units.first { unit in unit.lessons.contains { $0.id == lessonId } }
    }

    /// The next lesson in the same unit, or nil after the unit's last.
    public func lesson(after lessonId: String) -> Lesson? {
        guard let unit = unit(containingLesson: lessonId),
              let index = unit.lessons.firstIndex(where: { $0.id == lessonId }),
              index + 1 < unit.lessons.count
        else { return nil }
        return unit.lessons[index + 1]
    }

    /// The track an id belongs to, by its shape: `b1_l1` / `basics_1` are
    /// Basics, `u1_l1` / `unit_1` the Deep dive. Nil for anything else.
    public static func of(id: String) -> CurriculumTrack? {
        if BasicsCurriculum.isBasicsId(id) { return .basics }
        if id.range(of: #"^(u\d+_l\d+|unit_\d+)$"#, options: .regularExpression) != nil { return .deepDive }
        return nil
    }

    /// The unit holding a lesson, in whichever track has it.
    public static func unit(containingLesson lessonId: String) -> Unit? {
        for track in allCases {
            if let unit = track.unit(containingLesson: lessonId) { return unit }
        }
        return nil
    }

    /// A lesson by id, in whichever track has it.
    public static func lesson(withId lessonId: String) -> Lesson? {
        unit(containingLesson: lessonId)?.lessons.first { $0.id == lessonId }
    }
}

/// The Basics course: what a chatbot is, how to talk to one, and how to stay
/// safe, for anyone new to AI ("think of a grandma wanting to learn how to use
/// ChatGPT"). The content is the founder-reviewed curriculum
/// (`docs/basics/basics.json`, BASICS_CURRICULUM.md v1, 2026-10-21); a test
/// holds this file to that JSON.
///
/// A Basics lesson opens with a hidden starter that begins with the server's
/// Basics tag, `[BASICS: Unit N, Lesson M]`, at index 0. The server routes it
/// to its Basics guide (lib/basicsGuide.js) and never to the Deep-dive guide,
/// and records completion under the lesson's `b` id. The curriculum file's
/// older alias, `[CURRICULUM: Basics Unit N, Lesson M]`, is never sent: a
/// server from before Basics would read it as a Deep-dive lesson.
public enum BasicsCurriculum {
    /// "[BASICS:" — what every Basics starter begins with.
    public static let tagPrefix = "[BASICS:"

    /// "[BASICS: Unit 1, Lesson 3]", the server's canonical spelling.
    public static func tag(unit: Int, lesson: Int) -> String {
        "[BASICS: Unit \(unit), Lesson \(lesson)]"
    }

    /// `b1_l1` … `b5_l4`, or `basics_1` … `basics_5`.
    public static func isBasicsId(_ id: String) -> Bool {
        id.range(of: #"^(b\d+_l\d+|basics_\d+)$"#, options: .regularExpression) != nil
    }

    /// The lesson id for unit `unit`, lesson `lesson`: "b2_l3".
    public static func lessonId(unit: Int, lesson: Int) -> String { "b\(unit)_l\(lesson)" }

    /// The unit id for unit `number`: "basics_2".
    public static func unitId(_ number: Int) -> String { "basics_\(number)" }

    public static var allLessons: [Lesson] { units.flatMap(\.lessons) }

    public static func unit(withId id: String) -> Unit? { units.first { $0.id == id } }

    public static func unit(containingLesson lessonId: String) -> Unit? {
        CurriculumTrack.basics.unit(containingLesson: lessonId)
    }

    public static func lesson(withId lessonId: String) -> Lesson? {
        allLessons.first { $0.id == lessonId }
    }

    /// The four safety lessons. The server completes these only once the
    /// check is answered right (a wrong pick is corrected first).
    public static let safetyLessonIds: Set<String> = ["b2_l3", "b2_l4", "b5_l2", "b5_l3"]

    /// "Try this today": one real-life task for the screen after a lesson
    /// (BEGINNER_GUIDE §2.6), word for word from the curriculum.
    public static func tryThisToday(for lessonId: String) -> String? {
        tryThisToday[lessonId]
    }

    /// The message inside a "Try this today" line, ready to copy, when the
    /// line quotes one ("ask: “What could go wrong?”"). Nil when the line is
    /// a task with no message of its own.
    public static func tryThisTodayMessage(for lessonId: String) -> String? {
        guard let line = tryThisToday[lessonId] else { return nil }
        return quotedMessage(in: line)
    }

    /// The text between the first pair of straight or curly double quotes.
    static func quotedMessage(in line: String) -> String? {
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        guard let open = line.firstIndex(where: { quotes.contains($0) }) else { return nil }
        let rest = line[line.index(after: open)...]
        guard let close = rest.firstIndex(where: { quotes.contains($0) }) else { return nil }
        let message = rest[..<close].trimmingCharacters(in: .whitespaces)
        return message.isEmpty ? nil : message
    }

    static let tryThisToday: [String: String] = [
        "b1_l1": "Ask a chatbot one thing you've wondered about this week.",
        "b1_l2": "Ask a chatbot to help with a note you need to write this week.",
        "b1_l3": "Ask a chatbot about your hometown, and see what it gets right and wrong.",
        "b2_l1": "Ask a chatbot a real question you have this week. Try talking instead of typing.",
        "b2_l2": "When a chatbot uses a word you don't know, ask: \u{201C}What does that mean?\u{201D}",
        "b2_l3": "Next time you ask a chatbot for help, leave out names and numbers, and see if the help is still good.",
        "b2_l4": "Send the code-word text to your family.",
        "b3_l1": "Next time you ask a chatbot something, add who it's for and one limit.",
        "b3_l2": "Ask a chatbot to help with a plan, and add one detail about your situation.",
        "b3_l3": "Before your next plan, ask a chatbot: \u{201C}What could go wrong?\u{201D}",
        "b4_l1": "Ask a chatbot to write one email you've been putting off, then copy it into your email.",
        "b4_l2": "Find one confusing letter at home. Cover your name and numbers, then ask a chatbot what it means.",
        "b4_l3": "Ask a chatbot to plan a meal for your next visit with family or friends, or to cut a recipe down to size.",
        "b4_l4": "Ask a chatbot to teach you one small thing you've always wanted to know.",
        "b5_l1": "Next time a chatbot tells you something important, ask: \u{201C}Where could I check this?\u{201D}",
        "b5_l2": "Before your next appointment, ask a chatbot to help you list 3 questions to bring.",
        "b5_l3": "Tell a friend the four signs of a scam.",
        "b5_l4": "With someone you trust, get a chatbot app from the official app store and send your first message.",
    ]

    /// Basics' units and lessons. Titles, objectives and starters are the
    /// curriculum's; each starter's tag is the server's canonical one.
    public static let units: [Unit] = [
        Unit(
            id: "basics_1",
            number: "01",
            title: "Meet AI chatbots",
            summary: "What a chatbot is, what it's good at, and what it gets wrong.",
            lessons: [
                Lesson(
                    id: "b1_l1", number: 1,
                    title: "What is an AI chatbot?",
                    objective: "You'll send your first message to a chatbot.",
                    starter: "[BASICS: Unit 1, Lesson 1] Teach me what an AI chatbot is, in plain words. Keep it short, then let me try one."
                ),
                Lesson(
                    id: "b1_l2", number: 2,
                    title: "What chatbots are good at",
                    objective: "You'll get a chatbot to write a short note for you.",
                    starter: "[BASICS: Unit 1, Lesson 2] Show me what AI chatbots are good at in everyday life, in plain words. Then let me try one."
                ),
                Lesson(
                    id: "b1_l3", number: 3,
                    title: "What chatbots get wrong",
                    objective: "You'll see a chatbot get something wrong, and learn when to check.",
                    starter: "[BASICS: Unit 1, Lesson 3] Show me, in plain words, what AI chatbots get wrong and how to catch it. Then let me test you."
                ),
            ]
        ),
        Unit(
            id: "basics_2",
            number: "02",
            title: "Your first conversations, safely",
            summary: "Ask questions, follow up, keep private things private, and handle a fake family call.",
            lessons: [
                Lesson(
                    id: "b2_l1", number: 1,
                    title: "Asking a real question",
                    objective: "You'll ask a chatbot a real question from your own week.",
                    starter: "[BASICS: Unit 2, Lesson 1] Teach me how to ask an AI chatbot a real question, in plain words. Then let me ask you one."
                ),
                Lesson(
                    id: "b2_l2", number: 2,
                    title: "Following up",
                    objective: "You'll steer an answer with a follow-up, like \"shorter\" or \"in plain words.\"",
                    starter: "[BASICS: Unit 2, Lesson 2] Teach me how to follow up with an AI chatbot, including asking it for plainer words or a shorter answer. Then let me practice."
                ),
                Lesson(
                    id: "b2_l3", number: 3,
                    title: "What never to share",
                    objective: "You'll get good help from a chatbot without sharing anything private.",
                    starter: "[BASICS: Unit 2, Lesson 3] Teach me what I should never share with an AI chatbot, and why. Then let me practice asking for help safely."
                ),
                Lesson(
                    id: "b2_l4", number: 4,
                    title: "Fake calls that sound like family",
                    objective: "You'll know exactly what to do if a call sounds like family asking for money.",
                    starter: "[BASICS: Unit 2, Lesson 4] Teach me about AI voice-clone and family emergency scams, and exactly what to do if I get one of those calls. Then help me make a plan."
                ),
            ]
        ),
        Unit(
            id: "basics_3",
            number: "03",
            title: "Getting good answers",
            summary: "Small changes that get you clearer, more useful answers.",
            lessons: [
                Lesson(
                    id: "b3_l1", number: 1,
                    title: "Be specific",
                    objective: "You'll turn a general question into one that gets a much better answer.",
                    starter: "[BASICS: Unit 3, Lesson 1] Teach me how adding details gets better answers from an AI chatbot. Then let me try it."
                ),
                Lesson(
                    id: "b3_l2", number: 2,
                    title: "Tell it your situation",
                    objective: "You'll give a chatbot the background it needs, and leave out private details.",
                    starter: "[BASICS: Unit 3, Lesson 2] Teach me how to give an AI chatbot the right background so it can help me, without sharing private details. Then let me practice."
                ),
                Lesson(
                    id: "b3_l3", number: 3,
                    title: "Ask for the downsides",
                    objective: "You'll get honest pros and cons from a chatbot, not only agreement.",
                    starter: "[BASICS: Unit 3, Lesson 3] Teach me how to get honest, balanced answers from an AI chatbot instead of agreement. Then let me practice."
                ),
            ]
        ),
        Unit(
            id: "basics_4",
            number: "04",
            title: "Everyday tasks",
            summary: "Emails, confusing letters, meal plans, and learning something new.",
            lessons: [
                Lesson(
                    id: "b4_l1", number: 1,
                    title: "Write an email or letter",
                    objective: "You'll get a chatbot to write an email, then copy it out to use.",
                    starter: "[BASICS: Unit 4, Lesson 1] Teach me how to use an AI chatbot to help write an email or letter, and how to copy it out. Then let me try one."
                ),
                Lesson(
                    id: "b4_l2", number: 2,
                    title: "Understand a confusing letter",
                    objective: "You'll get a confusing letter explained in plain words, with private parts covered.",
                    starter: "[BASICS: Unit 4, Lesson 2] Teach me how to use an AI chatbot to understand a confusing letter or bill, safely. Then let me practice with a made-up letter."
                ),
                Lesson(
                    id: "b4_l3", number: 3,
                    title: "Meals, plans and lists",
                    objective: "You'll get a meal plan and a shopping list that fit the people you're feeding.",
                    starter: "[BASICS: Unit 4, Lesson 3] Teach me how to use an AI chatbot for recipes, plans and lists. Then let me try one."
                ),
                Lesson(
                    id: "b4_l4", number: 4,
                    title: "Learn something new, with a photo",
                    objective: "You'll learn something new one step at a time, and try asking about a photo.",
                    starter: "[BASICS: Unit 4, Lesson 4] Teach me how to use an AI chatbot to learn something new, one step at a time, including by sharing a photo. Then let me try."
                ),
            ]
        ),
        Unit(
            id: "basics_5",
            number: "05",
            title: "Using it wisely on your own",
            summary: "Check what matters, know when to ask a person, spot scams, and start on your own.",
            lessons: [
                Lesson(
                    id: "b5_l1", number: 1,
                    title: "Checking answers that matter",
                    objective: "You'll know which answers to check, and where to check them.",
                    starter: "[BASICS: Unit 5, Lesson 1] Teach me which AI answers to check and where to check them. Then let me practice."
                ),
                Lesson(
                    id: "b5_l2", number: 2,
                    title: "Health, money and legal: ask a person",
                    objective: "You'll use AI to get ready for a doctor, banker or lawyer, not to decide for you.",
                    starter: "[BASICS: Unit 5, Lesson 2] Teach me how to use AI safely for health, money and legal questions, and when to ask a real person instead. Then let me practice."
                ),
                Lesson(
                    id: "b5_l3", number: 3,
                    title: "Other scams that use AI",
                    objective: "You'll spot the signs of a scam, and know what to do if you already paid.",
                    starter: "[BASICS: Unit 5, Lesson 3] Teach me how scammers use AI in calls, emails, texts and pop-ups, the signs of any scam, and what to do if I already paid. Then let me practice spotting one."
                ),
                Lesson(
                    id: "b5_l4", number: 4,
                    title: "On your own",
                    objective: "You'll know how to get a real chatbot app safely, and leave with your own safety rules.",
                    starter: "[BASICS: Unit 5, Lesson 4] Teach me how to use a chatbot app on my own, safely, and recap my safety rules. Then let me practice."
                ),
            ]
        ),
    ]
}
