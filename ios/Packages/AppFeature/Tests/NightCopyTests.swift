#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
import ChatFeature
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// The honest-copy register (SPEC.md §6): no line the Mac's Night screens
/// say may promise a feature that doesn't exist. Every string
/// `MacNightCopy` and Today's Up next produce, over a spread of states, is
/// checked against the phrases the concept used and the product can't back.
@Suite("Night copy is honest")
@MainActor
struct NightCopyTests {

    /// The phrases that may never appear (case-insensitive regular
    /// expressions).
    static let banned: [String] = [
        "notebook",
        "saved to",
        "rest day",
        #"part \d+ of \d+"#,
        #"beat \d"#,
        #"\b\d+\s?min\b"#,
        #"\bminutes?\b"#,
        "previewable",
        "pinned",
        "give me a hint",
        "keep your streak alive",
        "never reset",
    ]

    /// Every line Today can say, across fresh, resumed, goal-met, unit-check
    /// and finished paths, and streaks of 0, 1 and many.
    static func everyLine() -> [String] {
        var lines: [String] = []
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit1 = MercuriusCurriculum.units[0]
        func collect() {
            for streak in [0, 1, 6] {
                let state = HomeState.build(streak: streak, progress: progress)
                lines.append(MacNightCopy.subline(state))
                let next = MacTodayView.upNext(state: state, progress: progress)
                lines += [next.eyebrow, next.title, next.detail, next.buttonTitle, next.accessibilityLabel]
                if let label = next.unitProgress?.label { lines.append(label) }
                lines.append(MacTodayView.weekHeadline(state.week))
                lines.append(MacTodayView.weekDetail(state.week))
                lines.append(MacNightCopy.weekCardAccessibilityLabel(
                    weekLabel: state.weekAccessibilityLabel, dayNames: ["Friday"], streak: streak))
                if let line = MacNightCopy.streakLine(streak) { lines.append(line) }
            }
        }
        collect()
        progress.markOpened(unit1.lessons[0].id)
        collect()
        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        collect()
        for lesson in unit1.lessons { progress.markCompleted(lesson.id) }
        collect()
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { progress.markCompleted(lesson.id) }
            progress.markUnitMastered(unit.id)
        }
        collect()
        for hour in 0..<24 { lines.append(MacNightCopy.greeting(hour: hour)) }
        lines.append(MacNightCopy.lessonDaysSentence([]))
        for mode in ChatMode.allCases {
            lines.append(MacNightCopy.thinkEyebrow(modeName: mode.displayName))
            for prompt in ModePromptProvider.prompts(for: mode) {
                lines.append(MacNightCopy.thinkAccessibilityLabel(prompt: prompt))
            }
        }
        lines += [MacNightCopy.weekCardHint, MacNightCopy.progressHelp, MacNightCopy.thinkHint,
                  MacNightCopy.thinkHelp, MacProgressButton.title, MacProgressButton.help]
        return lines
    }

    @Test("No Night line promises a notebook, a saved idea, a total, a time or a streak that never resets")
    func noBannedPhrases() throws {
        let lines = Self.everyLine()
        #expect(lines.count > 100)
        for pattern in Self.banned {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                #expect(regex.firstMatch(in: line, range: range) == nil, "“\(line)” matches /\(pattern)/")
            }
        }
    }

    @Test("The banned list catches the concept's own lines")
    func bannedListWorks() throws {
        let concept = [
            "Saved to notebook",
            "4 days running. Rest days never reset your progress.",
            "Beat 2 of 6 · Tokenization",
            "2 of 4 lessons in this unit · about 6 min",
            "Every lesson is previewable",
            "pinned source",
            "Give me a hint",
            "Day 4 — let's keep your streak alive!",
        ]
        for line in concept {
            let caught = try Self.banned.contains { pattern in
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            #expect(caught, "“\(line)” slipped through")
        }
    }
}
#endif
