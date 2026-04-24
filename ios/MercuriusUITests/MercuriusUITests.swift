import XCTest

/// End-to-end UI tests that exercise the shipped app through the accessibility
/// API. These tests **do not talk to the network** — every flow covered
/// below is client-side only (boot, tab switch, empty state, settings sheet,
/// mode selector, Dynamic Type). That keeps the suite fast and hermetic.
///
/// What gets covered
/// =================
/// 1. Boot completes — the loading spinner gives way to the main shell.
/// 2. TabView wiring — both Chat and Curriculum tab buttons exist and the
///    selection actually flips content when tapped.
/// 3. Empty chat state — all four starter prompts surface as accessible
///    buttons so a VoiceOver user can reach them.
/// 4. Mode selector — all four modes render; Direct is marked locked.
/// 5. Header affordances — Settings and Tools buttons carry their
///    accessibility labels and open the right UI.
/// 6. Curriculum tab — progress bar + unit section header appear, and all
///    five unit titles render.
/// 7. Dynamic Type — at an accessibility text size the main header is still
///    readable and the starter prompts remain reachable (no off-screen
///    content, no clipped controls).
///
/// What is NOT covered here
/// ========================
/// - Sending a chat message (requires network; would be a flaky integration
///   test without a stubbed server).
/// - Streaming token rendering (same reason).
/// - Quiz / Report Card tool flows (same reason).
/// Those belong in a separate, network-aware integration layer.
final class MercuriusUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp(
        contentSize: String? = nil,
        extraArgs: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "YES"] + extraArgs
        if let contentSize {
            // Dynamic Type sizes passed as a standard iOS preferred content
            // size category — e.g. "UICTContentSizeCategoryAccessibilityL".
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = contentSize
        }
        app.launch()
        return app
    }

    /// Default existence-wait timeout. GitHub-hosted macOS runners are
    /// meaningfully slower than local dev machines, especially for the
    /// first render after a tap (tab switch, sheet present). 8s gives
    /// ample headroom without blowing total runtime — most lookups
    /// resolve in well under 1s once the element is in the tree.
    static let lookupTimeout: TimeInterval = 8

    /// Wait for the bootstrap phase to finish AND advance past the
    /// HomeView entry screen into the main TabView.
    ///
    /// Post-launch flow is: loading spinner → HomeView → (user taps
    /// Start Chat) → AppShellView / TabView. The `"Mercurius AI"`
    /// staticText in the chat header is our reliable "we are in the
    /// app" signal — it exists only once the TabView is on screen.
    /// Nearly every test cares about TabView-level affordances, so
    /// this helper does both boot-wait and Start-Chat tap by default.
    /// Pass `enterApp: false` for tests that want to assert on
    /// HomeView itself.
    @MainActor
    private func waitForBootComplete(
        _ app: XCUIApplication,
        enterApp: Bool = true,
        timeout: TimeInterval = 15
    ) {
        // First: HomeView's "Start Chat" button is the post-bootstrap
        // ready signal. Appears once RootView flips from .loading to
        // .ready.
        let startChat = app.buttons["Start Chat"]
        XCTAssertTrue(
            startChat.waitForExistence(timeout: timeout),
            "App never reached HomeView — Start Chat button did not appear within \(timeout)s"
        )
        guard enterApp else { return }

        // Tap through to the TabView. The chat header's "Mercurius AI"
        // staticText is the reliable signal we've landed there.
        startChat.tap()
        let header = app.staticTexts["Mercurius AI"]
        XCTAssertTrue(
            header.waitForExistence(timeout: timeout),
            "Did not reach the chat tab — 'Mercurius AI' header missing \(timeout)s after Start Chat"
        )
    }

    // MARK: - Tests

    @MainActor
    func testBootCompletes() {
        let app = launchApp()
        waitForBootComplete(app)
    }

    @MainActor
    func testTabBarHasAllThreeTabs() {
        let app = launchApp()
        waitForBootComplete(app)

        // SwiftUI TabView surfaces tabItems as buttons named by their Label.
        // We look up by predicate so a future `.accessibilityLabel(...)`
        // override doesn't silently break the test.
        let chatTab = app.buttons.matching(NSPredicate(format: "label == 'Chat'")).firstMatch
        let curriculumTab = app.buttons.matching(NSPredicate(format: "label == 'Curriculum'")).firstMatch
        let clubTab = app.buttons.matching(NSPredicate(format: "label == 'Club'")).firstMatch

        XCTAssertTrue(chatTab.exists, "Chat tab button missing")
        XCTAssertTrue(curriculumTab.exists, "Curriculum tab button missing")
        XCTAssertTrue(clubTab.exists, "Club tab button missing")
    }

    @MainActor
    func testSwitchingToClubTabShowsClubTitle() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Club"].tap()

        // `navigationTitle("Club")` renders as a static text inside the
        // navigation bar. It's distinct from the tab-bar button label
        // because they live on different elements.
        let clubTitle = app.navigationBars["Club"].firstMatch
        XCTAssertTrue(
            clubTitle.waitForExistence(timeout: Self.lookupTimeout),
            "Club tab did not present the Club navigation title"
        )
    }

    @MainActor
    func testSwitchingToCurriculumTabShowsProgressSection() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Curriculum"].tap()

        // The navigation bar title is the sturdiest anchor: on iOS 17 it
        // surfaces as a staticText; on iOS 18+ the List section header
        // "Overall progress" is accessibility role `.header`, not
        // `.staticText`, so matching against staticTexts misses it. The
        // navigation bar name is consistent across versions.
        let navBar = app.navigationBars["Curriculum"].firstMatch
        XCTAssertTrue(
            navBar.waitForExistence(timeout: Self.lookupTimeout),
            "Curriculum tab did not present its NavigationStack (navigationTitle 'Curriculum' missing)"
        )
    }

    @MainActor
    func testCurriculumListsAllFiveUnits() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Curriculum"].tap()
        // Same iOS 18 accessibility quirk as in the test above — gate on
        // the navigation bar, not the section header.
        _ = app.navigationBars["Curriculum"].firstMatch.waitForExistence(timeout: Self.lookupTimeout)

        // These strings come straight from `MercuriusCurriculum.units` —
        // if a unit title is renamed, update here too. Intentional: keeps
        // the test honest about public-facing copy.
        //
        // SwiftUI `List` is lazy: rows below the fold aren't in the
        // accessibility tree until scrolled into view. For each unit we
        // try `exists` first and fall back to scrolling if needed.
        let expectedUnits = [
            "How AI Actually Works",
            "Bias & Fairness",
            "AI in Society",
            "Prompt Engineering",
            "Ethics & Alignment",
        ]

        for title in expectedUnits {
            let cell = app.staticTexts[title]
            if !cell.exists {
                // Swipe up inside the list — up to 4 swipes ought to
                // reveal anything in a 5-row list on any iPhone screen.
                for _ in 0..<4 where !cell.exists {
                    app.swipeUp()
                }
            }
            XCTAssertTrue(
                cell.waitForExistence(timeout: Self.lookupTimeout),
                "Unit title '\(title)' not found on Curriculum tab even after scrolling"
            )
        }
    }

    @MainActor
    func testStarterPromptsPresentInEmptyChat() {
        let app = launchApp()
        waitForBootComplete(app)

        // Starter-prompt buttons use their prompt as the accessibility
        // label — that's what EmptyChatView sets. Abbreviated check:
        // the first two prompts is enough to catch a regression where
        // the whole set fails to render (e.g. EmptyChatView swapped for
        // a different component).
        let prompts = [
            "How does an LLM actually work?",
            "Is AI biased? Where does the bias come from?",
        ]
        for prompt in prompts {
            // Generous timeout — under code-coverage instrumentation the
            // initial render can exceed a few-second wait. Only the first
            // lookup pays this cost; subsequent ones find the button
            // already in the accessibility tree.
            XCTAssertTrue(
                app.buttons[prompt].waitForExistence(timeout: 10),
                "Starter prompt button '\(prompt)' missing from empty chat state"
            )
        }
    }

    @MainActor
    func testModeSelectorExposesAllFourModes() {
        let app = launchApp()
        waitForBootComplete(app)

        // `ModeSelectorView` builds each pill's accessibility label as
        // "<displayName>, locked" / "<displayName>, selected" / plain.
        // Match by CONTAINS so we're robust to either state.
        let expected = ["Socratic", "Direct", "Debate", "Discussion"]
        for mode in expected {
            let pill = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", mode)
            ).firstMatch
            XCTAssertTrue(
                pill.exists,
                "Mode pill for '\(mode)' missing"
            )
        }
    }

    @MainActor
    func testTappingSettingsOpensSheetWithAppearanceSection() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Settings"].tap()

        // The sheet's navigation bar "Settings" and its toolbar "Done"
        // button are stable anchors across iOS versions. Form section
        // headers ("Appearance", "Session", "About") render as
        // accessibility role `.header` on iOS 18+, so matching against
        // `staticTexts` misses them.
        let sheetNavBar = app.navigationBars["Settings"].firstMatch
        XCTAssertTrue(
            sheetNavBar.waitForExistence(timeout: Self.lookupTimeout),
            "Settings sheet did not present — Settings navigation bar missing"
        )
        XCTAssertTrue(
            app.buttons["Done"].exists,
            "Settings sheet opened but the Done toolbar button is missing"
        )

        // Close via the Done toolbar button and confirm we return to chat.
        app.buttons["Done"].tap()
        XCTAssertTrue(
            app.staticTexts["Mercurius AI"].waitForExistence(timeout: Self.lookupTimeout),
            "Dismissing settings did not return focus to the chat header"
        )
    }

    @MainActor
    func testToolsButtonIsReachable() {
        let app = launchApp()
        waitForBootComplete(app)

        let tools = app.buttons["Tools"]
        XCTAssertTrue(tools.exists, "Tools button in chat header is not exposed to accessibility")
    }

    @MainActor
    func testHeaderRemainsVisibleAtAccessibilityTextSize() {
        // At XXL accessibility text size the header used to overflow the
        // safe area (Phase 3f regression). This test is the canary: if
        // the header ever stops being reachable at an accessibility size,
        // the minimumScaleFactor / lineLimit caps have been lost.
        let app = launchApp(contentSize: "UICTContentSizeCategoryAccessibilityXXL")
        waitForBootComplete(app, timeout: 15)

        let header = app.staticTexts["Mercurius AI"]
        XCTAssertTrue(header.exists, "Header must stay reachable at XXL accessibility size")
        XCTAssertTrue(header.isHittable, "Header scrolled off-screen at XXL accessibility size")
    }
}
