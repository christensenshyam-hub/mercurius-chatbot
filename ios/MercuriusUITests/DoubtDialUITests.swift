import XCTest

/// The Doubt Dial (U6L4) on the iPhone, end to end in its lesson
/// (`-Interactive doubt-dial`: the stub replies stream locally, no network,
/// and the real placement puts the card after the first reply's example):
/// a guess locks, the dial turns (it is one adjustable element), "Show me"
/// pairs the guess with the result and turns the dial to the setting it
/// names, "Check first" shows checking's count,
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
        // Locked, the chip is no longer a button (`InteractiveChip.isLocked`):
        // it reads as a selected choice.
        let locked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND isSelected == true", "Doubt everything")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5), "the guess didn't lock")

        // The one control: two stops toward doubt, touched as a student
        // would (XCUITest on iOS can't send an adjustable element its
        // VoiceOver increment).
        let dial = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Doubt dial")).firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        bringOnScreen(dial, in: app)
        turn(dial, to: 1, named: "Believe most", in: app)
        turn(dial, to: 2, named: "In the middle", in: app)
        keep("doubt-dial-turned", in: app)
        // The strip under the dial names the setting's mistakes (one element
        // at the regular sizes; a line of words at the accessibility sizes).
        let strip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Mistakes at this setting: School board, Water tower "
                                  + "(fakes shared); Seal, Bridge (real stories waved away).")).firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "the strip doesn't name In the middle's four mistakes")
        bringOnScreen(strip, in: app)
        keep("doubt-dial-strip", in: app)
        let value = dial.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("In the middle."), "the dial says \(value)")
        XCTAssertTrue(value.contains("2 fakes") && value.contains("2 real stories"), "the dial says \(value)")

        // Show me: the guess beside what happened.
        let showMe = button("Show me", in: app)
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        bringOnScreen(showMe, in: app)
        showMe.tap()
        let reveal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@",
                                  "You guessed Doubt everything. Doubt everything never shared a fake")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the reveal didn't pair the guess with the result")
        // Show me turned the dial to the setting the result names, so the
        // counters beside it agree (it was on "In the middle").
        let revealed = dial.value as? String ?? ""
        XCTAssertTrue(revealed.hasPrefix("Doubt everything."), "after Show me the dial says \(revealed)")
        XCTAssertTrue(revealed.contains("0 fakes") && revealed.contains("5 real stories"),
                      "after Show me the dial says \(revealed)")
        keep("doubt-dial-revealed", in: app)
        bringOnScreen(dial, in: app)
        keep("doubt-dial-revealed-dial", in: app)

        // Check first: no fake shared, no real story waved away, 2 not sure yet.
        let check = button("Check first", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        bringOnScreen(check, in: app)
        check.tap()
        let tally = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Fakes shared: 0. Real stories waved away: 0. Not sure yet: 2.")).firstMatch
        XCTAssertTrue(tally.waitForExistence(timeout: 5), "Check first's count didn't show")
        bringOnScreen(tally, in: app)
        keep("doubt-dial-checked", in: app)

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

    /// Turns the dial to stop `index` as a student would: a touch on its
    /// stop mark, or at the accessibility sizes (where the track is two
    /// step buttons, stacked or side by side, inside the one dial element)
    /// a touch on "More doubt" where it is drawn. Checks the stop by its name.
    @MainActor
    private func turn(_ dial: XCUIElement, to index: Int, named name: String, in app: XCUIApplication) {
        func there() -> Bool { (dial.value as? String ?? "").hasPrefix("\(name).") }
        bringOnScreen(dial, in: app)
        tapStop(index, of: dial, in: app)
        var tries = 0
        while !there() && tries < 6 {
            bringOnScreen(dial, in: app)
            let frame = dial.frame
            let x = tries % 2 == 0 ? frame.minX + 60 : frame.midX + 60
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: frame.maxY - 26)).tap()
            tries += 1
        }
        XCTAssertTrue(there(), "the dial didn't reach \(name): \(dial.value as? String ?? "")")
    }

    /// A picture of the screen, kept in the result bundle for review.
    @MainActor
    private func keep(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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

    /// Scrolls the lesson's list by about `points` (negative: up), with no
    /// fling: a drag that holds still before it lets go (a swipe overshoots
    /// at the accessibility sizes, where the card is many screens tall).
    @MainActor
    private func drag(_ app: XCUIApplication, by points: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: points)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The lesson's list doesn't take the accessibility scroll action for a
    /// row below the card: scroll as a student would, until `element` is on
    /// screen above the composer (its top, for one taller than that band).
    @MainActor
    private func bringOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let top = window.height * 0.12, bottom = window.height * 0.75
        let tall = element.frame.height > (bottom - top) * 0.8
        func below() -> Bool { tall ? element.frame.minY > (top + bottom) / 2 : element.frame.maxY > bottom }
        var drags = 0
        // At AX5 the card with "Check first" open is many screens tall.
        while below() && drags < 120 {
            drag(app, by: -240)
            drags += 1
        }
        while element.frame.minY < top && drags < 150 {
            drag(app, by: 200)
            drags += 1
        }
    }
}
