import Foundation
import PersistenceKit

/// Bounded waits for the launch screen.
enum LaunchWork {
    /// Waits for `work`, but no longer than `limit`. Past the limit the work
    /// keeps running and lands whenever it finishes; the limit only bounds
    /// how long the launch screen holds for it.
    @MainActor
    static func waitAtMost(_ limit: Duration, for work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in await work() }
        let (signal, continuation) = AsyncStream<Void>.makeStream()
        let finished = Task {
            await task.value
            continuation.yield()
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            continuation.yield()
        }
        for await _ in signal { break }
        continuation.finish()
        timer.cancel()
        _ = finished
    }
}

/// The cold-launch resume: reopening the app shortly after using it goes
/// back to the tab the student was on instead of replaying Home.
enum LaunchResume {
    static let window: TimeInterval = 30 * 60

    /// The tab to reopen, or nil for Home. Nil whenever the consent gate will
    /// show — the launch goes through the gate, never around it.
    static func tab(isRecent: Bool, lastTab: String?, gateShows: Bool) -> AppShellView.Tab? {
        guard isRecent, !gateShows,
              let lastTab, let tab = AppShellView.Tab(rawValue: lastTab), tab.isDestination
        else { return nil }
        return tab
    }

    @MainActor
    static func tab(store: LastActivityStore, gateShows: Bool, now: Date = Date()) -> AppShellView.Tab? {
        tab(isRecent: store.isWithin(window, now: now), lastTab: store.lastTab, gateShows: gateShows)
    }
}
