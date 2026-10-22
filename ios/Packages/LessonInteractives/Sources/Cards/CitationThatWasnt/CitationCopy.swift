import Foundation

/// Every line The Citation That Wasn't shows or speaks, on both platforms
/// (docs/interactives/citation-that-wasnt/CONTENT.md §1 lists them all).
/// Held to `InteractiveCopyRules` by `CitationThatWasntTests`: intent words
/// ("decided") appear only in `predictionLines`, the prediction and the
/// reveal that refutes it.
public enum CitationCopy {
    public static let title = "The citation that wasn\u{2019}t"

    /// The Mac's compact card (narrower than 440 pt).
    public static let compactLine = "Be the model: write a study\u{2019}s reference one likely piece at a time, and see how a source that never existed gets written."

    // MARK: The hook

    public static let studentQuestion = "Can you give me a study showing that houseplants help students concentrate?"
    public static let studentAccessibility = "A student asks: \(studentQuestion)"
    public static let replyEyebrow = "Example reply, written for this lesson"
    public static let replyOpening = "Sure, here\u{2019}s one:"

    // MARK: The labels (on the canvas, never a footnote)

    /// Under the example reply. SLATE.md's first and third labels.
    public static let replyLabel = InteractiveLabel(
        .example,
        "Example, written for this lesson. Every name in this reference is invented. Writing from memory, with no search."
    )
    /// Beside the bars. SLATE.md's first label's last sentence, and its
    /// second label.
    public static let chancesLabel = InteractiveLabel(
        .illustrative,
        "The chances are illustrative, not from a real model. Shown a few words at a time; real models go one small piece (token) at a time."
    )

    public static let labels: [InteractiveLabel] = [replyLabel, chancesLabel]

    /// The slate's three on-card labels, sentence by sentence: each one is
    /// in `labels` word for word (a test holds this).
    public static let slateLabelSentences: [String] = [
        "Example, written for this lesson.",
        "Every name in this reference is invented.",
        "The chances are illustrative, not from a real model.",
        "Shown a few words at a time; real models go one small piece (token) at a time.",
        "Writing from memory, with no search.",
    ]

    // MARK: The slots

    public static func slotName(_ slot: CitationSlot) -> String {
        switch slot {
        case .firstAuthor: return "First author"
        case .year: return "Year"
        case .title: return "Title"
        case .journal: return "Journal"
        case .volumeAndPages: return "Volume and pages"
        }
    }

    /// The step strip's short names.
    public static func slotShortName(_ slot: CitationSlot) -> String {
        switch slot {
        case .firstAuthor: return "Author"
        case .year: return "Year"
        case .title: return "Title"
        case .journal: return "Journal"
        case .volumeAndPages: return "Pages"
        }
    }

    /// The empty slot in the reference, before its piece is written.
    public static func placeholder(_ slot: CitationSlot) -> String {
        switch slot {
        case .firstAuthor: return "[author]"
        case .year: return "[year]"
        case .title: return "[title]"
        case .journal: return "[journal]"
        case .volumeAndPages: return "[volume, pages]"
        }
    }

    /// Under each slot's three bars: the rest of the chances.
    public static func moreLine(_ slot: CitationSlot) -> String {
        switch slot {
        case .firstAuthor: return "+ many more names"
        case .year: return "+ other years"
        case .title: return "+ many more titles"
        case .journal: return "+ many more journals"
        case .volumeAndPages: return "+ many more numbers"
        }
    }

    // MARK: Be the model

    public static let walkHeading = "Be the model"
    /// "Pick", not "tap": the Mac clicks and keys.
    public static let walkPrompt = "Pick the piece you think gets written next."
    /// "Step 2 of 5 · Year". "Step 2 of 5 ·" holds together (its spaces
    /// don't break), so at the accessibility sizes the line breaks only
    /// before the slot's name, never inside the count or before the dot.
    public static func stepHeading(_ walk: CitationWalk) -> String {
        let position = walk.steps.position.replacingOccurrences(of: " ", with: "\u{00A0}")
        return "\(position)\u{00A0}\u{00B7} \(slotName(walk.slot))"
    }

    public static let pickedTag = "picked"
    public static let guessTag = "your guess"

    /// After a guess: what the model drew.
    public static func drawnLine(_ walk: CitationWalk, slot: CitationSlot) -> String {
        let piece = CitationContent.candidates(slot)[walk.pick(slot)].text
        if walk.guessMatched(slot) == true {
            return "The model drew \(piece) this time, the same as your guess."
        }
        return "The model drew \(piece) this time."
    }

    /// When the pick isn't the top bar.
    public static let notTopLine = "Drawn by chance, not always the top bar."

    public static let nextPiece = "Next piece"
    public static let finishWalk = "See the finished reference"

    public static let finishedHeading = "The five pieces it drew"
    public static let finishedCaption = "The finished text looks equally sure at every step."

    // MARK: Predict, then reveal

    public static let predictionPrompt = "This study doesn\u{2019}t exist. At which step did the model decide to make it up?"

    public static func choiceTitle(_ choice: CitationStepGuess) -> String {
        switch choice {
        case .author: return "The author"
        case .journal: return "The journal"
        case .pageNumbers: return "The page numbers"
        case .noStep: return "No step did"
        }
    }

    public static let revealResult = "No step did. None of these steps chose to invent it, and none of them checks that the source is real. Each piece was just a likely next piece."
    /// Said as the reveal appears (SLATE.md's VoiceOver line).
    public static let revealAnnouncement = "No step decided to make it up. Each piece was a likely next piece, and no step checks that the source is real."
    public static let topicNote = "There may be real research on this question. This reference isn\u{2019}t part of it."

    // MARK: Write it again

    public static let rewrite = "Write it again"
    public static let rewriteHint = "Draws another reference from the same chances"
    public static let askedAgain = "The same question, asked again"
    public static let rewriteCaption = "A model draws from these chances, so the same question can get a different made-up source."

    // MARK: The takeaway

    public static let takeawayHeading = "Likely isn\u{2019}t true."
    public static let takeaway = "In Mata v. Avianca (2023), lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000."

    // MARK: VoiceOver

    /// A candidate, as a radio choice: "First author. Quillfeather, T., 12
    /// percent, illustrative, 1 of 3."
    public static func candidateAccessibility(_ slot: CitationSlot, index: Int) -> String {
        let list = CitationContent.candidates(slot)
        let candidate = list[index]
        return "\(slotName(slot)). \(candidate.spoken), \(candidate.percent) percent, illustrative, \(index + 1) of \(list.count)."
    }

    /// A candidate's state once its slot is drawn.
    public static func candidateValue(_ walk: CitationWalk, slot: CitationSlot, index: Int) -> String {
        guard walk.isDrawn(slot) else { return "" }
        let picked = walk.pick(slot) == index
        let guessed = walk.guess(at: slot) == index
        switch (picked, guessed) {
        case (true, true): return "\(guessTag), \(pickedTag)"
        case (true, false): return pickedTag
        case (false, true): return guessTag
        case (false, false): return ""
        }
    }

    /// The slot strip: "Step 2 of 5, Year. Written: First author."
    public static func stripAccessibility(_ walk: CitationWalk) -> String {
        let done = CitationSlot.allCases.filter { walk.isDrawn($0) && $0 != walk.slot }.map(slotName)
        let written = done.isEmpty ? "" : " Written: \(done.joined(separator: ", "))."
        return "\(walk.steps.position), \(slotName(walk.slot)).\(written)"
    }

    /// The reference as it stands, for VoiceOver.
    public static func referenceAccessibility(_ picks: [Int?]) -> String {
        let pieces = CitationSlot.allCases.map { slot in
            picks[slot.rawValue].map { CitationContent.candidates(slot)[$0].spoken }
        }
        let written = pieces.compactMap { $0 }
        let missing = CitationSlot.allCases.filter { pieces[$0.rawValue] == nil }.map { slotName($0).lowercased() }
        var line = "\(replyEyebrow). \(replyOpening)"
        if !written.isEmpty { line += " \(written.joined(separator: ", "))." }
        if !missing.isEmpty { line += " Not written yet: \(missing.joined(separator: ", "))." }
        return line
    }

    /// Announced after a guess: what was drawn and the reference so far.
    public static func drawAnnouncement(_ walk: CitationWalk, slot: CitationSlot) -> String {
        var line = drawnLine(walk, slot: slot)
        if !CitationContent.isTopBar(path: walk.path, slot: slot) { line += " " + notTopLine }
        if walk.isComplete {
            line += " The reference is finished: \(CitationContent.spokenReference(path: walk.path))"
        }
        return line
    }

    /// A row of the five drawn pieces: "Year: 2018, 21 percent, picked."
    public static func pickRowAccessibility(path: Int, slot: CitationSlot) -> String {
        let candidate = CitationContent.picked(path: path, slot: slot)
        return "\(slotName(slot)): \(candidate.spoken), \(candidate.percent) percent, \(pickedTag)."
    }

    public static func finishedAnnouncement(path: Int) -> String {
        "The finished reference: \(CitationContent.spokenReference(path: path)) \(finishedCaption)"
    }

    public static func rewriteAnnouncement() -> String {
        let path = CitationContent.rewritePath
        return "Written again: \(CitationContent.spokenReference(path: path)) \(rewriteCaption)"
    }

    /// The card's state in one sentence (the title's VoiceOver value).
    public static func accessibilitySummary(walk: CitationWalk, guess: CitationStepGuess?, revealed: Bool,
                                            spoiled: Bool, rewritten: Bool) -> String {
        if rewritten {
            return "Written again, from the same chances: \(CitationContent.spokenReference(path: CitationContent.rewritePath)) A different made-up source."
        }
        if revealed {
            return "No step made it up: each piece was a likely next piece, and no step checks that the source is real."
        }
        if walk.finished {
            if let guess { return "Your guess: \(choiceTitle(guess)). Show me is next." }
            return spoiled ? finishedCaption : "The reference is finished, and it looks equally sure at every step. Next, guess the step that made it up."
        }
        let slot = walk.slot
        if walk.isDrawn(slot) {
            let candidate = CitationContent.picked(path: walk.path, slot: slot)
            let rank = CitationContent.rank(of: walk.pick(slot), in: slot)
            let bar = rank == 1 ? "the top bar" : "bar \(rank) of \(CitationContent.candidates(slot).count)"
            return "\(walk.steps.position), \(slotName(slot)): the model drew \(candidate.spoken), at \(candidate.percent) percent, \(bar)."
        }
        return "\(walk.steps.position), \(slotName(slot)): \(walkPrompt)"
    }

    // MARK: The rules' lists

    /// The prediction and the reveal lines that refute it: the only lines
    /// that may say "decided" or "chose".
    public static var predictionLines: [String] {
        [predictionPrompt, revealResult, revealAnnouncement] + CitationStepGuess.allCases.map(choiceTitle)
    }

    /// Every line the card shows or speaks (with its variable lines filled
    /// in for every slot, both paths and every state).
    public static var everyLine: [String] {
        var lines: [String] = [
            title, compactLine, studentQuestion, studentAccessibility, replyEyebrow, replyOpening,
            walkHeading, walkPrompt, pickedTag, guessTag, notTopLine, nextPiece, finishWalk,
            finishedHeading, finishedCaption, predictionPrompt, revealResult, revealAnnouncement, topicNote,
            rewrite, rewriteHint, askedAgain, rewriteCaption, takeawayHeading, takeaway,
            finishedAnnouncement(path: 0), rewriteAnnouncement(),
        ]
        lines += labels.map(\.text)
        lines += CitationStepGuess.allCases.map(choiceTitle)
        for slot in CitationSlot.allCases {
            lines += [slotName(slot), slotShortName(slot), placeholder(slot), moreLine(slot)]
            for index in CitationContent.candidates(slot).indices {
                lines.append(candidateAccessibility(slot, index: index))
            }
            for path in CitationContent.paths.indices {
                lines.append(pickRowAccessibility(path: path, slot: slot))
            }
        }
        for walk in everyWalkState {
            lines.append(stepHeading(walk))
            lines.append(stripAccessibility(walk))
            lines.append(referenceAccessibility(walk.picks))
            for slot in CitationSlot.allCases where walk.isDrawn(slot) {
                lines.append(drawnLine(walk, slot: slot))
                lines.append(drawAnnouncement(walk, slot: slot))
                for index in CitationContent.candidates(slot).indices {
                    lines.append(candidateValue(walk, slot: slot, index: index))
                }
            }
            for guess in [nil] + CitationStepGuess.allCases.map(Optional.some) {
                for (revealed, spoiled, rewritten) in [(false, false, false), (false, true, false),
                                                       (true, false, false), (true, false, true)] {
                    lines.append(accessibilitySummary(walk: walk, guess: guess, revealed: revealed,
                                                      spoiled: spoiled, rewritten: rewritten))
                }
            }
        }
        return lines.filter { !$0.isEmpty }
    }

    /// Every walk state a student can reach: before and after each guess
    /// (each of the three guesses), and finished.
    static var everyWalkState: [CitationWalk] {
        var states: [CitationWalk] = []
        func explore(_ walk: CitationWalk) {
            states.append(walk)
            if walk.canGuess {
                for index in CitationContent.candidates(walk.slot).indices {
                    var next = walk
                    next.guess(index)
                    // One branch per guess at this slot; later slots follow
                    // the top guess only, which keeps the list small while
                    // every drawn line at every slot is still reached.
                    if index == 0 { explore(next) } else { states.append(next) }
                }
            } else if walk.canAdvance {
                var next = walk
                next.advance()
                explore(next)
            }
        }
        explore(CitationWalk())
        return states
    }
}
