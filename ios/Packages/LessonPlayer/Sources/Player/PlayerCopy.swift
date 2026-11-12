import Foundation

/// The player's own words (lesson content is in `Content/`).
enum PlayerCopy {
    static let finishForNow = "Finish for now"
    static let finishForNowHint = "Saves your place. You can come back to this step."
    static let keyIdea = "Key idea"
    static let fictional = "Fictional practice material"
    static func realSource(_ citation: String) -> String { "Real case: \(citation)" }
    static let youPracticed = "WHAT YOU PRACTICED"
    static let upNext = "UP NEXT"

    static let check = "Check answer"
    static let `continue` = "Continue"
    static let tryAgain = "Try again"
    static let revise = "Revise your answer"
    static let retry = "Retry"
    static let editAnswer = "Edit your answer"
    static let checking = "Checking…"
    static let cancel = "Cancel"
    static let finish = "Finish"
    static let showHint = "Show a hint"
    static let hint = "Hint"

    static let correct = "Correct"
    static let partly = "Partly right"
    static let notQuite = "Not quite"
    static let notGradedYet = "Not graded yet"
    static let mercReplied = "Merc replied"
    static let send = "Send"
    static let waitingForMerc = "Waiting for Merc…"
    static func useSuggestion(_ text: String) -> String { "Use this: “\(text)”" }

    static let option = "Option"
    static let selected = "Selected"
    static let correctAnswer = "Correct answer"
    static let yourCorrectAnswer = "Your answer, correct"
    static let yourWrongAnswer = "Your answer, not correct"
    static let chooseAll = "Choose all that apply."
    static let chooseClaim = "Choose the claim:"

    static let goDeeper = "Go deeper"
    static let goDeeperMore = "Go deeper still"
    static let askMerc = "Ask Merc"
    static let backToLesson = "Back to the lesson"
    static let supportShown = "Your answer is saved and wasn’t graded. Come back to it whenever you’re ready."
    static let askMercHint = "Opens a chat with Merc. Your place in the lesson is kept."

    static func letter(_ index: Int) -> String { String(UnicodeScalar(65 + index) ?? "?") }

    static func progress(_ done: Int, _ total: Int) -> String { "\(done) of \(total) done" }

    static func characters(_ count: Int, of max: Int) -> String { "\(count) of \(max) characters" }

    /// After a miss, the right answer, plainly. (The right answer's own
    /// feedback starts "Right." or "Yes.", which reads wrong after a miss; the
    /// missed option's feedback already explains.)
    static func revealed(_ answer: String) -> String { "The right answer: \(answer)." }

    static func exemplar(_ text: String) -> String {
        "Here’s one sound answer, to compare with yours: “\(text)” Now write your own version."
    }

    /// A line on the finish step about how the lesson went, or nil.
    static func success(_ level: SuccessLevel) -> String? {
        switch level {
        case .independent: return "You got every check right the first time."
        case .assisted: return "You worked through it, with a hint or a second try along the way."
        case .notDemonstrated: return nil
        }
    }
}
