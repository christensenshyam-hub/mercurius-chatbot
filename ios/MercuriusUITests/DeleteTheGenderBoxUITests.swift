import XCTest

/// Delete the Gender Box (U3L1) on the iPhone, end to end in its lesson
/// (`-Interactive delete-the-gender-box`: the u3_l1 stub replies stream
/// through the real replay and placement, and the card shows while it ships
/// dark): the toggle waits for a guess, a guess locks, deleting the gender
/// box reveals 42 vs 77 beside the guess, and the lesson's check after the
/// card still answers with one tap ("I picked A) …").
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

        // The one control waits for a guess.
        let deleted = app.buttons["Gender box: deleted"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 10))
        XCTAssertFalse(deleted.isEnabled, "the toggle worked before a guess")

        let tie = app.buttons["They\u{2019}ll tie"]
        XCTAssertTrue(tie.waitForExistence(timeout: 10))
        bringOnScreen(tie, in: app)
        tie.tap()
        let picked = NSPredicate(format: "isSelected == true")
        expectation(for: picked, evaluatedWith: tie)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["Yes, still lower"].isEnabled, "a locked guess can't change")

        bringOnScreen(deleted, in: app)
        XCTAssertTrue(deleted.isEnabled)
        deleted.tap()
        expectation(for: picked, evaluatedWith: deleted)
        waitForExpectations(timeout: 5)

        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You guessed They\u{2019}ll tie. Still lower: 42 vs 77"))
            .firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't pair the guess with 42 vs 77")
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
