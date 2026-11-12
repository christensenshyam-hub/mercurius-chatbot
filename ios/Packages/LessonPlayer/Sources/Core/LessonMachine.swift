import Foundation

/// What the learner (or the network) did.
public enum PlayerAction: Equatable, Sendable {
    /// Choose an option (single) or toggle it (multiple).
    case choose(String)
    /// Toggle a claim in a passage.
    case toggleClaim(String)
    /// Edit the short response.
    case editText(String)
    case submit
    /// After a miss: answer again.
    case tryAgain
    case showHint
    case openDepth(String)
    /// Continue past a teaching step, a resolved activity, or the finish. Carries
    /// the step it was tapped on, so a second tap that lands after the lesson
    /// moved on is ignored instead of skipping the next step.
    case advance(from: String)
    /// The server's evaluation for the request with this token.
    case evaluationArrived(token: Int, ResponseEvaluation)
    case evaluationFailed(token: Int, UngradedReason)
    /// Send an ungraded response for evaluation again.
    case retryEvaluation
    /// The learner left the screen: cancel any grading in flight.
    case cancelEvaluation
}

/// What the host must do after an action.
public enum PlayerEffect: Equatable, Sendable {
    /// Ask the server to evaluate a short response.
    case requestEvaluation(stepId: String, token: Int, text: String)
    case stepViewed(stepId: String)
    case answerSubmitted(stepId: String, submissionIndex: Int)
    case feedbackShown(stepId: String, status: GradingStatus)
    case depthOpened(stepId: String, depthId: String)
    /// Fired once per attempt, when the completion rule is first met.
    case lessonCompleted(CompletionRecord)
    /// The learner tapped Finish on the last step.
    case finished
}

public enum ActionResult: Equatable, Sendable {
    case applied([PlayerEffect])
    /// Not valid in the current state (a double tap, a stale result). Nothing
    /// changed.
    case ignored(String)

    public var effects: [PlayerEffect] {
        if case .applied(let e) = self { return e }
        return []
    }
    public var wasApplied: Bool {
        if case .applied = self { return true }
        return false
    }
}

/// The step state machine: one lesson's content plus one attempt, and the only
/// way the attempt changes. Every action is checked against the current
/// state, so a double tap, a second submit, or a late server result can't
/// advance the lesson twice or overwrite a newer answer.
public struct LessonMachine: Equatable, Sendable {
    /// Wrong objective answers before the right one is shown.
    public static let missesBeforeReveal = 2
    /// "Not yet" results before the exemplar is shown.
    public static let notYetBeforeExemplar = 2

    public let content: LessonContent
    public private(set) var attempt: LessonAttempt
    private var nextToken: Int

    /// Fails if the attempt belongs to a different lesson or content version:
    /// an attempt only ever runs on the content it started with.
    public init?(content: LessonContent, attempt: LessonAttempt) {
        guard content.lessonId == attempt.lessonId,
              content.contentVersion == attempt.contentVersion,
              content.step(id: attempt.currentStepId) != nil
        else { return nil }
        self.content = content
        self.attempt = attempt
        nextToken = (attempt.records.values.flatMap(\.submissions).map(\.evaluationToken).max() ?? 0) + 1
    }

    // MARK: Reading

    public var currentStep: LessonStep { content.step(id: attempt.currentStepId)! }
    public var currentRecord: StepRecord { attempt.record(attempt.currentStepId) }
    public var currentIndex: Int { content.index(ofStep: attempt.currentStepId) ?? 0 }

    /// Required steps done, for the progress indicator.
    public var requiredProgress: (done: Int, total: Int) {
        let required = content.requiredSteps
        let done = required.filter { attempt.record($0.id).phase == .done }.count
        return (done, required.count)
    }

    public var canSubmit: Bool {
        guard let activity = currentStep.activity else { return false }
        let record = currentRecord
        guard record.phase == .viewing, let draft = record.draft, !draft.isEmpty else { return false }
        if case .shortResponse(let sr) = activity.kind, case .text(let t) = draft {
            return t.count <= sr.maxCharacters
        }
        return true
    }

    /// The current activity is resolved: the learner may continue.
    public var isCurrentStepResolved: Bool { isResolved(currentStep) }

    // MARK: Acting

    public mutating func send(_ action: PlayerAction, now: Date = Date()) -> ActionResult {
        let result = apply(action, now: now)
        if result.wasApplied { attempt.lastActiveAt = now }
        return result
    }

    /// Adds foreground time, capped per call so a long background or a stuck
    /// timer can't inflate it.
    public mutating func recordActive(seconds: Double) {
        guard seconds > 0 else { return }
        attempt.activeSeconds += min(seconds, 60)
    }

    public mutating func markResumed() { attempt.resumeCount += 1 }

    private mutating func apply(_ action: PlayerAction, now: Date) -> ActionResult {
        let step = currentStep
        var record = currentRecord

        switch action {
        case .choose(let id):
            guard record.phase == .viewing, case .choice(let choice)? = step.activity?.kind else {
                return .ignored("not choosing")
            }
            guard choice.options.contains(where: { $0.id == id }) else { return .ignored("unknown option") }
            record.draft = .options(toggled(id, in: record.draft, selection: choice.selection, asOptions: true))
            return commit(record, [])

        case .toggleClaim(let id):
            guard record.phase == .viewing, case .claimSelection(let sel)? = step.activity?.kind else {
                return .ignored("not selecting claims")
            }
            guard sel.claims.contains(where: { $0.claimId == id }) else { return .ignored("unknown claim") }
            record.draft = .claims(toggled(id, in: record.draft, selection: sel.selection, asOptions: false))
            return commit(record, [])

        case .editText(let text):
            guard record.phase == .viewing, case .shortResponse(let sr)? = step.activity?.kind else {
                return .ignored("not writing")
            }
            record.draft = .text(String(text.prefix(sr.maxCharacters)))
            return commit(record, [])

        case .submit:
            guard canSubmit, let activity = step.activity, let draft = record.draft else {
                return .ignored("nothing to submit")
            }
            let index = record.submissions.count
            if activity.isDeterministic {
                guard case .success(let grade) = Grader.grade(activity, response: draft) else {
                    return .ignored("ungradable answer")
                }
                record.submissions.append(Submission(
                    index: index, response: draft, status: .graded(grade.verdict),
                    feedback: grade.feedback, hint: nil, flags: [], submittedAt: now,
                    hintsSeen: record.hintsShown, evaluationToken: 0
                ))
                record.phase = .feedback
                let misses = record.submissions.filter { $0.status.verdict != .correct }.count
                if grade.verdict != .correct, misses >= Self.missesBeforeReveal { record.revealed = true }
                return commit(record, [
                    .answerSubmitted(stepId: step.id, submissionIndex: index),
                    .feedbackShown(stepId: step.id, status: .graded(grade.verdict)),
                ])
            }
            guard case .text(let text) = draft else { return .ignored("not text") }
            let token = takeToken()
            record.submissions.append(Submission(
                index: index, response: draft, status: .pending, feedback: nil, hint: nil,
                flags: [], submittedAt: now, hintsSeen: record.hintsShown, evaluationToken: token
            ))
            record.phase = .awaitingGrade
            return commit(record, [
                .answerSubmitted(stepId: step.id, submissionIndex: index),
                .requestEvaluation(stepId: step.id, token: token, text: text),
            ])

        case .evaluationArrived(let token, let evaluation):
            guard record.phase == .awaitingGrade, var last = record.submissions.last,
                  last.status == .pending, last.evaluationToken == token,
                  case .shortResponse(let sr)? = step.activity?.kind
            else { return .ignored("stale or unexpected evaluation") }
            let verdict: Verdict = evaluation.status == .meets ? .correct : .incorrect
            last.status = .graded(verdict)
            last.feedback = evaluation.feedback
            last.hint = evaluation.hint
            last.flags = evaluation.flags.filter { id in sr.rubric.flags.contains { $0.id == id } }
            record.submissions[record.submissions.count - 1] = last
            record.phase = .feedback
            let notYet = record.submissions.filter { $0.status == .graded(.incorrect) }.count
            if verdict == .incorrect, notYet >= Self.notYetBeforeExemplar { record.revealed = true }
            return commit(record, [.feedbackShown(stepId: step.id, status: last.status)])

        case .evaluationFailed(let token, let reason):
            guard record.phase == .awaitingGrade, var last = record.submissions.last,
                  last.status == .pending, last.evaluationToken == token
            else { return .ignored("stale or unexpected failure") }
            last.status = .ungraded(reason)
            record.submissions[record.submissions.count - 1] = last
            record.phase = .feedback
            return commit(record, [.feedbackShown(stepId: step.id, status: last.status)])

        case .cancelEvaluation:
            guard record.phase == .awaitingGrade, var last = record.submissions.last, last.status == .pending else {
                return .ignored("nothing in flight")
            }
            last.status = .ungraded(.interrupted)
            record.submissions[record.submissions.count - 1] = last
            record.phase = .feedback
            return commit(record, [])

        case .retryEvaluation:
            guard record.phase == .feedback, var last = record.submissions.last,
                  case .ungraded = last.status, case .text(let text) = last.response
            else { return .ignored("nothing to retry") }
            let token = takeToken()
            last.status = .pending
            last.evaluationToken = token
            record.submissions[record.submissions.count - 1] = last
            record.phase = .awaitingGrade
            return commit(record, [.requestEvaluation(stepId: step.id, token: token, text: text)])

        case .tryAgain:
            guard record.phase == .feedback, let last = record.submissions.last,
                  last.status.verdict != .correct, let activity = step.activity
            else { return .ignored("nothing to try again") }
            if activity.isDeterministic {
                guard !record.revealed else { return .ignored("answer already shown") }
                record.draft = nil
            }
            // A short response keeps its text, so the learner revises it.
            record.phase = .viewing
            let misses = record.submissions.filter { $0.status.verdict != nil && $0.status.verdict != .correct }.count
            record.hintsShown = max(record.hintsShown, min(activity.hints.count, misses))
            return commit(record, [])

        case .showHint:
            guard record.phase == .viewing, let hints = step.activity?.hints, record.hintsShown < hints.count else {
                return .ignored("no hint to show")
            }
            record.hintsShown += 1
            return commit(record, [])

        case .openDepth(let id):
            guard step.depth.contains(where: { $0.id == id }) else { return .ignored("unknown depth item") }
            let isNew = record.depthOpened.insert(id).inserted
            return commit(record, isNew ? [.depthOpened(stepId: step.id, depthId: id)] : [])

        case .advance(let from):
            guard from == step.id else { return .ignored("continue from a step already left") }
            return advance(from: step, record: record, now: now)
        }
    }

    private mutating func advance(from step: LessonStep, record: StepRecord, now: Date) -> ActionResult {
        var record = record
        switch step.kind {
        case .teach:
            guard record.phase == .viewing else { return .ignored("already advanced") }
        case .activity:
            guard record.phase == .feedback, isResolved(step, record: record) else {
                return .ignored("activity not resolved")
            }
        case .finish:
            guard record.phase == .viewing else { return .ignored("already finished") }
            record.phase = .done
            attempt.records[step.id] = record
            return .applied([.finished])
        }
        record.phase = .done
        attempt.records[step.id] = record

        var effects: [PlayerEffect] = []
        if attempt.completion == nil, completionRuleMet() {
            let completion = CompletionRecord(completedAt: now, success: successLevel())
            attempt.completion = completion
            effects.append(.lessonCompleted(completion))
        }
        let index = content.index(ofStep: step.id) ?? 0
        if index + 1 < content.steps.count {
            let next = content.steps[index + 1]
            attempt.currentStepId = next.id
            effects.append(.stepViewed(stepId: next.id))
        }
        return .applied(effects)
    }

    // MARK: Rules

    private func isResolved(_ step: LessonStep, record: StepRecord? = nil) -> Bool {
        let record = record ?? attempt.record(step.id)
        guard let activity = step.activity else { return true }
        guard let last = record.lastSubmission, let verdict = last.status.verdict else { return false }
        if verdict == .correct { return true }
        if content.completion.mustBeAnswered.contains(step.id) { return true }
        // An objective answer shown after repeated misses lets the learner move
        // on (assisted). A short response needs a "meets" grade: there is no
        // way past it on an ungraded or "not yet" answer.
        return activity.isDeterministic && record.revealed
    }

    func completionRuleMet() -> Bool {
        for id in content.completion.mustBeCorrect {
            guard let step = content.step(id: id) else { return false }
            let record = attempt.record(id)
            guard record.phase == .done, isResolved(step, record: record) else { return false }
        }
        for id in content.completion.mustBeAnswered {
            guard attempt.record(id).phase == .done,
                  attempt.record(id).lastSubmission?.status.verdict != nil else { return false }
        }
        return true
    }

    func successLevel() -> SuccessLevel {
        var assisted = false
        let graded = content.completion.mustBeCorrect + content.completion.mustBeAnswered
        for id in graded {
            let record = attempt.record(id)
            guard let last = record.lastSubmission else { return .notDemonstrated }
            if last.status.verdict != .correct {
                if content.completion.mustBeCorrect.contains(id), record.revealed { assisted = true; continue }
                return .notDemonstrated
            }
            let gradedSubmissions = record.submissions.filter { $0.status.verdict != nil }
            if gradedSubmissions.count > 1 || record.hintsShown > 0 || record.revealed { assisted = true }
        }
        return assisted ? .assisted : .independent
    }

    // MARK: Helpers

    private mutating func commit(_ record: StepRecord, _ effects: [PlayerEffect]) -> ActionResult {
        attempt.records[attempt.currentStepId] = record
        return .applied(effects)
    }

    private mutating func takeToken() -> Int {
        defer { nextToken += 1 }
        return nextToken
    }

    private func toggled(_ id: String, in draft: LearnerResponse?, selection: ChoiceActivity.Selection, asOptions: Bool) -> Set<String> {
        var current: Set<String> = []
        switch draft {
        case .options(let ids)? where asOptions: current = ids
        case .claims(let ids)? where !asOptions: current = ids
        default: break
        }
        switch selection {
        case .single: return [id]
        case .multiple:
            if current.contains(id) { current.remove(id) } else { current.insert(id) }
            return current
        }
    }
}
