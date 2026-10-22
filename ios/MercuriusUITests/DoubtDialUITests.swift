import XCTest

/// The Doubt Dial (U6L4) on the iPhone, end to end in its lesson
/// (`-Interactive doubt-dial`: the stub replies stream locally, no network,
/// and the real placement puts the card after the first reply's example):
/// a guess locks, the dial turns (it is one adjustable element), "Show me"
/// pairs the guess with the result, "Check first" shows checking's count,
/// and the lesson's check after the card still answers with one tap.
final class DoubtDialUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuessDialRevealCheckFirstThenTheLessonCheckStillAnswers() {
        let app = XCUIApplication()
        // The same bypasses as MercuriusUITests.launchApp, then the card's
        // lesson.
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-Interactive", "doubt-dial",
        ]
        app.launch()

        let title = app.descendants(matching: .any)["Interactive: The Doubt Dial"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the Doubt Dial never arrived in u6_l4")

        // The guess: one tap locks it. (A chip reaches XCUITest as a button
        // inside a button with the same label, so every query takes its
        // first match.)
        let guess = button("Doubt everything", in: app)
        XCTAssertTrue(guess.waitForExistence(timeout: 10))
        bringOnScreen(guess, in: app)
        guess.tap()
        let locked = app.buttons
            .matching(NSPredicate(format: "label == %@ AND isSelected == true", "Doubt everything")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5), "the guess didn't lock")

        // The one control: two stops toward doubt, touched as a student
        // would (XCUITest on iOS can't send an adjustable element its
        // VoiceOver increment).
        let dial = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Doubt dial")).firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        bringOnScreen(dial, in: app)
        tapStop(1, of: dial, in: app)
        tapStop(2, of: dial, in: app)
        let value = dial.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("Unsure."), "the dial says \(value)")
        XCTAssertTrue(value.contains("2 fakes") && value.contains("2 real stories"), "the dial says \(value)")

        // Show me: the guess beside what happened.
        let showMe = button("Show me", in: app)
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        bringOnScreen(showMe, in: app)
        showMe.tap()
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You guessed Doubt everything.")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't pair the guess with the result")

        // Check first: no fake shared, no real story waved away, 2 not sure yet.
        let check = button("Check first", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        bringOnScreen(check, in: app)
        check.tap()
        let tally = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Fakes shared: 0. Real stories waved away: 0. Not sure yet: 2.")).firstMatch
        XCTAssertTrue(tally.waitForExistence(timeout: 5), "Check first's count didn't show")

        // The lesson's check after the card: one tap grades and sends.
        let option = button("Option A: A stand-in for Merc\u{2019}s reply", in: app)
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        bringOnScreen(option, in: app)
        XCTAssertLessThan(option.frame.maxY, app.windows.firstMatch.frame.height * 0.75,
                          "the check's option never came on screen")
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked A)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }

    /// The first button labelled `label`.
    @MainActor
    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Touches the dial's stop `index` (of 5): the stop marks are 44 pt
    /// targets spread across the dial's width, on a track 44 pt tall that
    /// sits above the ends' names (about 50 pt above the dial's bottom).
    @MainActor
    private func tapStop(_ index: Int, of dial: XCUIElement, in app: XCUIApplication) {
        let frame = dial.frame
        let x = frame.minX + 22 + CGFloat(index) * (frame.width - 44) / 4
        let y = frame.maxY - 50
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    /// The lesson's list doesn't take the accessibility scroll action for a
    /// row below the card: scroll as a student would, until `element` is on
    /// screen above the composer.
    @MainActor
    private func bringOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while element.frame.maxY > window.height * 0.75 && swipes < 16 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        swipes = 0
        while element.frame.minY < window.height * 0.12 && swipes < 8 {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
    }
}
