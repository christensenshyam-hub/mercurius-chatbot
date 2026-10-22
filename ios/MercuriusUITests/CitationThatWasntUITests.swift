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

        let title = app.descendants(matching: .any)["Interactive: The Citation That Wasn\u{2019}t"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u1_l3")

        let selected = NSPredicate(format: "isSelected == true")

        // Guess the next piece: the first candidate at each slot. (On the
        // iPhone a card's button is a Button inside its accessibility
        // element, so XCUI sees two with one label: `firstMatch`.)
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
                    .matching(NSPredicate(format: "label CONTAINS %@", "not always the likeliest")).firstMatch
                XCTAssertTrue(caption.waitForExistence(timeout: 5), "the second bar wasn't called out")
            } else {
                expectation(for: selected, evaluatedWith: first)
                waitForExpectations(timeout: 5)
            }
            let next = app.buttons[number == slots.count - 1 ? "See the finished reference" : "Next piece"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            tap(next, in: app)
        }

        // The step question: locks once. Locked, the chips are no longer
        // buttons (they draw as themselves, readable): the pick is a
        // selected element.
        let noStep = app.buttons["No step did"].firstMatch
        XCTAssertTrue(noStep.waitForExistence(timeout: 10), "the step question never came")
        tap(noStep, in: app)
        let locked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND isSelected == true", "No step did")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5), "the guess didn't lock")
        XCTAssertFalse(app.buttons["The journal"].exists, "a locked chip is still a button")

        let showMe = app.buttons["Show me"].firstMatch
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        tap(showMe, in: app)
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "None of these steps chose to invent it")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't come")
        XCTAssertTrue(reveal.label.hasPrefix("You guessed No step did."), reveal.label)

        let again = app.buttons["Write it again"].firstMatch
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

    /// At AX5 a draw's result, the next step and the reveal can each be a
    /// screen away from the button pressed. In a release build (no DEBUG
    /// `-CitationScroll`), each tap keeps what it changed in view: this
    /// walks the card by tapping and checks, before any swipe, that the
    /// result, the next step's heading, the five drawn pieces, "Show me",
    /// the reveal and the second reference are on screen. Each moment is
    /// kept as a screenshot attachment.
    @MainActor
    func testAtAccessibilitySizesEachTapKeepsWhatItChangedInView() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-Interactive", "citation-that-wasnt"
        ]
        app.launch()

        let title = app.descendants(matching: .any)["Interactive: The Citation That Wasn\u{2019}t"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the card never arrived in u1_l3")

        let slots = ["First author", "Year", "Title", "Journal", "Volume and pages"]
        for (number, slot) in slots.enumerated() {
            let first = candidate(app, slot, 1)
            XCTAssertTrue(first.waitForExistence(timeout: 10), "no candidates for \(slot)")
            tap(first, in: app)
            let last = number == slots.count - 1
            let next = app.buttons[last ? "See the finished reference" : "Next piece"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            expectInView(next, in: app, "after the guess at \(slot), its button")
            keep(app, "ax5-\(number + 1)-drawn")
            next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if !last {
                let heading = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(number + 2) of 5, \(slots[number + 1])."))
                    .firstMatch
                XCTAssertTrue(heading.waitForExistence(timeout: 5))
                expectInView(heading, in: app, "after Next piece, step \(number + 2)'s heading")
                if number == 0 { keep(app, "ax5-2-next-step") }
            }
        }
        let finished = app.descendants(matching: .any)["The five pieces it drew"]
        XCTAssertTrue(finished.waitForExistence(timeout: 5))
        expectInView(finished, in: app, "after See the finished reference, its heading")
        keep(app, "ax5-6-finished")

        let journal = app.buttons["The journal"].firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        tap(journal, in: app)
        let showMe = app.buttons["Show me"].firstMatch
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        expectInView(showMe, in: app, "after the lock, Show me")
        keep(app, "ax5-7-locked")
        showMe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You guessed The journal.")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't come")
        XCTAssertTrue(reveal.label.contains("as made up as the author"), reveal.label)
        expectTopInView(reveal, in: app, "after Show me, the reveal")
        keep(app, "ax5-8-revealed")

        let again = app.buttons["Write it again"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        tap(again, in: app)
        let second = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The same question, asked again")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8), "the second reference wasn't written")
        expectTopInView(second, in: app, "after Write it again, the second reference")
        sleep(2)
        keep(app, "ax5-9-rewritten")
    }

    /// `element` is wholly on screen, before any swipe (a tap's scroll has
    /// had a moment to settle).
    @MainActor
    private func expectInView(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        sleep(1)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertTrue(frame.minY >= window.minY - 1 && frame.maxY <= window.maxY + 1 && element.isHittable,
                      "\(what) is off screen: \(frame) in \(window)")
    }

    /// `element`'s top is on screen (it may be taller than the screen).
    @MainActor
    private func expectTopInView(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        sleep(1)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertTrue(frame.minY >= window.minY - 1 && frame.minY <= window.maxY * 0.6,
                      "\(what)'s top is off screen: \(frame) in \(window)")
    }

    /// A screenshot of this moment, kept with the test's results.
    @MainActor
    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A slot's candidate by its place ("1 of 3"): a button until its slot
    /// is drawn, then the slot's choice, the pick selected.
    @MainActor
    private func candidate(_ app: XCUIApplication, _ slot: String, _ place: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
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
