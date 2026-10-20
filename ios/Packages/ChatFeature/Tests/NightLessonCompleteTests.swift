#if os(macOS)
import Foundation
import Testing
import DesignSystem
@testable import ChatFeature

/// The Mac's lesson-complete card (SPEC.md §5.6, step 03): the credential
/// it derives from the objective, the key ideas it recaps, the week and
/// next-stop lines, and the honest-copy register over all of it.
@Suite("Night lesson complete")
@MainActor
struct NightLessonCompleteTests {

    // MARK: The credential

    @Test("\"Understand X.\" becomes \"You can now explain X.\"")
    func credentialFromUnderstand() {
        #expect(NightCompleteCopy.credential(objective: "Understand tokenization and next-token prediction.")
                == "You can now explain tokenization and next-token prediction.")
        #expect(NightCompleteCopy.credential(objective: "Understand how LLMs are trained and what their knowledge actually is.")
                == "You can now explain how LLMs are trained and what their knowledge actually is.")
        #expect(NightCompleteCopy.credential(objective: "  Understand AI that sees, hears, and speaks.  ")
                == "You can now explain AI that sees, hears, and speaks.")
        #expect(NightCompleteCopy.credential(objective: "Understand the pipeline of bias: data, design, deployment")
                == "You can now explain the pipeline of bias: data, design, deployment.")
    }

    @Test("Any other objective claims nothing: the headline stays \"Lesson complete\"")
    func noCredentialOtherwise() {
        for objective in ["Apply everything from Unit 1 to a real scenario.",
                          "Master intermediate prompting techniques.",
                          "Learn how different phrasings produce different outputs.",
                          "Analyze a real-world case of algorithmic bias.",
                          "Grapple with the ethics of autonomous weapons systems.",
                          "Understanding is hard.", "Understand ", "Understand.", ""] {
            #expect(NightCompleteCopy.credential(objective: objective) == nil, "\(objective)")
            #expect(NightCompleteCopy.headline(objective: objective) == "Lesson complete")
        }
    }

    // MARK: Key ideas

    private func message(_ role: ChatMessage.Role, _ content: String) -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    @Test("The thread's [KEY] ideas, Merc's only, in order, each once")
    func collectsKeyIdeas() {
        let messages = [
            message(.assistant, "Intro.\n\n[KEY]Tokens are pieces of words.[/KEY]\n\nMore.\n\n[KEY]Models predict the next token.[/KEY]"),
            message(.user, "[KEY]A student typing tags[/KEY]"),
            message(.assistant, "Again: [KEY]Tokens are pieces of words.[/KEY] And [KEY] Training data shapes answers. [/KEY]"),
            message(.assistant, "[KEY]   [/KEY] no idea here"),
        ]
        #expect(NightKeyIdeas.collect(from: messages) == [
            "Tokens are pieces of words.",
            "Models predict the next token.",
            "Training data shapes answers.",
        ])
        #expect(NightKeyIdeas.collect(from: []) == [])
    }

    @Test("The card lists the last three ideas and says how many more the lesson holds")
    func shownKeyIdeas() {
        let five = ["1", "2", "3", "4", "5"]
        let shown = NightCompleteCopy.shownKeyIdeas(five)
        #expect(shown.shown == ["3", "4", "5"])
        #expect(shown.more == 2)
        #expect(NightCompleteCopy.moreKeyIdeas(2) == "+2 more in the lesson")
        let two = NightCompleteCopy.shownKeyIdeas(["a", "b"])
        #expect(two.shown == ["a", "b"])
        #expect(two.more == 0)
    }

    // MARK: Lines

    @Test("The eyebrow names the unit and lesson in title case")
    func eyebrow() {
        #expect(NightCompleteCopy.eyebrow(unitLabel: "UNIT 01", lessonNumber: 1) == "Unit 1 · Lesson 1 · Complete")
        #expect(NightCompleteCopy.eyebrow(unitLabel: nil, lessonNumber: 3) == "Lesson 3 · Complete")
        #expect(NightCompleteCopy.eyebrow(unitLabel: " ", lessonNumber: nil) == "Complete")
    }

    @Test("The week row: the count, and a stopping cue true at any hour")
    func weekLines() {
        #expect(NightCompleteCopy.weekHeadline(done: 1, goal: 2) == "1 of 2 this week")
        #expect(NightCompleteCopy.weekHeadline(done: 3, goal: 2) == "3 this week")
        #expect(NightCompleteCopy.weekDetail(done: 1, goal: 2) == "One more meets this week's goal. Or stop here for today.")
        #expect(NightCompleteCopy.weekDetail(done: 0, goal: 2) == "2 more meet this week's goal. Or stop here for today.")
        #expect(NightCompleteCopy.weekDetail(done: 2, goal: 2) == "Weekly goal met. Anything more is a bonus.")
        #expect(NightCompleteCopy.weekDetail(done: 4, goal: 2) == "Weekly goal met. Anything more is a bonus.")
    }

    @Test("The ring starts one arc back only when this lesson counts this week")
    func ringStart() {
        #expect(NightLessonWeek(done: 2, goal: 2, includesThisLesson: true).before == 1)
        #expect(NightLessonWeek(done: 2, goal: 2, includesThisLesson: false).before == 2)
        #expect(NightLessonWeek(done: 0, goal: 2, includesThisLesson: true).before == 0)
    }

    @Test("Up next, the primary button and the announcement follow the next stop")
    func nextStop() {
        let lesson = LessonCompleteOverlay.NextStop.lesson(number: 2, title: "Training data and where knowledge comes from")
        let check = LessonCompleteOverlay.NextStop.unitTest(unitNumber: "01", unitTitle: "How AI Actually Works")
        #expect(NightCompleteCopy.upNextEyebrow(lesson) == "Up next · Lesson 2")
        #expect(NightCompleteCopy.upNextTitle(lesson) == "Training data and where knowledge comes from")
        #expect(NightCompleteCopy.upNextEyebrow(check) == "Up next · Unit 1 check")
        #expect(NightCompleteCopy.upNextTitle(check) == "How AI Actually Works")
        #expect(NightCompleteCopy.primaryTitle(lesson) == "Start Lesson 2")
        #expect(NightCompleteCopy.primaryTitle(check) == "Take the Unit 1 Check")
        #expect(NightCompleteCopy.primaryTitle(nil) == nil)
        #expect(NightCompleteCopy.upNextAnnouncement(lesson)
                == "Up next: Lesson 2, Training data and where knowledge comes from.")
        #expect(NightCompleteCopy.upNextAnnouncement(check) == "Up next: the Unit 1 check.")
        #expect(NightCompleteCopy.upNextAnnouncement(nil) == nil)
    }

    // MARK: Honest copy

    static let banned: [String] = [
        "notebook", "saved", "rest day", #"part \d+ of \d+"#, #"beat \d"#, #"\b\d+\s?min\b"#, #"\bminutes?\b"#,
        "previewable", "pinned", "give me a hint", "nailed it", "call it a night", "never reset", "mastered",
    ]

    @Test("No line on the card promises a notebook, a saving, a time, or more than the lesson showed")
    func honestCopy() throws {
        let stops: [LessonCompleteOverlay.NextStop?] = [
            .lesson(number: 2, title: "Training data and where knowledge comes from"),
            .unitTest(unitNumber: "01", unitTitle: "How AI Actually Works"), nil,
        ]
        var lines = [NightCompleteCopy.lessonComplete, NightCompleteCopy.attribution, NightCompleteCopy.keyIdeasLabel,
                     NightCompleteCopy.moreKeyIdeas(1), NightCompleteCopy.doneForNow, NightCompleteCopy.doneForNowHelp,
                     NightCompleteCopy.share, NightCompleteCopy.shareHelp, NightCompleteCopy.keepReading,
                     NightCompleteCopy.eyebrow(unitLabel: "UNIT 01", lessonNumber: 1),
                     NightCompleteCopy.credential(objective: "Understand tokenization and next-token prediction.") ?? ""]
        for stop in stops {
            lines += [NightCompleteCopy.primaryTitle(stop), NightCompleteCopy.upNextAnnouncement(stop)].compactMap { $0 }
            if let stop { lines += [NightCompleteCopy.upNextEyebrow(stop), NightCompleteCopy.upNextTitle(stop)] }
        }
        for done in 0...4 {
            lines += [NightCompleteCopy.weekHeadline(done: done, goal: 2), NightCompleteCopy.weekDetail(done: done, goal: 2)]
        }
        for pattern in Self.banned {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for line in lines {
                #expect(regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil,
                        "“\(line)” matches /\(pattern)/")
            }
        }
    }

    @Test("The banned list catches the concept's and the old Mac card's own lines")
    func bannedListWorks() throws {
        for line in ["2 key ideas saved to your notebook", "Nailed it!",
                     "One more meets your weekly goal — or call it a night.", "about 6 min"] {
            let caught = try Self.banned.contains { pattern in
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            #expect(caught, "“\(line)” slipped through")
        }
    }
}

/// The chat's Quiz me sheet on the Mac: the shared row's marks.
@Suite("Night quiz sheet")
struct NightQuizSheetTests {
    @Test("Before Submit a row is picked or not; after, right, wrong or neither")
    func marks() {
        #expect(NightQuizSheet.mark(letter: "B", selection: "B", answer: "C", submitted: false) == .picked)
        #expect(NightQuizSheet.mark(letter: "A", selection: "B", answer: "C", submitted: false) == .rest)
        #expect(NightQuizSheet.mark(letter: "C", selection: "C", answer: "C", submitted: true) == .correct(picked: true))
        #expect(NightQuizSheet.mark(letter: "C", selection: "B", answer: "C", submitted: true) == .correct(picked: false))
        #expect(NightQuizSheet.mark(letter: "B", selection: "B", answer: "C", submitted: true) == .wrong)
        #expect(NightQuizSheet.mark(letter: "A", selection: "B", answer: "C", submitted: true) == .other)
    }

    @Test("A server option's own letter is dropped once")
    func strippedOption() {
        #expect(NightQuizSheet.strippedOption("A) Tokens", letter: "A") == "Tokens")
        #expect(NightQuizSheet.strippedOption("B. Tokens", letter: "B") == "Tokens")
        #expect(NightQuizSheet.strippedOption("Tokens", letter: "A") == "Tokens")
        #expect(NightQuizSheet.strippedOption("B) Tokens", letter: "A") == "B) Tokens")
    }
}
#endif
