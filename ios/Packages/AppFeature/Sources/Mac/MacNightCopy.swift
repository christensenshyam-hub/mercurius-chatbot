#if os(macOS)
import Foundation
import CurriculumFeature

/// Every new or changed line of UI text the Mac's Night Studio screens in
/// AppFeature say (SPEC.md §6), in one place so `NightCopyTests` can hold it
/// to the honest-copy rules: nothing promises a feature that doesn't exist
/// (no notebook, no "saved"), the daily streak isn't said not to reset, no
/// part totals, no time estimates.
enum MacNightCopy {
    // MARK: Today's header

    /// "Good evening." — `HomeState.opener`'s wording, calmer punctuation.
    static func greeting(hour: Int) -> String {
        HomeState.opener(hour: hour).replacingOccurrences(of: "!", with: ".")
    }

    /// The line under the greeting: `HomeState.greeting`'s, without its
    /// opener and without the streak cheer ("keep your streak alive!").
    static func subline(_ state: HomeState) -> String {
        switch state.next {
        case nil:
            return "You've finished the whole path. Chat with Merc any time to go deeper."
        case .unitTest(let unit):
            return "Unit \(unitNumber(unit))'s lessons are done. Ready for the check?"
        case .lesson:
            if state.week.done >= state.week.goal {
                return "This week's goal is done — anything more is a bonus."
            }
            if !state.hasProgress && !state.resumesNext {
                return "Your first lesson is ready when you are."
            }
            return "Your next lesson is waiting."
        }
    }

    /// The date eyebrow: the localised weekday, month and day.
    static func dateLine(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))
    }

    // MARK: The week card

    /// The streak, said once and quietly: only when there is one (never a
    /// zero), with the Mac's existing line about how it keeps going. The
    /// daily streak does reset, so nothing here says otherwise.
    static func streakLine(_ streak: Int) -> String? {
        guard streak >= 1 else { return nil }
        let days = streak == 1 ? "1 day running." : "\(streak) days running."
        return "\(days) One lesson or chat a day keeps it going."
    }

    /// VoiceOver's sentence for the week's days: "Lessons done on Tuesday
    /// and Thursday." / "No lessons yet this week."
    static func lessonDaysSentence(_ dayNames: [String]) -> String {
        guard !dayNames.isEmpty else { return "No lessons yet this week." }
        let list = ListFormatter.localizedString(byJoining: dayNames)
        return dayNames.count == 1 ? "A lesson done on \(list)." : "Lessons done on \(list)."
    }

    /// The whole week card for VoiceOver.
    static func weekCardAccessibilityLabel(weekLabel: String, dayNames: [String], streak: Int) -> String {
        [weekLabel, lessonDaysSentence(dayNames), streakLine(streak)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    static let weekCardHint = "Opens your progress."
    static let progressHelp = "Your progress and achievements (⌘4)"

    // MARK: Think it through

    static func thinkEyebrow(modeName: String) -> String { "Think it through · \(modeName)" }

    static func thinkAccessibilityLabel(prompt: String) -> String { "Think it through: \(prompt)" }

    static let thinkHint = "Opens a new chat with this question ready to send."
    static let thinkHelp = "Open a new chat with this question in the message box. Nothing is sent until you send it."

    // MARK: The hero

    /// The hero's text, as one header for VoiceOver: "Lesson 3: Why AI
    /// sounds confident but can be wrong. Understand hallucination and the
    /// confidence-accuracy gap. 2 of 4 lessons done in Unit 1."
    static func heroAccessibilityLabel(lead: String, title: String, detail: String, progress: String?) -> String {
        var parts = ["\(lead): \(title).", ensurePeriod(detail)]
        if let progress { parts.append(ensurePeriod(progress)) }
        return parts.joined(separator: " ")
    }

    private static func ensurePeriod(_ s: String) -> String {
        guard let last = s.last else { return s }
        return ".!?".contains(last) ? s : s + "."
    }

    private static func unitNumber(_ unit: CurriculumFeature.Unit) -> String {
        Int(unit.number).map(String.init) ?? unit.number
    }
}
#endif
