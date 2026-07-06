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

    private static let timeout: TimeInterval = 25

    override func setUpWithError() throws {
        continueAfterFailure = true   // capture as many screens as we can
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
        app.launch()

        // Home → Chat. ("AI LITERACY TUTOR" is unique to the chat header;
        // the Home welcome also shows "Mercurius AI".)
        let chatCTA = app.buttons["Chat with Merc"]
        XCTAssertTrue(chatCTA.waitForExistence(timeout: Self.timeout), "Never reached Home")
        chatCTA.tap()
        XCTAssertTrue(
            app.staticTexts["AI LITERACY TUTOR"].waitForExistence(timeout: Self.timeout),
            "Never reached the chat tab"
        )
        settle()

        // 1 — Chat (hero): seeded conversation + the mode pills up top.
        snapshot("01-chat")

        // 2 — Settings sheet.
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: Self.timeout) {
            settings.tap()
            settle()
            snapshot("02-settings")
            dismissSheet(app)
            settle()
        }

        // 3 — Curriculum tab.
        let curriculum = app.buttons.matching(NSPredicate(format: "label == 'Curriculum'")).firstMatch
        if curriculum.waitForExistence(timeout: Self.timeout) {
            curriculum.tap()
            settle()
            snapshot("03-curriculum")
            // Back to chat for the next step.
            let chat = app.buttons.matching(NSPredicate(format: "label == 'Chat'")).firstMatch
            if chat.exists { chat.tap(); settle() }
        }

        // 4 — Chat History (the History tab presents it as a sheet).
        let history = app.buttons.matching(NSPredicate(format: "label == 'History'")).firstMatch
        if history.waitForExistence(timeout: Self.timeout) {
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

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Close", "Done"] where app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        app.swipeDown(velocity: .fast)
    }
}
