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

    @Test("A replay keeps the completed attempt in history; an unreadable record is never replaced")
    func noSilentOverwrite() {
        let prefs = InMemoryPreferenceStore()
        let store = LessonAttemptStore(preferences: prefs)
        var done = LessonMachine(content: lesson, attempt: attempt())!
        while !done.attempt.isComplete {
            let step = done.currentStep
            switch step.activity?.kind {
            case .choice(let c)?: _ = done.send(.choose(c.correct.first!)); _ = done.send(.submit)
            case .claimSelection(let s)?: _ = done.send(.toggleClaim(s.correct.first!)); _ = done.send(.submit)
            case .shortResponse?:
                _ = done.send(.editText("Find the study."))
                let t = done.send(.submit).effects.compactMap { e -> Int? in
                    if case .requestEvaluation(_, let t, _) = e { return t }; return nil }.first!
                _ = done.send(.evaluationArrived(token: t, ResponseEvaluation(status: .meets, feedback: "Yes.")))
            default: break
            }
            _ = done.send(.advance(from: step.id))
        }
        store.save(done.attempt)
        let replay = attempt("00000000-0000-0000-0000-00000000000B")
        store.save(replay)
        #expect(store.attempt(for: "u1_l3")?.attemptId == replay.attemptId)
        #expect(store.previousCompletedAttempt(for: "u1_l3")?.attemptId == done.attempt.attemptId)

        prefs.set(#"{"u1_l3":"bm90IGFuIGF0dGVtcHQ="}"#, for: LessonAttemptStore.attemptsKey)
        #expect(store.hasUnreadableRecord(for: "u1_l3"))
        store.save(attempt("00000000-0000-0000-0000-00000000000C"))
        #expect(prefs.string(for: LessonAttemptStore.attemptsKey)?.contains("bm90IGFuIGF0dGVtcHQ=") == true)
        #expect(!store.hasUnreadableRecord(for: "b1_l1"))
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

    @Test("A server without the route (404) turns a cached 'on' off")
    func notServedTurnsOff() async {
        let flag = LessonPlayerFlag(preferences: InMemoryPreferenceStore(), arguments: [])
        await flag.refresh { LessonPlayerConfig(enabled: true, lessons: ["u1_l3"]) }
        await flag.refresh(using: { throw APIError.unknown(underlying: "HTTP 404") }, isNotServed: LessonPlayerFlag.isNotServed)
        #expect(!flag.isEnabled(for: "u1_l3"))
        #expect(!LessonPlayerFlag.isNotServed(APIError.offline))
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

@Suite("Lesson player: server outcomes map to honest states")
struct LessonPlayerEvaluationMappingTests {
    @Test("Network and server failures are reasons, never grades")
    func reasons() {
        #expect(LessonPlayerEvaluation.reason(for: .offline) == .offline)
        #expect(LessonPlayerEvaluation.reason(for: .connectionLost) == .offline)
        #expect(LessonPlayerEvaluation.reason(for: .unreachableOnThisNetwork) == .offline)
        #expect(LessonPlayerEvaluation.reason(for: .timeout) == .timeout)
        #expect(LessonPlayerEvaluation.reason(for: .server(status: 504)) == .timeout)
        #expect(LessonPlayerEvaluation.reason(for: .unknown(underlying: "HTTP 422")) == .invalidResult)
        #expect(LessonPlayerEvaluation.reason(for: .server(status: 502)) == .unavailable)
        #expect(LessonPlayerEvaluation.reason(for: .rateLimited) == .unavailable)
        #expect(LessonPlayerEvaluation.reason(for: .serviceUnavailable(code: "spend_cap", message: "x", retryAfter: nil)) == .unavailable)
        #expect(LessonPlayerEvaluation.reason(for: .cancelled) == .interrupted)
        #expect(LessonPlayerEvaluation.reason(for: .crisisSupport(message: "x")) == .support)
    }

    @Test("A result decodes to an evaluation; an unknown status or a crisis does not")
    func outcomes() {
        #expect(LessonPlayerEvaluation.outcome(for: .evaluated(status: "meets", feedback: "Yes.", hint: nil, flags: []))
                == .evaluated(ResponseEvaluation(status: .meets, feedback: "Yes.")))
        #expect(LessonPlayerEvaluation.outcome(for: .evaluated(status: "correct", feedback: "Yes.", hint: nil, flags: []))
                == .failed(.invalidResult))
        #expect(LessonPlayerEvaluation.outcome(for: .crisis(message: "988")) == .failed(.support))
    }

    @Test("The DEBUG stub reads only its own argument")
    func stub() {
        #expect(LessonPlayerEvaluation.stubbedOutcome(arguments: []) == nil)
        #expect(LessonPlayerEvaluation.stubbedOutcome(arguments: ["-LessonPlayerStubGrade", "offline"]) == .failed(.offline))
    }
}

@Suite("Lesson player: events")
@MainActor
struct LessonPlayerTelemetryTests {
    final class Sink: LessonEventSink {
        var lines: [(String, [String: String])] = []
        func write(name: String, fields: [String: String]) { lines.append((name, fields)) }
    }

    @Test("first_open is written once, for a new learner only, with a pseudonymous id and the app version")
    func firstOpenOnce() {
        let prefs = InMemoryPreferenceStore()
        let sink = Sink()
        let t = LessonPlayerTelemetry(preferences: prefs, sink: sink, appVersion: "9.9 (1)")
        t.recordFirstOpenIfNeeded(isNewLearner: true, playerEligible: true)
        t.recordFirstOpenIfNeeded(isNewLearner: true, playerEligible: true)
        LessonPlayerTelemetry(preferences: prefs, sink: sink, appVersion: "9.9 (1)").recordFirstOpenIfNeeded(isNewLearner: true, playerEligible: false)
        #expect(sink.lines.map(\.0) == ["first_open"])
        let f = sink.lines[0].1
        #expect(f["experience"] == "player")
        #expect(f["app_version"] == "9.9 (1)")
        #expect(UUID(uuidString: f["install_id"] ?? "") != nil)
        // "Delete my data" makes a new learner with a new id.
        let old = t.installId
        t.reset()
        t.recordFirstOpenIfNeeded(isNewLearner: true, playerEligible: nil)
        #expect(sink.lines.count == 2)
        #expect(sink.lines[1].1["experience"] == "unknown")
        #expect(t.installId != old)
    }

    @Test("An existing learner updating to this build is never counted as a first open")
    func upgraderNotCounted() {
        let prefs = InMemoryPreferenceStore()
        let sink = Sink()
        let t = LessonPlayerTelemetry(preferences: prefs, sink: sink, appVersion: "1")
        t.recordFirstOpenIfNeeded(isNewLearner: false, playerEligible: true)
        t.recordFirstOpenIfNeeded(isNewLearner: true, playerEligible: true)
        #expect(sink.lines.isEmpty)
    }

    @Test("A full Lesson 3 run logs the spec's events, with no answer text anywhere")
    func eventsCarryNoText() async {
        let prefs = InMemoryPreferenceStore()
        let sink = Sink()
        let t = LessonPlayerTelemetry(preferences: prefs, sink: sink, appVersion: "1")
        let secret = "MY-PRIVATE-ANSWER rain study"
        let lesson = LessonCatalog.u1_l3_v1
        let machine = LessonMachine(content: lesson, attempt: LessonAttempt(lesson: lesson, now: Date()))!
        let host = LessonPlayerHost(
            saveAttempt: { _ in },
            evaluate: { _ in .evaluated(ResponseEvaluation(status: .meets, feedback: "Yes.")) },
            lessonCompleted: { _, _ in },
            exit: { _ in },
            record: { t.record($0) }
        )
        let m = LessonPlayerModel(machine: machine, host: host, resumed: false)
        m.send(.openDepth("claim-state.why"))
        m.send(.showHint)
        m.send(.choose("unverified")); m.send(.submit); m.send(.advance(from: "claim-state"))
        m.send(.advance(from: "principle"))
        m.send(.toggleClaim("34-percent")); m.send(.submit); m.send(.advance(from: "testable-claim"))
        m.send(.choose("original-study")); m.send(.submit); m.send(.advance(from: "best-check"))
        m.send(.choose("still-unverified")); m.send(.submit); m.send(.advance(from: "excerpt"))
        m.send(.editText(secret)); m.send(.submit)
        for _ in 0..<200 where m.record.phase == .awaitingGrade { try? await Task.sleep(for: .milliseconds(10)) }
        m.send(.advance(from: "transfer"))
        m.send(.advance(from: "finish"))

        let names = Set(sink.lines.map(\.0))
        for name in ["lesson_start", "step_viewed", "answer_submitted", "feedback_shown",
                     "explanation_expanded", "help_used", "lesson_completed"] {
            #expect(names.contains(name), "missing \(name)")
        }
        for (name, fields) in sink.lines {
            for value in fields.values {
                #expect(!value.contains("MY-PRIVATE-ANSWER") && !value.contains("rain"), "\(name) leaked text")
            }
            #expect(fields["install_id"] != nil && fields["app_version"] == "1" && fields["lesson_id"] == "u1_l3")
        }
        let submitted = sink.lines.filter { $0.0 == "answer_submitted" }.map(\.1)
        #expect(submitted.contains { $0["interaction"] == "short_response" && $0["attempt_index"] == "0" })
        #expect(submitted.contains { $0["interaction"] == "claim_selection" })
        #expect(submitted.contains { $0["interaction"] == "claim_vs_evidence" })
        let feedback = sink.lines.filter { $0.0 == "feedback_shown" }.map(\.1)
        #expect(feedback.contains { $0["grading_status"] == "graded_correct" && $0["step_id"] == "transfer" })
    }
}

@Suite("Lesson player: practice replies")
struct LessonPlayerPracticeTests {
    @Test("The chat's card markers, answer lines and Markdown are dropped from the reply")
    func plainText() {
        let raw = "No, I'm **Merc**, an AI.\n\n[KEY]A chatbot is a program.[/KEY]\n\n[Q]Which?\nA) x\nB) y\nANS: B\n[/Q]"
        let text = LessonPlayerPractice.plainText(raw)
        #expect(text.hasPrefix("No, I'm Merc, an AI."))
        #expect(!text.contains("[KEY]") && !text.contains("**") && !text.contains("ANS:"))
        #expect(text.contains("A chatbot is a program."))
    }

    @Test("The DEBUG stub answers practice without the network")
    func stub() {
        #expect(LessonPlayerPractice.stubbedOutcome(arguments: []) == nil)
        #expect(LessonPlayerPractice.stubbedOutcome(arguments: ["-LessonPlayerStubGrade", "offline"]) == .failed(.offline))
        if case .replied? = LessonPlayerPractice.stubbedOutcome(arguments: ["-LessonPlayerStubGrade", "meets"]) {} else {
            Issue.record("expected a stubbed reply")
        }
    }
}
