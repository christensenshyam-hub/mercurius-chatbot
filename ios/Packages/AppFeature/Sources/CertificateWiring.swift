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

    /// **The Basics seam.** AI Basics' 18 lessons in course order, under the
    /// ids the progress store records (`b1_l1` … `b5_l4`), named for "what's
    /// left" ("Unit 2 · Following up"). The lesson-complete handlers mark
    /// them inside `CertificateCenter.recordingNewlyEarned` (see
    /// `docs/certificate/INTEGRATION.md`).
    static var basicsLessons: [CertificateRequirement] {
        BasicsCurriculum.units.flatMap { unit in
            unit.lessons.map {
                CertificateRequirement(id: $0.id, title: "Unit \(Int(unit.number) ?? 0) · \($0.title)")
            }
        }
    }
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

/// A lesson's host: the "You finished AI Basics" card on its complete
/// screen when the lesson's completion finished the course, and the name
/// sheet it opens, over the lesson. The card stays as long as that screen
/// does, also once its sheet has opened and closed (the sheet clears
/// `justEarned`): in Basics nothing goes before the learner is done with it
/// (BEGINNER_GUIDE §2.3). On the iPhone only the screen's buttons close it
/// while the card shows (a tap on the dimmed lesson doesn't), since neither
/// Home nor the path leads a Basics learner to Progress ▸ Certificates; on
/// the Mac, Escape and a click beside it still do, with Progress (⌘4) in
/// every toolbar.
struct CertificateLessonSlot: ViewModifier {
    let center: CertificateCenter
    @State private var sheet: CertificateKind?
    /// The certificate this lesson's completion earned.
    @State private var earned: CertificateKind?

    func body(content: Content) -> some View {
        content
            .environment(\.lessonCompleteAccessory, earned.map { kind in
                // Compact on the iPhone, so the sheet keeps room for "Try
                // this today" under it.
                AnyView(CertificateReadyCard(kind: kind, name: center.store.name ?? "", compact: true,
                                             onOpen: { sheet = kind }))
            })
            .onChange(of: center.justEarned) { _, kind in
                if let kind { earned = kind }
            }
            // Settings' erase (the Mac's Settings window, with the lesson
            // open) takes the certificate, and the card with it.
            .onChange(of: center.store.resetCount) { _, _ in earned = nil }
            .sheet(item: $sheet) { kind in
                CertificateSheet(center: center, kind: kind, onClose: { sheet = nil })
            }
    }
}

extension View {
    func certificateMasterySlot(_ center: CertificateCenter) -> some View {
        modifier(CertificateMasterySlot(center: center))
    }

    func certificateLessonSlot(_ center: CertificateCenter) -> some View {
        modifier(CertificateLessonSlot(center: center))
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
/// AI Basics' card is reached the real way: `-CurriculumTrack basics
/// -OpenLesson b1_l1 -LessonReplay YES -LessonSkipIntro YES
/// -LessonReplayScript 3` with the other 17 lessons in `-SeedCompleted`
/// (the Mac's `certificate-card-basics` shot).
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

    /// Seed the state `mode` shows.
    @MainActor
    static func seed(_ mode: Mode, env: AppEnvironment) {
        let center = env.certificates
        let progress = env.progressStore
        let units = MercuriusCurriculum.units
        let basics = CertificateCourses.basicsLessons
        let lessonDates = Dictionary(uniqueKeysWithValues: basics.map { ($0.id, Date().addingTimeInterval(-86_400)) })
        switch mode {
        case .sheet, .list, .hub:
            center.recordingNewlyEarned {
                progress.merge(completed: [], mastered: units.map(\.id), remoteVersion: MercuriusCurriculum.version)
            }
            let basicsDone = mode == .sheet(.basics) ? basics : Array(basics.prefix(12))
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
            .tint(BrandAppearance.tint)
        case .hub:
            ProgressHubView(
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                reminderStore: env.reminderStore,
                scheduler: NotificationScheduler(),
                certificates: env.certificates,
                onDone: {}
            )
            .tint(BrandAppearance.tint)
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
