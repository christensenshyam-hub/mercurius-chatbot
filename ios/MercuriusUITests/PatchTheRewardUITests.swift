import XCTest

/// Patch the Reward (U5L1) on the iPhone, end to end in its stubbed lesson
/// (`-Interactive patch-the-reward`: stub replies through the real
/// placement, no network). The card ships dark; DEBUG shows it anyway.
///
/// - The whole card by tap: the 2016-style rule plays, each patch takes a
///   guess and runs, the reveal pairs the guesses with what happened, and
///   the lesson's check after the card still answers by tap.
/// - A run plays on the track and "Skip to the result" ends it.
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

    /// Swipes the lesson up, as a student would, until `element` sits in the
    /// top three quarters of the window (the composer covers the bottom).
    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared", file: file, line: line)
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while (!element.isHittable || element.frame.maxY > window.height * 0.75) && swipes < 14 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never came on screen", file: file, line: line)
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

        tap(app.buttons["Play it"], in: app)
        XCTAssertTrue(element(app, labelContains: "It hit 26 targets").waitForExistence(timeout: 5))

        let patches: [(chip: String, guess: String, result: String)] = [
            ("Rule A: plus 100 per finish-line crossing.", "Yes", "It crossed the line 30 times"),
            ("Rule B: plus 1 per metre moved.", "No", "It moved 1,114 metres"),
            ("Rule C: plus 100 per full lap through gates 1, 2 and 3 in order.", "Yes", "finished 3 laps"),
        ]
        for patch in patches {
            let chip = app.buttons[patch.chip]
            tap(chip, in: app)
            expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: chip)
            waitForExpectations(timeout: 5)
            tap(app.buttons[patch.guess], in: app)
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

    @MainActor
    func testARunPlaysOnTheTrackAndSkipEndsIt() {
        let app = launch([])
        let title = app.descendants(matching: .any)["Interactive: Patch the Reward"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u5_l1")
        tap(app.buttons["Play it"], in: app)
        let skip = app.buttons["Skip to the result"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "the run didn't play")
        skip.tap()
        XCTAssertTrue(element(app, labelContains: "It hit 26 targets").waitForExistence(timeout: 5))
        XCTAssertFalse(skip.exists)
    }
}
