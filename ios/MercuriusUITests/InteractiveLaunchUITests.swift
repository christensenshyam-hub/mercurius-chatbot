import XCTest

/// The lesson interactives' DEBUG launch paths, end to end (the template a
/// card's own UI test starts from: docs/interactives/FRAMEWORK.md):
///
/// - `-Interactive <slug>` alone opens the card's lesson with its replay
///   (Lesson 1.1's recording, or stub replies for any other lesson), and the
///   card arrives through the real placement, even while it ships dark.
/// - `-InteractiveGallery <slug>` shows the card alone, with no lesson.
///
/// Every card's header is "Interactive: <title>" for VoiceOver, which is
/// what these find.
final class InteractiveLaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The same bypasses as MercuriusUITests.launchApp, then `extra`.
    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
        ] + extra
        app.launch()
        return app
    }

    @MainActor
    private func cardHeader(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Interactive: ")).firstMatch
    }

    @MainActor
    func testInteractiveOpensLessonOnesReplayWithItsCard() {
        let app = launch(["-Interactive", "tokenizer"])
        let title = app.descendants(matching: .any)["Interactive: How a model reads bank"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "Lesson 1.1's card never arrived")
    }

    @MainActor
    func testInteractivePlacesADarkCardInItsStubbedLesson() {
        // The Doubt Dial ships dark; its lesson (u6_l4) has no recording, so
        // the stub replies stream and the real anchor places the card.
        let app = launch(["-Interactive", "doubt-dial"])
        XCTAssertTrue(cardHeader(app).waitForExistence(timeout: 30), "the Doubt Dial never arrived in u6_l4")
    }

    @MainActor
    func testInteractiveAnswersStubChecksUntilALaterReplysCard() {
        // Two Tests, One Line sits in the second teach reply: the stub replay
        // answers the first check by itself, then the card arrives.
        let app = launch(["-Interactive", "two-tests-one-line"])
        XCTAssertTrue(cardHeader(app).waitForExistence(timeout: 45), "the card in reply 2 never arrived")
        let answered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I picked A)")).firstMatch
        XCTAssertTrue(answered.exists, "the stub check wasn't answered")
    }

    @MainActor
    func testGalleryShowsACardAlone() {
        let app = launch(["-InteractiveGallery", "tokenizer"])
        let title = app.descendants(matching: .any)["Interactive: How a model reads bank"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the gallery didn't show the card")
        // Alone: no lesson around it (no composer, no chat header).
        XCTAssertFalse(app.textViews.firstMatch.exists || app.textFields.firstMatch.exists)
    }
}
