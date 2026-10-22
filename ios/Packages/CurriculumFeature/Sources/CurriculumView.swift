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
    /// The learner's course choice. With a store the path shows the
    /// "Basics | Deep dive" switch and follows it; without one it is the
    /// Deep dive's path alone, exactly as before Basics.
    let tracks: CurriculumTrackStore?

    public init(
        progress: CurriculumProgressStore,
        unitId: String? = nil,
        tracks: CurriculumTrackStore? = nil,
        onStartLesson: @escaping (Lesson) -> Void,
        onStartUnitTest: @escaping (Unit) -> Void,
        @ViewBuilder topBar: () -> TopBar
    ) {
        self.progress = progress
        self.unitId = unitId
        self.tracks = tracks
        self.onStartLesson = onStartLesson
        self.onStartUnitTest = onStartUnitTest
        self.topBar = topBar()
    }

    private var track: CurriculumTrack { tracks?.track ?? .deepDive }

    public var body: some View {
        NavigationStack {
            if let tracks {
                trackedPath(tracks)
            } else {
                deepDivePath
            }
        }
    }

    /// The path with the "Basics | Deep dive" switch pinned under the top
    /// bar, following the learner's choice.
    private func trackedPath(_ tracks: CurriculumTrackStore) -> some View {
        LearningPathView(
            progress: progress,
            unitId: unitId,
            track: track,
            tracks: tracks,
            onStartLesson: onStartLesson,
            onStartUnitTest: onStartUnitTest
        )
        // A new track is a new path: it opens scrolled to its own frontier.
        .id(track)
        // Basics: the learner's text size (a floor; a bigger system size wins).
        .readingSizeFloor(track == .basics ? tracks.basicsReadingSize : .standard)
        .background(BrandColor.background.ignoresSafeArea())
#if os(iOS)
        .navigationTitle(Self.title(unitId: unitId))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                topBar
                TrackSwitch(tracks: tracks)
            }
        }
#else
        .navigationTitle("Learning Path")
        .navigationSubtitle(Self.macSubtitle(unitId: unitId))
#endif
    }

    /// The Deep dive's path alone, built exactly as before Basics (the
    /// snapshot test's screen; no store, no switch).
    private var deepDivePath: some View {
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

/// "Basics | Deep dive": which course the path shows. Two large, labelled
/// segments across the top (BEGINNER_GUIDE §2.1); each course keeps its own
/// progress, and the choice is remembered.
struct TrackSwitch: View {
    @Bindable var tracks: CurriculumTrackStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CurriculumTrack.allCases, id: \.self) { track in
                segment(track)
            }
        }
        .padding(4)
        .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(BrandColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Course")
    }

    private func segment(_ track: CurriculumTrack) -> some View {
        let selected = tracks.track == track
        return Button {
            guard !selected else { return }
            tracks.choose(track)
        } label: {
            Text(track.displayName)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(selected ? Color.white : BrandColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                            .fill(BrandGradient.merc)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.displayName)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("path.track.\(track.rawValue)")
    }
}
