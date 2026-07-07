import Testing
import NetworkingKit
@testable import EngagementFeature

/// Stub fetcher for leaderboard tests.
private struct StubLeaderboard: LeaderboardFetching {
    let result: Result<[LeaderboardEntry], Error>
    func leaderboard() async throws -> [LeaderboardEntry] {
        try result.get()
    }
}

@MainActor
@Suite("LeaderboardViewModel")
struct LeaderboardViewModelTests {

    private func entry(rank: Int, badge: String, name: String? = nil) -> LeaderboardEntry {
        LeaderboardEntry(rank: rank, badge: badge, streak: 3, messages: 10, unlocked: false, name: name)
    }

    @Test("Successful load lands on .ready")
    func loadReady() async {
        let vm = LeaderboardViewModel(
            fetcher: StubLeaderboard(result: .success([entry(rank: 1, badge: "AB12")])),
            ownBadge: "AB12"
        )
        await vm.load()
        guard case .ready(let rows) = vm.phase else {
            Issue.record("expected .ready, got \(vm.phase)")
            return
        }
        #expect(rows.count == 1)
    }

    @Test("Network failure lands on .failed (retryable)")
    func loadFailed() async {
        let vm = LeaderboardViewModel(
            fetcher: StubLeaderboard(result: .failure(APIError.timeout)),
            ownBadge: nil
        )
        await vm.load()
        guard case .failed(_, let retryable) = vm.phase else {
            Issue.record("expected .failed, got \(vm.phase)")
            return
        }
        #expect(retryable == true)
    }

    @Test("isYou matches own badge case-insensitively")
    func isYou() {
        let vm = LeaderboardViewModel(fetcher: StubLeaderboard(result: .success([])), ownBadge: "AB12")
        #expect(vm.isYou(entry(rank: 1, badge: "ab12")) == true)
        #expect(vm.isYou(entry(rank: 2, badge: "ZZ99")) == false)
    }
}
