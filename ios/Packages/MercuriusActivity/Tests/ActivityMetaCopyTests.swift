import Testing
@testable import MercuriusActivity

/// The lock card renders the active meta line on one tail-truncating line in
/// a text column ~149pt wide on the narrowest cards (a 360pt card minus the
/// row's 211pt of padding, spacing, ring and art column). At 12pt semibold
/// the line measures about 5.4pt a character ("2 left · 23:59:59 left" is
/// 117pt), so 24 characters (~130pt) keeps the countdown on the card with
/// room for wide glyphs.
@Suite("Live Activity meta line")
struct ActivityMetaCopyTests {

    static let lockCardBudget = 24
    /// The widest countdown: the deadline is the end of the local day.
    static let widestCountdown = "23:59:59"

    private func line(lessonsLeft: Int, unit: Int, compact: Bool) -> String {
        ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: lessonsLeft, unitNumber: unit, compact: compact)
            + ActivityMetaCopy.separator + Self.widestCountdown + ActivityMetaCopy.countdownSuffix
    }

    @Test("The lock card's line fits its column for every unit and lessons-left count",
          arguments: 1...8)
    func lockCardFits(unit: Int) {
        for left in [0, 1, 2, 3, 4, 5, 9] {
            let text = line(lessonsLeft: left, unit: unit, compact: true)
            #expect(text.count <= Self.lockCardBudget, "\(text) is \(text.count) characters")
        }
    }

    @Test("The budget catches the long form, which only the Dynamic Island has room for")
    func longFormIsTooWideForTheLockCard() {
        #expect(line(lessonsLeft: 2, unit: 6, compact: false).count > Self.lockCardBudget)
    }

    @Test("Lock card copy: a count, or done when replaying a finished unit")
    func compactCopy() {
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 2, unitNumber: 6, compact: true) == "2 to go")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 1, unitNumber: 6, compact: true) == "1 to go")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 0, unitNumber: 6, compact: true) == "All done")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: -1, unitNumber: 6, compact: true) == "All done")
    }

    @Test("Dynamic Island copy keeps the unit")
    func expandedCopy() {
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 2, unitNumber: 6, compact: false)
                == "2 lessons left in Unit 6")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 1, unitNumber: 6, compact: false)
                == "1 lesson left in Unit 6")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 0, unitNumber: 6, compact: false)
                == "Unit 6 complete")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 3, unitNumber: 0, compact: false)
                == "3 lessons left")
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 0, unitNumber: 0, compact: false)
                == "All lessons done")
    }
}
