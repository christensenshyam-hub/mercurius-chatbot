import XCTest

/// Patch the Reward (U5L1) on the iPhone, end to end in its stubbed lesson
/// (`-Interactive patch-the-reward`: stub replies through the real
/// placement, no network). The card ships dark; DEBUG shows it anyway.
///
/// - The whole card by tap: the 2016-style rule plays, each patch takes a
///   guess and runs, the reveal pairs the guesses with what happened, and
///   the lesson's check after the card still answers by tap.
/// - A run plays on the track and "Skip to the result" ends it.
/// - A run started from a chip far below the track plays in view, and the
///   reveal comes into view when the last run ends.
/// - At AX5 every line stays inside the window.
///
/// The shared controls show up twice in the UI test tree (a button inside
/// a button with the same label; VoiceOver reads one), so every button
/// query takes its `firstMatch`.
final class PatchTheRewardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-Interactive", "patch-the-reward",
        ] + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls the lesson, as a student would, until `element` sits between
    /// the lesson's header and the composer (the top 15% and the bottom
    /// quarter of the window). By its frame, not `isHittable`: the lesson's
    /// list reports a row's controls as not hittable even on screen
    /// (LessonInteractiveUITests scrolls the same way).
    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared", file: file, line: line)
        let window = app.windows.firstMatch.frame
        let top = window.height * 0.15, bottom = window.height * 0.75
        for _ in 0..<24 {
            let frame = element.frame
            if frame.maxY > bottom {
                drag(app, up: true)
            } else if frame.minY < top {
                drag(app, up: false)
            } else {
                break
            }
        }
        let frame = element.frame
        XCTAssertTrue(frame.minY >= top && frame.maxY <= bottom, "\(element) never came on screen (\(frame))",
                      file: file, line: line)
    }

    /// Moves the list by `span` of the window (a quarter by default), held
    /// at the end so it doesn't coast (a swipe can fling a row past the
    /// window).
    @MainActor
    private func drag(_ app: XCUIApplication, up: Bool, span: CGFloat = 0.25) {
        let window = app.windows.firstMatch
        let low = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.475 + span / 2))
        let high = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.475 - span / 2))
        (up ? low : high).press(forDuration: 0.05, thenDragTo: up ? high : low, withVelocity: .slow,
                                thenHoldForDuration: 0.2)
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        bringIntoView(element, in: app, file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testEveryPatchTakesAGuessThenTheRevealAndTheCheckStillAnswers() {
        // Reduce Motion: each run's still and result show at once.
        let app = launch(["-InteractiveReduceMotion", "YES"])
        let title = app.descendants(matching: .any)["Interactive: Patch the Reward"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u5_l1")

        tap(app.buttons["Play it"].firstMatch, in: app)
        XCTAssertTrue(element(app, labelContains: "It hit 26 targets").waitForExistence(timeout: 5))

        let patches: [(chip: String, guess: String, result: String)] = [
            ("Rule A: plus 100 per finish-line crossing.", "Yes", "It crossed the line 30 times"),
            ("Rule B: plus 1 per metre moved.", "No", "It moved 1,114 metres"),
            ("Rule C: plus 100 per full lap through gates 1, 2 and 3 in order.", "Yes", "finished 3 laps"),
        ]
        for patch in patches {
            let chip = app.buttons[patch.chip].firstMatch
            tap(chip, in: app)
            expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: chip)
            waitForExpectations(timeout: 5)
            tap(app.buttons[patch.guess].firstMatch, in: app)
            XCTAssertTrue(element(app, labelContains: patch.result).waitForExistence(timeout: 5),
                          "no result for \(patch.chip)")
        }
        let reveal = element(app, labelContains: "It finished for 1 of them: rule C.")
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal never showed")
        XCTAssertTrue(reveal.label.contains("You guessed It would finish for 2 of the 3 rules."), reveal.label)

        // The check after the card: one tap still grades and sends.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option A: A stand-in")).firstMatch
        tap(option, in: app)
        let sent = element(app, labelContains: "I picked A)")
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }

    /// The largest text size (AX5), every state on at once (revealed): a
    /// student scrolling the card from its title to its last rule (the
    /// reveal sits under the last run's result, the rules last) never meets
    /// a word outside the window's width (nothing scrolls sideways, nothing
    /// is cut off at the side). Set TEST_RUNNER_PATCH_SHOTS_DIR to keep a
    /// screenshot of each screen (for review; nothing is compared).
    @MainActor
    func testAtTheLargestTextSizeEveryLineStaysInsideTheWindow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-InteractiveGallery", "patch-the-reward",
            "-InteractiveState", "revealed",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let title = app.descendants(matching: .any)["Interactive: Patch the Reward"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the card never showed")
        let window = app.windows.firstMatch.frame
        // Rule C's chip, the card's last control ("… Tried: 3 laps.").
        let last = element(app, labelContains: "Tried: 3 laps")
        let shots = ProcessInfo.processInfo.environment["PATCH_SHOTS_DIR"]
        var checked = Set<String>()
        // One snapshot of the tree per screen (querying each text would
        // take minutes at this size).
        func texts(in node: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            (node.elementType == .staticText ? [node] : []) + node.children.flatMap { texts(in: $0) }
        }
        for screen in 0..<40 {
            for text in try texts(in: app.snapshot()) where !text.label.isEmpty {
                let frame = text.frame
                guard frame.height > 0, frame.maxY > window.minY, frame.minY < window.maxY else { continue }
                checked.insert(text.label)
                XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\"\(text.label)\" leaves the window")
                XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\"\(text.label)\" leaves the window")
            }
            if let shots {
                let url = URL(fileURLWithPath: shots).appendingPathComponent(String(format: "ax5-%02d.png", screen))
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            }
            if last.exists && last.frame.minY >= window.minY && last.frame.maxY <= window.maxY { break }
            drag(app, up: true, span: 0.6)
        }
        XCTAssertTrue(last.exists && last.frame.maxY <= window.maxY, "never scrolled to the card's last rule")
        // The walk saw the card's words, not just its title.
        XCTAssertTrue(checked.contains { $0.hasPrefix("You\u{2019}re training a boat") }, "\(checked)")
        XCTAssertTrue(checked.contains { $0.hasPrefix("Nothing was broken") }, "\(checked)")
        XCTAssertTrue(checked.contains { $0.hasPrefix("Patch the rule so the boat finishes") }, "\(checked)")
    }

    /// The chips sit far below the track: a run started from one plays in
    /// view (the lesson brings the track up as it starts), with the panel's
    /// Skip under it, and the reveal comes into view when the last run ends.
    @MainActor
    func testARunStartedBelowTheTrackPlaysInViewAndTheRevealFollows() {
        let app = launch(["-InteractiveState", "explored"])
        let title = app.descendants(matching: .any)["Interactive: Patch the Reward"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u5_l1")
        let window = app.windows.firstMatch.frame
        func onScreen(_ element: XCUIElement) -> Bool {
            let frame = element.frame
            return element.exists && frame.minY >= window.minY + window.height * 0.05
                && frame.maxY <= window.minY + window.height * 0.88
        }
        tap(app.buttons["Rule C: plus 100 per full lap through gates 1, 2 and 3 in order."].firstMatch, in: app)
        tap(app.buttons["Yes"].firstMatch, in: app)
        let track = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The toy track")).firstMatch
        let skip = app.buttons["Skip to the result"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "the run didn't play")
        // Give the scroll its moment, well inside the 6 s run.
        let inView = expectation(for: NSPredicate { _, _ in onScreen(track) && onScreen(skip) }, evaluatedWith: track)
        wait(for: [inView], timeout: 3)
        XCTAssertTrue(track.label.contains("The boat is running rule C."), track.label)
        skip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reveal = element(app, labelContains: "It finished for 1 of them: rule C.")
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal never showed")
        let revealInView = expectation(for: NSPredicate { _, _ in onScreen(reveal) }, evaluatedWith: reveal)
        wait(for: [revealInView], timeout: 3)
    }

    @MainActor
    func testARunPlaysOnTheTrackAndSkipEndsIt() {
        let app = launch([])
        let title = app.descendants(matching: .any)["Interactive: Patch the Reward"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u5_l1")
        tap(app.buttons["Play it"].firstMatch, in: app)
        let skip = app.buttons["Skip to the result"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "the run didn't play")
        skip.tap()
        XCTAssertTrue(element(app, labelContains: "It hit 26 targets").waitForExistence(timeout: 5))
        XCTAssertFalse(skip.exists)
    }
}
