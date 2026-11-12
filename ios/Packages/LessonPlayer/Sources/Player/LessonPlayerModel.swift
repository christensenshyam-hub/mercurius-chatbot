import Foundation
import Observation

/// A short response to evaluate, as the host sends it to the server.
public struct EvaluationRequest: Equatable, Sendable {
    public let lessonId: String
    public let contentVersion: Int
    public let stepId: String
    public let rubricId: String
    public let text: String
}

/// A practice message for the live tutor.
public struct PracticeRequest: Equatable, Sendable {
    public let lessonId: String
    public let stepId: String
    public let text: String
}

public enum PracticeOutcome: Equatable, Sendable {
    /// Merc's reply, as plain text.
    case replied(String)
    case failed(UngradedReason)
}

public enum EvaluationOutcome: Equatable, Sendable {
    case evaluated(ResponseEvaluation)
    case failed(UngradedReason)
}

/// Where the learner asked Merc from, so the host can open the live tutor with
/// a useful starting point. The learner's own answer is never included.
public struct AskMercContext: Equatable, Sendable {
    public let lessonId: String
    public let lessonTitle: String
    public let stepId: String
    /// The step's prompt or heading, to suggest a first question.
    public let topic: String
}

/// Everything the player needs from the app. The player module itself never
/// stores, sends or logs anything; AppFeature supplies these.
public struct LessonPlayerHost {
    /// Persist the attempt (called after every change).
    public var saveAttempt: (LessonAttempt) -> Void
    /// Evaluate a short response through the server relay.
    public var evaluate: (EvaluationRequest) async -> EvaluationOutcome
    /// The completion rule was met (once per attempt). The host records the
    /// completion and grants one-time rewards through its ledger.
    public var lessonCompleted: (LessonContent, CompletionRecord) -> Void
    /// Open the live tutor without leaving the lesson.
    public var askMerc: ((AskMercContext) -> Void)?
    /// Send a practice message to the live tutor and return its reply.
    public var practice: (PracticeRequest) async -> PracticeOutcome
    /// The learner left: `finished` is true from the finish step, false for
    /// "finish for now".
    public var exit: (_ finished: Bool) -> Void
    /// Player events for measurement (see `LessonPlayerEvent`).
    public var record: (LessonPlayerEvent) -> Void

    public init(
        saveAttempt: @escaping (LessonAttempt) -> Void,
        evaluate: @escaping (EvaluationRequest) async -> EvaluationOutcome,
        lessonCompleted: @escaping (LessonContent, CompletionRecord) -> Void,
        askMerc: ((AskMercContext) -> Void)? = nil,
        practice: @escaping (PracticeRequest) async -> PracticeOutcome = { _ in .failed(.unavailable) },
        exit: @escaping (_ finished: Bool) -> Void,
        record: @escaping (LessonPlayerEvent) -> Void = { _ in }
    ) {
        self.saveAttempt = saveAttempt
        self.evaluate = evaluate
        self.lessonCompleted = lessonCompleted
        self.askMerc = askMerc
        self.practice = practice
        self.exit = exit
        self.record = record
    }
}

/// Drives one attempt: forwards learner actions to `LessonMachine`, saves after
/// every change, runs short-response evaluations with a timeout, and turns
/// the machine's effects into host calls and events.
@MainActor
@Observable
public final class LessonPlayerModel {
    /// How long the player waits for an evaluation before showing the
    /// reviewed fallback and Retry. The server has its own, shorter limit.
    public nonisolated static let defaultEvaluationTimeout: Duration = .seconds(25)

    public private(set) var machine: LessonMachine
    /// Bumped whenever feedback or optional depth appears, so the view can
    /// bring it into sight (also on a second answer to the same step).
    public private(set) var revealRevision = 0
    /// What VoiceOver should hear when feedback appears (its title and first
    /// line), so a screen-reader user learns the result without hunting for it.
    public private(set) var announcement: String?

    /// The last evaluation read as a crisis: the view shows support.
    public var showsCrisisSupport = false

    @ObservationIgnored private let host: LessonPlayerHost
    @ObservationIgnored private var evaluation: Task<Void, Never>?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var activeSince: Date?
    @ObservationIgnored private let evaluationTimeout: Duration

    public init(machine: LessonMachine, host: LessonPlayerHost, resumed: Bool,
                evaluationTimeout: Duration = LessonPlayerModel.defaultEvaluationTimeout,
                clock: @escaping () -> Date = Date.init) {
        self.machine = machine
        self.host = host
        self.clock = clock
        self.evaluationTimeout = evaluationTimeout
        if resumed {
            self.machine.markResumed()
            host.saveAttempt(self.machine.attempt)
            host.record(.lessonResumed(context()))
        } else {
            host.saveAttempt(machine.attempt)
            host.record(.lessonStarted(context()))
        }
        host.record(.stepViewed(context(), stepId: machine.attempt.currentStepId))
    }

    public var content: LessonContent { machine.content }
    public var step: LessonStep { machine.currentStep }
    public var record: StepRecord { machine.currentRecord }
    public var canAskMerc: Bool { host.askMerc != nil }

    // MARK: Actions

    public func send(_ action: PlayerAction) {
        // Count the foreground time up to this action first, so every event
        // it causes carries an up-to-date active time.
        flushActiveTime()
        let result = machine.send(action, now: clock())
        guard case .applied(let effects) = result else { return }
        host.saveAttempt(machine.attempt)
        if action == .showHint { host.record(.helpUsed(context(), stepId: step.id, kind: .hint)) }
        for effect in effects { handle(effect) }
    }

    public func askMerc() {
        let topic: String
        switch step.kind {
        case .teach(let t): topic = t.heading
        case .activity(let a): topic = a.prompt
        case .finish(let f): topic = f.heading
        }
        host.record(.helpUsed(context(), stepId: step.id, kind: .askMerc))
        host.askMerc?(AskMercContext(lessonId: content.lessonId, lessonTitle: content.title, stepId: step.id, topic: topic))
    }

    /// "Finish for now": cancel any grading in flight (the answer is kept as
    /// ungraded, to retry later), save, and leave.
    public func leave() {
        if record.phase == .awaitingGrade { send(.cancelEvaluation) }
        evaluation?.cancel()
        sceneBecameInactive()
        host.saveAttempt(machine.attempt)
        host.exit(false)
    }

    // MARK: Active time

    public func sceneBecameActive() {
        if activeSince == nil { activeSince = clock() }
    }

    public func sceneBecameInactive() {
        guard activeSince != nil else { return }
        flushActiveTime()
        activeSince = nil
        host.saveAttempt(machine.attempt)
    }

    /// Adds the foreground time since the last flush (each gap capped by
    /// `LessonMachine.maxActiveGap`) and restarts the clock.
    private func flushActiveTime() {
        guard let since = activeSince else { return }
        let now = clock()
        machine.recordActive(seconds: now.timeIntervalSince(since))
        activeSince = now
    }

    // MARK: Effects

    private func handle(_ effect: PlayerEffect) {
        switch effect {
        case .requestEvaluation(let stepId, let token, let text):
            startEvaluation(stepId: stepId, token: token, text: text)
        case .requestPractice(let stepId, let token, let text):
            startPractice(stepId: stepId, token: token, text: text)
        case .stepViewed(let stepId):
            host.record(.stepViewed(context(), stepId: stepId))
        case .answerSubmitted(let stepId, let index):
            host.record(.answerSubmitted(context(), stepId: stepId, attemptIndex: index, interaction: interaction(stepId)))
        case .feedbackShown(let stepId, let status):
            revealRevision += 1
            let detail: String? = {
                guard let feedback = record.lastSubmission?.feedback, !feedback.isEmpty else { return nil }
                return feedback
            }()
            announcement = [FeedbackLook.title(for: status), detail].compactMap { $0 }.joined(separator: ". ")
            host.record(.feedbackShown(context(), stepId: stepId, status: status))
        case .depthOpened(let stepId, let depthId):
            revealRevision += 1
            host.record(.explanationExpanded(context(), stepId: stepId, depthId: depthId))
        case .lessonCompleted(let completion):
            host.lessonCompleted(content, completion)
            host.record(.lessonCompleted(context(), success: completion.success))
        case .finished:
            sceneBecameInactive()
            host.exit(true)
        }
    }

    private func startEvaluation(stepId: String, token: Int, text: String) {
        guard case .shortResponse(let sr)? = content.step(id: stepId)?.activity?.kind else { return }
        let request = EvaluationRequest(
            lessonId: content.lessonId, contentVersion: content.contentVersion,
            stepId: stepId, rubricId: sr.rubricId, text: text
        )
        evaluation?.cancel()
        let evaluate = host.evaluate
        let limit = evaluationTimeout
        evaluation = Task { [weak self] in
            let outcome = await Self.withTimeout(limit) { await evaluate(request) }
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .evaluated(let e):
                // Validate again here: only a well-formed result with the
                // rubric's own flags is ever shown as a grade.
                let allowed = Set(sr.rubric.flags.map(\.id))
                if let checked = EvaluationParser.check(e, allowedFlags: allowed) {
                    self.send(.evaluationArrived(token: token, checked))
                } else {
                    self.send(.evaluationFailed(token: token, .invalidResult))
                    self.host.record(.lessonError(self.context(), stepId: stepId, kind: UngradedReason.invalidResult.rawValue))
                }
            case .failed(.support):
                self.send(.evaluationFailed(token: token, .support))
                self.showsCrisisSupport = true
            case .failed(let reason):
                self.send(.evaluationFailed(token: token, reason))
                if reason != .interrupted {
                    self.host.record(.lessonError(self.context(), stepId: stepId, kind: reason.rawValue))
                }
            }
        }
    }

    private func startPractice(stepId: String, token: Int, text: String) {
        let request = PracticeRequest(lessonId: content.lessonId, stepId: stepId, text: text)
        evaluation?.cancel()
        let practice = host.practice
        let limit = evaluationTimeout
        evaluation = Task { [weak self] in
            let outcome = await withTaskGroup(of: PracticeOutcome.self) { group in
                group.addTask { await practice(request) }
                group.addTask {
                    try? await Task.sleep(for: limit)
                    return .failed(.timeout)
                }
                let first = await group.next() ?? .failed(.timeout)
                group.cancelAll()
                return first
            }
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .replied(let reply):
                let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.send(.evaluationFailed(token: token, .invalidResult))
                } else {
                    self.send(.practiceReplied(token: token, reply: trimmed))
                }
            case .failed(.support):
                self.send(.evaluationFailed(token: token, .support))
                self.showsCrisisSupport = true
            case .failed(let reason):
                self.send(.evaluationFailed(token: token, reason))
                if reason != .interrupted {
                    self.host.record(.lessonError(self.context(), stepId: stepId, kind: reason.rawValue))
                }
            }
        }
    }

    /// Runs `work`, or gives up with `.failed(.timeout)` after `limit`.
    nonisolated static func withTimeout(
        _ limit: Duration,
        _ work: @escaping @Sendable () async -> EvaluationOutcome
    ) async -> EvaluationOutcome {
        await withTaskGroup(of: EvaluationOutcome.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return .failed(.timeout)
            }
            let first = await group.next() ?? .failed(.timeout)
            group.cancelAll()
            return first
        }
    }

    // MARK: Event context

    func context() -> LessonPlayerEvent.Context {
        LessonPlayerEvent.Context(
            attemptId: machine.attempt.attemptId,
            lessonId: content.lessonId,
            contentVersion: content.contentVersion,
            experience: machine.attempt.experience,
            activeSeconds: Int(machine.attempt.activeSeconds.rounded())
        )
    }

    private func interaction(_ stepId: String) -> LessonPlayerEvent.Interaction {
        switch content.step(id: stepId)?.activity?.kind {
        case .choice(let c)?:
            if c.presentation == .claimVersusEvidence { return .claimVersusEvidence }
            return c.selection == .single ? .singleChoice : .multiSelect
        case .claimSelection?: return .claimSelection
        case .shortResponse?: return .shortResponse
        case .practice?: return .practice
        case nil: return .teach
        }
    }
}
