import Foundation
import Testing
@testable import LessonInteractives

/// The registry: one card per lesson, the slate's anchors and spoilers, no
/// card in a Review lesson, and only built, reviewed cards enabled. (Every
/// lesson id is checked against `Curriculum.swift` in AppFeature's
/// `InteractiveCurriculumTests`, the one module that sees both.)
@Suite("Interactives: the registry")
struct RegistryTests {

    @Test("Every card has exactly one row, and every lesson at most one card")
    func oneEach() {
        let ids = InteractiveRegistry.all.map(\.id)
        #expect(Set(ids) == Set(InteractiveID.allCases))
        #expect(ids.count == InteractiveID.allCases.count)
        let lessons = InteractiveRegistry.all.map(\.lessonID)
        #expect(Set(lessons).count == lessons.count, "two cards in one lesson (D6: one per lesson)")
        for id in InteractiveID.allCases {
            #expect(InteractiveRegistry.spec(for: id)?.id == id)
        }
    }

    @Test("No card sits in a Review lesson")
    func noReviewLessons() {
        for spec in InteractiveRegistry.all {
            #expect(!InteractiveRegistry.reviewLessons.contains(spec.lessonID), "\(spec.id) is in \(spec.lessonID)")
        }
        #expect(InteractiveRegistry.reviewLessons.count == 8)
    }

    @Test("Lesson ids look like the curriculum's (uN_lM)")
    func lessonIDShape() {
        for spec in InteractiveRegistry.all {
            #expect(spec.lessonID.range(of: #"^u[1-8]_l[1-5]$"#, options: .regularExpression) != nil, "\(spec.lessonID)")
        }
    }

    @Test("The slate's table (BUILD_PLAN.md §1.2): lessons, anchors, spoilers, waves")
    func slateTable() {
        func row(_ id: InteractiveID) -> InteractiveSpec { InteractiveRegistry.spec(for: id)! }
        let expected: [(InteractiveID, String, InteractiveAnchorRule, [String], Int)] = [
            (.tokenizer, "u1_l1", .firstExample, [], 0),
            (.citationThatWasnt, "u1_l3", .firstExample, [], 1),
            (.twoTestsOneLine, "u2_l2", .teachReply(2), ["Kleinberg", "Chouldechova", "impossib"], 2),
            (.whosInTheTest, "u2_l3", .firstExample, [], 2),
            (.deleteTheGenderBox, "u3_l1", .firstExample, [], 1),
            (.wardOf1000, "u3_l2", .firstReplyMentioning(["sepsis"], fallback: 2), ["88%", "12%", "1 in 8"], 2),
            (.readMyMind, "u4_l1", .firstExample, [], 2),
            (.patchTheReward, "u5_l1", .firstExample, [], 1),
            (.grownFromStatic, "u6_l1", .firstExample, [], 2),
            (.doubtDial, "u6_l4", .firstExample, [], 1),
            (.predictTheExam, "u7_l1", .firstExample, ["17%", "48%", "Bastani"], 2),
            (.pageWithASecret, "u8_l1", .firstExample, ["hidden text", "prompt injection", "Guardian"], 1),
        ]
        #expect(expected.count == InteractiveID.allCases.count)
        for (id, lesson, anchor, spoilers, wave) in expected {
            let spec = row(id)
            #expect(spec.lessonID == lesson, "\(id)")
            #expect(spec.anchor == anchor, "\(id)")
            #expect(spec.spoilers == spoilers, "\(id)")
            #expect(spec.wave == wave, "\(id)")
        }
        // Wave 1 is the slate's five ★ cards, all on today's anchor.
        let waveOne = InteractiveRegistry.all.filter { $0.wave == 1 }.map(\.id)
        #expect(Set(waveOne) == [.doubtDial, .pageWithASecret, .citationThatWasnt, .deleteTheGenderBox, .patchTheReward])
        #expect(InteractiveRegistry.all.filter { $0.wave == 1 }.allSatisfy { $0.anchor == .firstExample })
    }

    @Test("Only built cards may be enabled; today that is Lesson 1.1's alone")
    func enabledCards() {
        for spec in InteractiveRegistry.all where spec.enabled {
            #expect(InteractiveCardViews.built.contains(spec.id), "\(spec.id) is enabled but not built")
        }
        #expect(InteractiveRegistry.all.filter(\.enabled).map(\.id) == [.tokenizer])
        #expect(InteractiveCardViews.built.contains(.tokenizer))
    }

    @Test("A lesson shows its enabled card; free chat, unknown lessons and dark cards show none")
    func lookup() {
        let specs = InteractiveRegistry.all
        #expect(InteractiveRegistry.spec(forLesson: "u1_l1", in: specs, forcing: nil)?.id == .tokenizer)
        #expect(InteractiveRegistry.spec(forLesson: "u6_l4", in: specs, forcing: nil) == nil, "the Doubt Dial ships dark")
        #expect(InteractiveRegistry.spec(forLesson: "u1_l2", in: specs, forcing: nil) == nil)
        #expect(InteractiveRegistry.spec(forLesson: nil, in: specs, forcing: nil) == nil)
        #expect(InteractiveRegistry.spec(forLesson: "", in: specs, forcing: nil) == nil)
        // Outside DEBUG launch arguments the live lookup agrees.
        #expect(InteractiveRegistry.spec(forLesson: "u1_l1")?.id == .tokenizer)
        #expect(InteractiveRegistry.spec(forLesson: "u2_l1") == nil)
    }

    @Test("DEBUG forcing shows that dark card in its own lesson only, enabled")
    func forcing() throws {
        let specs = InteractiveRegistry.all
        let forced = try #require(InteractiveRegistry.spec(forLesson: "u6_l4", in: specs, forcing: .doubtDial))
        #expect(forced.id == .doubtDial)
        #expect(forced.enabled)
        #expect(forced.anchor == .firstExample)
        // Another lesson's dark card stays dark; Lesson 1.1 keeps its own.
        #expect(InteractiveRegistry.spec(forLesson: "u8_l1", in: specs, forcing: .doubtDial) == nil)
        #expect(InteractiveRegistry.spec(forLesson: "u1_l1", in: specs, forcing: .doubtDial)?.id == .tokenizer)
    }

    @Test("Slugs: the slate's file names, round-tripped, case-insensitive")
    func slugs() {
        let slugs = InteractiveID.allCases.map(\.slug)
        #expect(Set(slugs).count == slugs.count)
        for id in InteractiveID.allCases {
            #expect(InteractiveID(slug: id.slug) == id)
            #expect(InteractiveID(slug: id.rawValue) == id)
            #expect(InteractiveID(slug: id.slug.uppercased()) == id)
            #expect(id.slug.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil)
            #expect(!id.workingName.isEmpty)
        }
        #expect(InteractiveID(slug: "doubt-dial") == .doubtDial)
        #expect(InteractiveID(slug: "nope") == nil)
        // The slate's sketches are named by these slugs.
        let slateSlugs: Set<String> = ["citation-that-wasnt", "two-tests-one-line", "whos-in-the-test",
                                       "delete-the-gender-box", "ward-of-1000", "read-my-mind", "patch-the-reward",
                                       "grown-from-static", "doubt-dial", "predict-the-exam", "page-with-a-secret"]
        #expect(Set(slugs).subtracting(["tokenizer"]) == slateSlugs)
    }

    @Test("How many replies a stub replay answers its way to, per anchor")
    func repliesToReach() {
        #expect(InteractiveAnchorRule.firstExample.repliesToReach == 1)
        #expect(InteractiveAnchorRule.teachReply(2).repliesToReach == 2)
        #expect(InteractiveAnchorRule.teachReply(3).repliesToReach == 3)
        #expect(InteractiveAnchorRule.firstReplyMentioning(["sepsis"], fallback: 2).repliesToReach == 2)
        #expect(InteractiveAnchorRule.firstReplyMentioning(["sepsis"], fallback: 1).repliesToReach == 1)
    }
}

@Suite("Interactives: spoiler and mention terms")
struct TermMatchingTests {

    @Test("Case-insensitive, at the start of a word, any ending")
    func matching() {
        #expect(InteractiveTerms.contains("sepsis", in: "Sepsis is rare."))
        #expect(InteractiveTerms.contains("impossib", in: "the impossibility result"))
        #expect(InteractiveTerms.contains("prompt injection", in: "This is PROMPT INJECTION."))
        #expect(InteractiveTerms.contains("Guardian", in: "In The Guardian's test…"))
        #expect(InteractiveTerms.contains("88%", in: "it was right **88%** of the time"))
        // Not inside another word or number.
        #expect(!InteractiveTerms.contains("12%", in: "it rose 112% that year"))
        #expect(!InteractiveTerms.contains("sepsis", in: "antisepsis"))
        #expect(!InteractiveTerms.contains("17%", in: "nothing here"))
        // A later, standalone match is still found.
        #expect(InteractiveTerms.contains("12%", in: "112% then 12%"))
        #expect(InteractiveTerms.firstMatch(of: ["17%", "Bastani"], in: "Bastani et al.") == "Bastani")
        #expect(InteractiveTerms.firstMatch(of: [], in: "anything") == nil)
        #expect(InteractiveTerms.firstMatch(of: [""], in: "anything") == nil)
    }

    @Test("A spec finds its own spoilers; a card without any is never spoiled")
    func specSpoilers() throws {
        let page = try #require(InteractiveRegistry.spec(for: .pageWithASecret))
        #expect(page.spoilerTerm(in: "Some pages hide text. This is called prompt injection.") == "prompt injection")
        #expect(page.spoilerTerm(in: "An agent plans, acts and observes.") == nil)
        let dial = try #require(InteractiveRegistry.spec(for: .doubtDial))
        #expect(dial.spoilerTerm(in: "the liar's dividend, hidden text, Guardian") == nil)
    }
}
