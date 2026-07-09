import Foundation
#if os(iOS)
import ActivityKit

/// App-side lifecycle for the learning Live Activity: one activity at a time,
/// started when a lesson session begins, updated as progress lands, completed
/// with a lingering win, ended when the session is abandoned.
///
/// Updates here are local (`activity.update`); the attributes support
/// `pushType: .token` for a future server-driven path, but nothing in this
/// controller depends on it.
@MainActor
public final class LearningActivityController {
    public static let shared = LearningActivityController()
    private init() {}

    private var activity: Activity<LearningActivityAttributes>?

    /// The in-memory reference dies with the process, but the Lock Screen
    /// card doesn't — after a relaunch (killed mid-lesson, then resumed),
    /// adopt the system's surviving activity so `update`/`complete` refresh
    /// the visible card instead of silently no-opping against a nil handle.
    private var tracked: Activity<LearningActivityAttributes>? {
        if let activity { return activity }
        activity = Activity<LearningActivityAttributes>.activities.first
        return activity
    }

    /// Whether the user has allowed Live Activities (Settings toggle).
    public var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start (or replace) the session activity. `staleDate` = the deadline,
    /// so the system flips `isStale` exactly when the window closes.
    public func startSession(title: String, state: LearningActivityAttributes.ContentState) {
        guard isEnabled else { return }
        let content = ActivityContent(state: state, staleDate: state.deadline, relevanceScore: 100)
        activity = nil
        Task {
            // End EVERY existing activity for these attributes — the tracked
            // one and any orphans from a previous process run — and await the
            // ends before requesting, so old and new never stack and the
            // request can't trip ActivityKit's per-app activity limit.
            for stale in Activity<LearningActivityAttributes>.activities {
                await stale.end(stale.content, dismissalPolicy: .immediate)
            }
            do {
                activity = try Activity.request(
                    attributes: LearningActivityAttributes(sessionTitle: title),
                    content: content
                )
            } catch {
                // Denied/limited — the session just runs without a banner.
                #if DEBUG
                print("LearningActivityController: request failed — \(error)")
                #endif
            }
        }
    }

    /// Push fresh progress into the running activity.
    public func update(state: LearningActivityAttributes.ContentState) {
        guard let activity = tracked else { return }
        let content = ActivityContent(state: state, staleDate: state.deadline, relevanceScore: 100)
        Task { await activity.update(content) }
    }

    /// Mark the session completed — `end(..., .default)` keeps the win on the
    /// Lock Screen for the system's linger window (a few hours), then
    /// dismisses. A plain `update` would leave the activity alive (and
    /// counting against the app's limit) until the 8-hour cap.
    public func complete(state: LearningActivityAttributes.ContentState) {
        guard let activity = tracked else { return }
        var s = state
        s.phase = .completed
        s.progress = 1
        s.lastUpdated = Date()
        let content = ActivityContent(state: s, staleDate: nil, relevanceScore: 100)
        self.activity = nil
        Task { await activity.end(content, dismissalPolicy: .default) }
    }

    /// End the activity (user abandoned the session / app cleanup).
    public func endSession(immediately: Bool = false) {
        guard let activity = tracked else { return }
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .default
        self.activity = nil
        Task { await activity.end(activity.content, dismissalPolicy: policy) }
    }

    #if DEBUG
    /// `-LiveActivityPreview`: the handoff's exact sample data — streak 24,
    /// Lesson 3 of 5, 2 to Level 7, 2h 40m left — so every surface can be
    /// eyeballed without running a real session.
    public func startDemo() {
        startSession(
            title: "Unit 4 · Foundations",
            state: .init(
                phase: .active,
                lessonsDone: 3,
                lessonsTotal: 5,
                progress: 0.6,
                streakCount: 24,
                level: 7,
                lessonsToLevel: 2,
                deadline: Date().addingTimeInterval(2 * 3600 + 40 * 60),
                lastUpdated: Date()
            )
        )
    }
    #endif
}
#endif
