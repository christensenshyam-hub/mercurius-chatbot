import Foundation
import Observation
import NetworkingKit

/// Loads the global leaderboard and knows which row is "you".
///
/// Mirrors `QuizViewModel`: `@MainActor @Observable`, a `loading/ready/failed`
/// phase, and dependency-injected via a narrow protocol so tests inject a stub.
@MainActor
@Observable
public final class LeaderboardViewModel {

    public enum Phase: Equatable, Sendable {
        case loading
        case ready([LeaderboardEntry])
        case failed(reason: String, isRetryable: Bool)
    }

    public private(set) var phase: Phase = .loading

    /// The 4-char badge of the current session (last-4 of the session id,
    /// uppercased — matching the server's projection), used to highlight the
    /// current user's row. Nil if unavailable.
    public let ownBadge: String?

    private let fetcher: LeaderboardFetching

    public init(fetcher: LeaderboardFetching, ownBadge: String?) {
        self.fetcher = fetcher
        self.ownBadge = ownBadge
    }

    public func load() async {
        phase = .loading
        do {
            let entries = try await fetcher.leaderboard()
            phase = .ready(entries)
        } catch let error as APIError {
            phase = .failed(reason: error.userFacingMessage, isRetryable: error.isRetryable)
        } catch {
            phase = .failed(reason: "Couldn't load the leaderboard. Try again.", isRetryable: true)
        }
    }

    /// Whether `entry` is the current user's row (case-insensitive badge match).
    public func isYou(_ entry: LeaderboardEntry) -> Bool {
        guard let ownBadge, !ownBadge.isEmpty else { return false }
        return entry.badge.uppercased() == ownBadge.uppercased()
    }
}
