import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature
import EngagementFeature
import LessonPlayer
import NetworkingKit
import PersistenceKit

/// The app side of the lesson player pilot: its saved attempts, its one-time
/// reward ledger, the switch, and what "delete my data" erases.
@Suite("Lesson player: attempt store")
@MainActor
struct LessonAttemptStoreTests {
    let lesson = LessonCatalog.u1_l3_v1

    func attempt(_ id: String = "00000000-0000-0000-0000-00000000000A") -> LessonAttempt {
        LessonAttempt(lesson: lesson, attemptId: UUID(uuidString: id)!, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("An attempt saves and loads back unchanged, per lesson")
    func roundTrip() {
        let store = LessonAttemptStore(preferences: InMemoryPreferenceStore())
        #expect(store.attempt(for: "u1_l3") == nil)
        var machine = LessonMachine(content: lesson, attempt: attempt())!
        _ = machine.send(.choose("unverified"))
        _ = machine.send(.submit)
        store.save(machine.attempt)
        #expect(store.attempt(for: "u1_l3") == machine.attempt)
        #expect(store.attempt(for: "b1_l1") == nil)
    }

    @Test("Resume after the app was closed mid-grading: the answer is kept, ungraded (interrupted)")
    func resumeAfterKill() {
        let prefs = InMemoryPreferenceStore()
        let store = LessonAttemptStore(preferences: prefs)
        var machine = LessonMachine(content: lesson, attempt: attempt())!
        while machine.attempt.currentStepId != "transfer" {
            let step = machine.currentStep
            switch step.activity?.kind {
            case .choice(let c)?: _ = machine.send(.choose(c.correct.first!)); _ = machine.send(.submit)
            case .claimSelection(let s)?: _ = machine.send(.toggleClaim(s.correct.first!)); _ = machine.send(.submit)
            default: break
            }
            _ = machine.send(.advance(from: step.id))
        }
        _ = machine.send(.editText("I'd look for the study first."))
        _ = machine.send(.submit)
        store.save(machine.attempt)

        // A new process: a fresh store on the same preferences.
        let reloaded = LessonAttemptStore(preferences: prefs).attempt(for: "u1_l3")!
        let record = reloaded.record("transfer")
        #expect(reloaded.currentStepId == "transfer")
        #expect(record.lastSubmission?.response == .text("I'd look for the study first."))
        #expect(record.lastSubmission?.status == .ungraded(.interrupted))
        #expect(reloaded.completion == nil)
    }

    @Test("A record this version can't read is left alone, and other lessons' records survive a save")
    func unreadableRecordUntouched() {
        let prefs = InMemoryPreferenceStore()
        let future = #"{"b1_l1":"bm90IGFuIGF0dGVtcHQ="}"#   // base64 of junk: unreadable
        prefs.set(future, for: LessonAttemptStore.attemptsKey)
        let store = LessonAttemptStore(preferences: prefs)
        #expect(store.attempt(for: "b1_l1") == nil)
        store.save(attempt())
        let raw = prefs.string(for: LessonAttemptStore.attemptsKey) ?? ""
        #expect(raw.contains("bm90IGFuIGF0dGVtcHQ="), "the unreadable record was overwritten")
        #expect(store.attempt(for: "u1_l3") != nil)
    }

    @Test("Completion goes through the app once; a replay of a completed lesson grants nothing again")
    func completionOnce() {
        let store = LessonAttemptStore(preferences: InMemoryPreferenceStore())
        #expect(store.shouldRecordCompletion(lessonId: "u1_l3", progressShowsCompleted: false))
        #expect(!store.shouldRecordCompletion(lessonId: "u1_l3", progressShowsCompleted: true), "a replay")
        #expect(!store.shouldRecordCompletion(lessonId: "u1_l3", progressShowsCompleted: true), "another replay")
        // Progress was reset elsewhere (e.g. restored from an older backup)
        // but the ledger remembers: the completion is still recorded, so
        // progress is never left behind; the app's own path is idempotent.
        #expect(store.shouldRecordCompletion(lessonId: "u1_l3", progressShowsCompleted: false))
        // Another lesson has its own key.
        #expect(store.shouldRecordCompletion(lessonId: "b1_l1", progressShowsCompleted: false))
    }

    @Test("Reset erases every attempt (answer text included) and the ledger")
    func reset() {
        let store = LessonAttemptStore(preferences: InMemoryPreferenceStore())
        store.save(attempt())
        _ = store.grantOnce(RewardLedger.completionKey(lessonId: "u1_l3"))
        store.reset()
        #expect(store.attempt(for: "u1_l3") == nil)
        #expect(store.ledger.granted.isEmpty)
    }
}

@Suite("Lesson player: the switch")
@MainActor
struct LessonPlayerFlagTests {
    @Test("Off until the server says on, and only for the lessons it names")
    func serverDecides() async {
        let prefs = InMemoryPreferenceStore()
        let flag = LessonPlayerFlag(preferences: prefs, arguments: [])
        #expect(!flag.isEnabled(for: "u1_l3"))
        await flag.refresh { LessonPlayerConfig(enabled: true, lessons: ["u1_l3"]) }
        #expect(flag.isEnabled(for: "u1_l3") == LessonPlayerFlag.clientAllowed)
        #expect(!flag.isEnabled(for: "b1_l1"))
        await flag.refresh { .off }
        #expect(!flag.isEnabled(for: "u1_l3"))
    }

    @Test("The last answer is cached across launches; a failed refresh keeps it")
    func cached() async {
        let prefs = InMemoryPreferenceStore()
        await LessonPlayerFlag(preferences: prefs, arguments: []).refresh { LessonPlayerConfig(enabled: true, lessons: ["u1_l3"]) }
        let next = LessonPlayerFlag(preferences: prefs, arguments: [])
        #expect(next.isEnabled(for: "u1_l3") == LessonPlayerFlag.clientAllowed)
        struct Offline: Error {}
        await next.refresh { throw Offline() }
        #expect(next.isEnabled(for: "u1_l3") == LessonPlayerFlag.clientAllowed)
    }

    @Test("The DEBUG launch argument overrides both ways")
    func debugOverride() async {
        let on = LessonPlayerFlag(preferences: InMemoryPreferenceStore(), arguments: ["-LessonPlayer", "YES"])
        #expect(on.isEnabled(for: "u1_l3"))
        let off = LessonPlayerFlag(preferences: InMemoryPreferenceStore(), arguments: ["-LessonPlayer", "NO"])
        await off.refresh { LessonPlayerConfig(enabled: true, lessons: ["u1_l3"]) }
        #expect(!off.isEnabled(for: "u1_l3"))
        #expect(LessonPlayerFlag.override(in: ["-LessonPlayer"]) == nil)
    }
}

@Suite("Lesson player: pilot lessons match the curriculum")
struct LessonPlayerCurriculumTests {
    @Test("Every pilot lesson is a real curriculum lesson with the same title, gated the same way")
    func matches() {
        let units = MercuriusCurriculum.units + BasicsCurriculum.units
        for content in LessonCatalog.all {
            let lesson = units.flatMap(\.lessons).first { $0.id == content.lessonId }
            #expect(lesson != nil, "\(content.lessonId) is not in the curriculum")
            #expect(lesson?.title == content.title)
            // Prerequisites mirror the sequential gate: the lesson before it
            // in its unit (none for a unit's first lesson).
            if let unit = units.first(where: { $0.lessons.contains { $0.id == content.lessonId } }),
               let index = unit.lessons.firstIndex(where: { $0.id == content.lessonId }) {
                let expected = index == 0 ? [] : [unit.lessons[index - 1].id]
                #expect(content.prerequisites == expected, "\(content.lessonId)")
            }
        }
    }
}

@Suite("Lesson player: delete my data")
@MainActor
struct LessonPlayerResetTests {
    @Test("Settings' reset erases the player's attempts and ledger")
    func settingsResetErasesAttempts() async {
        let attempts = LessonAttemptStore(preferences: InMemoryPreferenceStore())
        attempts.save(LessonAttempt(lesson: LessonCatalog.u1_l3_v1, now: Date()))
        _ = attempts.grantOnce(RewardLedger.completionKey(lessonId: "u1_l3"))
        let sheet = SettingsResetTests().makeSheetForPlayer(lessonAttempts: attempts)
        #expect(await sheet.makeModel(dismiss: {}).resetSession())
        #expect(attempts.attempt(for: "u1_l3") == nil)
        #expect(attempts.ledger.granted.isEmpty)
    }
}
