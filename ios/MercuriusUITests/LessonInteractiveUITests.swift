import XCTest

/// Lesson 1.1's interactive on the iPhone, end to end on the recorded
/// lesson (`-LessonReplay`: Merc's real replies, streamed locally, no
/// network): the card arrives in the first reply, an opening is a button
/// that picks, and the check after the card still answers with one tap, as
/// before ("I picked B) …" goes as the student's turn).
final class LessonInteractiveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheCardPicksAndTheCheckAfterItStillAnswersByTap() {
        let app = XCUIApplication()
        // The same bypasses as MercuriusUITests.launchApp, then Unit 1
        // Lesson 1 with the recorded replies.
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-LessonPreview", "-LessonSkipIntro", "-LessonReplay",
        ]
        app.launch()

        let title = app.descendants(matching: .any)["Interactive: How a model reads bank"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the interactive never arrived in Lesson 1.1")

        let money = app.buttons["Start the sentence: I got my paycheck, so"]
        XCTAssertTrue(money.waitForExistence(timeout: 10))
        money.tap()
        let picked = NSPredicate(format: "isSelected == true")
        expectation(for: picked, evaluatedWith: money)
        waitForExpectations(timeout: 5)

        // The check after the card: one tap grades and sends, as before.
        let option = app.buttons["Option B: A chunk of text converted into a number the model can process"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        // The lesson's list doesn't take the accessibility scroll action
        // for a row below the card: scroll as a student would, until the
        // option is on screen above the composer, then touch it there.
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while option.frame.maxY > window.height * 0.75 && swipes < 12 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertLessThan(option.frame.maxY, window.height * 0.75, "the check's option never came on screen")
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked B)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }
}
