import Testing
@testable import LessonPlayer

@Suite("Player copy")
struct PlayerCopyTests {

    @Test("The revealed answer gets a full stop only when it doesn't already end a sentence")
    func revealedPunctuation() {
        // Basics 1.1's postcard step: the answer is a question.
        #expect(PlayerCopy.revealed("What’s a good soup for a cold day?") == "The right answer: What’s a good soup for a cold day?")
        #expect(PlayerCopy.revealed("Find the original study and read what it found") == "The right answer: Find the original study and read what it found.")
        #expect(PlayerCopy.revealed("It stops here.") == "The right answer: It stops here.")
        #expect(PlayerCopy.revealed("Wow!") == "The right answer: Wow!")
        // Claim picks are quoted: the quote's own punctuation counts.
        #expect(PlayerCopy.revealed("“students remembered 34% more words”") == "The right answer: “students remembered 34% more words”.")
        #expect(PlayerCopy.revealed("“Is it real?”") == "The right answer: “Is it real?”")
    }

    @Test("Every authored option and claim reads cleanly when revealed")
    func noDoublePunctuationInContent() {
        for lesson in LessonCatalog.all {
            for step in lesson.steps {
                guard let activity = step.activity else { continue }
                var answers: [String] = []
                switch activity.kind {
                case .choice(let c): answers = c.options.filter { c.correct.contains($0.id) }.map(\.text)
                case .claimSelection(let s): answers = s.claims.filter { s.correct.contains($0.claimId ?? "") }.map { "“\($0.text)”" }
                default: continue
                }
                let line = PlayerCopy.revealed(answers.joined(separator: "; "))
                for bad in ["?.", "!.", "..", "….", "?”.", "!”.", ".”."] {
                    #expect(!line.hasSuffix(bad), "\(lesson.lessonId) \(step.id): \(line)")
                }
            }
        }
    }
}
