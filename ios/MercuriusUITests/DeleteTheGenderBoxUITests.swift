import XCTest

/// Delete the Gender Box (U3L1) on the iPhone, end to end in its lesson
/// (`-Interactive delete-the-gender-box`: the u3_l1 stub replies stream
/// through the real replay and placement, and the card shows while it ships
/// dark): the toggle waits for a guess, a guess about the gap locks,
/// deleting the gender box reveals that it grew (42 vs 77, 35 points apart)
/// beside the guess, and the lesson's check after the card still answers
/// with one tap ("I picked A) …").
final class DeleteTheGenderBoxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-Interactive", "delete-the-gender-box",
        ]
        app.launch()
        return app
    }

    /// Scrolls the lesson as a student would until `element` sits in the
    /// middle of the screen, above the composer.
    @MainActor
    private func bringOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while swipes < 16 {
            let frame = element.frame
            if frame.maxY > window.height * 0.72 {
                app.swipeUp(velocity: .slow)
            } else if frame.minY < window.height * 0.12 {
                app.swipeDown(velocity: .slow)
            } else {
                return
            }
            swipes += 1
        }
    }

    @MainActor
    func testGuessDeleteRevealThenTheCheckStillAnswers() {
        let app = launch()
        let title = app.descendants(matching: .any)["Interactive: Delete the Gender Box"]
        XCTAssertTrue(title.waitForExistence(timeout: 45), "the card never arrived in u3_l1")

        // The one control waits for a guess: it says so, and a tap does nothing.
        let deleted = app.buttons["Gender box: deleted"]
        let kept = app.buttons["Gender box: kept"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 10))
        XCTAssertEqual(deleted.value as? String, "Make your guess first.")
        bringOnScreen(deleted, in: app)
        deleted.tap()
        XCTAssertFalse(deleted.isSelected, "the toggle worked before a guess")
        XCTAssertTrue(kept.isSelected)

        // `firstMatch`: XCUITest finds two buttons per shared chip whose
        // label is its title (the chip's element and its inner button).
        let shrink = app.buttons["Shrink"].firstMatch
        XCTAssertTrue(shrink.waitForExistence(timeout: 10))
        bringOnScreen(shrink, in: app)
        shrink.tap()
        let picked = NSPredicate(format: "isSelected == true")
        expectation(for: picked, evaluatedWith: shrink)
        waitForExpectations(timeout: 5)
        // A locked guess can't change: another chip's tap does nothing.
        let other = app.buttons["Grow"].firstMatch
        other.tap()
        XCTAssertFalse(other.isSelected, "a locked guess changed")
        XCTAssertTrue(shrink.isSelected)

        bringOnScreen(deleted, in: app)
        XCTAssertNotEqual(deleted.value as? String, "Make your guess first.")
        deleted.tap()
        expectation(for: picked, evaluatedWith: deleted)
        waitForExpectations(timeout: 5)

        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@",
                                  "You guessed Shrink. It grew: 42 vs 77, 35 points apart (it was 29)."))
            .firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't pair the guess with the grown gap")
        let newScore = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Score: 42 out of 100.")).firstMatch
        XCTAssertTrue(newScore.exists, "the test résumé's score didn't change to 42")

        // The lesson's check after the card: one tap still grades and sends.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option A:")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        bringOnScreen(option, in: app)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked A)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }
}
