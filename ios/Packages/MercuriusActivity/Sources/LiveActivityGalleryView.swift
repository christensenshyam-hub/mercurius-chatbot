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
                section("First lesson, no streak yet — lock card") {
                    LockCardView(state: .demoActiveNoStreak, isStale: false)
                }
                section("Streak ends tonight — lock card") {
                    LockCardView(state: .demoActiveStreakAtRisk, isStale: false)
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
                section("First lesson — DI expanded") {
                    islandWell { ExpandedBody(state: .demoActiveNoStreak, isStale: false) }
                }
                section("Streak ends tonight — DI expanded") {
                    islandWell { ExpandedBody(state: .demoActiveStreakAtRisk, isStale: false) }
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
    /// The handoff's sample data: streak 24, 3 of 5 done in Unit 6 (`level`
    /// 7 = unit + 1), one lesson done this week, streak already saved today.
    static var demoActive: Self {
        .init(
            phase: .active, lessonsDone: 3, lessonsTotal: 5, progress: 0.6,
            streakCount: 24, level: 7, lessonsToLevel: 2,
            deadline: Date().addingTimeInterval(2 * 3600 + 40 * 60),
            lastUpdated: Date().addingTimeInterval(-6 * 60),
            weekDone: 1, weekGoal: 2, streakAtRisk: false
        )
    }

    /// A new student's first lesson (AUD-37's case): Unit 1, nothing done,
    /// no streak — a neutral headline and the week, no countdown.
    static var demoActiveNoStreak: Self {
        .init(
            phase: .active, lessonsDone: 0, lessonsTotal: 4, progress: 0,
            streakCount: 0, level: 2, lessonsToLevel: 4,
            deadline: Date().addingTimeInterval(15 * 3600 + 30 * 60),
            lastUpdated: Date(),
            weekDone: 0, weekGoal: 2, streakAtRisk: false
        )
    }

    /// A live streak whose last save day is today, not yet saved: the one
    /// case with a countdown, and it says what it counts down to.
    static var demoActiveStreakAtRisk: Self {
        .init(
            phase: .active, lessonsDone: 2, lessonsTotal: 4, progress: 0.5,
            streakCount: 6, level: 3, lessonsToLevel: 2,
            deadline: Date().addingTimeInterval(4 * 3600 + 12 * 60),
            lastUpdated: Date(),
            weekDone: 0, weekGoal: 2, streakAtRisk: true
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
