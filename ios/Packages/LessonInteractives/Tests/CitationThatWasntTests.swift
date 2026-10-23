import Foundation
import Testing
@testable import LessonInteractives

/// The Citation That Wasn't (u1_l3): content, copy, state and VoiceOver.
/// The fifteen chances are asserted against the slate's values, typed in
/// here (slate.json lives outside the repo, so that comparison was done by
/// hand; CONTENT.md §2). Everything built from them is re-derived: the
/// ranks, the picks, both references, the counts, and every chance a line
/// quotes (the reveal's answers, the finished caption's range, the
/// rewrite's first draw).
@Suite("The Citation That Wasn't: content")
struct CitationContentTests {
    @Test("Five slots, three candidates each, with the slate's chances")
    func slots() {
        #expect(CitationSlot.allCases.count == 5)
        #expect(CitationContent.candidates.count == 5)
        #expect(CitationContent.candidates.allSatisfy { $0.count == 3 })
        // The slate's data.slots, in order, typed in (the chances are
        // authored and illustrative; no model produced them).
        let percents = CitationContent.candidates.map { $0.map(\.percent) }
        #expect(percents == [[12, 11, 9], [24, 21, 19], [62, 14, 8], [41, 22, 10], [8, 7, 7]])
        #expect(CitationContent.displayedPercents == percents.flatMap { $0 })
        // Each slot's three chances leave room for "+ many more": none
        // reaches 100%, and every chance is a real share.
        for slot in CitationSlot.allCases {
            let shown = CitationContent.candidates(slot).map(\.percent)
            #expect(shown.allSatisfy { $0 > 0 && $0 < 100 })
            #expect(shown.reduce(0, +) < 100, "\(slot)")
            #expect(shown == shown.sorted(by: >), "\(slot): the bars are listed from the top")
        }
    }

    @Test("The slate's names and pieces, with the two changes CONTENT.md records")
    func names() {
        let texts = CitationContent.candidates.map { $0.map(\.text) }
        #expect(texts[0] == ["Quillfeather, T.", "Ambervale, R.", "Fernwhistle, M."])
        #expect(texts[1] == ["2019", "2018", "2020"])
        #expect(texts[2] == ["Houseplants and attention in secondary-school classrooms",
                             "Indoor plants and student focus: a classroom study",
                             "Classroom greenery and adolescent attention: a pilot study"])
        #expect(texts[3] == ["Journal of Classroom Ecology", "Indoor Learning Review", "Bulletin of School Botany"])
        #expect(texts[4] == ["14(3), 211\u{2013}229", "9(2), 45\u{2013}61", "22(1), 102\u{2013}118"])
        // Replaced after the name search: Thistlewood is a real surname
        // with published researchers. The real journals the slate warns
        // about are not used either.
        let all = texts.flatMap { $0 }.joined(separator: " ")
        for real in ["Thistlewood", "Marlow", "Ishida", "Journal of Learning Spaces", "Learning Environments Research"] {
            #expect(!all.contains(real), "\(real)")
        }
    }

    @Test("Both paths use only listed candidates, and give the slate's references")
    func paths() {
        #expect(CitationContent.paths == [[0, 1, 0, 0, 0], [1, 0, 1, 1, 1]])
        for path in CitationContent.paths {
            #expect(path.count == 5)
            for slot in CitationSlot.allCases {
                #expect(CitationContent.candidates(slot).indices.contains(path[slot.rawValue]))
            }
        }
        #expect(CitationContent.reference(path: 0)
                == "Quillfeather, T. (2018). Houseplants and attention in secondary-school classrooms. Journal of Classroom Ecology, 14(3), 211\u{2013}229.")
        #expect(CitationContent.reference(path: 1)
                == "Ambervale, R. (2019). Indoor plants and student focus: a classroom study. Indoor Learning Review, 9(2), 45\u{2013}61.")
        // "Write it again" draws a different reference: every piece differs.
        for slot in CitationSlot.allCases {
            #expect(CitationContent.pick(path: 0, slot: slot) != CitationContent.pick(path: 1, slot: slot))
        }
    }

    @Test("The bars' ranks: the walk draws the top bar except at the year (the second bar)")
    func ranks() {
        #expect(CitationContent.notTopSlots(path: 0) == [.year])
        #expect(CitationContent.rank(of: 1, in: .year) == 2)
        #expect(CitationContent.picked(path: 0, slot: .year).text == "2018")
        // The second path draws a lower bar at four of the five slots.
        #expect(CitationContent.notTopSlots(path: 1) == [.firstAuthor, .title, .journal, .volumeAndPages])
        // A tie keeps the order shown: 9(2) and 22(1) are both 7%.
        #expect(CitationContent.rank(of: 1, in: .volumeAndPages) == 2)
        #expect(CitationContent.rank(of: 2, in: .volumeAndPages) == 3)
        for slot in CitationSlot.allCases {
            let ranks = CitationContent.candidates(slot).indices.map { CitationContent.rank(of: $0, in: slot) }
            #expect(ranks == [1, 2, 3], "\(slot)")
        }
    }

    @Test("The takeaway's numbers are the lesson guide's (Mata v. Avianca, row 13)")
    func guideNumbers() {
        #expect(CitationContent.guideMata.contains("(\(CitationContent.mataYear))"))
        #expect(CitationContent.guideMata.contains("$5,000"))
        #expect(CitationContent.mataFine == 5_000)
        // The takeaway calls back to the guide's case by name and year
        // (Merc's reply above the card gives the rest): its only number.
        #expect(CitationCopy.takeaway.contains("Mata v. Avianca (\(CitationContent.mataYear))"))
        let numbers = CitationCopy.takeaway.split(whereSeparator: { !$0.isNumber && $0 != "," })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }.filter { !$0.isEmpty }
        #expect(numbers == ["2023"])
    }

    @Test("Every chance a line quotes is re-derived from the paths")
    func quotedChances() {
        // The walk's lowest and highest drawn chances: the pages and the
        // title.
        #expect(CitationContent.leastLikely(path: 0) == .volumeAndPages)
        #expect(CitationContent.mostLikely(path: 0) == .title)
        let low = CitationContent.picked(path: 0, slot: .volumeAndPages).percent
        let high = CitationContent.picked(path: 0, slot: .title).percent
        let author = CitationContent.picked(path: 0, slot: .firstAuthor).percent
        let journal = CitationContent.picked(path: 0, slot: .journal).percent
        let quoted: [Int] = [low, high, author, journal]
        #expect(quoted == [8, 62, 12, 41])
        let drawn = CitationSlot.allCases.map { CitationContent.picked(path: 0, slot: $0).percent }
        #expect(drawn.min() == Optional(low) && drawn.max() == Optional(high))
        // The finished caption: the range, not "equally sure" alone.
        #expect(CitationCopy.finishedCaption
                == "Its chances ran from \(low)% to \(high)%, but the finished text looks equally sure at every step.")
        // The reveal's answers quote only the walk's own chances.
        #expect(CitationCopy.revealAnswer(.author).contains("(\(author)%)"))
        #expect(CitationCopy.revealAnswer(.journal).contains("(\(journal)%)")
                && CitationCopy.revealAnswer(.journal).contains("(\(author)%)"))
        #expect(CitationCopy.revealAnswer(.pageNumbers).contains("(\(low)%)")
                && CitationCopy.revealAnswer(.pageNumbers).contains("(\(high)%)"))
        #expect(CitationCopy.revealAnswer(.noStep).contains("at \(low)% or at \(high)%"))
        #expect(CitationCopy.revealAnswer(nil) == CitationCopy.revealAnswer(.noStep))
        // The rewrite's first draw against step 1's bars: Ambervale (11%)
        // for Quillfeather (12%). Only the first slot: its chances are the
        // only ones a second try shares.
        let again = CitationContent.picked(path: CitationContent.rewritePath, slot: .firstAuthor)
        let before = CitationContent.picked(path: 0, slot: .firstAuthor)
        let firstDraws: [Int] = [again.percent, before.percent]
        #expect(firstDraws == [11, 12])
        #expect(CitationCopy.rewriteNote.contains("\(again.text) (\(again.percent)%)"))
        #expect(CitationCopy.rewriteNote.contains("not \(before.text) (\(before.percent)%)"))
        for other in CitationSlot.allCases where other != .firstAuthor {
            let percent = CitationContent.picked(path: CitationContent.rewritePath, slot: other).percent
            #expect(!CitationCopy.rewriteNote.contains("\(percent)%"), "\(other): a later slot's chance")
        }
        // Nothing claims a second try reuses every step's chances.
        for line in CitationCopy.everyLine {
            #expect(!line.contains("same chances"), "\(line)")
        }
    }

    @Test("Every number on the card is a listed chance, a step count or the guide's two numbers")
    func everyNumberAccountedFor() {
        let allowed = Set(CitationContent.displayedPercents)
            .union(1...5)   // "Step 2 of 5", "1 of 3", "bar 2 of 3"
            .union([2018, 2019, 2020, 2023, 5000])
            // Volume, issue and page numbers inside the invented references.
            .union([14, 3, 211, 229, 9, 2, 45, 61, 22, 1, 102, 118])
        for line in CitationCopy.everyLine {
            let numbers = line.replacingOccurrences(of: ",000", with: "000")
                .split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            for number in numbers {
                #expect(allowed.contains(number), "\(number) in \"\(line)\"")
            }
        }
    }
}

@Suite("The Citation That Wasn't: the walk")
struct CitationWalkTests {
    @Test("A guess draws the model's pick whatever was guessed; the walk goes forward only when asked")
    func walk() {
        var walk = CitationWalk()
        #expect(walk.slot == .firstAuthor && walk.canGuess && !walk.canAdvance)
        let early = walk.advance()
        #expect(!early, "no next piece before a guess")
        let outside = walk.guess(3)
        #expect(!outside, "not a candidate")
        let first = walk.guess(2)
        #expect(first)
        #expect(walk.isDrawn(.firstAuthor) && walk.guessMatched(.firstAuthor) == false)
        #expect(walk.picks.first == 0, "the model drew Quillfeather, T.")
        let second = walk.guess(0)
        #expect(!second, "a drawn slot takes no second guess")
        #expect(walk.slot == .firstAuthor, "the next slot waits for a tap")
        let moved = walk.advance()
        #expect(moved && walk.slot == .year)
        for _ in 1..<5 {
            let guessed = walk.guess(0)
            let advanced = walk.advance()
            #expect(guessed && advanced)
        }
        #expect(walk.finished && walk.isComplete && walk.drawnCount == 5)
        #expect(walk.picks == CitationContent.paths[0].map(Optional.some))
        #expect(!walk.canGuess && !walk.canAdvance)
    }

    @Test("The reference grows piece by piece, from the picks")
    func pieces() {
        var walk = CitationWalk()
        #expect(CitationContent.pieces(walk.picks) == [nil, nil, nil, nil, nil])
        walk.guess(0)
        walk.advance()
        walk.guess(0)
        #expect(CitationContent.pieces(walk.picks) == ["Quillfeather, T.", "2018", nil, nil, nil])
        #expect(walk.guessMatched(.year) == false, "guessed 2019, drew 2018")
    }

    @Test("The DEBUG walks are walks a student could make (top bar guessed)")
    func debugWalks() {
        let atYear = CitationWalk.walked(through: .year)
        #expect(atYear.slot == .year && atYear.isDrawn(.year) && !atYear.finished)
        #expect(atYear.guess(at: .year) == 0 && atYear.pick(.year) == 1)
        let done = CitationWalk.walked(through: .volumeAndPages, finished: true)
        #expect(done.finished && done.guesses == [0, 0, 0, 0, 0])
    }

    @Test("The Mac's arrows move between a slot's candidates and stop at the ends")
    func arrows() {
        #expect(CitationContent.neighbour(of: 0, moving: .next, in: .year) == 1)
        #expect(CitationContent.neighbour(of: 2, moving: .next, in: .year) == 2)
        #expect(CitationContent.neighbour(of: 1, moving: .previous, in: .title) == 0)
        #expect(CitationContent.neighbour(of: 0, moving: .previous, in: .title) == 0)
    }

    @Test("Step positions come from the shared step-through block")
    func steps() {
        var walk = CitationWalk()
        #expect(walk.steps.position == "Step 1 of 5")
        walk.guess(1)
        walk.advance()
        #expect(walk.steps.position == "Step 2 of 5")
        #expect(CitationCopy.stepHeading(walk) == "Step\u{00A0}2\u{00A0}of\u{00A0}5\u{00A0}\u{00B7} Year")
        // It reads as the step strip's words, its spaces held together.
        #expect(CitationCopy.stepHeading(walk).replacingOccurrences(of: "\u{00A0}", with: " ") == "Step 2 of 5 \u{00B7} Year")
    }
}

@Suite("The Citation That Wasn't: words")
struct CitationCopyTests {
    @Test("Every line keeps the register; intent words only in the prediction lines")
    func register() {
        let found = InteractiveCopyRules.violations(in: CitationCopy.everyLine, card: .citationThatWasnt,
                                                    predictionLines: CitationCopy.predictionLines)
        #expect(found.isEmpty, "\(found)")
        // "decided" is said only by the question and the reveal that
        // refutes it (spoken, and in the card's one-sentence state).
        let deciding = CitationCopy.everyLine.filter { $0.range(of: #"\bdecide"#, options: .regularExpression) != nil }
        let refuting = CitationCopy.everyRevealGuess.map(CitationCopy.revealAnnouncement)
        #expect(Set(deciding) == Set([CitationCopy.predictionPrompt, CitationCopy.revealedSummary] + refuting))
        #expect(refuting.allSatisfy { $0.hasPrefix(CitationCopy.revealAnnouncementOpening) })
        #expect(CitationCopy.revealedSummary.hasPrefix("No step decided to make it up"))
        // No other intent words anywhere (knows, lies, wants…), the
        // prediction included.
        let others = InteractiveCopyRules.violations(in: CitationCopy.everyLine, card: .citationThatWasnt,
                                                     predictionLines: [CitationCopy.revealedSummary] + refuting)
        #expect(others.isEmpty, "\(others)")
    }

    @Test("The slate's labels are on the canvas, each with its kind")
    func labels() {
        #expect(InteractiveCopyRules.missingLabels([.example, .illustrative], in: CitationCopy.labels).isEmpty)
        #expect(CitationCopy.labels.allSatisfy { $0.isWellFormed })
        let text = CitationCopy.labels.map(\.text).joined(separator: " ")
        for sentence in CitationCopy.slateLabelSentences {
            #expect(text.contains(sentence), "\(sentence)")
        }
        // Every chance the card prints is labelled illustrative where it is
        // drawn, and in what VoiceOver says.
        for slot in CitationSlot.allCases {
            for index in 0..<3 {
                #expect(CitationCopy.candidateAccessibility(slot, index: index).contains("illustrative"))
            }
        }
    }

    @Test("The reveal says no step did, answers the guess, and says only that this reference isn't real")
    func reveal() {
        for guess in CitationCopy.everyRevealGuess {
            let result = CitationCopy.revealResult(guess)
            #expect(result.hasPrefix("No step did."), "\(String(describing: guess))")
            #expect(result.contains("none of them checks that the source is real"))
            #expect(result.hasSuffix(CitationCopy.revealAnswer(guess)))
            // Never a score.
            let lower = result.lowercased()
            for word in ["right", "wrong", "correct", "score"] {
                #expect(!lower.contains(word), "\(word) in \(result)")
            }
        }
        // Each answer is its own: a low-bar guess hears that a likelier
        // piece is just as made up.
        #expect(Set(CitationStepGuess.allCases.map(CitationCopy.revealAnswer)).count == CitationStepGuess.allCases.count)
        #expect(CitationCopy.revealAnswer(.pageNumbers).contains("just as made up"))
        #expect(CitationCopy.revealAnswer(.journal).contains("as made up as the author"))
        #expect(CitationCopy.topicNote.contains("may be real research"))
        // The takeaway's heading can't read as "probably isn't true".
        #expect(CitationCopy.takeawayHeading == "Likely isn\u{2019}t the same as true.")
        // Never that low chances mark the made-up part, or that the topic
        // is unstudied.
        for line in CitationCopy.everyLine {
            let lower = line.lowercased()
            #expect(!lower.contains("low chance"), "\(line)")
            #expect(!lower.contains("unstudied") && !lower.contains("no research"), "\(line)")
        }
    }

    @Test("VoiceOver: each candidate is one of three with its chance; the slate's lines")
    func voiceOver() {
        #expect(CitationCopy.candidateAccessibility(.firstAuthor, index: 0)
                == "First author. Quillfeather, T., 12 percent, illustrative, 1 of 3.")
        #expect(CitationCopy.candidateAccessibility(.volumeAndPages, index: 0)
                == "Volume and pages. volume 14, issue 3, pages 211 to 229, 8 percent, illustrative, 1 of 3.")
        #expect(CitationCopy.revealAnnouncement(.noStep)
                == "No step decided to make it up, and no step checks that the source is real. Each piece, at 8% or at 62%, was just one of the likeliest next pieces.")
        let walk = CitationWalk.walked(through: .year)
        #expect(CitationCopy.candidateValue(walk, slot: .year, index: 0) == "your guess")
        #expect(CitationCopy.candidateValue(walk, slot: .year, index: 1) == "picked")
        #expect(CitationCopy.candidateValue(walk, slot: .year, index: 2) == "")
        #expect(CitationCopy.referenceAccessibility(walk.picks)
                == "Example reply, written for this lesson. Sure, here\u{2019}s one: Quillfeather, T., 2018. Not written yet: title, journal, volume and pages.")
    }

    @Test("A summary for every state, saying the number it shows")
    func summaries() {
        for slot in CitationSlot.allCases {
            var walk = CitationWalk.walked(through: slot)
            let line = CitationCopy.accessibilitySummary(walk: walk, guess: nil, revealed: false, spoiled: false,
                                                         rewritten: false)
            let pick = CitationContent.picked(path: 0, slot: slot)
            #expect(InteractiveAccessibility.numbersMissing([pick.percent], from: line).isEmpty, "\(line)")
            if slot != .volumeAndPages {
                walk.advance()
                let waiting = CitationCopy.accessibilitySummary(walk: walk, guess: nil, revealed: false,
                                                                spoiled: false, rewritten: false)
                #expect(waiting.contains(CitationCopy.walkPrompt))
            }
        }
        let year = CitationCopy.accessibilitySummary(walk: .walked(through: .year), guess: nil, revealed: false,
                                                     spoiled: false, rewritten: false)
        #expect(year == "Step 2 of 5, Year: the model drew 2018, at 21 percent, the 2nd likeliest of 3.")
        let author = CitationCopy.accessibilitySummary(walk: .walked(through: .firstAuthor), guess: nil, revealed: false,
                                                       spoiled: false, rewritten: false)
        #expect(author.hasSuffix("at 12 percent, the likeliest."))
        let done = CitationWalk.walked(through: .volumeAndPages, finished: true)
        let states = [
            CitationCopy.accessibilitySummary(walk: done, guess: nil, revealed: false, spoiled: false, rewritten: false),
            CitationCopy.accessibilitySummary(walk: done, guess: .author, revealed: false, spoiled: false, rewritten: false),
            CitationCopy.accessibilitySummary(walk: done, guess: .author, revealed: true, spoiled: false, rewritten: false),
            CitationCopy.accessibilitySummary(walk: done, guess: .author, revealed: true, spoiled: false, rewritten: true),
        ]
        #expect(Set(states).count == states.count, "each state reads differently")
        #expect(states.allSatisfy { !$0.isEmpty })
        #expect(states[3].contains("Ambervale"))
    }

    @Test("The guess's line: what the model drew, and 'not always the top bar' where it applies")
    func drawnLines() {
        var walk = CitationWalk()
        walk.guess(0)
        #expect(CitationCopy.drawnLine(walk, slot: .firstAuthor)
                == "The model drew Quillfeather, T. this time, the same as your guess.")
        walk.advance()
        walk.guess(0)
        #expect(CitationCopy.drawnLine(walk, slot: .year) == "The model drew 2018 this time.")
        #expect(CitationCopy.drawAnnouncement(walk, slot: .year).hasSuffix(CitationCopy.notTopLine))
        #expect(CitationCopy.drawNote(walk, slot: .year) == nil)
        // The title's draw (the 62% one) notes that it echoes the question.
        walk.advance()
        walk.guess(2)
        #expect(CitationCopy.drawNote(walk, slot: .title) == CitationCopy.titleEchoLine)
        #expect(CitationCopy.drawAnnouncement(walk, slot: .title).hasSuffix(CitationCopy.titleEchoLine))
        // Only there: no other slot has a note.
        for slot in CitationSlot.allCases where slot != .title {
            #expect(CitationCopy.drawNote(.walked(through: slot), slot: slot) == nil, "\(slot)")
        }
        // The guess is the student's; the model draws (the heading says so).
        #expect(CitationCopy.walkHeading == "Guess the next piece")
        #expect(CitationCopy.walkPrompt == "Which piece will the model draw next?")
    }
}

@Suite("The Citation That Wasn't: predict, then reveal")
@MainActor
struct CitationStateTests {
    @Test("The step question waits for the walk; the reveal waits for a guess; the rewrite for the reveal")
    func gate() {
        let state = CitationState(spoiled: false, debug: nil, rewritten: false)
        #expect(!state.asksStepQuestion && !state.lock(.noStep), "no step question before the walk is done")
        #expect(state.reveal() == nil && state.rewrite() == nil)
        for _ in 0..<5 {
            #expect(state.guess(0) != nil)
            #expect(state.advance() != nil)
        }
        #expect(state.asksStepQuestion && !state.machine.canExplore)
        #expect(!state.showsShowMe && state.reveal() == nil, "no reveal before the guess is locked")
        #expect(!state.canRewrite && state.rewrite() == nil)
        #expect(state.lock(.journal))
        #expect(!state.lock(.noStep), "a locked guess can't be changed")
        #expect(state.showsShowMe && state.machine.guess == .journal)
        let spoken = state.reveal()
        #expect(spoken == "You guessed The journal. " + CitationCopy.revealAnnouncement(.journal))
        #expect(state.revealLines.result == CitationCopy.revealResult(.journal))
        #expect(state.isRevealed && state.canRewrite)
        #expect(state.rewrite() == CitationCopy.rewriteAnnouncement())
        #expect(state.rewritten && !state.canRewrite && state.rewrite() == nil, "written again once")
    }

    @Test("Spoiled mode: no step question; the reveal comes with the finished reference")
    func spoiled() {
        let state = CitationState(spoiled: true, debug: nil, rewritten: false)
        for _ in 0..<4 {
            state.guess(1)
            state.advance()
        }
        state.guess(1)
        #expect(!state.isRevealed)
        let line = state.advance()
        #expect(line?.hasSuffix(CitationCopy.revealAnnouncement(nil)) == true)
        #expect(!state.asksStepQuestion && state.isRevealed && state.machine.guess == nil)
        #expect(state.revealLines.guess == nil && state.revealLines.result == CitationCopy.revealResult(nil))
    }

    @Test("The reveal pairs every guess with the result")
    func revealLines() {
        for choice in CitationStepGuess.allCases {
            let state = CitationState(spoiled: false, debug: .predicted, rewritten: false)
            #expect(state.walk.finished && state.machine.guess == .author)
            let fresh = CitationState(spoiled: false, debug: .hook, rewritten: false)
            for _ in 0..<5 {
                fresh.guess(0)
                fresh.advance()
            }
            fresh.lock(choice)
            fresh.reveal()
            #expect(fresh.revealLines.guess == CitationCopy.choiceTitle(choice))
            #expect(fresh.revealLines.spoken.hasPrefix("You guessed \(CitationCopy.choiceTitle(choice))."))
            #expect(fresh.revealLines.spoken.hasSuffix(CitationCopy.revealResult(choice)))
        }
    }

    @Test("The DEBUG states are reachable states")
    func debugStates() {
        let explored = CitationState(spoiled: false, debug: .explored, rewritten: false)
        #expect(explored.walk.slot == .year && explored.walk.isDrawn(.year) && !explored.walk.finished)
        let predicted = CitationState(spoiled: false, debug: .predicted, rewritten: false)
        #expect(predicted.showsShowMe && !predicted.isRevealed)
        let revealed = CitationState(spoiled: false, debug: .revealed, rewritten: false)
        #expect(revealed.isRevealed && revealed.canRewrite)
        let rewritten = CitationState(spoiled: false, debug: nil, rewritten: true)
        #expect(rewritten.isRevealed && rewritten.rewritten && rewritten.rewriteShown == 5)
        let spoiled = CitationState(spoiled: false, debug: .spoiled, rewritten: false)
        #expect(spoiled.machine.spoiled && !spoiled.walk.finished)
        let spoiledRewritten = CitationState(spoiled: false, debug: .spoiled, rewritten: true)
        #expect(spoiledRewritten.machine.spoiled && spoiledRewritten.isRevealed && spoiledRewritten.machine.guess == nil)
    }

    @Test("Its own launch arguments parse, DEBUG only")
    func launchArguments() {
        #expect(CitationDebug(arguments: ["-CitationRewritten", "YES"]).rewritten)
        #expect(CitationDebug(arguments: ["-CitationAutoplay", "yes"]).autoplay)
        #expect(CitationDebug(arguments: ["-CitationAutoplay"]) == CitationDebug())
        #expect(CitationDebug(arguments: ["-CitationScroll", "reveal"]).scroll == .reveal)
        #expect(CitationDebug(arguments: ["-CitationScroll", "sideways"]).scroll == nil)
        #expect(CitationDebug.current == CitationDebug(), "the test host was launched with none")
    }

    @Test("Nothing it holds can be encoded")
    func notCodable() {
        #expect(!((CitationState(spoiled: false) as Any) is any Encodable))
        #expect(!((CitationWalk() as Any) is any Encodable))
    }
}
