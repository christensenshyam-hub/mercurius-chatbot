import Foundation
import Observation
import DesignSystem

/// The certificates for the app: what each asks for, where the learner
/// stands, and the device-only store. Built once by `AppEnvironment`, which
/// hands it the curriculum's units and readers onto `CurriculumProgressStore`
/// (EngagementFeature can't see the curriculum).
///
/// **The Basics seam.** Without lessons handed in (`basicsLessons`), the
/// Basics certificate isn't offered. The app:
/// 1. sets `basicsLessons` to AI Basics' lessons in course order (ids
///    `b1_l1` … `b5_l4`, with titles for "what's left") when it's composed
///    (`CertificateCourses.basicsLessons`);
/// 2. wraps the call that marks a lesson finished in
///    `recordingNewlyEarned { … }`, so the moment the last one lands is
///    recorded and its course-complete card can show (`justEarned`).
/// See `docs/certificate/INTEGRATION.md`.
@MainActor
@Observable
public final class CertificateCenter {
    /// Read-only views of the learner's progress.
    public struct Progress {
        public var masteredUnitIds: @MainActor () -> Set<String>
        public var completedLessonIds: @MainActor () -> Set<String>
        public var completedAt: @MainActor (String) -> Date?

        public init(
            masteredUnitIds: @escaping @MainActor () -> Set<String>,
            completedLessonIds: @escaping @MainActor () -> Set<String>,
            completedAt: @escaping @MainActor (String) -> Date?
        ) {
            self.masteredUnitIds = masteredUnitIds
            self.completedLessonIds = completedLessonIds
            self.completedAt = completedAt
        }
    }

    public let store: CertificateStore

    /// The Deep dive's unit checks, in course order.
    public let deepDiveUnits: [CertificateRequirement]

    /// AI Basics' lessons, in course order; nil (or empty) and the
    /// certificate isn't offered.
    public var basicsLessons: [CertificateRequirement]?

    /// A certificate earned a moment ago, in this session: the unit check's
    /// (or lesson's) result shows its "Get your certificate" card. Cleared
    /// when the card's sheet opens or the result closes.
    public var justEarned: CertificateKind?

    @ObservationIgnored private let progress: Progress
    @ObservationIgnored private let now: () -> Date

    public init(
        store: CertificateStore,
        deepDiveUnits: [CertificateRequirement],
        basicsLessons: [CertificateRequirement]? = nil,
        progress: Progress,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.deepDiveUnits = deepDiveUnits
        self.basicsLessons = basicsLessons
        self.progress = progress
        self.now = now
    }

    /// The certificates this build offers, in order.
    public var kinds: [CertificateKind] {
        CertificateKind.allCases.filter { status($0) != nil }
    }

    /// Where the learner stands on a certificate; nil when the course isn't
    /// in this build.
    public func status(_ kind: CertificateKind) -> CertificateStatus? {
        switch kind {
        case .deepDive:
            return CertificateEligibility.deepDive(units: deepDiveUnits,
                                                   masteredUnitIds: progress.masteredUnitIds(),
                                                   earnedAt: store.earnedAt(.deepDive))
        case .basics:
            guard let lessons = basicsLessons, !lessons.isEmpty else { return nil }
            var dates: [String: Date] = [:]
            for lesson in lessons {
                if let date = progress.completedAt(lesson.id) { dates[lesson.id] = date }
            }
            let completed = progress.completedLessonIds()
            let earnedAt = store.earnedAt(.basics)
            let status = CertificateEligibility.basics(lessons: lessons, completedLessonIds: completed,
                                                       completedAt: dates)
            // A last lesson finished before its date was kept: the moment
            // this device saw it stands in.
            if status.isEarned, status.lastMetAt == nil, let earnedAt {
                return CertificateStatus(kind: .basics, requirements: status.requirements,
                                         remaining: [], lastMetAt: earnedAt)
            }
            return status
        }
    }

    /// The date a certificate prints, fixed (and stored) the first time it's
    /// asked for: when its last requirement was met if that's known, else
    /// today. Nil while it isn't earned.
    @discardableResult
    public func completionDate(_ kind: CertificateKind) -> Date? {
        guard let status = status(kind), status.isEarned else { return store.completionDate(kind) }
        return store.fixCompletionDate(kind, lastMetAt: status.lastMetAt, now: now())
    }

    /// Settings' resets: the name and every date go, and so does a
    /// course-complete card still waiting to show (a check left open on the
    /// Mac while its Settings window erased everything).
    public func reset() {
        store.reset()
        justEarned = nil
    }

    /// Run a progress change (a unit check passed, a Basics lesson
    /// finished) and record any certificate it completes: its earned-at
    /// moment is stored and `justEarned` set. Returns the certificates the
    /// change completed.
    @discardableResult
    public func recordingNewlyEarned(_ change: () -> Void) -> [CertificateKind] {
        let before = Set(CertificateKind.allCases.filter { status($0)?.isEarned == true })
        change()
        let newly = CertificateKind.allCases.filter { !before.contains($0) && status($0)?.isEarned == true }
        let moment = now()
        for kind in newly { store.recordEarned(kind, at: moment) }
        if let first = newly.first { justEarned = first }
        return newly
    }
}
