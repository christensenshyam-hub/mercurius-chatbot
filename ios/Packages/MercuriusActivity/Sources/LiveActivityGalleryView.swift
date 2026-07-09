#if os(iOS) && DEBUG
import SwiftUI

/// DEBUG-only: every Live Activity phase rendered in-app, so the lock card
/// and the DI expanded body can be eyeballed/screenshotted without pushing a
/// real activity through each transition (the sim can't fake stale/error).
/// Reached via the `-LiveActivityGallery` launch argument (RootView).
public struct LiveActivityGalleryView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Live Activity — all phases")
                    .font(.system(size: 22, weight: .heavy))
                    .padding(.top, 8)

                section("Active — lock card") {
                    LockCardView(state: .demoActive, isStale: false)
                }
                section("Completed — lock card") {
                    LockCardView(state: .demoCompleted, isStale: false)
                }
                section("Stale — lock card (dim, no timer)") {
                    LockCardView(state: .demoActive, isStale: true)
                }
                section("Error — lock card") {
                    LockCardView(state: .demoError, isStale: false)
                }

                section("Active — DI expanded") {
                    islandWell { ExpandedBody(state: .demoActive, isStale: false) }
                }
                section("Error — DI expanded") {
                    islandWell { ExpandedBody(state: .demoError, isStale: false) }
                }
            }
            // 10pt sides ≈ the real Lock Screen banner width, so truncation
            // behavior here predicts the real surface.
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        // `-LiveActivityGalleryBottom`: open scrolled to the DI sections
        // (screenshot tooling can't swipe).
        .defaultScrollAnchor(
            ProcessInfo.processInfo.arguments.contains("-LiveActivityGalleryBottom") ? .bottom : .top
        )
        .background(Color(.systemGroupedBackground))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Approximates the expanded island's black well so the on-island colors
    /// read the way they will in situ.
    private func islandWell(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

extension LearningActivityAttributes.ContentState {
    /// The handoff's sample data: streak 24, Lesson 3 of 5, 2 to Level 7.
    static var demoActive: Self {
        .init(
            phase: .active, lessonsDone: 3, lessonsTotal: 5, progress: 0.6,
            streakCount: 24, level: 7, lessonsToLevel: 2,
            deadline: Date().addingTimeInterval(2 * 3600 + 40 * 60),
            lastUpdated: Date().addingTimeInterval(-6 * 60)
        )
    }

    static var demoCompleted: Self {
        .init(
            phase: .completed, lessonsDone: 5, lessonsTotal: 5, progress: 1,
            streakCount: 24, level: 7, lessonsToLevel: 0,
            deadline: Date().addingTimeInterval(2 * 3600),
            lastUpdated: Date()
        )
    }

    static var demoError: Self {
        .init(
            phase: .error, lessonsDone: 3, lessonsTotal: 5, progress: 0.6,
            streakCount: 24, level: 7, lessonsToLevel: 2,
            deadline: Date().addingTimeInterval(2 * 3600),
            lastUpdated: Date().addingTimeInterval(-2 * 60)
        )
    }
}
#endif
