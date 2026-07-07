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
    let onStartLesson: (Lesson) -> Void
    let onStartUnitTest: (Unit) -> Void
    let topBar: TopBar

    public init(
        progress: CurriculumProgressStore,
        onStartLesson: @escaping (Lesson) -> Void,
        onStartUnitTest: @escaping (Unit) -> Void,
        @ViewBuilder topBar: () -> TopBar
    ) {
        self.progress = progress
        self.onStartLesson = onStartLesson
        self.onStartUnitTest = onStartUnitTest
        self.topBar = topBar()
    }

    public var body: some View {
        NavigationStack {
            LearningPathView(
                progress: progress,
                onStartLesson: onStartLesson,
                onStartUnitTest: onStartUnitTest
            )
            .background(BrandColor.background.ignoresSafeArea())
            .navigationTitle("Curriculum")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
        }
    }
}

// Source-compatible convenience init: the original three-argument call site
// (AppShellView's old wiring, the snapshot test) resolves here with no top bar.
public extension CurriculumView where TopBar == EmptyView {
    init(
        progress: CurriculumProgressStore,
        onStartLesson: @escaping (Lesson) -> Void,
        onStartUnitTest: @escaping (Unit) -> Void
    ) {
        self.init(
            progress: progress,
            onStartLesson: onStartLesson,
            onStartUnitTest: onStartUnitTest,
            topBar: { EmptyView() }
        )
    }
}
