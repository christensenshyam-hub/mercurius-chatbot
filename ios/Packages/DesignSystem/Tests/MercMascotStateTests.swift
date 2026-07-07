import Testing
@testable import DesignSystem

@Suite("MercMascotState resolution")
struct MercMascotStateTests {

    // MARK: Fallback

    @Test("Idle is the fallback")
    func idleFallback() {
        let s = MercMascotState.resolve(MercSignals())
        #expect(s.activity == .idle)
        #expect(s.mood == .neutral)
        #expect(s.priority == .idle)
        #expect(s.duration == nil)
    }

    // MARK: Override rules

    @Test("Error overrides normal idle states (and every active signal)")
    func errorOverridesEverything() {
        let s = MercMascotState.resolve(
            MercSignals(isUserTyping: true, isAIThinking: true, isAISpeaking: true, hasError: true))
        #expect(s.activity == .error)
        #expect(s.priority == .error)
        #expect(s.duration != nil)   // temporary reaction
    }

    @Test("AI thinking overrides user typing after submit")
    func thinkingOverridesTyping() {
        let s = MercMascotState.resolve(MercSignals(isUserTyping: true, isAIThinking: true))
        #expect(s.activity == .aiThinking)
    }

    @Test("AI speaking overrides generic idle")
    func speakingOverridesIdle() {
        let s = MercMascotState.resolve(MercSignals(isAISpeaking: true))
        #expect(s.activity == .aiSpeaking)
    }

    @Test("User typing maps to listening when nothing else is active")
    func typingListens() {
        let s = MercMascotState.resolve(MercSignals(isUserTyping: true))
        #expect(s.activity == .userTyping)
        #expect(s.mood == .listening)
    }

    // MARK: Celebrations

    @Test("Lesson completion triggers celebration")
    func completionCelebrates() {
        let s = MercMascotState.resolve(MercSignals(lessonCompleted: true))
        #expect(s.activity == .success)
        #expect(s.mood == .celebrating)
        #expect(s.priority == .celebration)
        #expect(s.speech != nil)
        #expect(s.duration != nil)
    }

    @Test("Streak increase triggers celebration")
    func streakCelebrates() {
        let s = MercMascotState.resolve(MercSignals(streakIncreased: true))
        #expect(s.mood == .celebrating)
        #expect(s.priority == .celebration)
    }

    @Test("Lesson completion outranks a simultaneous streak bump")
    func completionBeatsStreak() {
        let s = MercMascotState.resolve(MercSignals(lessonCompleted: true, streakIncreased: true))
        #expect(s.speech == "Lesson complete!")
    }

    @Test("Error outranks a celebration")
    func errorBeatsCelebration() {
        let s = MercMascotState.resolve(MercSignals(lessonCompleted: true, hasError: true))
        #expect(s.activity == .error)
        #expect(s.priority == .error)
    }

    // MARK: Answer-quality reactions

    @Test("A strong answer gives a brief positive reaction")
    func strongAnswerReacts() {
        let s = MercMascotState.resolve(MercSignals(lastAnswerQuality: .strong))
        #expect(s.activity == .success)
        #expect(s.priority == .reaction)
        #expect(s.duration != nil)
    }

    @Test("A weak/incorrect answer stays encouraging, never punishing")
    func weakAnswerEncourages() {
        let s = MercMascotState.resolve(MercSignals(lastAnswerQuality: .incorrect))
        #expect(s.mood == .encouraging)
        #expect(s.activity == .idle)   // gentle — no error shake
    }

    @Test("Celebration outranks a per-answer reaction")
    func celebrationBeatsReaction() {
        let s = MercMascotState.resolve(MercSignals(lessonCompleted: true, lastAnswerQuality: .strong))
        #expect(s.priority == .celebration)
    }

    // MARK: Idle nuance

    @Test("Deep lesson progress gives an encouraging idle disposition")
    func deepProgressEncourages() {
        let s = MercMascotState.resolve(MercSignals(screen: .lesson, lessonProgress: 0.8))
        #expect(s.activity == .idle)
        #expect(s.mood == .encouraging)
    }

    @Test("Early lesson progress stays neutral idle")
    func earlyProgressNeutral() {
        let s = MercMascotState.resolve(MercSignals(screen: .lesson, lessonProgress: 0.2))
        #expect(s.mood == .neutral)
    }

    // MARK: Durations + priority

    @Test("Ambient states are persistent (no auto-revert duration)")
    func ambientPersistent() {
        #expect(MercMascotState.resolve(MercSignals(isAIThinking: true)).duration == nil)
        #expect(MercMascotState.resolve(MercSignals(isAISpeaking: true)).duration == nil)
        #expect(MercMascotState.resolve(MercSignals(isUserTyping: true)).duration == nil)
    }

    @Test("Priority ordering is error > celebration > reaction > ambient > idle")
    func priorityOrdering() {
        #expect(MercMascotState.Priority.error > .celebration)
        #expect(MercMascotState.Priority.celebration > .reaction)
        #expect(MercMascotState.Priority.reaction > .ambient)
        #expect(MercMascotState.Priority.ambient > .idle)
    }
}
