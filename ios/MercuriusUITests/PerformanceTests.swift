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
            XCUIApplication().launch()
        }
    }
}
