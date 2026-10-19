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
/// 5. Header affordances — Settings and Home buttons carry their
///    accessibility labels and open the right UI; Settings → About exposes
///    "Send feedback" and pushes "How Mercurius teaches".
/// 6. Curriculum tab — the path's navigation title appears, and all eight
///    unit titles render.
/// 7. Dynamic Type — at an accessibility text size the main header is still
///    readable and the starter prompts remain reachable (no off-screen
///    content, no clipped controls).
/// 8. Home — the primary CTA is the next stop on the path ("Start Lesson 1"
///    on a fresh path), with "Chat with Merc" still beside it.
/// 9. First-run gate (2.3.0) — Meet Merc → age picker → disclosure →
///    limits → path lands in Lesson 1; under-13 is a dead end; "Not now"
///    pauses and "Review" returns; an existing install (`hasSeenOnboarding`
///    already true, consent never given) sees the gate once and then Home.
///    All of it is client-side: the first network call happens only after
///    the shell mounts, which the lesson-intro anchor sits in front of.
///
/// `-UITests` gives lesson progress, last activity and the Home reminder
/// card their own UserDefaults suites, wiped at every launch (AppFeature's
/// `AppEnvironment`), so every test starts on Home at Lesson 1 no matter
/// what an earlier test did.
///
/// What is NOT covered here
/// ========================
/// - Sending a chat message (requires network; would be a flaky integration
///   test without a stubbed server).
/// - Streaming token rendering (same reason).
/// - The Quiz tool flow (same reason).
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
            "-consentVersion", "1",   // must equal ConsentGate.currentVersion (AppFeature) — bump in lockstep
            "-hasSeenChatInputHint", "YES",
        ]
        if bypassModeDescriptions {
            defaults += ["-seenAllModeDescriptions", "YES"]
        }
        app.launchArguments += defaults + extraArgs
        if let contentSize {
            // Dynamic Type size as a standard iOS content size category,
            // e.g. "UICTContentSizeCategoryAccessibilityXXXL". It must be a
            // launch ARGUMENT (UserDefaults' argument domain, which UIKit
            // reads): set in `launchEnvironment` it was silently ignored,
            // and the app launched at the simulator's own text size.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
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
        // At accessibility text sizes the pills are one "Mode" menu
        // (AUD-48), and "Debate" is an item inside it — so the menu is the
        // signal there.
        let chatSignal = app.buttons["Debate"]
        let modeMenu = element(app, Self.modeMenuIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while !chatSignal.exists && !modeMenu.exists && Date() < deadline {
            _ = chatSignal.waitForExistence(timeout: 0.5)
        }
        XCTAssertTrue(
            chatSignal.exists || modeMenu.exists,
            "Did not reach the chat tab — neither the 'Debate' mode pill nor the mode menu appeared \(timeout)s after Chat with Merc"
        )
    }

    /// `ModeSelectorView.menuIdentifier`: the mode menu that replaces the
    /// pills at accessibility text sizes.
    static let modeMenuIdentifier = "chat.modeMenu"

    /// Any element by accessibility identifier, whatever type SwiftUI exposes
    /// it as (a `Link` and a `NavigationLink` both surface as buttons today,
    /// but that is not a contract).
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Swipe up until `element` is in the accessibility tree — lazy stacks
    /// and forms only build rows near the viewport. Slow swipes so a row
    /// isn't flung past between checks.
    @MainActor
    private func scrollUntilExists(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 30
    ) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.waitForExistence(timeout: Self.lookupTimeout)
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
    func testCurriculumListsAllUnits() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Curriculum"].tap()
        // Same iOS 18 accessibility quirk as in the test above — gate on
        // the navigation bar, not the section header.
        _ = app.navigationBars["Curriculum"].firstMatch.waitForExistence(timeout: Self.lookupTimeout)

        // These strings come straight from `MercuriusCurriculum.units` —
        // if a unit title is renamed, update here too. Intentional: keeps
        // the test honest about public-facing copy.
        let expectedUnits = [
            "How AI Actually Works",
            "Bias & Fairness",
            "AI in Society",
            "Prompt Engineering",
            "Ethics & Alignment",
            "Spotting AI: Deepfakes & Synthetic Media",
            "Using AI Well",
            "The Frontier: Agents & What's Next",
        ]

        // Each unit header is one combined accessibility element labelled
        // "Unit 0N: <title>. …", so match on CONTAINS rather than an exact
        // static text. The path is a LazyVStack: later units only enter the
        // tree once scrolled near, and the titles are in path order, so one
        // downward pass finds them all.
        for title in expectedUnits {
            let header = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", title))
                .firstMatch
            XCTAssertTrue(
                scrollUntilExists(header, in: app),
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

    /// Whether something answers on the dev server port `-UseLocalServer`
    /// points the app at. The delete-failure test needs it closed.
    private func localServerAnswers() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var answered = false
        let request = URLRequest(url: URL(string: "http://localhost:3000/health")!, timeoutInterval: 2)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            answered = response != nil
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 4)
        return answered
    }

    /// AUD-54: when "Delete my data" can't reach the server, the fallback
    /// doesn't reset at once. It first shows the ID the server data is still
    /// under, with a Copy button, and says only an email to privacy@ can
    /// delete it after a reset. Cancelling leaves the ID as it was.
    @MainActor
    func testDeleteFailureShowsTheOldIdBeforeADeviceOnlyReset() throws {
        // `-UseLocalServer` points the app at localhost:3000; with nothing
        // listening there, the server delete fails as it would offline.
        if localServerAnswers() {
            throw XCTSkip("A server is listening on localhost:3000; this test needs the delete to fail")
        }
        let app = launchApp(extraArgs: ["-UseLocalServer"])
        waitForBootComplete(app)

        app.buttons["Settings"].tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: Self.lookupTimeout),
            "Settings sheet did not present"
        )
        let idLabel = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Session identifier: ")).firstMatch
        XCTAssertTrue(idLabel.waitForExistence(timeout: Self.lookupTimeout), "Settings shows no session ID")
        let sessionId = String(idLabel.label.dropFirst("Session identifier: ".count))
        XCTAssertGreaterThan(sessionId.count, 8, "Unexpected session ID '\(sessionId)'")

        element(app, "settings.deleteData").tap()
        let confirmDelete = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: Self.lookupTimeout), "No delete confirmation")
        confirmDelete.tap()

        let failure = app.alerts["Couldn't delete your data"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30), "The failed delete didn't show its alert")
        let fallback = failure.buttons["Reset this device only…"]
        XCTAssertTrue(fallback.exists, "The failure alert has no device-only fallback")
        fallback.tap()

        let confirmReset = element(app, "settings.deviceReset.confirm")
        XCTAssertTrue(confirmReset.waitForExistence(timeout: Self.lookupTimeout),
                      "The fallback reset straight away instead of showing what it leaves behind")
        XCTAssertTrue(element(app, "settings.deviceReset.copyId").exists, "No Copy ID button")
        XCTAssertTrue(app.staticTexts["Session ID: \(sessionId)"].exists
                      || app.staticTexts[sessionId].exists,
                      "The sheet doesn't show the ID the server data is under")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "privacy@trymercurius.com")).firstMatch.exists,
            "The sheet doesn't say an email to privacy@ is the only way to delete it afterwards"
        )
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "device-only-reset-sheet"
        shot.lifetime = .keepAlways
        add(shot)

        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(confirmReset.waitForExistence(timeout: 2), "Cancel didn't close the sheet")
        XCTAssertEqual(idLabel.label, "Session identifier: \(sessionId)", "Cancel must leave the ID alone")
    }

    @MainActor
    func testSettingsHasFeedbackAndHowItTeaches() {
        let app = launchApp()
        waitForBootComplete(app)

        app.buttons["Settings"].tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: Self.lookupTimeout),
            "Settings sheet did not present — Settings navigation bar missing"
        )

        // Both rows sit in the About section at the bottom of the form, which
        // is lazily built — scroll until each is in the tree. The feedback
        // Link is only checked, never tapped: it leaves the app for Safari.
        let feedback = element(app, "settings.sendFeedback")
        XCTAssertTrue(
            scrollUntilExists(feedback, in: app),
            "Settings → About is missing 'Send feedback' (settings.sendFeedback)"
        )
        let howItTeaches = element(app, "settings.howItTeaches")
        XCTAssertTrue(
            scrollUntilExists(howItTeaches, in: app),
            "Settings → About is missing 'How Mercurius teaches' (settings.howItTeaches)"
        )

        howItTeaches.tap()
        XCTAssertTrue(
            app.navigationBars["How Mercurius teaches"].firstMatch.waitForExistence(timeout: Self.lookupTimeout),
            "'How Mercurius teaches' did not push its page"
        )
    }

    // MARK: - Home

    @MainActor
    func testHomeShowsNextStop() {
        let app = launchApp()
        waitForBootComplete(app, enterApp: false)

        // `-UITests` starts every launch with no lesson progress, so the next
        // stop is Lesson 1. The CTA label may go on to name the lesson,
        // hence BEGINSWITH.
        let nextStop = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Start Lesson 1"))
            .firstMatch
        XCTAssertTrue(
            nextStop.waitForExistence(timeout: Self.lookupTimeout),
            "Home's primary CTA should offer the next stop ('Start Lesson 1…') on a fresh path"
        )
        XCTAssertTrue(
            app.buttons["Chat with Merc"].exists,
            "Home lost its 'Chat with Merc' button next to the next-stop CTA"
        )
    }

    // MARK: - First-run gate (2.3.0)

    /// Launch budget for the first gate screen. Cold launch holds the
    /// Merc launch screen for at least 1.2 s before `AppEntryView`
    /// renders, and CI runners are slower still — same 15 s the Home
    /// anchor gets.
    static let firstScreenTimeout: TimeInterval = 15

    /// Launch arguments for a brand-new install: the tutorial flag and
    /// the consent flag are both unset. Overrides the `launchApp`
    /// defaults because `extraArgs` is appended after them.
    static let freshInstallArgs = [
        "-hasSeenOnboarding", "NO",
        "-consentVersion", "0",   // 0 = never consented; any value below ConsentGate.currentVersion gates
    ]

    /// Launch arguments for an install that finished onboarding before
    /// 2.3.0 and has never seen the consent gate.
    static let preConsentInstallArgs = [
        "-hasSeenOnboarding", "YES",
        "-consentVersion", "0",   // 0 = never consented; any value below ConsentGate.currentVersion gates
    ]

    /// Look an onboarding element up by its accessibility identifier,
    /// whatever element type SwiftUI happens to expose it as (button,
    /// switch, static text, picker). The flow's identifiers are the
    /// contract between the UI tests and `OnboardingFlow` — see the
    /// `onboarding.*` strings below.
    @MainActor
    private func onboardingElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        element(app, identifier)
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

    /// AUD-35: consent is recorded at "Got it", one screen before the flow
    /// ends. An app closed on Your path reopens there, not on Meet Merc.
    @MainActor
    func testInterruptedFirstRunResumesOnYourPath() {
        let app = launchApp(extraArgs: [
            "-hasSeenOnboarding", "NO",
            "-consentVersion", "1",   // ConsentGate.currentVersion: agreed at "Got it"
        ])

        XCTAssertTrue(
            onboardingElement(app, "onboarding.startLesson1").waitForExistence(timeout: Self.firstScreenTimeout),
            "An interrupted first run with consent on record should reopen on Your path"
        )
        XCTAssertFalse(
            onboardingElement(app, "onboarding.continue").exists,
            "An interrupted first run must not replay Meet Merc"
        )
        XCTAssertFalse(
            onboardingElement(app, "onboarding.agePicker").exists,
            "An interrupted first run must not ask for the age again"
        )
    }

    /// AUD-50: the consent switch is pinned above "Agree and continue" on a
    /// short screen, and its sentence is part of the tap target: a student
    /// who taps what they just read turns it on (a bare SwiftUI Toggle only
    /// flips on the switch). The switch itself carries the sentence for
    /// VoiceOver.
    @MainActor
    func testConsentSentenceTogglesTheSwitch() {
        let app = launchApp(extraArgs: Self.freshInstallArgs + ["-GateStep", "disclosure"])
        let toggle = onboardingElement(app, "onboarding.consentToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: Self.firstScreenTimeout), "Consent switch missing")
        XCTAssertTrue(toggle.isHittable, "The consent switch should be on screen without scrolling")
        XCTAssertTrue(toggle.label.hasPrefix("I understand my messages"), "The switch should carry the sentence: '\(toggle.label)'")
        XCTAssertEqual(toggle.value as? String, "0")

        // The sentence sits to the left of the switch, in the same row.
        let sentence = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: toggle.frame.minX - 120, dy: toggle.frame.midY))
        sentence.tap()
        XCTAssertTrue(waitForValue(toggle, "1"), "Tapping the sentence didn't turn the switch on")
        sentence.tap()
        XCTAssertTrue(waitForValue(toggle, "0"), "Tapping the sentence again didn't turn it off")
        toggle.tap()
        XCTAssertTrue(waitForValue(toggle, "1"), "Tapping the switch didn't turn it on")
        XCTAssertTrue(onboardingElement(app, "onboarding.agree").isEnabled, "Agree stays disabled with the switch on")
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                timeout: timeout) == .completed
    }

    @MainActor
    func testUnderThirteenIsBlocked() {
        let app = launchApp(extraArgs: Self.freshInstallArgs)

        tapOnboarding(app, "onboarding.continue", timeout: Self.firstScreenTimeout)

        // The wheel opens on a placeholder, so Continue waits for a pick.
        XCTAssertTrue(
            onboardingElement(app, "onboarding.agePicker").waitForExistence(timeout: Self.lookupTimeout),
            "Age picker (onboarding.agePicker) did not appear"
        )
        XCTAssertFalse(
            onboardingElement(app, "onboarding.ageContinue").isEnabled,
            "Continue must stay disabled until an age is picked"
        )
        chooseAge(app, "12 or younger")
        assertUnderThirteenDeadEnd(app)

        // Relaunching doesn't undo it: the device remembers the block.
        app.terminate()
        let relaunched = launchApp(extraArgs: Self.freshInstallArgs + [Self.keepAgeBlockArgument])
        XCTAssertTrue(
            onboardingElement(relaunched, "onboarding.underThirteen").waitForExistence(timeout: Self.firstScreenTimeout),
            "A relaunch after an under-13 answer must open on the under-13 screen"
        )
        XCTAssertFalse(
            onboardingElement(relaunched, "onboarding.continue").exists,
            "A relaunch after an under-13 answer must not offer Meet Merc again"
        )
        assertUnderThirteenDeadEnd(relaunched)
    }

    /// Lets a relaunch keep the age block the previous launch recorded
    /// (`-UITests` otherwise wipes it at every launch).
    static let keepAgeBlockArgument = "-KeepAgeBlock"

    /// The under-13 screen is showing and nothing on it moves the flow:
    /// no forward control, and no way back to the age picker.
    @MainActor
    private func assertUnderThirteenDeadEnd(_ app: XCUIApplication) {
        XCTAssertTrue(
            onboardingElement(app, "onboarding.underThirteen").waitForExistence(timeout: Self.lookupTimeout),
            "Choosing '12 or younger' must land on the under-13 screen (onboarding.underThirteen missing)"
        )
        for identifier in ["onboarding.ageContinue", "onboarding.agePicker", "onboarding.ageRetry",
                           "onboarding.consentToggle", "onboarding.agree"] {
            XCTAssertFalse(
                onboardingElement(app, identifier).waitForExistence(timeout: 1),
                "Under-13 screen must be a dead end — '\(identifier)' is still reachable"
            )
        }
        XCTAssertEqual(
            app.buttons.count, 0,
            "Under-13 screen must have no controls at all, found: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
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

    /// The largest accessibility text size (AX5).
    static let largestTextSize = "UICTContentSizeCategoryAccessibilityXXXL"

    /// Swipe the screen up until `element` can be tapped. The gate's CTAs
    /// are pinned and need none; content controls (the consent switch) sit
    /// in a scroll view that, at AX5, is taller than the screen. With
    /// `above`, the element must also have cleared the top of that pinned
    /// control (`isHittable` alone can be true for a point under it).
    ///
    /// It drags from 45% to 12% of the screen's height and holds, rather
    /// than `app.swipeUp()`: on an iPhone SE at AX5 the pinned CTAs fill the
    /// lower 40% of the screen, and sixteen `swipeUp`s in a row left the
    /// disclosure unscrolled (a finger drag from the same point scrolls it).
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication,
                                     above pinned: XCUIElement? = nil, maxSwipes: Int = 24) -> Bool {
        func reachable() -> Bool {
            guard element.exists, element.isHittable else { return false }
            guard let pinned, pinned.exists else { return true }
            return element.frame.maxY <= pinned.frame.minY
        }
        var swipes = 0
        while !reachable() && swipes < maxSwipes {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            swipes += 1
        }
        return reachable()
    }

    /// AUD-12: at the largest text size a new student must be able to walk
    /// the whole first-run gate. Every step's CTA is pinned on screen
    /// (hittable without scrolling), and the age wheel and consent switch
    /// stay reachable.
    @MainActor
    func testFirstRunGateCompletesAtLargestTextSize() {
        let app = launchApp(contentSize: Self.largestTextSize, extraArgs: Self.freshInstallArgs)

        // Meet Merc: the copy overflows the screen at AX5; Continue is pinned.
        let meetContinue = onboardingElement(app, "onboarding.continue")
        XCTAssertTrue(meetContinue.waitForExistence(timeout: Self.firstScreenTimeout),
                      "Meet Merc did not appear")
        // A canary that the text size really took effect: at standard size
        // the button is about 49 pt tall; at AX5 its label alone is ~60 pt.
        XCTAssertGreaterThan(meetContinue.frame.height, 70,
                             "Continue is \(meetContinue.frame.height) pt tall: the AX5 text size didn't apply")
        XCTAssertTrue(meetContinue.isHittable, "Meet Merc's Continue is off-screen at AX5")
        meetContinue.tap()

        // Age: the wheel keeps a usable height; Continue is pinned.
        let picker = onboardingElement(app, "onboarding.agePicker")
        XCTAssertTrue(picker.waitForExistence(timeout: Self.lookupTimeout), "Age picker missing at AX5")
        let ageContinue = onboardingElement(app, "onboarding.ageContinue")
        XCTAssertTrue(scrollUntilHittable(app.pickerWheels.element, in: app, above: ageContinue),
                      "Age wheel unreachable at AX5")
        XCTAssertGreaterThanOrEqual(app.pickerWheels.element.frame.height, 100,
                                    "Age wheel squeezed to \(app.pickerWheels.element.frame.height) pt at AX5")
        app.pickerWheels.element.adjust(toPickerWheelValue: "15")
        XCTAssertTrue(ageContinue.isHittable, "The age step's Continue is off-screen at AX5")
        ageContinue.tap()

        // Disclosure: the switch scrolls into reach; Agree is pinned. At AX5
        // the toggle's label is ~660 pt tall and the switch itself sits at
        // its foot, so the test scrolls to and taps the switch, as a
        // student would.
        let toggle = onboardingElement(app, "onboarding.consentToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: Self.lookupTimeout), "Consent switch missing at AX5")
        let agree = onboardingElement(app, "onboarding.agree")
        let innerSwitch = toggle.descendants(matching: .switch).firstMatch
        let switchControl = innerSwitch.exists ? innerSwitch : toggle
        XCTAssertTrue(scrollUntilHittable(switchControl, in: app, above: agree), "Consent switch unreachable at AX5")
        switchControl.tap()
        XCTAssertEqual(toggle.value as? String, "1", "Tapping the consent switch at AX5 didn't turn it on")
        XCTAssertTrue(agree.isHittable, "'Agree and continue' is off-screen at AX5")
        agree.tap()

        // Limits, then Your path.
        let limitsAck = onboardingElement(app, "onboarding.limitsAck")
        XCTAssertTrue(limitsAck.waitForExistence(timeout: Self.lookupTimeout), "Limits step missing at AX5")
        XCTAssertTrue(limitsAck.isHittable, "'Got it' is off-screen at AX5")
        limitsAck.tap()

        let startLesson = onboardingElement(app, "onboarding.startLesson1")
        XCTAssertTrue(startLesson.waitForExistence(timeout: Self.lookupTimeout), "Your path missing at AX5")
        XCTAssertTrue(startLesson.isHittable, "'Start Lesson 1' is off-screen at AX5")
        startLesson.tap()

        XCTAssertTrue(
            app.buttons["Continue. Start the lesson."].waitForExistence(timeout: Self.firstScreenTimeout),
            "At AX5 the gate did not land in the Lesson 1 intro"
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

        // The modes are one menu at this size, and "Debate" is in it.
        let modeMenu = element(app, Self.modeMenuIdentifier)
        XCTAssertTrue(modeMenu.exists, "At XXL the mode pills should be one menu (\(Self.modeMenuIdentifier))")
        XCTAssertTrue(modeMenu.isHittable, "The mode menu is off-screen at XXL accessibility size")
        XCTAssertTrue(modeMenu.label.hasPrefix("Mode: Socratic"),
                      "The mode menu should name the current mode, got '\(modeMenu.label)'")
        modeMenu.tap()
        XCTAssertTrue(
            app.buttons["Debate"].waitForExistence(timeout: Self.lookupTimeout),
            "'Debate' is missing from the mode menu at XXL accessibility size"
        )
    }

    /// AUD-48: at an accessibility size, picking a mode from the menu runs
    /// the same first-time flow as tapping its pill.
    @MainActor
    func testModeMenuShowsDescriptionSheetAtAccessibilityTextSize() {
        let app = launchApp(
            contentSize: "UICTContentSizeCategoryAccessibilityXXL",
            extraArgs: [
                "-seenModeDescription.socratic", "NO",
                "-seenModeDescription.debate", "NO",
                "-seenModeDescription.discussion", "NO",
            ],
            bypassModeDescriptions: false
        )
        waitForBootComplete(app)

        let modeMenu = element(app, Self.modeMenuIdentifier)
        XCTAssertTrue(modeMenu.waitForExistence(timeout: Self.lookupTimeout), "Mode menu missing at XXL")
        modeMenu.tap()
        let debate = app.buttons["Debate"]
        XCTAssertTrue(debate.waitForExistence(timeout: Self.lookupTimeout), "'Debate' missing from the mode menu")
        debate.tap()
        XCTAssertTrue(
            app.buttons["Got it"].waitForExistence(timeout: Self.lookupTimeout),
            "Picking Debate from the menu should present its description sheet"
        )
    }
}
