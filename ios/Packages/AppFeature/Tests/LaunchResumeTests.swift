import Foundation
import Testing
@testable import AppFeature
import PersistenceKit

@Suite("Cold-launch resume")
@MainActor
struct LaunchResumeTests {

    private let now = Date(timeIntervalSince1970: 1_790_244_000)

    @Test("Active within 30 minutes on a destination tab: reopen that tab")
    func resumesRecentTab() {
        let store = LastActivityStore(defaults: freshDefaults("resume.recent"))
        store.touch(now: now.addingTimeInterval(-29 * 60))
        store.lastTab = AppShellView.Tab.curriculum.rawValue
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == .curriculum)

        store.lastTab = AppShellView.Tab.chat.rawValue
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == .chat)
    }

    @Test("Older than 30 minutes, never active, or a clock that went backwards: Home")
    func staleGoesHome() {
        let store = LastActivityStore(defaults: freshDefaults("resume.stale"))
        store.lastTab = AppShellView.Tab.chat.rawValue
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == nil)

        store.touch(now: now.addingTimeInterval(-31 * 60))
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == nil)

        store.touch(now: now.addingTimeInterval(60))
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == nil)
    }

    @Test("Never resumes around the consent gate")
    func gateWins() {
        #expect(LaunchResume.tab(isRecent: true, lastTab: "curriculum", gateShows: true) == nil)
    }

    @Test("Going Home clears the tab, so the next launch starts at Home")
    func homeClearsTab() {
        let store = LastActivityStore(defaults: freshDefaults("resume.home"))
        store.touch(now: now)
        store.lastTab = nil
        #expect(LaunchResume.tab(store: store, gateShows: false, now: now) == nil)
    }

    @Test("Action tabs and unknown values are never resumed")
    func onlyDestinations() {
        #expect(LaunchResume.tab(isRecent: true, lastTab: "history", gateShows: false) == nil)
        #expect(LaunchResume.tab(isRecent: true, lastTab: "newChat", gateShows: false) == nil)
        #expect(LaunchResume.tab(isRecent: true, lastTab: "settings", gateShows: false) == nil)
        #expect(AppShellView.Tab.chat.isDestination && AppShellView.Tab.curriculum.isDestination)
    }

    @Test("The launch-time gate check reads the persisted flags")
    func gateShowsAtLaunch() {
        let defaults = freshDefaults("resume.gate")
        #expect(AppEntryView.gateShowsAtLaunch(defaults: defaults))
        defaults.set(ConsentGate.currentVersion, forKey: ConsentGate.storageKey)
        #expect(AppEntryView.gateShowsAtLaunch(defaults: defaults), "onboarding not finished yet")
        defaults.set(true, forKey: OnboardingFlow.storageKey)
        #expect(!AppEntryView.gateShowsAtLaunch(defaults: defaults))
    }
}

/// No tight wall-clock bounds here: under `swift test --parallel` every
/// @MainActor test shares the main thread, and a neighbour holding it for a
/// couple of seconds delays both the work and the timer. Ordering is pinned
/// with a gate instead, and each time bound is loose enough to survive that.
@Suite("LaunchWork.waitAtMost")
@MainActor
struct LaunchWorkTests {

    @Test("Returns when the work finishes, well before the limit")
    func fastWork() async {
        var ran = false
        let clock = ContinuousClock()
        let start = clock.now
        await LaunchWork.waitAtMost(.seconds(60)) { ran = true }
        #expect(ran)
        // Half the limit: it returned because the work completed, not
        // because the timer fired.
        #expect(start.duration(to: clock.now) < .seconds(30))
    }

    @Test("Stops waiting at the limit; the work still finishes afterwards",
          .timeLimit(.minutes(1)))
    func slowWork() async {
        var finished = false
        // The work can't finish until the test opens this gate, which it
        // does only after `waitAtMost` has returned.
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        let clock = ContinuousClock()
        let start = clock.now
        await LaunchWork.waitAtMost(.milliseconds(50)) {
            for await _ in gate { break }
            finished = true
        }
        #expect(!finished, "the wait ended at the limit, before the work")
        // Loose on purpose: it proves only that the wait didn't hang on the
        // gated work.
        #expect(start.duration(to: clock.now) < .seconds(10))

        openGate.yield()
        openGate.finish()
        #expect(await eventually { finished }, "the work keeps running past the limit")
    }
}

@Suite("Home reminder card")
@MainActor
struct ReminderCardStoreTests {

    struct Row: Sendable, CustomTestStringConvertible {
        let weeklyEnabled: Bool
        let handled: Bool
        let onboardingComplete: Bool
        let permission: ReminderCardStore.Permission?
        let shows: Bool
        var testDescription: String {
            "weekly \(weeklyEnabled), handled \(handled), onboarded \(onboardingComplete), "
                + "permission \(permission.map { "\($0)" } ?? "unknown") → \(shows ? "shown" : "hidden")"
        }
    }

    @Test("Offered once to an onboarded student whose weekly nudges are off, unless iOS refused notifications",
          arguments: [
              // A 2.2 install that never allowed notifications.
              Row(weeklyEnabled: false, handled: false, onboardingComplete: true, permission: .notDetermined, shows: true),
              // A 2.2 install that allowed them, then turned the daily reminder off: asked, not subscribed.
              Row(weeklyEnabled: false, handled: false, onboardingComplete: true, permission: .allowed, shows: true),
              Row(weeklyEnabled: false, handled: false, onboardingComplete: true, permission: .denied, shows: false),
              Row(weeklyEnabled: false, handled: false, onboardingComplete: true, permission: nil, shows: false),
              // Already on (Progress hub, "Your path"): nothing to offer.
              Row(weeklyEnabled: true, handled: false, onboardingComplete: true, permission: .allowed, shows: false),
              // "Remind me", "Not now", or answered on "Your path".
              Row(weeklyEnabled: false, handled: true, onboardingComplete: true, permission: .notDetermined, shows: false),
              Row(weeklyEnabled: false, handled: true, onboardingComplete: true, permission: .allowed, shows: false),
              Row(weeklyEnabled: false, handled: false, onboardingComplete: false, permission: .notDetermined, shows: false),
          ])
    func visibility(_ row: Row) {
        #expect(ReminderCardStore.shows(
            weeklyEnabled: row.weeklyEnabled,
            handled: row.handled,
            onboardingComplete: row.onboardingComplete,
            permission: row.permission
        ) == row.shows)
    }

    @Test("'Not now' persists as handled, so the card never comes back")
    func notNowPersists() {
        let defaults = freshDefaults("card.notNow")
        ReminderCardStore(defaults: defaults).markHandled()
        let reloaded = ReminderCardStore(defaults: defaults)
        #expect(!ReminderCardStore.shows(weeklyEnabled: false, handled: reloaded.isHandled,
                                         onboardingComplete: true, permission: .notDetermined))
    }

    @Test("Handled persists across instances")
    func persists() {
        let defaults = freshDefaults("card")
        let first = ReminderCardStore(defaults: defaults)
        #expect(!first.isHandled)
        first.markHandled()
        #expect(first.isHandled)
        #expect(ReminderCardStore(defaults: defaults).isHandled)
        #expect(defaults.bool(forKey: ReminderCardStore.storageKey))
    }
}
