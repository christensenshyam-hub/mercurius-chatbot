import Foundation

/// Centralized decision logic for "what should Merc be doing right now."
///
/// The lesson and chat screens each have many overlapping signals (typing,
/// thinking, streaming, errors, completions, streaks). Rather than scatter
/// `if isThinking { ... } else if ...` ladders across those views, they feed
/// their signals into `MercSignals` and read back a single resolved
/// `MercMascotState`. The resolver is a **pure value-type function** — no app
/// dependencies, no side effects — so it's trivial to unit-test and reuse.
///
/// It does NOT drive any UI on its own; a host decides when to apply the result
/// (and can use `priority` / `duration` to manage temporary reactions).

// MARK: - Inputs

/// Where the mascot is being shown — lets context nuance the idle disposition.
public enum MercScreen: Equatable {
    case lesson
    case chat
    case other
}

/// A coarse quality signal for the learner's most recent answer, IF the host has
/// one. The app has no single "answer quality" type, so hosts map their own
/// grade / correctness into this and the resolver stays decoupled.
public enum MercAnswerQuality: Equatable {
    case strong
    case good
    case weak
    case incorrect
}

/// Everything the resolver reads. All fields are defaulted, so a caller passes
/// only the signals it actually knows about.
public struct MercSignals: Equatable {
    public var screen: MercScreen
    public var isUserTyping: Bool
    public var isAIThinking: Bool
    public var isAISpeaking: Bool
    /// 0...1 through the current lesson, if applicable.
    public var lessonProgress: Double?
    public var lessonCompleted: Bool
    public var hasError: Bool
    public var streakIncreased: Bool
    public var lastAnswerQuality: MercAnswerQuality?

    public init(
        screen: MercScreen = .other,
        isUserTyping: Bool = false,
        isAIThinking: Bool = false,
        isAISpeaking: Bool = false,
        lessonProgress: Double? = nil,
        lessonCompleted: Bool = false,
        hasError: Bool = false,
        streakIncreased: Bool = false,
        lastAnswerQuality: MercAnswerQuality? = nil
    ) {
        self.screen = screen
        self.isUserTyping = isUserTyping
        self.isAIThinking = isAIThinking
        self.isAISpeaking = isAISpeaking
        self.lessonProgress = lessonProgress
        self.lessonCompleted = lessonCompleted
        self.hasError = hasError
        self.streakIncreased = streakIncreased
        self.lastAnswerQuality = lastAnswerQuality
    }
}

// MARK: - Resolved state

/// The resolved mascot UI state — what to show, plus how important and how long.
public struct MercMascotState: Equatable {
    public var mood: MercMood
    public var activity: MercActivity
    /// Optional short line for a speech bubble (reactions / celebrations only).
    public var speech: String?
    public var priority: Priority
    /// For temporary reactions (celebration / error / answer feedback): how long
    /// to hold before reverting to the steady state. `nil` = persistent.
    public var duration: TimeInterval?

    /// Higher wins. Lets a host decide whether an incoming state should
    /// supersede a still-running temporary one.
    public enum Priority: Int, Comparable {
        case idle = 0
        case ambient = 10       // typing / thinking / speaking
        case reaction = 20      // per-answer feedback
        case celebration = 30   // lesson complete / streak up
        case error = 40         // overrides everything normal
        public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }

    public init(
        mood: MercMood = .neutral,
        activity: MercActivity = .idle,
        speech: String? = nil,
        priority: Priority = .idle,
        duration: TimeInterval? = nil
    ) {
        self.mood = mood
        self.activity = activity
        self.speech = speech
        self.priority = priority
        self.duration = duration
    }

    /// The single source of truth for Merc's UI state. The early-return order
    /// encodes the precedence rules (also reflected in `priority`):
    /// error > celebration > answer-reaction > ai-thinking > ai-speaking >
    /// user-typing > idle.
    public static func resolve(_ s: MercSignals) -> MercMascotState {
        // 1. Error overrides everything normal.
        if s.hasError {
            return MercMascotState(mood: .confused, activity: .error,
                                   speech: "Something went wrong.",
                                   priority: .error, duration: 1.2)
        }

        // 4 & 5. Terminal positive moments → celebration. Lesson completion
        // outranks a streak bump when both land together.
        if s.lessonCompleted {
            return MercMascotState(mood: .celebrating, activity: .success,
                                   speech: "Lesson complete!",
                                   priority: .celebration, duration: 2.6)
        }
        if s.streakIncreased {
            return MercMascotState(mood: .celebrating, activity: .success,
                                   speech: "Streak up!",
                                   priority: .celebration, duration: 2.0)
        }

        // Brief per-answer reaction, if the host supplies a quality signal.
        if let quality = s.lastAnswerQuality {
            switch quality {
            case .strong, .good:
                return MercMascotState(mood: .happy, activity: .success,
                                       priority: .reaction, duration: 1.4)
            case .weak, .incorrect:
                return MercMascotState(mood: .encouraging, activity: .idle,
                                       speech: "Almost — let's look again.",
                                       priority: .reaction, duration: 1.6)
            }
        }

        // 2. AI thinking overrides user typing (after submit).
        if s.isAIThinking {
            return MercMascotState(mood: .thinking, activity: .aiThinking, priority: .ambient)
        }
        // 3. AI speaking overrides generic idle.
        if s.isAISpeaking {
            return MercMascotState(mood: .neutral, activity: .aiSpeaking, priority: .ambient)
        }
        // User typing → attentive / listening.
        if s.isUserTyping {
            return MercMascotState(mood: .listening, activity: .userTyping, priority: .ambient)
        }

        // 6. Idle fallback — nuanced slightly by context/progress.
        return idle(for: s)
    }

    private static func idle(for s: MercSignals) -> MercMascotState {
        // Deep into a lesson, Merc takes an encouraging resting disposition.
        if s.screen == .lesson, let progress = s.lessonProgress, progress > 0.66 {
            return MercMascotState(mood: .encouraging, activity: .idle, priority: .idle)
        }
        return MercMascotState(mood: .neutral, activity: .idle, priority: .idle)
    }

    /// A brief reaction to a lesson-progress increase (the visible
    /// `completed/total` counter). Reaching `total` celebrates; any earlier step
    /// encourages — both with a `.success` pop. `speech` is left to the caller so
    /// it can supply lesson-specific copy. Centralizes the mood/activity choice
    /// (the rule in this task) so screens don't re-derive it.
    public static func lessonProgress(completed: Int, total: Int) -> MercMascotState {
        let isComplete = total > 0 && completed >= total
        return MercMascotState(
            mood: isComplete ? .celebrating : .encouraging,
            activity: .success,
            priority: isComplete ? .celebration : .reaction,
            duration: isComplete ? 2.6 : 2.2
        )
    }
}
