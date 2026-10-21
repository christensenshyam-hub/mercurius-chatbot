import Foundation
import Testing
import DesignSystem
@testable import EngagementFeature

private func freshDefaults(_ name: String) -> UserDefaults {
    let suite = "engagement.tests.certificate.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let units = CertificateEligibility.deepDiveUnitIds.enumerated().map {
    CertificateRequirement(id: $0.element, title: "Unit \($0.offset + 1)")
}

/// The Basics lessons, injected as the Basics branch will (b1_l1 … b5_l4).
private let basicsLessons: [CertificateRequirement] = {
    var lessons: [CertificateRequirement] = []
    for (u, count) in [3, 4, 3, 4, 4].enumerated() {
        for l in 1...count { lessons.append(CertificateRequirement(id: "b\(u + 1)_l\(l)", title: "B\(u + 1).\(l)")) }
    }
    return lessons
}()

@Suite("Certificate eligibility")
struct CertificateEligibilityTests {
    @Test("Deep dive: none of the eight checks passed")
    func deepDiveNone() {
        let status = CertificateEligibility.deepDive(units: units, masteredUnitIds: [])
        #expect(!status.isEarned)
        #expect(status.met == 0 && status.total == 8)
        #expect(status.remaining.map { $0.id } == CertificateEligibility.deepDiveUnitIds)
        #expect(status.progressText == "0 of 8 unit checks passed")
    }

    @Test("Deep dive: some passed, and what's left names the rest in order")
    func deepDivePartial() {
        let status = CertificateEligibility.deepDive(units: units,
                                                     masteredUnitIds: ["unit_1", "unit_2", "unit_3", "unit_5", "unit_6"])
        #expect(!status.isEarned)
        #expect(status.met == 5)
        #expect(status.remaining.map { $0.id } == ["unit_4", "unit_7", "unit_8"])
        #expect(status.remainingText == "Still to pass: Unit 4, Unit 7 and 1 more")
        #expect(status.lastMetAt == nil)
    }

    @Test("Deep dive: all eight passed (other ids don't count)")
    func deepDiveComplete() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let status = CertificateEligibility.deepDive(units: units,
                                                     masteredUnitIds: Set(CertificateEligibility.deepDiveUnitIds + ["unit_9"]),
                                                     earnedAt: when)
        #expect(status.isEarned)
        #expect(status.remainingText == nil)
        #expect(status.lastMetAt == when)
        // Seven of eight plus a stray id is not the course.
        let notQuite = CertificateEligibility.deepDive(
            units: units, masteredUnitIds: Set(CertificateEligibility.deepDiveUnitIds.dropLast() + ["unit_9"]))
        #expect(!notQuite.isEarned)
    }

    @Test("Basics with injected lesson ids: none, partial, complete")
    func basics() {
        let none = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: [])
        #expect(!none.isEarned && none.total == 18)

        let some = Set(basicsLessons.prefix(12).map(\.id))
        let partial = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: some)
        #expect(!partial.isEarned)
        #expect(partial.progressText == "12 of 18 lessons finished")
        #expect(partial.remaining.first?.id == "b4_l3")
        #expect(partial.remainingText == "Still to finish: B4.3, B4.4 and 4 more")

        let all = Set(basicsLessons.map(\.id) + ["u1_l1"])
        let complete = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: all)
        #expect(complete.isEarned)
    }

    @Test("Basics: the last lesson's date is the certificate's when every date is known")
    func basicsDate() {
        let ids = basicsLessons.map(\.id)
        var dates: [String: Date] = [:]
        for (i, id) in ids.enumerated() { dates[id] = Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60) }
        let status = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: Set(ids), completedAt: dates)
        #expect(status.lastMetAt == Date(timeIntervalSince1970: 1_800_000_000 + 17 * 60))
        dates["b2_l2"] = nil
        let missing = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: Set(ids), completedAt: dates)
        #expect(missing.isEarned && missing.lastMetAt == nil)
    }

    @Test("An empty lesson list earns nothing")
    func emptyCourse() {
        #expect(!CertificateEligibility.basics(lessons: [], completedLessonIds: ["b1_l1"]).isEarned)
    }

    @Test("The date: the stored one, else the last requirement's, else now")
    func completionDate() {
        let stored = Date(timeIntervalSince1970: 1)
        let last = Date(timeIntervalSince1970: 2)
        let now = Date(timeIntervalSince1970: 3)
        #expect(CertificateEligibility.completionDate(stored: stored, lastMetAt: last, now: now) == stored)
        #expect(CertificateEligibility.completionDate(stored: nil, lastMetAt: last, now: now) == last)
        #expect(CertificateEligibility.completionDate(stored: nil, lastMetAt: nil, now: now) == now)
    }
}

@Suite("Certificate store: the name stays on this device")
@MainActor
struct CertificateStoreTests {
    @Test("The name is normalized, kept in the given defaults only, and survives a relaunch")
    func name() {
        let suite = "engagement.tests.certificate.name.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CertificateStore(defaults: defaults)
        store.setName("  Alexandria   Montgomery-Vasquez \n")
        #expect(store.name == "Alexandria Montgomery-Vasquez")
        #expect(CertificateStore(defaults: defaults).name == "Alexandria Montgomery-Vasquez")
        // Nothing but the store's own key was written…
        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        #expect(written == [CertificateStore.nameKey])
        // …and nothing reached the standard defaults.
        #expect(UserDefaults.standard.string(forKey: CertificateStore.nameKey) == nil)
        store.setName("   ")
        #expect(store.name == nil)
        #expect(defaults.string(forKey: CertificateStore.nameKey) == nil)
    }

    @Test("Reset erases the name and every date")
    func reset() {
        let defaults = freshDefaults("reset")
        let store = CertificateStore(defaults: defaults)
        store.setName("Li Wei")
        store.recordEarned(.deepDive, at: Date(timeIntervalSince1970: 10))
        store.fixCompletionDate(.deepDive, lastMetAt: nil, now: Date(timeIntervalSince1970: 20))
        store.reset()
        #expect(store.name == nil)
        #expect(store.earnedAt(.deepDive) == nil)
        #expect(store.completionDate(.deepDive) == nil)
        for key in CertificateStore.allKeys { #expect(defaults.object(forKey: key) == nil) }
        let reloaded = CertificateStore(defaults: defaults)
        #expect(reloaded.name == nil && reloaded.completionDate(.deepDive) == nil)
        // An open name sheet watches the count, and closes.
        #expect(store.resetCount == 1)
    }

    @Test("The first earned moment and the first printed date stand")
    func datesStand() {
        let store = CertificateStore(defaults: freshDefaults("dates"))
        store.recordEarned(.basics, at: Date(timeIntervalSince1970: 100))
        store.recordEarned(.basics, at: Date(timeIntervalSince1970: 200))
        #expect(store.earnedAt(.basics) == Date(timeIntervalSince1970: 100))
        let first = store.fixCompletionDate(.basics, lastMetAt: nil, now: Date(timeIntervalSince1970: 300))
        let second = store.fixCompletionDate(.basics, lastMetAt: Date(timeIntervalSince1970: 5),
                                             now: Date(timeIntervalSince1970: 400))
        #expect(first == Date(timeIntervalSince1970: 300) && second == first)
    }

}

@Suite("Certificate center")
@MainActor
struct CertificateCenterTests {
    final class FakeProgress {
        var mastered: Set<String> = []
        var completed: Set<String> = []
        var dates: [String: Date] = [:]
    }

    private func center(_ progress: FakeProgress, basics: [CertificateRequirement]? = nil,
                        now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> CertificateCenter {
        CertificateCenter(
            store: CertificateStore(defaults: freshDefaults("center")),
            deepDiveUnits: units,
            basicsLessons: basics,
            progress: .init(masteredUnitIds: { progress.mastered },
                            completedLessonIds: { progress.completed },
                            completedAt: { progress.dates[$0] }),
            now: { now }
        )
    }

    @Test("Without the Basics course only the Deep dive is offered; the seam adds Basics")
    func seam() {
        let progress = FakeProgress()
        let c = center(progress)
        #expect(c.kinds == [.deepDive])
        #expect(c.status(.basics) == nil)
        c.basicsLessons = basicsLessons
        #expect(c.kinds == [.deepDive, .basics])
        #expect(c.status(.basics)?.total == 18)
    }

    @Test("The eighth mastery is the moment: recorded, and the card is due")
    func eighthMastery() {
        let progress = FakeProgress()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let c = center(progress, now: now)
        for id in CertificateEligibility.deepDiveUnitIds.dropLast() {
            #expect(c.recordingNewlyEarned { progress.mastered.insert(id) }.isEmpty)
        }
        #expect(c.justEarned == nil)
        let newly = c.recordingNewlyEarned { progress.mastered.insert("unit_8") }
        #expect(newly == [.deepDive])
        #expect(c.justEarned == .deepDive)
        #expect(c.store.earnedAt(.deepDive) == now)
        // Passing a check again doesn't re-earn it.
        c.justEarned = nil
        #expect(c.recordingNewlyEarned { progress.mastered.insert("unit_3") }.isEmpty)
        #expect(c.justEarned == nil)
        // The certificate prints the day it was earned, fixed from then on.
        #expect(c.completionDate(.deepDive) == now)
    }

    @Test("A certificate earned elsewhere (synced) takes the day it's first made")
    func earnedElsewhere() {
        let progress = FakeProgress()
        progress.mastered = Set(CertificateEligibility.deepDiveUnitIds)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let c = center(progress, now: now)
        #expect(c.status(.deepDive)?.isEarned == true)
        #expect(c.store.completionDate(.deepDive) == nil)
        #expect(c.completionDate(.deepDive) == now)
        #expect(c.store.completionDate(.deepDive) == now)
    }

    @Test("Basics through the seam: the last lesson's date, or the moment it was seen")
    func basicsThroughSeam() {
        let progress = FakeProgress()
        let c = center(progress, basics: basicsLessons)
        for lesson in basicsLessons.dropLast() { progress.completed.insert(lesson.id) }
        #expect(c.status(.basics)?.isEarned == false)
        let newly = c.recordingNewlyEarned { progress.completed.insert("b5_l4") }
        #expect(newly == [.basics])
        // No lesson dates: the moment this device saw it stands in.
        #expect(c.status(.basics)?.lastMetAt == c.store.earnedAt(.basics))
    }

    @Test("Not earned: no date is fixed")
    func notEarnedNoDate() {
        let c = center(FakeProgress())
        #expect(c.completionDate(.deepDive) == nil)
        #expect(c.store.completionDate(.deepDive) == nil)
    }

    @Test("The hub row's summary")
    func summary() {
        let earned = CertificateEligibility.deepDive(units: units, masteredUnitIds: Set(CertificateEligibility.deepDiveUnitIds))
        let open = CertificateEligibility.basics(lessons: basicsLessons, completedLessonIds: ["b1_l1"])
        let none = CertificateEligibility.deepDive(units: units, masteredUnitIds: [])
        #expect(CertificatesListCopy.summary([earned, open]) == "1 earned · 1 in progress")
        #expect(CertificatesListCopy.summary([earned]) == "1 earned")
        #expect(CertificatesListCopy.summary([none]) == "Pass all eight unit checks to earn yours")
        #expect(CertificatesListCopy.summary([none, open]) == "Finish a course to earn one")
    }

    @Test("The sheet says the name stays on this device")
    func privacyCopy() {
        #expect(CertificateSheetCopy.privacy.hasPrefix("Your name stays on this device."))
        #expect(CertificateSheetCopy.nameLabel == "Your name, as it should appear")
    }
}
