import SwiftUI
import DesignSystem

/// Root curriculum screen — the "Duolingo-blueprint" learning path. A single
/// winding scroll of unit checkpoints and lesson nodes (`LearningPathView`),
/// auto-scrolled to the learner's frontier. Tapping an unlocked node invokes the
/// `onStartLesson` / `onStartUnitTest` callback provided by the host.
///
/// `TopBar` is an optional header pinned above the path via `safeAreaInset`. The
/// curriculum screen lives in `CurriculumFeature`, which (by the architecture
/// layering rules) may NOT depend on `EngagementFeature`; so the gamified
/// streak/XP bar is composed at the `AppFeature` root and injected here through
/// this slot. The defaulted `EmptyView` convenience init keeps the original
/// three-argument call site (and the snapshot test) source-compatible.
public struct CurriculumView<TopBar: View>: View {
    @Bindable var progress: CurriculumProgressStore
    /// Only this unit's stretch of the path (the Mac sidebar's "Path by
    /// unit"); nil is the whole path, as on iOS.
    let unitId: String?
    let onStartLesson: (Lesson) -> Void
    let onStartUnitTest: (Unit) -> Void
    let topBar: TopBar

    public init(
        progress: CurriculumProgressStore,
        unitId: String? = nil,
        onStartLesson: @escaping (Lesson) -> Void,
        onStartUnitTest: @escaping (Unit) -> Void,
        @ViewBuilder topBar: () -> TopBar
    ) {
        self.progress = progress
        self.unitId = unitId
        self.onStartLesson = onStartLesson
        self.onStartUnitTest = onStartUnitTest
        self.topBar = topBar()
    }

    public var body: some View {
        NavigationStack {
            LearningPathView(
                progress: progress,
                unitId: unitId,
                onStartLesson: onStartLesson,
                onStartUnitTest: onStartUnitTest
            )
            .background(BrandColor.background.ignoresSafeArea())
#if os(iOS)
            .navigationTitle(Self.title(unitId: unitId))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
#else
            // The unit's banner names it; the window says where that is.
            // No top bar on the Mac: its streak is a toolbar button. (Even
            // an empty top inset left the path drawn blank once the split
            // view folded its sidebar away in a narrow window, macOS 26.)
            .navigationTitle("Learning Path")
            .navigationSubtitle(Self.macSubtitle(unitId: unitId))
#endif
        }
    }
}

extension CurriculumView {
    /// "Curriculum" for the whole path; "Unit 1 · <title>" for one unit.
    static func title(unitId: String?) -> String {
        guard let unitId, let unit = MercuriusCurriculum.unit(withId: unitId) else { return "Curriculum" }
        return "Unit \(Int(unit.number) ?? 0) · \(unit.title)"
    }

    /// The Mac window's subtitle under "Learning Path": "Unit 1 of 8", or
    /// "All units" for the whole path.
    static func macSubtitle(unitId: String?) -> String {
        let units = MercuriusCurriculum.units
        guard let unitId, let index = units.firstIndex(where: { $0.id == unitId }) else { return "All units" }
        return "Unit \(index + 1) of \(units.count)"
    }
}

// Source-compatible convenience init: the original three-argument call site
// (AppShellView's old wiring, the snapshot test) resolves here with no top bar.
public extension CurriculumView where TopBar == EmptyView {
    init(
        progress: CurriculumProgressStore,
        unitId: String? = nil,
        onStartLesson: @escaping (Lesson) -> Void,
        onStartUnitTest: @escaping (Unit) -> Void
    ) {
        self.init(
            progress: progress,
            unitId: unitId,
            onStartLesson: onStartLesson,
            onStartUnitTest: onStartUnitTest,
            topBar: { EmptyView() }
        )
    }
}
