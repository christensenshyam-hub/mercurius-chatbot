import Foundation

public struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public let severity: Severity
    public let stepId: String?
    public let message: String

    public var description: String {
        "[\(severity.rawValue)] \(stepId.map { "\($0): " } ?? "")\(message)"
    }
}

/// Runtime validation of lesson data. Errors make a lesson unusable (the host
/// falls back to the legacy lesson); warnings are the editorial targets, which
/// a justified exception may exceed.
public enum LessonValidator {
    /// `uN_lM` (Deep dive) or `bN_lM` (Basics): the curriculum's id format.
    static let lessonIdPattern = #"^[ub]\d+_l\d+$"#
    static let stableIdPattern = #"^[a-z0-9][a-z0-9_.-]{0,47}$"#

    public static func validate(_ lesson: LessonContent) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ step: String?, _ message: String) { issues.append(.init(severity: .error, stepId: step, message: message)) }
        func warn(_ step: String?, _ message: String) { issues.append(.init(severity: .warning, stepId: step, message: message)) }

        if lesson.lessonId.range(of: lessonIdPattern, options: .regularExpression) == nil {
            error(nil, "lesson id \(lesson.lessonId) is not a curriculum id")
        }
        if lesson.schemaVersion != LessonContent.currentSchemaVersion {
            error(nil, "schema version \(lesson.schemaVersion) is not \(LessonContent.currentSchemaVersion)")
        }
        if lesson.contentVersion < 1 { error(nil, "content version must be 1 or more") }
        if lesson.title.isBlank || lesson.objective.isBlank { error(nil, "title and objective are required") }
        for p in lesson.prerequisites where p.range(of: lessonIdPattern, options: .regularExpression) == nil || p == lesson.lessonId {
            error(nil, "bad prerequisite \(p)")
        }

        // Steps
        guard !lesson.steps.isEmpty else { error(nil, "no steps"); return issues }
        let ids = lesson.steps.map(\.id)
        for id in Set(ids) where ids.filter({ $0 == id }).count > 1 { error(id, "duplicate step id") }
        for id in ids where id.range(of: stableIdPattern, options: .regularExpression) == nil { error(id, "unstable step id") }
        guard case .finish = lesson.steps.last!.kind else { error(nil, "the last step must be the finish"); return issues }
        if lesson.steps.dropLast().contains(where: { if case .finish = $0.kind { return true } else { return false } }) {
            error(nil, "only the last step may be a finish")
        }
        if lesson.steps.first?.activity == nil {
            warn(lesson.steps.first?.id, "the first screen should hold a meaningful decision")
        }
        let count = lesson.steps.count
        if count < 6 || count > 8 { warn(nil, "\(count) steps (target 6 to 8)") }

        // Completion rule
        let rule = lesson.completion
        let ruled = rule.mustBeCorrect + rule.mustBeAnswered
        for id in Set(ruled) where ruled.filter({ $0 == id }).count > 1 { error(id, "listed twice in the completion rule") }
        for id in ruled {
            guard let step = lesson.step(id: id) else { error(id, "completion rule names a missing step"); continue }
            if step.activity == nil { error(id, "completion rule names a step with no activity") }
            if !step.required { error(id, "a completion step must be required") }
        }
        for step in lesson.steps where step.required && step.activity != nil && !ruled.contains(step.id) {
            error(step.id, "a required activity must be in the completion rule")
        }
        for id in rule.mustBeAnswered {
            if case .shortResponse? = lesson.step(id: id)?.activity?.kind {
                error(id, "a short response must be graded, not just answered")
            }
        }
        for id in rule.mustBeCorrect {
            if case .practice? = lesson.step(id: id)?.activity?.kind {
                error(id, "a practice message isn't graded, so it can only be answered")
            }
        }

        var correctPositions: [Int] = []
        for step in lesson.steps {
            validateDepth(step, error: error)
            switch step.kind {
            case .teach(let t):
                if t.body.isBlank { error(step.id, "empty teaching text") }
                checkWords(t.body, range: 30...60, what: "explanation", step.id, warn)
                checkVisible(step, warn)
            case .finish(let f):
                if f.practiced.isBlank || f.next.isBlank { error(step.id, "finish needs what was practiced and what's next") }
            case .activity(let a):
                if a.prompt.isBlank { error(step.id, "empty prompt") }
                checkWords(a.prompt, range: 15...35, what: "question", step.id, warn)
                checkVisible(step, warn)
                for m in [a.scenario, a.evidence].compactMap({ $0 }) where m.text.isBlank {
                    error(step.id, "empty material")
                }
                if let position = validateActivity(a, step.id, error: error, warn: warn) {
                    correctPositions.append(position)
                }
            }
        }
        if correctPositions.count >= 3, Set(correctPositions).count == 1 {
            warn(nil, "every single-choice answer is in position \(correctPositions[0] + 1)")
        }
        return issues
    }

    /// Returns the correct option's position for a single choice (for the
    /// repeated-position check).
    private static func validateActivity(
        _ a: Activity, _ stepId: String,
        error: (String?, String) -> Void, warn: (String?, String) -> Void
    ) -> Int? {
        switch a.kind {
        case .choice(let c):
            let ids = c.options.map(\.id)
            if c.options.count < 2 || c.options.count > 5 { error(stepId, "a choice needs 2 to 5 options") }
            if Set(ids).count != ids.count { error(stepId, "duplicate option id") }
            for id in ids where id.range(of: stableIdPattern, options: .regularExpression) == nil { error(stepId, "unstable option id \(id)") }
            if !c.correct.isSubset(of: Set(ids)) || c.correct.isEmpty { error(stepId, "answer key names a missing option") }
            if c.selection == .single, c.correct.count != 1 { error(stepId, "a single choice needs exactly one answer") }
            if c.selection == .multiple, c.partialFeedback == nil { error(stepId, "a multi-select needs partial feedback") }
            if c.presentation == .claimVersusEvidence, a.scenario == nil || a.evidence == nil {
                error(stepId, "claim versus evidence needs both a claim and evidence")
            }
            if c.correctFeedback.isBlank { error(stepId, "missing feedback for the right answer") }
            checkWords(c.correctFeedback, range: 15...35, what: "feedback", stepId, warn)
            for o in c.options where !c.correct.contains(o.id) {
                if o.feedback.isBlank { error(stepId, "option \(o.id) has no feedback") }
                checkWords(o.feedback, range: 15...35, what: "feedback for \(o.id)", stepId, warn)
            }
            // Option length can give the answer away.
            if c.selection == .single, let right = c.options.first(where: { c.correct.contains($0.id) }) {
                let others = c.options.filter { $0.id != right.id }.map { $0.text.count }
                if let longest = others.max(), right.text.count > Int(Double(longest) * 1.5) {
                    warn(stepId, "the right option is much longer than the others")
                }
                return ids.firstIndex(of: right.id)
            }
            return nil
        case .claimSelection(let s):
            let claimIds = s.claims.compactMap(\.claimId)
            if claimIds.count < 2 { error(stepId, "a claim selection needs at least 2 selectable claims") }
            if Set(claimIds).count != claimIds.count { error(stepId, "duplicate claim id") }
            if !s.correct.isSubset(of: Set(claimIds)) || s.correct.isEmpty { error(stepId, "answer key names a missing claim") }
            if s.selection == .single, s.correct.count != 1 { error(stepId, "a single selection needs exactly one answer") }
            for id in claimIds where !s.correct.contains(id) && (s.claimFeedback[id] ?? "").isBlank {
                error(stepId, "claim \(id) has no feedback")
            }
            if a.scenario == nil { warn(stepId, "say where the passage comes from (scenario material)") }
            // A right claim much longer than the others gives itself away.
            if s.selection == .single, let right = s.claims.first(where: { s.correct.contains($0.claimId ?? "") }) {
                let others = s.claims.filter { $0.claimId != right.claimId }.map(\.text.count)
                if let longest = others.max(), right.text.count > Int(Double(longest) * 1.5) {
                    warn(stepId, "the right claim is much longer than the others")
                }
            }
            return nil
        case .practice(let p):
            if p.suggestion.isBlank || p.fallbackGuidance.isBlank || p.notice.isBlank {
                error(stepId, "practice needs a suggestion, fallback guidance and a notice")
            }
            if p.suggestion.count > p.maxCharacters { error(stepId, "the suggestion is longer than the limit") }
            return nil
        case .shortResponse(let r):
            if r.rubricId.range(of: stableIdPattern, options: .regularExpression) == nil { error(stepId, "bad rubric id") }
            if r.rubric.core.isEmpty { error(stepId, "a rubric needs a core requirement") }
            if r.fallbackGuidance.isBlank || r.exemplar.isBlank { error(stepId, "short response needs fallback guidance and an exemplar") }
            if r.maxCharacters < 40 || r.maxCharacters > 1000 { error(stepId, "max length out of range") }
            return nil
        }
    }

    private static func validateDepth(_ step: LessonStep, error: (String?, String) -> Void) {
        let ids = step.depth.map(\.id)
        if Set(ids).count != ids.count { error(step.id, "duplicate depth id") }
        var stages: [Int] = []
        for d in step.depth {
            if d.body.isBlank { error(step.id, "empty depth item \(d.id)") }
            if case .stage(let n) = d.kind { stages.append(n) }
        }
        if !stages.isEmpty, stages != Array(1...stages.count) {
            error(step.id, "Go deeper stages must run 1, 2, 3 in order")
        }
    }

    // Editorial targets: warnings only.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func checkWords(_ text: String, range: ClosedRange<Int>, what: String, _ stepId: String, _ warn: (String?, String) -> Void) {
        let n = wordCount(text)
        if n > Int(Double(range.upperBound) * 1.4) { warn(stepId, "\(what) is \(n) words (target \(range.lowerBound) to \(range.upperBound))") }
    }

    /// Visible text before any optional expansion: about 100 words or fewer.
    static func visibleWords(_ step: LessonStep) -> Int {
        switch step.kind {
        case .teach(let t): return wordCount(t.heading) + wordCount(t.body) + wordCount(t.keyIdea ?? "")
        case .finish(let f): return wordCount(f.heading) + wordCount(f.practiced) + wordCount(f.next)
        case .activity(let a):
            var n = wordCount(a.prompt) + wordCount(a.scenario?.text ?? "") + wordCount(a.evidence?.text ?? "")
            switch a.kind {
            case .choice(let c): n += c.options.map { wordCount($0.text) }.reduce(0, +)
            case .claimSelection: break // the passage is the scenario's text
            case .shortResponse, .practice: break
            }
            return n
        }
    }

    private static func checkVisible(_ step: LessonStep, _ warn: (String?, String) -> Void) {
        let n = visibleWords(step)
        if n > 110 { warn(step.id, "\(n) visible words (target about 100)") }
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
