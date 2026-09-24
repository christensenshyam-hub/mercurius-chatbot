import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ChatFeature

// MARK: - Share card

@Suite("LessonShareCard")
@MainActor
struct LessonShareCardTests {
    private let card = LessonShareCard(
        lessonTitle: "Reward hacking & specification gaming",
        unitLabel: "UNIT 01",
        lessonNumber: 3
    )

    @Test("Renders a 1080×1350 PNG")
    func pngSize() throws {
        let data = try #require(card.pngData())
        let (type, width, height) = try decode(data)
        #expect(type == UTType.png.identifier)
        #expect(width == 1080)
        #expect(height == 1350)
    }

    @Test("The share item carries the full-size PNG")
    func shareItemSize() throws {
        let rendered = try #require(card.renderShareable())
        let (type, width, height) = try decode(rendered.item.png)
        #expect(type == UTType.png.identifier)
        #expect(width == 1080)
        #expect(height == 1350)
    }

    @Test("A title too long for three lines still renders")
    func longTitle() throws {
        let long = LessonShareCard(
            lessonTitle: String(repeating: "Specification gaming in the wild ", count: 6),
            unitLabel: nil,
            lessonNumber: nil
        )
        let (_, width, height) = try decode(try #require(long.pngData()))
        #expect(width == 1080)
        #expect(height == 1350)
    }

    @Test("The unit/lesson line reads in sentence case and drops missing parts")
    func progressLine() {
        #expect(LessonShareCard.progressLine(unitLabel: "UNIT 01", lessonNumber: 3) == "Unit 01 · Lesson 3")
        #expect(LessonShareCard.progressLine(unitLabel: nil, lessonNumber: 3) == "Lesson 3")
        #expect(LessonShareCard.progressLine(unitLabel: "UNIT 02", lessonNumber: nil) == "Unit 02")
        #expect(LessonShareCard.progressLine(unitLabel: "  ", lessonNumber: nil) == nil)
        #expect(LessonShareCard.progressLine(unitLabel: nil, lessonNumber: nil) == nil)
    }

    private func decode(_ data: Data) throws -> (type: String?, width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (CGImageSourceGetType(source) as String?, image.width, image.height)
    }
}

// MARK: - Next stop

@Suite("LessonCompleteOverlay next stop")
@MainActor
struct LessonCompleteOverlayNextStopTests {
    private func overlay(
        nextLessonNumber: Int? = nil,
        nextLessonTitle: String? = nil,
        nextStop: LessonCompleteOverlay.NextStop? = nil
    ) -> LessonCompleteOverlay {
        LessonCompleteOverlay(
            lessonTitle: "The alignment problem",
            nextLessonNumber: nextLessonNumber,
            nextLessonTitle: nextLessonTitle,
            nextStop: nextStop,
            reduceMotion: true,
            onNext: {}, onBackToLessons: {}, onDismiss: {}
        )
    }

    @Test("The old next-lesson params map to .lesson")
    func legacyParamsMapToLesson() {
        let view = overlay(nextLessonNumber: 2, nextLessonTitle: "Reward hacking")
        #expect(view.nextStop == .lesson(number: 2, title: "Reward hacking"))
        #expect(view.primaryActionTitle == "Next lesson")
        #expect(view.upNextLabel == "Lesson 2 · Reward hacking")
    }

    @Test("No next lesson means no next stop")
    func noNext() {
        let view = overlay()
        #expect(view.nextStop == nil)
        #expect(view.primaryActionTitle == nil)
        #expect(view.upNextLabel == nil)
    }

    @Test("A title without a number isn't enough to build a next stop")
    func partialLegacyParams() {
        #expect(overlay(nextLessonTitle: "Reward hacking").nextStop == nil)
        #expect(overlay(nextLessonNumber: 2).nextStop == nil)
    }

    @Test("An explicit next stop wins over the old params")
    func explicitWins() {
        let view = overlay(
            nextLessonNumber: 2,
            nextLessonTitle: "Reward hacking",
            nextStop: .unitTest(unitNumber: "05", unitTitle: "Ethics & Alignment")
        )
        #expect(view.nextStop == .unitTest(unitNumber: "05", unitTitle: "Ethics & Alignment"))
    }

    @Test("A unit check reads as \"Take the Unit N check\"")
    func unitTestCopy() {
        let view = overlay(nextStop: .unitTest(unitNumber: "05", unitTitle: "Ethics & Alignment"))
        #expect(view.primaryActionTitle == "Take the Unit 5 check")
        #expect(view.upNextLabel == "Unit 5 check · Ethics & Alignment")
    }

    @Test("A non-numeric unit number is shown as given")
    func nonNumericUnit() {
        let view = overlay(nextStop: .unitTest(unitNumber: "A", unitTitle: "Bonus"))
        #expect(view.primaryActionTitle == "Take the Unit A check")
    }
}

// MARK: - Exits

@MainActor
private final class ExitLog {
    var events: [String] = []
}

@Suite("LessonCompleteOverlay exits")
@MainActor
struct LessonCompleteExitsTests {
    private func overlay(log: ExitLog, reportsDismissal: Bool = true) -> LessonCompleteOverlay {
        LessonCompleteOverlay(
            lessonTitle: "The alignment problem",
            nextStop: .lesson(number: 2, title: "Reward hacking"),
            reduceMotion: true,
            onNext: { log.events.append("next") },
            onBackToLessons: { log.events.append("back") },
            onDismiss: { log.events.append("dismiss") },
            onCelebrationDismissed: reportsDismissal ? { log.events.append("dismissed") } : nil
        )
    }

    @Test("Every path runs its own action, then reports the dismissal",
          arguments: LessonCompleteExits.Path.allCases)
    func everyPathReports(_ path: LessonCompleteExits.Path) {
        let log = ExitLog()
        overlay(log: log).exits.take(path)

        let action: String
        switch path {
        case .next: action = "next"
        case .backToLessons: action = "back"
        case .dismiss: action = "dismiss"
        }
        #expect(log.events == [action, "dismissed"])
    }

    @Test("A repeat exit still runs its action but doesn't report again")
    func repeatExitReportsOnce() {
        let log = ExitLog()
        let exits = overlay(log: log).exits
        exits.take(.dismiss)
        exits.take(.backToLessons, reportDismissal: false)
        #expect(log.events == ["dismiss", "dismissed", "back"])
    }

    @Test("Without a dismissal hook the actions still run")
    func noHook() {
        let log = ExitLog()
        let exits = overlay(log: log, reportsDismissal: false).exits
        for path in LessonCompleteExits.Path.allCases { exits.take(path) }
        #expect(log.events == ["next", "back", "dismiss"])
    }
}
