import XCTest

/// Performance baselines captured through the shipped simulator build.
///
/// Deliberately narrow scope: only launch time today. Scroll and memory
/// metrics need a populated chat history, which means a real ChatStore
/// seeded at boot — that's a separate piece of test infrastructure we
/// haven't built yet.
///
/// Numbers are collected across 5 iterations per metric; XCTest records
/// mean and standard deviation. To capture a new baseline locally from
/// the Xcode UI: run this test suite, then **Product → Set Baseline**
/// on each reported metric. Baselines stored in xcresult bundles that
/// ship alongside the xcodeproj are picked up automatically — but
/// because GitHub runners have variable performance, we deliberately do
/// NOT commit baselines. The metric exists to spot regressions locally
/// and to trend over time, not to gate PR merges.
///
/// Running from CLI:
///   xcodebuild test -project Mercurius.xcodeproj -scheme Mercurius \
///     -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
///     -only-testing:MercuriusUITests/PerformanceTests
///
/// The XCTest default is a single measure block runs 5 iterations and
/// takes about 45-60 seconds per metric on a local dev machine.
final class PerformanceTests: XCTestCase {

    /// Launch arguments every perf test passes. `-hasSeenOnboarding`
    /// flips the `@AppStorage` flag in the process's argument-domain
    /// UserDefaults, bypassing InteractiveOnboardingView so measurements
    /// land on the real app surface — not on the tutorial flow.
    /// `-seenAllModeDescriptions` suppresses the first-time mode
    /// description sheets for the same reason. Cold-launch measurement
    /// uses these too so bootstrap time is comparable to what a
    /// returning user sees, not what a fresh install sees.
    static let defaultLaunchArgs = [
        "-UITests", "YES",
        "-hasSeenOnboarding", "YES",
        "-seenAllModeDescriptions", "YES",
    ]

    /// Post-launch: advance past HomeView into the main TabView so
    /// the subsequent scroll / memory measurements are against the
    /// real chat screen. Cold-launch measurement (below) doesn't
    /// use this — it's deliberately measuring the whole bootstrap.
    @MainActor
    private func enterAppFromHome(_ app: XCUIApplication, timeout: TimeInterval = 15) {
        let startChat = app.buttons["Start Chat"]
        XCTAssertTrue(
            startChat.waitForExistence(timeout: timeout),
            "HomeView never rendered — Start Chat button missing after \(timeout)s"
        )
        startChat.tap()
        XCTAssertTrue(
            app.staticTexts["Mercurius AI"].waitForExistence(timeout: timeout),
            "Did not reach the chat screen after tapping Start Chat"
        )
    }

    @MainActor
    func testColdLaunchTime() throws {
        // `XCTApplicationLaunchMetric()` reports total time from process
        // spawn to the app becoming interactive. Each iteration starts a
        // fresh process so the bootstrap path (session resolve, SwiftData
        // container init, RootView loading → ready transition) is fully
        // exercised every time.
        let metric = XCTApplicationLaunchMetric()

        // Disable warmup — the iOS Simulator itself keeps the app alive
        // under the hood, so XCTest's built-in warmup iteration isn't
        // adding signal.
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [metric], options: options) {
            let app = XCUIApplication()
            app.launchArguments += Self.defaultLaunchArgs
            app.launch()
        }
    }

    @MainActor
    func testSeededChatScrollPerformance() throws {
        // Launches the app with `-SeedDemoChat`, which swaps in an
        // InMemoryChatStore pre-populated with 50 messages. Measures
        // wall-clock time + memory during a fast swipe-up / swipe-down
        // cycle against the message list. Signal comes from the
        // LazyVStack creating and tearing down cells under scroll
        // pressure.

        let app = XCUIApplication()
        app.launchArguments += Self.defaultLaunchArgs + ["-SeedDemoChat"]
        app.launch()

        // Walk past HomeView → TabView so the scroll target is the
        // populated chat message list.
        enterAppFromHome(app)

        // Anchor on the scroll view that holds the message list.
        // SwiftUI ScrollView renders as an XCUIElement.Type.scrollView.
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Chat scroll view missing after boot")

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: options
        ) {
            // Up twice, down twice — enough to force many LazyVStack
            // cell creations and a couple of layout re-passes.
            scrollView.swipeUp(velocity: .fast)
            scrollView.swipeUp(velocity: .fast)
            scrollView.swipeDown(velocity: .fast)
            scrollView.swipeDown(velocity: .fast)
        }
    }

    @MainActor
    func testSeededChatMemoryFootprint() throws {
        // Separate from scroll perf — this one measures peak memory at
        // rest with a populated conversation visible. Catches leaks
        // introduced by ChatViewModel or message bubble renderers
        // without a scroll gesture adding variance.
        let app = XCUIApplication()
        app.launchArguments += Self.defaultLaunchArgs + ["-SeedDemoChat"]
        app.launch()

        enterAppFromHome(app)

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(
            metrics: [XCTMemoryMetric(application: app)],
            options: options
        ) {
            // `XCTMemoryMetric` samples during the block. Give the
            // layout a moment to settle and the view model to hydrate
            // from the seeded store.
            _ = app.staticTexts.count
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}
