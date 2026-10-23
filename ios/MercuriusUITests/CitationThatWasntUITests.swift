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

        // CI's simulator answers a query in about a second at this size, so
        // each wait gives what a tap brought 10 s to arrive.
        let wait: TimeInterval = 10
        let slots = ["First author", "Year", "Title", "Journal", "Volume and pages"]
        for (number, slot) in slots.enumerated() {
            let first = candidate(app, slot, 1)
            XCTAssertTrue(first.waitForExistence(timeout: wait), "no candidates for \(slot)")
            tap(first, in: app)
            let last = number == slots.count - 1
            let label = last ? "See the finished reference" : "Next piece"
            let next = app.buttons[label].firstMatch
            guard next.waitForExistence(timeout: wait) else {
                keep(app, "ax5-\(number + 1)-no-button")
                XCTFail("after the guess at \(slot), no \"\(label)\" button (screenshot ax5-\(number + 1)-no-button)")
                return
            }
            expectInView(next, in: app, "after the guess at \(slot), its button")
            keep(app, "ax5-\(number + 1)-drawn")
            next.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if !last {
                let heading = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(number + 2) of 5, \(slots[number + 1])."))
                    .firstMatch
                XCTAssertTrue(heading.waitForExistence(timeout: wait))
                expectInView(heading, in: app, "after Next piece, step \(number + 2)'s heading")
                if number == 0 { keep(app, "ax5-2-next-step") }
            }
        }
        let finished = app.descendants(matching: .any)["The five pieces it drew"]
        XCTAssertTrue(finished.waitForExistence(timeout: wait))
        expectInView(finished, in: app, "after See the finished reference, its heading")
        keep(app, "ax5-6-finished")

        let journal = app.buttons["The journal"].firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout: wait))
        tap(journal, in: app)
        let showMe = app.buttons["Show me"].firstMatch
        XCTAssertTrue(showMe.waitForExistence(timeout: wait))
        expectInView(showMe, in: app, "after the lock, Show me")
        keep(app, "ax5-7-locked")
        showMe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "You guessed The journal.")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: wait), "the reveal didn't come")
        XCTAssertTrue(reveal.label.contains("as made up as the author"), reveal.label)
        expectTopInView(reveal, in: app, "after Show me, the reveal")
        keep(app, "ax5-8-revealed")

        let again = app.buttons["Write it again"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: wait))
        tap(again, in: app)
        let second = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The same question, asked again")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: wait), "the second reference wasn't written")
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
    /// rows off screen: scroll as a student would until enough of `element`
    /// shows in the list, then touch the middle of the part that shows.
    ///
    /// Not the element's centre: at AX5 on an iPhone 16 (852 pt) the
    /// title's first candidate is 448 pt tall. On CI (iOS 18) it was left
    /// at y 450 to 898 with the list ending at about 671, so its centre
    /// (674) was on the "Jump to latest" strip: the list jumped to its end,
    /// no guess was made, and "Next piece" never came.
    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        var shown = CGRect.null
        for _ in 0..<40 {
            // A little inside the list, clear of its edges.
            let list = readingArea(app).insetBy(dx: 0, dy: 8)
            let frame = element.frame
            shown = frame.intersection(list)
            if !shown.isNull, shown.height >= min(frame.height, 88) { break }
            let below = frame.midY > list.midY
            // How far the element sits outside the list.
            let gap = below ? frame.minY - list.maxY : list.minY - frame.maxY
            if gap > list.height * 1.5 {
                // Far off: a swipe (about half a screen and more) can't
                // carry it past the list.
                below ? app.swipeUp(velocity: .slow) : app.swipeDown(velocity: .slow)
            } else {
                drag(app, in: list, by: list.height * 0.4, up: below)
            }
        }
        XCTAssertFalse(shown.isNull || shown.height < 1, "\(element) never came into the lesson's list: \(element.frame)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: shown.midX, dy: shown.midY)).tap()
    }

    /// The lesson's list on screen, between its header and the "Jump to
    /// latest" strip or the composer (it shrinks while the strip shows).
    @MainActor
    private func readingArea(_ app: XCUIApplication) -> CGRect {
        let list = app.scrollViews.firstMatch
        let frame = list.exists ? list.frame : .null
        return frame.isNull || frame.height < 100 ? app.windows.firstMatch.frame : frame
    }

    /// Moves the list by `distance` points, held at the end so it doesn't
    /// coast, from a point inside the list (a drag that starts on the "Jump
    /// to latest" strip doesn't scroll).
    @MainActor
    private func drag(_ app: XCUIApplication, in list: CGRect, by distance: CGFloat, up: Bool) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let low = origin.withOffset(CGVector(dx: list.midX, dy: list.midY + distance / 2))
        let high = origin.withOffset(CGVector(dx: list.midX, dy: list.midY - distance / 2))
        (up ? low : high).press(forDuration: 0.05, thenDragTo: up ? high : low, withVelocity: .slow,
                                thenHoldForDuration: 0.2)
    }
}
