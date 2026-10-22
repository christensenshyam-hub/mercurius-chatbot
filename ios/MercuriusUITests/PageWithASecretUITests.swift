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

        let title = app.descendants(matching: .any)["Interactive: The Page with a Secret"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 45), "the card never arrived in u8_l1")

        // Steps 1 → 3: the page opens, and the guess is asked.
        next(app)
        next(app)
        let guess = app.buttons["It sticks to your task"].firstMatch
        XCTAssertTrue(guess.waitForExistence(timeout: 10), "the prediction never appeared at the page")
        // Before a guess: the toggle doesn't switch, and Next holds at the
        // page. (Checked by what a tap does: the shared controls' outer
        // element doesn't carry the disabled state to XCUITest.)
        let flip = app.buttons["What the agent reads"].firstMatch
        XCTAssertTrue(flip.exists)
        bringOnScreen(flip, in: app)
        flip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(flip.isSelected, "the toggle switched before a guess was locked")
        next(app)
        XCTAssertFalse(stepHeader(4, in: app).exists, "Next left the page before a guess was locked")
        bringOnScreen(guess, in: app)
        guess.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: guess)
        waitForExpectations(timeout: 5)

        // The one control, now on: the page as the agent reads it.
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
        XCTAssertTrue(stepHeader(6, in: app).exists)

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
        let button = app.buttons["Next"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        bringOnScreen(button, in: app)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// A step's header ("Step 4: Plan" to VoiceOver), once the step is shown.
    @MainActor
    private func stepHeader(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(number): ")).firstMatch
    }

    /// Scrolls the lesson's list by about `points` (negative: up), with no
    /// fling: a drag that holds still before it lets go.
    @MainActor
    private func drag(_ app: XCUIApplication, by points: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: points)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The lesson's list doesn't take the accessibility scroll action for a
    /// row: scroll as a student would, until `element` is on screen above
    /// the composer (its top, for one taller than that band).
    @MainActor
    private func bringOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let top = window.height * 0.12, bottom = window.height * 0.75
        let tall = element.frame.height > (bottom - top) * 0.8
        func below() -> Bool { tall ? element.frame.minY > (top + bottom) / 2 : element.frame.maxY > bottom }
        var drags = 0
        while below() && drags < 30 {
            drag(app, by: -240)
            drags += 1
        }
        while element.frame.minY < top && drags < 40 {
            drag(app, by: 240)
            drags += 1
        }
        XCTAssertFalse(below(), "\(element) never came on screen")
        XCTAssertGreaterThanOrEqual(element.frame.minY, top, "\(element) went above the screen")
    }
}
