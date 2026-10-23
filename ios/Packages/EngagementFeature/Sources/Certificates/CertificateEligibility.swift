import Foundation
import DesignSystem

/// One thing a certificate asks for: a unit check passed (Deep dive) or a
/// lesson finished (AI Basics).
public struct CertificateRequirement: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    /// How "what's left" names it: "Unit 4 · Prompt Engineering".
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Where a learner stands on one certificate.
public struct CertificateStatus: Equatable, Sendable {
    public let kind: CertificateKind
    /// Every requirement, in course order.
    public let requirements: [CertificateRequirement]
    /// The requirements not met yet, in course order.
    public let remaining: [CertificateRequirement]
    /// When the last requirement was met, if every requirement's date is
    /// known; nil otherwise (the certificate then takes the day it's first
    /// made).
    public let lastMetAt: Date?

    public var total: Int { requirements.count }
    public var met: Int { total - remaining.count }
    public var isEarned: Bool { total > 0 && remaining.isEmpty }

    /// "5 of 8 unit checks passed" / "12 of 18 lessons finished".
    public var progressText: String {
        switch kind {
        case .deepDive: return "\(met) of \(total) unit checks passed"
        case .basics: return "\(met) of \(total) lessons finished"
        }
    }

    /// What's left, short: "Still to pass: Unit 4 · Prompt Engineering, Unit
    /// 7 · Using AI Well and 1 more"; for AI Basics only the next lesson,
    /// "Next: Unit 4 · Meals, plans and lists" (its titles hold commas and
    /// "and", so two in a list run together; `progressText` gives the
    /// count). Nil once earned.
    public var remainingText: String? {
        guard let next = remaining.first else { return nil }
        switch kind {
        case .deepDive:
            let shown = remaining.prefix(2).map(\.title)
            let more = remaining.count - shown.count
            var list = shown.joined(separator: ", ")
            if more > 0 { list += " and \(more) more" }
            return "Still to pass: \(list)"
        case .basics:
            return "Next: \(next.title)"
        }
    }
}

/// Who has earned which certificate. Pure: progress goes in as values.
public enum CertificateEligibility {
    /// The Deep dive's unit ids, as `CurriculumProgressStore` records
    /// mastery ("unit_1" … "unit_8").
    public static let deepDiveUnitIds = (1...8).map { "unit_\($0)" }

    /// The Deep dive: every unit's mastery check passed. `earnedAt` is when
    /// this device saw the last one pass (`CertificateStore.earnedAt`):
    /// mastery itself carries no date.
    public static func deepDive(
        units: [CertificateRequirement] = deepDiveUnitIds.enumerated().map {
            CertificateRequirement(id: $0.element, title: "Unit \($0.offset + 1)")
        },
        masteredUnitIds: Set<String>,
        earnedAt: Date? = nil
    ) -> CertificateStatus {
        let remaining = units.filter { !masteredUnitIds.contains($0.id) }
        return CertificateStatus(kind: .deepDive, requirements: units, remaining: remaining,
                                 lastMetAt: remaining.isEmpty ? earnedAt : nil)
    }

    /// AI Basics: every Basics lesson finished. The lesson list comes from
    /// the Basics curriculum (`CertificateCenter.basicsLessons`); its last
    /// completion date is the certificate's, when every lesson has one.
    public static func basics(
        lessons: [CertificateRequirement],
        completedLessonIds: Set<String>,
        completedAt: [String: Date] = [:]
    ) -> CertificateStatus {
        let remaining = lessons.filter { !completedLessonIds.contains($0.id) }
        var last: Date?
        if remaining.isEmpty, !lessons.isEmpty {
            let dates = lessons.compactMap { completedAt[$0.id] }
            if dates.count == lessons.count { last = dates.max() }
        }
        return CertificateStatus(kind: .basics, requirements: lessons, remaining: remaining, lastMetAt: last)
    }

    /// The date a certificate prints: the one stored the first time it was
    /// made, else when the last requirement was met (if known), else now.
    public static func completionDate(stored: Date?, lastMetAt: Date?, now: Date) -> Date {
        stored ?? lastMetAt ?? now
    }
}
