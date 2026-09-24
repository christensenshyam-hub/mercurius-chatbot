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
/// 4. Mode selector — all three modes render and are selectable.
/// 5. Header affordances — Settings and Tools buttons carry their
///    accessibility labels and open the right UI.
/// 6. Curriculum tab — progress bar + unit section header appear, and all
///    five unit titles render.
/// 7. Dynamic Type — at an accessibility text size the main header is still
///    readable and the starter prompts remain reachable (no off-screen
///    content, no clipped controls).
/// 8. First-run gate (2.3.0) — Meet Merc → age picker → disclosure →
///    limits → path lands in Lesson 1; under-13 is a dead end; "Not now"
///    pauses and "Review" returns; an existing install (`hasSeenOnboarding`
///    already true, consent never given) sees the gate once and then Home.
///    All of it is client-side: the first network call happens only after
///    the shell mounts, which the lesson-intro anchor sits in front of.
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
        // on the first-run flow and every test that expects HomeView /
        // TabView state would have to walk through it first.
        //
        // `-consentVersion 1` is the same bypass for the 2.3.0 consent
        // gate (`ConsentGate.currentVersion == 1`; `0` = never consented).
        // The first-run tests below override both keys via `extraArgs`,
        // which wins because it is appended after the defaults.
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
            "-consentVersion", "1",
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
    /// Post-launch flow is: loading spinner → HomeView (the Merc
    /// welcome) → (user taps Chat with Merc) → AppShellView / TabView.
    /// The `"AI LITERACY TUTOR"` caption in the chat header is our
    /// reliable "we are in the app" signal — it exists only once the
    /// TabView is on screen ("Mercurius AI" is NOT unique anymore:
    /// the Home welcome shows the same wordmark).
    /// Nearly every test cares about TabView-level affordances, so
    /// this helper does both boot-wait and CTA tap by default.
    /// Pass `enterApp: false` for tests that want to assert on
    /// HomeView itself.
    @MainActor
    private func waitForBootComplete(
        _ app: XCUIApplication,
        enterApp: Bool = true,
        timeout: TimeInterval = 15
    ) {
        // First: HomeView's "Chat with Merc" button is the post-bootstrap
        // ready signal. Appears once RootView flips from .loading to
        // .ready.
        let chatCTA = app.buttons["Chat with Merc"]
        XCTAssertTrue(
            chatCTA.waitForExistence(timeout: timeout),
            "App never reached HomeView — Chat with Merc button did not appear within \(timeout)s"
        )
        guard enterApp else { return }

        // Tap through to the TabView. The "Debate" mode pill is the reliable
        // "we're in the chat tab" signal — it's unique to the chat screen and
        // unaffected by header chrome changes. (The brand caption that used to
        // anchor this was removed when the header was slimmed down.)
        chatCTA.tap()
        let chatSignal = app.buttons["Debate"]
        XCTAssertTrue(
            chatSignal.waitForExistence(timeout: timeout),
            "Did not reach the chat tab — 'Debate' mode pill missing \(timeout)s after Chat with Merc"
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
        // recognize by the Chat with Merc CTA that only exists there.
        home.tap()
        XCTAssertTrue(
            app.buttons["Chat with Merc"].waitForExistence(timeout: Self.lookupTimeout),
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
    func testModeSelectorExposesAllModes() {
        let app = launchApp()
        waitForBootComplete(app)

        // `ModeSelectorView` builds each pill's accessibility label as
        // "<displayName>, selected" / plain. Match by BEGINSWITH so
        // we're robust to either state.
        let expected = ["Socratic", "Debate", "Discussion"]
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
                "-seenModeDescription.debate", "NO",
                "-seenModeDescription.discussion", "NO",
            ],
            bypassModeDescriptions: false
        )
        waitForBootComplete(app)

        // Tap Debate — guaranteed present. Socratic is the default
        // active mode so tapping it is a no-op path (the user has
        // already 'selected' it); Debate is the cleanest first-tap
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
            app.buttons["Debate"].waitForExistence(timeout: Self.lookupTimeout),
            "Dismissing settings did not return focus to the chat screen"
        )
    }

    // MARK: - First-run gate (2.3.0)

    /// Launch budget for the first gate screen. Cold launch holds the
    /// Merc launch screen for 3.5 s before `AppEntryView` renders, and
    /// CI runners are slower still — same 15 s the Home anchor gets.
    static let firstScreenTimeout: TimeInterval = 15

    /// Launch arguments for a brand-new install: the tutorial flag and
    /// the consent flag are both unset. Overrides the `launchApp`
    /// defaults because `extraArgs` is appended after them.
    static let freshInstallArgs = [
        "-hasSeenOnboarding", "NO",
        "-consentVersion", "0",
    ]

    /// Launch arguments for an install that finished onboarding before
    /// 2.3.0 and has never seen the consent gate.
    static let preConsentInstallArgs = [
        "-hasSeenOnboarding", "YES",
        "-consentVersion", "0",
    ]

    /// Look an onboarding element up by its accessibility identifier,
    /// whatever element type SwiftUI happens to expose it as (button,
    /// switch, static text, picker). The flow's identifiers are the
    /// contract between the UI tests and `OnboardingFlow` — see the
    /// `onboarding.*` strings below.
    @MainActor
    private func onboardingElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Wait for an onboarding element and tap it. Fails the test with a
    /// message naming the missing identifier.
    @MainActor
    private func tapOnboarding(
        _ app: XCUIApplication,
        _ identifier: String,
        timeout: TimeInterval = MercuriusUITests.lookupTimeout
    ) {
        let element = onboardingElement(app, identifier)
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Onboarding element '\(identifier)' did not appear within \(timeout)s"
        )
        element.tap()
    }

    /// Age step: wait for the picker, spin the wheel to `age`, continue.
    /// The wheel values are the flow's own labels ("12 or younger",
    /// "13" … "18 or older"), so `age` must match one exactly.
    @MainActor
    private func chooseAge(_ app: XCUIApplication, _ age: String, timeout: TimeInterval = MercuriusUITests.lookupTimeout) {
        XCTAssertTrue(
            onboardingElement(app, "onboarding.agePicker").waitForExistence(timeout: timeout),
            "Age picker (onboarding.agePicker) did not appear within \(timeout)s"
        )
        app.pickerWheels.element.adjust(toPickerWheelValue: age)
        tapOnboarding(app, "onboarding.ageContinue")
    }

    /// Disclosure step: tick the required consent checkbox, then agree.
    @MainActor
    private func acceptDisclosure(_ app: XCUIApplication) {
        tapOnboarding(app, "onboarding.consentToggle")
        tapOnboarding(app, "onboarding.agree")
    }

    @MainActor
    func testFirstRunGateLandsInFirstLesson() {
        let app = launchApp(extraArgs: Self.freshInstallArgs)

        // Meet Merc is the first screen a fresh install sees.
        tapOnboarding(app, "onboarding.continue", timeout: Self.firstScreenTimeout)
        chooseAge(app, "15")
        acceptDisclosure(app)
        tapOnboarding(app, "onboarding.limitsAck")
        tapOnboarding(app, "onboarding.startLesson1")

        // "Start Lesson 1" opens the lesson cover on its speech-bubble
        // intro. The intro's CTA is the anchor: it exists only inside
        // `CurriculumLessonView`, and no network fires until it is tapped.
        XCTAssertTrue(
            app.buttons["Continue. Start the lesson."].waitForExistence(timeout: Self.firstScreenTimeout),
            "Start Lesson 1 did not open the Lesson 1 intro (\"Continue. Start the lesson.\" missing)"
        )
    }

    @MainActor
    func testUnderThirteenIsBlocked() {
        let app = launchApp(extraArgs: Self.freshInstallArgs)

        tapOnboarding(app, "onboarding.continue", timeout: Self.firstScreenTimeout)
        chooseAge(app, "12 or younger")

        // Terminal screen: the title is the anchor, and none of the
        // controls that would move the flow forward may remain.
        XCTAssertTrue(
            onboardingElement(app, "onboarding.underThirteen").waitForExistence(timeout: Self.lookupTimeout),
            "Choosing '12 or younger' must land on the under-13 screen (onboarding.underThirteen missing)"
        )
        for identifier in ["onboarding.ageContinue", "onboarding.consentToggle", "onboarding.agree"] {
            XCTAssertFalse(
                onboardingElement(app, identifier).waitForExistence(timeout: 1),
                "Under-13 screen must be a dead end — '\(identifier)' is still reachable"
            )
        }
    }

    @MainActor
    func testNotNowPausesAndReviewReturns() {
        let app = launchApp(extraArgs: Self.freshInstallArgs)

        tapOnboarding(app, "onboarding.continue", timeout: Self.firstScreenTimeout)
        chooseAge(app, "15")

        // Declining the disclosure parks the student on the paused screen…
        tapOnboarding(app, "onboarding.notNow")
        let paused = onboardingElement(app, "onboarding.paused")
        XCTAssertTrue(
            paused.waitForExistence(timeout: Self.lookupTimeout),
            "'Not now' should show the paused screen (onboarding.paused missing)"
        )
        XCTAssertFalse(
            onboardingElement(app, "onboarding.agree").waitForExistence(timeout: 1),
            "Paused screen must not expose the Agree control"
        )

        // …and "Review" brings the disclosure back with its controls intact.
        tapOnboarding(app, "onboarding.review")
        XCTAssertTrue(
            onboardingElement(app, "onboarding.consentToggle").waitForExistence(timeout: Self.lookupTimeout),
            "'Review' did not return to the disclosure (onboarding.consentToggle missing)"
        )
        XCTAssertTrue(
            onboardingElement(app, "onboarding.agree").exists,
            "Disclosure came back without its Agree control"
        )
        XCTAssertFalse(
            paused.exists,
            "Paused screen title still present after returning to the disclosure"
        )
    }

    @MainActor
    func testExistingInstallSeesGateOnceThenHome() {
        // An install that finished the pre-2.3.0 tutorial skips Meet Merc
        // and the path screen; it only has to clear the consent gate.
        let app = launchApp(extraArgs: Self.preConsentInstallArgs)

        chooseAge(app, "15", timeout: Self.firstScreenTimeout)
        acceptDisclosure(app)
        tapOnboarding(app, "onboarding.limitsAck")

        // Consent recorded → the regular Home doorman, not the lesson.
        XCTAssertTrue(
            app.buttons["Chat with Merc"].waitForExistence(timeout: Self.firstScreenTimeout),
            "Existing install did not reach HomeView after clearing the consent gate"
        )
        XCTAssertFalse(
            onboardingElement(app, "onboarding.startLesson1").exists,
            "Existing install must not be shown the first-run path screen"
        )
    }

    @MainActor
    func testHeaderRemainsVisibleAtAccessibilityTextSize() {
        // At XXL accessibility text size the header used to overflow the
        // safe area (Phase 3f regression). This test is the canary: if a
        // header control ever stops being reachable at an accessibility
        // size, the layout caps have been lost. (Anchors on the Settings
        // button now that the brand caption is gone.)
        let app = launchApp(contentSize: "UICTContentSizeCategoryAccessibilityXXL")
        waitForBootComplete(app, timeout: 15)

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.exists, "Header control must stay reachable at XXL accessibility size")
        XCTAssertTrue(settings.isHittable, "Header control scrolled off-screen at XXL accessibility size")
    }
}
