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

    /// "Try it", on the card's first screen, brings step 4's openings up:
    /// on a phone they are a screen or two further down.
    @MainActor
    func testTryItBringsTheOpeningsUp() {
        let app = XCUIApplication()
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
        // The reply has finished arriving: its check is there.
        let option = app.buttons["Option B: A chunk of text converted into a number the model can process"]
        XCTAssertTrue(option.waitForExistence(timeout: 30))

        let tryIt = app.buttons["Try it"]
        XCTAssertTrue(tryIt.waitForExistence(timeout: 10))
        // The card's top on screen, as a student reaches it.
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while tryIt.frame.minY > window.height * 0.6 && swipes < 12 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertLessThan(tryIt.frame.maxY, window.height * 0.75, "Try it never came on screen")
        let money = app.buttons["Start the sentence: I got my paycheck, so"]
        XCTAssertTrue(money.exists)
        let before = money.frame.minY
        XCTAssertGreaterThan(before, window.height * 0.75, "the openings were already in reach")

        tryIt.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        var inReach = false
        for _ in 0..<25 where !inReach {
            Thread.sleep(forTimeInterval: 0.2)
            let frame = money.frame
            inReach = frame.minY > 0 && frame.maxY < window.height * 0.8
        }
        XCTAssertTrue(inReach, "Try it didn't bring the openings on screen: \(money.frame)")
        XCTAssertLessThan(money.frame.minY, before - 200, "Try it didn't bring the openings up")

        // And they pick from there.
        money.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: money)
        waitForExpectations(timeout: 5)
    }
}
