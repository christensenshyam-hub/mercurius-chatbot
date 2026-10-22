import XCTest

/// The Page with a Secret (u8_l1) on the iPhone, end to end in its stubbed
/// lesson (`-Interactive page-with-a-secret`: authored stub replies that
/// say they are stubs, streamed locally, placed by the real anchor rule;
/// the card ships dark and DEBUG forces it on): step to the page, lock a
/// guess, flip the page to what the agent reads, step to the reveal, then
/// answer the lesson's check after the card by tap, as before.
final class PageWithASecretUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuessFlipRevealThenTheCheckStillAnswersByTap() {
        let app = XCUIApplication()
        // The same bypasses as MercuriusUITests.launchApp, then the card's
        // lesson.
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-Interactive", "page-with-a-secret",
        ]
        app.launch()

        let title = app.descendants(matching: .any)["Interactive: The Page with a Secret"]
        XCTAssertTrue(title.waitForExistence(timeout: 45), "the card never arrived in u8_l1")

        // Steps 1 → 3: the page opens, and the guess is asked.
        next(app)
        next(app)
        let guess = app.buttons["It sticks to your task"]
        XCTAssertTrue(guess.waitForExistence(timeout: 10), "the prediction never appeared at the page")
        let flip = app.buttons["What the agent reads"]
        XCTAssertTrue(flip.exists)
        XCTAssertFalse(flip.isEnabled, "the toggle works before a guess is locked")
        bringOnScreen(guess, in: app)
        guess.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: guess)
        waitForExpectations(timeout: 5)

        // The one control, now on: the page as the agent reads it.
        XCTAssertTrue(flip.isEnabled)
        bringOnScreen(flip, in: app)
        flip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: flip)
        waitForExpectations(timeout: 5)
        let hidden = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Hidden on the page, white text on white")).firstMatch
        XCTAssertTrue(hidden.exists, "the agent's view doesn't say the hidden line")

        // Steps 4 → 6, then the reveal beside the guess.
        next(app)
        next(app)
        next(app)
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You guessed It sticks to your task.")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "no reveal at step 6")
        // The guess beside what happened, on screen as the student scrolls.
        bringOnScreen(reveal, in: app)
        XCTAssertFalse(app.buttons["Next"].isEnabled, "Next is still on at the run's last step")

        // The check after the card: one tap grades and sends, as before.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option A")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        bringOnScreen(option, in: app)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked A)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }

    /// Taps the card's Next, scrolling it on screen first (the card grows
    /// with each step, pushing Next down).
    @MainActor
    private func next(_ app: XCUIApplication) {
        let button = app.buttons["Next"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(button.isEnabled, "Next is off")
        bringOnScreen(button, in: app)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The lesson's list doesn't take the accessibility scroll action for a
    /// row: scroll as a student would, until `element` is on screen above
    /// the composer.
    @MainActor
    private func bringOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while element.frame.maxY > window.height * 0.75 && swipes < 14 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        while element.frame.minY < window.height * 0.12 && swipes < 20 {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
        XCTAssertLessThan(element.frame.maxY, window.height * 0.75, "\(element) never came on screen")
    }
}
