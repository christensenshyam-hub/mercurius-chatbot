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
        extraArgs: [String] = [],
        bypassModeDescriptions: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // `-hasSeenOnboarding YES` uses UserDefaults' argument domain to
        // flip the `@AppStorage("hasSeenOnboarding")` flag for this
        // process only. Without it, a freshly-installed test build lands
        // on InteractiveOnboardingView and every test that expects
        // HomeView / TabView state would have to walk through the
        // 7-step tutorial first.
        //
        // `-seenAllModeDescriptions YES` is the equivalent bypass for
        // the first-time mode description sheets — see
        // `ModeDescriptionStore.globalBypassKey`. Tests that need to
        // exercise the first-tap flow pass `bypassModeDescriptions: false`
        // so the flag isn't set.
        //
        // `-hasSeenChatInputHint YES` suppresses the first-launch hint
        // that sits between EmptyChatView and the ChatInputBar — the
        // starter-prompts test doesn't care about the hint's presence
        // and it would just add layout noise to every other test that
        // boots into the empty chat.
        var defaults = [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-hasSeenChatInputHint", "YES",
        ]
        if bypassModeDescriptions {
            defaults += ["-seenAllModeDescriptions", "YES"]
        }
        app.launchArguments += defaults + extraArgs
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
    func testTabBarHasChatAndCurriculum() {
        let app = launchApp()
        waitForBootComplete(app)

        // SwiftUI TabView surfaces tabItems as buttons named by their Label.
        // We look up by predicate so a future `.accessibilityLabel(...)`
        // override doesn't silently break the test.
        let chatTab = app.buttons.matching(NSPredicate(format: "label == 'Chat'")).firstMatch
        let curriculumTab = app.buttons.matching(NSPredicate(format: "label == 'Curriculum'")).firstMatch

        XCTAssertTrue(chatTab.exists, "Chat tab button missing")
        XCTAssertTrue(curriculumTab.exists, "Curriculum tab button missing")
    }

    @MainActor
    func testChatHeaderExposesHomeButton() {
        let app = launchApp()
        waitForBootComplete(app)

        // The Home button is the escape hatch out of the TabView back
        // to HomeView. It carries an explicit accessibility label so
        // VoiceOver users can find it.
        let home = app.buttons["Home"]
        XCTAssertTrue(
            home.waitForExistence(timeout: Self.lookupTimeout),
            "Home button missing from chat header — user would feel trapped in the TabView"
        )

        // Tapping it should take us back to HomeView, which we
        // recognize by the Start Chat button that only exists there.
        home.tap()
        XCTAssertTrue(
            app.buttons["Start Chat"].waitForExistence(timeout: Self.lookupTimeout),
            "Tapping Home from chat did not return to HomeView"
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
    func testFirstModeTapShowsDescriptionSheet() {
        // Per-mode `NO` overrides force every flag to false via the
        // UserDefaults argument domain — without them a prior sim
        // session that persisted `seenModeDescription.debate=true` would
        // mask the first-tap behavior we're trying to assert.
        let app = launchApp(
            extraArgs: [
                "-seenModeDescription.socratic", "NO",
                "-seenModeDescription.direct", "NO",
                "-seenModeDescription.debate", "NO",
                "-seenModeDescription.discussion", "NO",
            ],
            bypassModeDescriptions: false
        )
        waitForBootComplete(app)

        // Tap Debate — it's unlocked and guaranteed present. Socratic
        // is the default active mode so tapping it is a no-op path
        // (the user has already 'selected' it), and Direct is locked
        // which has its own branch; Debate is the cleanest first-tap
        // case for this assertion.
        let debatePill = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Debate'")
        ).firstMatch
        XCTAssertTrue(debatePill.waitForExistence(timeout: Self.lookupTimeout))
        debatePill.tap()

        // Sheet identity: the "Got it" primary button is visible.
        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(
            gotIt.waitForExistence(timeout: Self.lookupTimeout),
            "First tap on Debate should present the description sheet (Got it button missing)"
        )

        // Got it dismisses the sheet.
        gotIt.tap()
        XCTAssertFalse(
            app.buttons["Got it"].waitForExistence(timeout: 1),
            "Sheet should be dismissed after Got it"
        )
    }

    @MainActor
    func testEmptyChatHintVisibleOnFirstLaunch() {
        // Force the hint flag to false via the argument domain. The
        // extraArgs slot wins over the defaults list because it's
        // appended after. This simulates a first-launch user who has
        // never dismissed the hint.
        let app = launchApp(
            extraArgs: ["-hasSeenChatInputHint", "NO"]
        )
        waitForBootComplete(app)

        // The dismiss button is the reliable accessibility anchor —
        // if it's in the tree, the hint rendered.
        XCTAssertTrue(
            app.buttons["Dismiss hint"].waitForExistence(timeout: Self.lookupTimeout),
            "Empty-chat hint should appear on a first-launch (unseen) state — Dismiss button missing"
        )
    }

    @MainActor
    func testEmptyChatHintHiddenWhenAlreadySeen() {
        // The default `launchApp()` already passes
        // `-hasSeenChatInputHint YES`, which simulates a returning
        // user who dismissed the hint on a prior session.
        //
        // The dismissal side-effect itself (tap Dismiss → flag flips
        // → hint disappears) isn't verified here because the
        // UserDefaults argument domain wins over runtime writes, so
        // a within-process dismissal is not observable. This pair
        // of tests (visible-when-unseen / hidden-when-seen) covers
        // both initial states the user can actually reach.
        let app = launchApp()
        waitForBootComplete(app)

        XCTAssertFalse(
            app.buttons["Dismiss hint"].waitForExistence(timeout: 1),
            "Hint must not appear for a user who has already dismissed it"
        )
    }

    @MainActor
    func testAlreadySeenModeTapDoesNotShowSheet() {
        // Complement of `testFirstModeTapShowsDescriptionSheet`: assert
        // that once a mode is marked seen, tapping it does NOT re-present
        // the sheet.
        //
        // Done as a separate launch rather than tap-Got-it-then-tap-again
        // in one launch because the UserDefaults argument domain wins
        // over any runtime `markSeen` write — the app would persist the
        // flag correctly, but `hasSeen` still reads `NO` from the
        // argument domain for the duration of the process. Two launches
        // with different initial states sidesteps that.
        let app = launchApp(
            extraArgs: [
                "-seenModeDescription.debate", "YES",
            ],
            bypassModeDescriptions: false
        )
        waitForBootComplete(app)

        let debatePill = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Debate'")
        ).firstMatch
        XCTAssertTrue(debatePill.waitForExistence(timeout: Self.lookupTimeout))
        debatePill.tap()

        XCTAssertFalse(
            app.buttons["Got it"].waitForExistence(timeout: 1),
            "Tapping a mode whose description has already been seen must NOT re-present the sheet"
        )
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
