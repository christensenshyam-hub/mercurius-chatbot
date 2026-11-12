import XCTest

/// The interactive lesson player pilot, end to end on the iPhone, with no
/// network: `-LessonPlayer YES` turns the pilot on for this run, and
/// `-LessonPlayerStubGrade` answers the short response's evaluation.
final class LessonPlayerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func launch(grade: String, seeded: String = "u1_l1,u1_l2", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES",
            "-hasSeenOnboarding", "YES",
            "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES",
            "-seenAllModeDescriptions", "YES",
            "-CurriculumTrack", "deepDive",
            "-EnterShellCurriculum", "YES",
            "-SeedCompleted", seeded,
            "-LessonPlayer", "YES",
            "-LessonPlayerStubGrade", grade,
            // Opens the lesson through the route a tapped reminder takes.
            // (`app.open(URL)` never reached the lesson on CI's runners.)
            "-OpenLesson", "u1_l3",
        ] + extra
        app.launch()
        return app
    }

    /// Reopens Unit 1 Lesson 3 from its stop on the learning path.
    @MainActor private func reopenLesson3(_ app: XCUIApplication) {
        let node = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lesson 3:")).firstMatch
        tap(node, "Lesson 3's stop on the path")
    }

    @MainActor private func tap(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(what) never appeared", file: file, line: line)
        element.tap()
    }

    @MainActor private func primary(_ app: XCUIApplication) -> XCUIElement { app.buttons["player.primary"] }

    @MainActor
    func testLesson3RunsToCompletion() {
        let app = launch(grade: "meets")

        // 1. A decision on the first screen.
        tap(app.buttons["player.option.unverified"], "step 1's options")
        tap(primary(app), "Check answer")
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 5))
        tap(primary(app), "Continue")

        // 2. The principle.
        XCTAssertTrue(app.staticTexts["Sounding sure isn’t evidence"].waitForExistence(timeout: 5))
        tap(primary(app), "Continue")

        // 3. The testable claim.
        tap(app.buttons["player.claim.34-percent"], "step 3's claims")
        tap(primary(app), "Check answer")
        tap(primary(app), "Continue")

        // 4. The strongest check.
        tap(app.buttons["player.option.original-study"], "step 4's options")
        tap(primary(app), "Check answer")
        tap(primary(app), "Continue")

        // 5. The excerpt.
        tap(app.buttons["player.option.still-unverified"], "step 5's options")
        tap(primary(app), "Check answer")
        tap(primary(app), "Continue")

        // 6. The transfer: the only text field in the lesson.
        let response = app.textViews["player.response"]
        tap(response, "the short response")
        response.typeText("I wouldn't trust the 22% yet; I'd look for the original study and check what it measured.")
        tap(primary(app), "Check answer")
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 10), "the response was never graded")
        tap(primary(app), "Continue")

        // 7. The finish, then back to the path.
        XCTAssertTrue(app.staticTexts["Lesson complete"].waitForExistence(timeout: 5))
        tap(primary(app), "Finish")
        XCTAssertFalse(app.buttons["player.primary"].waitForExistence(timeout: 3), "the player didn't close")
    }

    @MainActor
    func testAnUngradedResponseNeverCompletesAndResumesWithTheTextKept() {
        let app = launch(grade: "offline")
        for (option, isTeach) in [("unverified", false), ("", true), ("claim:34-percent", false),
                                  ("original-study", false), ("still-unverified", false)] {
            if isTeach { tap(primary(app), "Continue"); continue }
            if option.hasPrefix("claim:") {
                tap(app.buttons["player.claim.\(option.dropFirst(6))"], option)
            } else {
                tap(app.buttons["player.option.\(option)"], option)
            }
            tap(primary(app), "Check answer")
            tap(primary(app), "Continue")
        }
        let response = app.textViews["player.response"]
        tap(response, "the short response")
        response.typeText("I'd look for the study first.")
        tap(primary(app), "Check answer")
        XCTAssertTrue(app.staticTexts["Not graded yet"].waitForExistence(timeout: 10))
        XCTAssertEqual(primary(app).label, "Retry")

        // Leave, and come back: same step, same text, still not graded.
        tap(app.buttons["player.leave"], "Finish for now")
        XCTAssertFalse(primary(app).waitForExistence(timeout: 3))
        reopenLesson3(app)
        XCTAssertTrue(app.textViews["player.response"].waitForExistence(timeout: 10), "didn't resume on the short response")
        XCTAssertEqual(app.textViews["player.response"].value as? String, "I'd look for the study first.")
        XCTAssertTrue(app.staticTexts["Not graded yet"].exists)
    }

    @MainActor
    func testFlagOffOpensTheLegacyLesson() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITests", "YES", "-hasSeenOnboarding", "YES", "-consentVersion", "1",
            "-hasSeenChatInputHint", "YES", "-seenAllModeDescriptions", "YES",
            "-CurriculumTrack", "deepDive", "-EnterShellCurriculum", "YES",
            "-SeedCompleted", "u1_l1,u1_l2", "-LessonPlayer", "NO",
            "-OpenLesson", "u1_l3",
        ]
        app.launch()
        // The legacy lesson's intro: "Continue. Start the lesson."
        XCTAssertTrue(app.buttons["Continue. Start the lesson."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["player.primary"].exists)
    }
}
