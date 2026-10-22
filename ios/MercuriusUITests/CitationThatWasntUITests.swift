import XCTest

/// The Citation That Wasn't (u1_l3) on the iPhone, end to end in its
/// stubbed lesson (`-Interactive citation-that-wasnt`: stub replies that
/// say they are stubs, the real placement, no network; the card shows
/// while it ships dark): each slot's guess is a button that draws the
/// model's pick, the step question locks, "Show me" reveals, "Write it
/// again" writes a second reference, and the lesson's check after the card
/// still answers with one tap.
final class CitationThatWasntUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheWalkThePredictionTheRevealAndTheCheckAfter() {
        let app = XCUIApplication()
        // The same bypasses as MercuriusUITests.launchApp, then the card's
        // lesson.
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-Interactive", "citation-that-wasnt",
        ]
        app.launch()

        let title = app.descendants(matching: .any)["Interactive: The citation that wasn\u{2019}t"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u1_l3")

        let selected = NSPredicate(format: "isSelected == true")

        // Be the model: guess the first candidate at each slot.
        let slots = ["First author", "Year", "Title", "Journal", "Volume and pages"]
        for (number, slot) in slots.enumerated() {
            let first = candidate(app, slot, 1)
            XCTAssertTrue(first.waitForExistence(timeout: 10), "no candidates for \(slot)")
            tap(first, in: app)
            if slot == "Year" {
                // The model drew the second bar, 2018, not the guess.
                let drawn = candidate(app, slot, 2)
                expectation(for: selected, evaluatedWith: drawn)
                waitForExpectations(timeout: 5)
                let caption = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", "not always the top bar")).firstMatch
                XCTAssertTrue(caption.waitForExistence(timeout: 5), "the second bar wasn't called out")
            } else {
                expectation(for: selected, evaluatedWith: first)
                waitForExpectations(timeout: 5)
            }
            let next = app.buttons[number == slots.count - 1 ? "See the finished reference" : "Next piece"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            tap(next, in: app)
        }

        // The step question: locks once.
        let noStep = app.buttons["No step did"]
        XCTAssertTrue(noStep.waitForExistence(timeout: 10), "the step question never came")
        tap(noStep, in: app)
        expectation(for: selected, evaluatedWith: noStep)
        waitForExpectations(timeout: 5)

        let showMe = app.buttons["Show me"]
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        tap(showMe, in: app)
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "None of these steps chose to invent it")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't come")
        XCTAssertTrue(reveal.label.hasPrefix("You guessed No step did."), reveal.label)

        let again = app.buttons["Write it again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        tap(again, in: app)
        let second = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Ambervale, R., 2019")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8), "the second reference wasn't written")

        // The lesson's check after the card: one tap still answers it.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option A")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        tap(option, in: app)
        let sent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked A)")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the check's tap didn't send the pick")
    }

    /// A slot's candidate by its place ("1 of 3").
    @MainActor
    private func candidate(_ app: XCUIApplication, _ slot: String, _ place: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                                         "\(slot). ", "illustrative, \(place) of 3.")).firstMatch
    }

    /// The lesson's list doesn't take the accessibility scroll action for
    /// rows off screen: scroll as a student would until `element` is in the
    /// middle band of the window, then touch it there.
    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while element.frame.maxY > window.height * 0.72 && swipes < 14 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        while element.frame.minY < window.height * 0.12 && swipes < 20 {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
