import XCTest

/// Captures App Store screenshots from a seeded, network-free app state.
///
/// Not part of the normal CI suite — drive it with `./scripts/screenshots.sh`,
/// which boots the right device sizes, runs only this test, and exports the
/// images. Each screen is saved as a named `keepAlways` attachment; the driver
/// pulls them out of the `.xcresult` with `xcresulttool export attachments`.
///
/// Covers the screens reachable without network: the seeded chat (hero),
/// Settings, Curriculum, and Chat History. The photo-in-chat and quiz/report
/// screens need live backend/media and look best captured by hand on-device —
/// see APP_STORE_LISTING.md.
final class AppStoreScreenshots: XCTestCase {

    /// Per-query existence budget. This is the slowest UI test (~169s): it
    /// seeds a ~50-message conversation, so the accessibility tree is large
    /// and every snapshot XCUITest takes is expensive. On a loaded, shared CI
    /// runner a query fired while a screen is still transitioning has
    /// intermittently aborted with "Timed out while evaluating UI query"
    /// (seen on the feature/merc-reminder-layer run — failed once, passed on
    /// re-run). A generous budget, combined with `settleAndWait` letting each
    /// transition quiesce first, gives that headroom. Most lookups still
    /// resolve in well under a second once the element is in the tree.
    private static let timeout: TimeInterval = 45

    override func setUpWithError() throws {
        continueAfterFailure = true   // capture as many screens as we can
    }

    /// While the launch-retry loop is running, swallow the launch-phase
    /// failures XCUITest records on a cold-simulator misfire ("does not have
    /// a process ID"). `app.launch()` doesn't throw — it RECORDS the issue —
    /// so without this, one flaky first launch marks the whole test failed
    /// even when the retry succeeds. Cleared after the loop; a genuine
    /// never-launches case still fails via the explicit assert.
    private var suppressLaunchIssues = false

    override func record(_ issue: XCTIssue) {
        if suppressLaunchIssues,
           issue.compactDescription.contains("does not have a process ID")
            || issue.compactDescription.contains("Failed to launch") {
            return
        }
        super.record(issue)
    }

    @MainActor
    func testCaptureAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",       // skip the onboarding tutorial
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES", // skip first-tap mode sheets
            "-SeedDemoChat",                   // ~50-message in-memory conversation
        ]
        // This suite runs FIRST on CI, against a freshly booted simulator, and
        // the very first launch has repeatedly died with "does not have a
        // process ID" (the app never reaches foreground) before any UI query
        // runs. Retry the launch itself — every later suite's launch succeeds,
        // so one warm-up round trip is all the runner needs. Launch-phase
        // issues are suppressed during the loop (see `record(_:)`) because
        // XCUITest records them rather than throwing.
        suppressLaunchIssues = true
        var launched = false
        for attempt in 1...3 {
            app.launch()
            if app.wait(for: .runningForeground, timeout: 30) {
                launched = true
                break
            }
            app.terminate()
            if attempt < 3 { sleep(5) }
        }
        suppressLaunchIssues = false
        XCTAssertTrue(launched, "App never reached foreground after 3 launch attempts")

        // Home → Chat. The "Debate" mode pill is unique to the chat screen
        // (unaffected by the slimmed-down header that dropped the brand caption).
        let chatCTA = app.buttons["Chat with Merc"]
        XCTAssertTrue(chatCTA.waitForExistence(timeout: Self.timeout), "Never reached Home")
        chatCTA.tap()
        // Entering the seeded 50-message chat is the heaviest transition of the
        // run, so gate on the pill through the settle-first poll helper rather
        // than a single blocking query.
        XCTAssertTrue(
            settleAndWait(app.buttons["Debate"]),
            "Never reached the chat tab"
        )

        // 1 — Chat (hero): seeded conversation + the mode pills up top.
        snapshot("01-chat")

        // 2 — Settings sheet.
        let settings = app.buttons["Settings"]
        if settleAndWait(settings) {
            settings.tap()
            // Wait for the sheet to actually present before capturing, instead
            // of a blind sleep — its nav bar is a stable cross-version anchor.
            _ = settleAndWait(app.navigationBars["Settings"].firstMatch)
            snapshot("02-settings")
            dismissSheet(app)
            settle()
        }

        // 3 — Curriculum tab.
        let curriculum = app.buttons.matching(NSPredicate(format: "label == 'Curriculum'")).firstMatch
        if settleAndWait(curriculum) {
            curriculum.tap()
            _ = settleAndWait(app.navigationBars["Curriculum"].firstMatch)
            snapshot("03-curriculum")
            // Back to chat for the next step.
            let chat = app.buttons.matching(NSPredicate(format: "label == 'Chat'")).firstMatch
            if chat.exists { chat.tap(); settle() }
        }

        // 4 — Chat History (the History tab presents it as a sheet).
        let history = app.buttons.matching(NSPredicate(format: "label == 'History'")).firstMatch
        if settleAndWait(history) {
            history.tap()
            settle()
            snapshot("04-history")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Let presentation/transition animations finish before capturing.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// Wait for `element` to appear, but let the in-flight transition settle
    /// first and then poll in short slices up to `timeout`, rather than betting
    /// the capture on a single long-running query.
    ///
    /// Same poll-with-deadline shape as `MercPresenceControllerTests.poll`,
    /// adapted to XCUIElement: on a loaded shared runner the seeded chat's large
    /// accessibility tree makes any query fired mid-transition slow, so we
    /// (1) `settle()` so the finite present/dismiss/tab animation is done before
    /// we look, then (2) re-evaluate existence in ~2s slices until the deadline —
    /// a check that returns the instant the element is in the tree and re-tries
    /// across a transient snapshot hiccup instead of failing the run outright.
    @MainActor
    @discardableResult
    private func settleAndWait(
        _ element: XCUIElement,
        timeout: TimeInterval = AppStoreScreenshots.timeout
    ) -> Bool {
        settle()
        if element.exists { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 2) { return true }
        }
        return element.exists
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Close", "Done"] where app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        app.swipeDown(velocity: .fast)
    }
}
