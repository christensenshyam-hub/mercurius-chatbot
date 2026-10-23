import Testing
@testable import EngagementFeature

/// The reminder switches' words. The first-run "Your path" form is plain:
/// one weekly switch, no streak (review 2026-10-22: it sits next to the
/// Basics choice, and Basics has no streak).
@Suite("Reminder switch words")
struct RemindersSectionCopyTests {
    @Test("The plain form says what it does in everyday words, with no streak and no jargon")
    func plainForm() {
        typealias Copy = RemindersSection.Copy
        #expect(Copy.plainTitle == "Remind me to practice")
        #expect(Copy.plainDetail == "Twice a week: Sunday at 6 PM and Wednesday at 7 PM.")
        for line in [Copy.plainTitle, Copy.plainDetail] {
            for word in ["streak", "nudge", "Wed &", "just "] {
                #expect(!line.lowercased().contains(word.lowercased()), "\"\(word)\" in: \(line)")
            }
        }
        // The Progress hub's full form keeps both switches' words.
        #expect(Copy.weeklyTitle == "Weekly nudges (Wed & Sun)")
        #expect(Copy.dailyTitle == "Daily streak reminder")
    }
}
