import Foundation
import Observation
import NetworkingKit

/// View model for the Club tab.
///
/// Owns the loaded events + blog posts and exposes a single `phase`
/// that the view switches over.
///
/// Both endpoints are fetched in parallel — it's the same page-load
/// story the web site tells, and there's no point serializing two
/// independent GETs.
@MainActor
@Observable
public final class ClubViewModel {

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(reason: String, isRetryable: Bool)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var events: ClubEvents?
    public private(set) var posts: [BlogPost] = []

    private let client: ClubDataProviding

    public init(client: ClubDataProviding) {
        self.client = client
    }

    /// Fetch both endpoints. Safe to call multiple times — pull-to-refresh
    /// just invokes this again.
    public func load() async {
        // Don't thrash the UI with a full-screen spinner on refreshes —
        // keep the loaded content visible and let `.refreshable` show the
        // system indicator. Only flip to `.loading` from `.idle`.
        if case .idle = phase { phase = .loading }

        do {
            async let eventsTask = client.fetchEvents()
            async let postsTask = client.fetchBlogPosts()
            let (fetchedEvents, fetchedPosts) = try await (eventsTask, postsTask)
            events = fetchedEvents
            posts = fetchedPosts
            phase = .loaded
        } catch let error as APIError {
            // Preserve previously-loaded data if we had any — the user
            // probably prefers seeing stale content with a retry nudge
            // over a blank screen.
            phase = .failed(
                reason: error.userFacingMessage,
                isRetryable: error.isRetryable
            )
        } catch {
            phase = .failed(
                reason: "Couldn't reach the club. Try again.",
                isRetryable: true
            )
        }
    }

    /// The "nearest meeting" — the upcoming one closest to today. Returns
    /// nil if `events` isn't loaded or there are no upcoming meetings.
    public var nextMeeting: UpcomingMeeting? {
        events?.upcoming.first
    }

    /// True iff at least one of events/posts has been loaded successfully.
    /// The view uses this to distinguish "never loaded" from "failed but
    /// we have stale data" for pull-to-refresh UX.
    public var hasAnyContent: Bool {
        events != nil || !posts.isEmpty
    }
}
