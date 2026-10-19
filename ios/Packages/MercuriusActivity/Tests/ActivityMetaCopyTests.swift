import Testing
@testable import MercuriusActivity

/// The lock card renders the active meta line on one tail-truncating line in
/// a text column ~149pt wide on the narrowest cards (a 360pt card minus the
/// row's 211pt of padding, spacing, ring and art column). At 12pt semibold
/// the line measures about 5.4pt a character ("2 left · 23:59:59 left" is
/// 117pt), so 24 characters (~130pt) keeps it on the card with room for wide
/// glyphs. The headline is 20pt heavy on one line in the same column, about
/// 11pt a character, so it gets 13.
@Suite("Live Activity meta line")
struct ActivityMetaCopyTests {

    static let lockCardBudget = 24
    static let headlineBudget = 13
    /// The widest countdown: the deadline is the end of the local day.
    static let widestCountdown = "23:59:59"

    /// The meta line as the card renders it, with the widest countdown.
    private func rendered(_ meta: ActivityMetaCopy.ActiveMeta) -> String {
        switch meta {
        case .countdown(let prefix): return prefix + Self.widestCountdown
        case .text(let line): return line
        }
    }

    private func meta(weekDone: Int? = 0, weekGoal: Int? = 2, atRisk: Bool = false,
                      lessonsLeft: Int = 4, unit: Int = 1, compact: Bool = true) -> ActivityMetaCopy.ActiveMeta {
        ActivityMetaCopy.activeMeta(weekDone: weekDone, weekGoal: weekGoal, streakAtRisk: atRisk,
                                    lessonsLeft: lessonsLeft, unitNumber: unit, compact: compact)
    }

    // MARK: - AUD-37

    @Test("A first lesson reads as a lesson in progress this week, with no countdown")
    func firstLesson() {
        #expect(ActivityMetaCopy.activeHeadline(weekDone: 0, lessonsDone: 0) == "In a lesson")
        #expect(meta(weekDone: 0) == .text("This week · 0 of 2"))
        #expect(meta(weekDone: 0, compact: false) == .text("This week · 0 of 2 lessons"))
        #expect(ActivityMetaCopy.activeProgressPhrase(lessonsDone: 0, lessonsTotal: 4, unitNumber: 1)
                == "Unit 1 · 0 of 4 done")
    }

    @Test("Something done this week: On a roll, and the week's count")
    func onARoll() {
        #expect(ActivityMetaCopy.activeHeadline(weekDone: 1, lessonsDone: 0) == "On a roll")
        #expect(meta(weekDone: 1) == .text("This week · 1 of 2"))
        #expect(meta(weekDone: 2) == .text("This week · 2 of 2"))
        // Past the goal it counts lessons, as Home does.
        #expect(meta(weekDone: 3) == .text("This week · 3 lessons"))
        #expect(meta(weekDone: 3, compact: false) == .text("This week · 3 lessons"))
    }

    @Test("The only countdown is a labelled streak deadline")
    func streakCountdown() {
        #expect(meta(atRisk: true) == .countdown(prefix: "Streak ends in "))
        #expect(meta(atRisk: true, compact: false) == .countdown(prefix: "Streak ends in "))
        // Not at risk: never a countdown, whatever else is known.
        for weekDone in [nil, 0, 1, 2, 5] as [Int?] {
            for compact in [true, false] {
                if case .countdown = meta(weekDone: weekDone, atRisk: false, compact: compact) {
                    Issue.record("countdown without a streak at risk (weekDone \(String(describing: weekDone)))")
                }
            }
        }
    }

    @Test("An activity from an older build (no week) shows the unit's lessons left and no countdown")
    func legacyActivity() {
        #expect(meta(weekDone: nil, weekGoal: nil, lessonsLeft: 2, unit: 6) == .text("2 to go"))
        #expect(meta(weekDone: nil, weekGoal: nil, lessonsLeft: 2, unit: 6, compact: false)
                == .text("2 lessons left in Unit 6"))
        #expect(ActivityMetaCopy.activeHeadline(weekDone: nil, lessonsDone: 0) == "In a lesson")
        #expect(ActivityMetaCopy.activeHeadline(weekDone: nil, lessonsDone: 3) == "On a roll")
    }

    @Test("No active line ever pairs the unit's lessons left with a clock")
    func noSameDayDeadline() {
        for unit in 1...8 {
            for left in 0...5 {
                for weekDone in [nil, 0, 1, 2] as [Int?] {
                    let line = rendered(meta(weekDone: weekDone, weekGoal: weekDone == nil ? nil : 2,
                                             lessonsLeft: left, unit: unit))
                    #expect(!line.contains(":"), "\(line)")
                    #expect(!line.contains(" left"), "\(line)")
                }
            }
        }
    }

    // MARK: - Lock card budget

    @Test("Every active meta line fits the lock card's column", arguments: 1...8)
    func lockCardFits(unit: Int) {
        var lines: [String] = []
        for weekDone in 0...9 {
            lines.append(rendered(meta(weekDone: weekDone, lessonsLeft: 3, unit: unit)))
        }
        lines.append(rendered(meta(atRisk: true, unit: unit)))
        for left in [0, 1, 2, 3, 4, 5, 9] {
            lines.append(rendered(meta(weekDone: nil, weekGoal: nil, lessonsLeft: left, unit: unit)))
        }
        for line in lines {
            #expect(line.count <= Self.lockCardBudget, "\(line) is \(line.count) characters")
        }
    }

    @Test("The island's longer forms are what the lock card's budget is there to catch")
    func longFormIsTooWideForTheLockCard() {
        #expect(rendered(meta(weekDone: 1, compact: false)).count > rendered(meta(weekDone: 1)).count)
        #expect(ActivityMetaCopy.lessonsLeftPhrase(lessonsLeft: 2, unitNumber: 6, compact: false).count
                + ActivityMetaCopy.separator.count + Self.widestCountdown.count > Self.lockCardBudget)
    }

    @Test("Active headlines fit the lock card's one line")
    func headlinesFit() {
        for weekDone in [nil, 0, 1, 3] as [Int?] {
            for lessonsDone in [0, 2] {
                let headline = ActivityMetaCopy.activeHeadline(weekDone: weekDone, lessonsDone: lessonsDone)
                #expect(headline.count <= Self.headlineBudget, "\(headline)")
            }
        }
    }

    @Test("The active second line names the unit and fits beside the ring")
    func progressPhrase() {
        #expect(ActivityMetaCopy.activeProgressPhrase(lessonsDone: 3, lessonsTotal: 5, unitNumber: 6)
                == "Unit 6 · 3 of 5 done")
        #expect(ActivityMetaCopy.activeProgressPhrase(lessonsDone: 3, lessonsTotal: 5, unitNumber: 0)
                == "3 of 5 done")
        // 13.5pt semibold, ~6.3pt a character in the ~149pt column.
        for unit in 1...12 {
            let line = ActivityMetaCopy.activeProgressPhrase(lessonsDone: 9, lessonsTotal: 9, unitNumber: unit)
            #expect(line.count <= 23, "\(line)")
        }
    }

    // MARK: - Lessons-left phrase (older activities)

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
