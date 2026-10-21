import SwiftUI
import DesignSystem
import CurriculumFeature
import EngagementFeature

/// What each certificate asks for, from the curricula this build has.
enum CertificateCourses {
    /// The Deep dive's eight unit checks, in course order, named for "what's
    /// left" ("Unit 4 · Prompt Engineering").
    static var deepDiveUnits: [CertificateRequirement] {
        MercuriusCurriculum.units.map {
            CertificateRequirement(id: $0.id, title: "Unit \(Int($0.number) ?? 0) · \($0.title)")
        }
    }

    /// **The Basics seam.** AI Basics' lessons in course order (ids `b1_l1`
    /// … `b5_l4`), once its curriculum is in this build; nil until then, and
    /// the Basics certificate isn't offered. The Basics branch returns its
    /// lessons here (see `docs/certificate/INTEGRATION.md`), and wraps its
    /// "lesson finished" call in `CertificateCenter.recordingNewlyEarned`.
    static var basicsLessons: [CertificateRequirement]? { nil }
}

extension CertificateCenter {
    /// The app's certificates, reading `progress` (mastered units, finished
    /// lessons and their dates) and keeping the name and dates in
    /// `defaults`, on this device.
    @MainActor
    static func make(progress: CurriculumProgressStore, defaults: UserDefaults) -> CertificateCenter {
        CertificateCenter(
            store: CertificateStore(defaults: defaults),
            deepDiveUnits: CertificateCourses.deepDiveUnits,
            basicsLessons: CertificateCourses.basicsLessons,
            progress: Progress(
                masteredUnitIds: { progress.masteredUnits },
                completedLessonIds: { Set(progress.completedIds) },
                completedAt: { progress.completedAt($0) }
            )
        )
    }

    /// The "Get your certificate" card for a check's result, when the pass
    /// just completed a course; nil otherwise.
    @MainActor
    func masteryAccessory(open: @escaping (CertificateKind) -> Void) -> AnyView? {
        guard let kind = justEarned else { return nil }
        return AnyView(CertificateReadyCard(kind: kind, name: store.name ?? "", onOpen: { open(kind) }))
    }
}

/// A unit check's host: the "Get your certificate" card in the check's
/// result slot while a pass has just completed a course, and the name sheet
/// it opens, over the check.
struct CertificateMasterySlot: ViewModifier {
    let center: CertificateCenter
    @State private var sheet: CertificateKind?

    func body(content: Content) -> some View {
        content
            .environment(\.unitMasteryAccessory, center.masteryAccessory(open: { sheet = $0 }))
            .sheet(item: $sheet) { kind in
                CertificateSheet(center: center, kind: kind, onClose: { sheet = nil })
            }
    }
}

extension View {
    func certificateMasterySlot(_ center: CertificateCenter) -> some View {
        modifier(CertificateMasterySlot(center: center))
    }
}

#if DEBUG
/// DEBUG launch arguments for screenshots of the certificates without taps.
/// They seed progress only in the `-UITests` suites (emptied at every
/// launch), and the progress is never pushed to the server.
///
/// - `-CertificatePreview deepDive|basics`: the name sheet for that
///   certificate, open, with a sample name (`-CertificateName <name>`, else
///   "Alexandria Montgomery-Vasquez").
/// - `-CertificateList YES`: the Certificates list (the Deep dive earned, AI
///   Basics part way).
/// - `-CertificateHub YES`: the Progress hub with its Certificates row.
/// - `-CertificateCardPreview YES`: the last unit's check passed, completing
///   the course: its result with the "Get your certificate" card.
///
/// AI Basics isn't in this build, so these hand the certificates a demo
/// lesson list through the Basics seam (`demoBasicsLessons`).
@MainActor
enum CertificateDebug {
    enum Mode: Equatable {
        case sheet(CertificateKind)
        case list
        case hub
        case card
    }

    static var mode: Mode? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(AppEnvironment.uiTestArgument) else { return nil }
        if let raw = UserDefaults.standard.string(forKey: "CertificatePreview"),
           let kind = CertificateKind(rawValue: raw) {
            return .sheet(kind)
        }
        if args.contains("-CertificateList") { return .list }
        if args.contains("-CertificateHub") { return .hub }
        if args.contains("-CertificateCardPreview") { return .card }
        return nil
    }

    static var sampleName: String {
        UserDefaults.standard.string(forKey: "CertificateName") ?? "Alexandria Montgomery-Vasquez"
    }

    /// AI Basics' 18 lessons as the Basics branch names them (`b1_l1` …
    /// `b5_l4`), titled by position only.
    static let demoBasicsLessons: [CertificateRequirement] = {
        let lessonsPerUnit = [3, 4, 3, 4, 4]
        var lessons: [CertificateRequirement] = []
        for (u, count) in lessonsPerUnit.enumerated() {
            for l in 1...count {
                lessons.append(CertificateRequirement(id: "b\(u + 1)_l\(l)", title: "Basics \(u + 1).\(l)"))
            }
        }
        return lessons
    }()

    /// Seed the state `mode` shows.
    @MainActor
    static func seed(_ mode: Mode, env: AppEnvironment) {
        let center = env.certificates
        let progress = env.progressStore
        center.basicsLessons = demoBasicsLessons
        let units = MercuriusCurriculum.units
        let lessonDates = Dictionary(uniqueKeysWithValues: demoBasicsLessons.map { ($0.id, Date().addingTimeInterval(-86_400)) })
        switch mode {
        case .sheet, .list, .hub:
            center.recordingNewlyEarned {
                progress.merge(completed: [], mastered: units.map(\.id), remoteVersion: MercuriusCurriculum.version)
            }
            let basicsDone = mode == .sheet(.basics) ? demoBasicsLessons : Array(demoBasicsLessons.prefix(12))
            progress.merge(completed: basicsDone.map(\.id), mastered: [], remoteVersion: MercuriusCurriculum.version,
                           remoteUpdatedAt: lessonDates)
            center.justEarned = nil
        case .card:
            // The check's pass masters every unit at once (`passCourse`).
            break
        }
        center.store.setName(sampleName)
    }

    /// The card shot's pass: all eight units mastered by the one change, so
    /// the course completes there and then.
    @MainActor
    static func passCourse(env: AppEnvironment) {
        let progress = env.progressStore
        env.certificates.recordingNewlyEarned {
            progress.merge(completed: [], mastered: MercuriusCurriculum.units.map(\.id),
                           remoteVersion: MercuriusCurriculum.version)
        }
    }
}

#if os(iOS)
/// The iPhone's certificate shots (`RootView`, DEBUG): the Certificates
/// list (with the name sheet over it for `.sheet`), the Progress hub, or
/// the last unit's check passed with its card.
struct CertificateDebugHost: View {
    @EnvironmentObject private var env: AppEnvironment
    let mode: CertificateDebug.Mode
    @State private var seeded = false
    @State private var sheet: CertificateKind?

    var body: some View {
        content
            .sheet(item: $sheet) { kind in
                CertificateSheet(center: env.certificates, kind: kind, onClose: { sheet = nil })
            }
            .task {
                guard !seeded else { return }
                seeded = true
                CertificateDebug.seed(mode, env: env)
                if case .sheet(let kind) = mode {
                    try? await Task.sleep(for: .milliseconds(400))
                    sheet = kind
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .sheet, .list:
            NavigationStack {
                CertificatesListView(center: env.certificates)
            }
            .tint(BrandColor.accentText)
        case .hub:
            ProgressHubView(
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                reminderStore: env.reminderStore,
                scheduler: NotificationScheduler(),
                certificates: env.certificates,
                onDone: {}
            )
            .tint(BrandColor.accent)
        case .card:
            if let unit = MercuriusCurriculum.units.last, let test = MercuriusCurriculum.unitTest(for: unit.id) {
                UnitTestPreviewHost(unit: unit, test: test, stage: "mastered", onMastered: { _ in
                    CertificateDebug.passCourse(env: env)
                })
                .certificateMasterySlot(env.certificates)
            }
        }
    }
}
#endif
#endif
