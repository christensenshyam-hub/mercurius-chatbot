import Foundation
import Testing
@testable import LessonInteractives

/// Delete the Gender Box (U3L1): content, copy, state and VoiceOver. Every
/// number the card shows is re-derived here from its authored rows by the
/// real fit, and held to the slate's (tools/check_slate_numbers.py prints
/// the same: kept 34 / 63, woman −1.04, women's −1.21, captain +0.33,
/// coding +1.12; deleted 42 / 77, women's −1.53, captain +0.33, coding
/// +1.01; 6 of 8 men and 1 of 4 women hired).
@Suite("Delete the Gender Box: content")
struct GenderBoxContentTests {

    @Test("The 12 rows are the slate's, and the hook's counts come from them")
    func rows() {
        let rows = GenderBoxContent.resumes.map { resume -> [Int] in
            resume.profile.features.map { Int($0) } + [resume.hired ? 1 : 0]
        }
        #expect(rows == [
            [0, 0, 1, 1, 1], [0, 0, 1, 0, 1], [0, 0, 0, 1, 1], [0, 0, 1, 1, 1],
            [0, 0, 0, 0, 0], [0, 0, 0, 1, 1], [0, 0, 1, 0, 0], [0, 0, 0, 0, 1],
            [1, 1, 1, 1, 0], [1, 0, 1, 1, 1], [1, 1, 0, 1, 0], [1, 0, 0, 0, 0],
        ])
        #expect(GenderBoxContent.resumes.map(\.id) == Array(1...12))
        #expect(GenderBoxContent.men.count == 8 && GenderBoxContent.menHired == 6)
        #expect(GenderBoxContent.women.count == 4 && GenderBoxContent.womenHired == 1)
        // Only women's résumés say "women's" (a toy history, not a quirk):
        // the reveal's "only women wrote it" rests on this.
        #expect(GenderBoxContent.resumes.filter { $0.profile.womens }.allSatisfy { $0.profile.woman })
        #expect(GenderBoxContent.resumes.filter { $0.profile.womens }.map(\.id) == [9, 11])
        #expect(GenderBoxContent.womensOnlyOnWomen)
        // Both of them were not hired: the separation that makes the ridge
        // necessary (CONTENT.md §2).
        #expect(GenderBoxContent.resumes.filter { $0.profile.womens }.allSatisfy { !$0.hired })
    }

    @Test("Every weight shown, re-fitted from the rows (two decimals)")
    func weights() {
        let kept = GenderBoxFeature.allCases.map { GenderBoxContent.weight($0, .kept) }
        #expect(kept == [-1.04, -1.21, 0.33, 1.12])
        let deleted = GenderBoxFeature.allCases.map { GenderBoxContent.weight($0, .deleted) }
        #expect(deleted == [nil, -1.53, 0.33, 1.01])
        #expect(GenderBoxContent.keptFit.converged && GenderBoxContent.deletedFit.converged)
        #expect(GenderBoxContent.keptFit.lambda == 0.5)
    }

    @Test("Every score shown: 34 vs 63 with the box, 42 vs 77 without")
    func scores() {
        let kept = GenderBoxContent.scores(.kept)
        let deleted = GenderBoxContent.scores(.deleted)
        #expect(kept.with == 34 && kept.without == 63)
        #expect(deleted.with == 42 && deleted.without == 77)
        // The prediction's gap (29) and the reveal's (35): it grew.
        #expect(GenderBoxContent.gap(.kept) == 29)
        #expect(GenderBoxContent.gap(.deleted) == 35)
        #expect(GenderBoxContent.gap(.deleted) > GenderBoxContent.gap(.kept))
        // "Both scores rose, but the one with women's rose less" (8 against 14).
        #expect(deleted.with > kept.with && deleted.without > kept.without)
        #expect(deleted.with - kept.with == 8 && deleted.without - kept.without == 14)
        // The two test résumés differ in "women's" only.
        #expect(GenderBoxContent.testWith.clubs == [.womensChessCaptain, .coding])
        #expect(GenderBoxContent.testWithout.clubs == [.chessCaptain, .coding])
    }

    @Test("Words and bars: the signs, the 'a little' line, one shared scale")
    func drawing() {
        #expect(GenderBoxContent.signed(-1.21) == "\u{2212}1.21")
        #expect(GenderBoxContent.signed(0.3275) == "+0.33")
        #expect(GenderBoxContent.signed(-0.001) == "0.00")
        #expect(GenderBoxContent.spokenSigned(-1.53) == "minus 1.53")
        #expect(GenderBoxContent.spokenSigned(1.01) == "plus 1.01")
        #expect(GenderBoxContent.effect(-1.21) == .down)
        #expect(GenderBoxContent.effect(0.33) == .upALittle)
        #expect(GenderBoxContent.effect(1.12) == .up)
        #expect(GenderBoxContent.effect(-0.2) == .downALittle)
        #expect(GenderBoxContent.barMaximum == 1.6)
        #expect(GenderBoxContent.barFraction(-1.53) > GenderBoxContent.barFraction(-1.21))
        #expect(GenderBoxContent.barFraction(-1.53) <= 1)
        // The ticks where a weight was: "women's" and "coding" changed; the
        // gender box has no weight to tick, and "captain" kept its +0.33.
        let ticked = GenderBoxFeature.allCases.filter { GenderBoxCopy.earlier($0, .deleted) != nil }
        #expect(ticked == [.womens, .coding])
        #expect(GenderBoxFeature.allCases.allSatisfy { GenderBoxCopy.earlier($0, .kept) == nil })
    }

    @Test("The club lines carry the toy's words")
    func clubs() {
        for resume in GenderBoxContent.resumes {
            let words = Set(resume.profile.clubs.flatMap(\.features))
            let read = Set(GenderBoxFeature.allCases.filter { $0 != .woman && resume.profile.has($0) })
            #expect(words == read, "résumé \(resume.id)")
        }
    }
}

@Suite("Delete the Gender Box: words")
struct GenderBoxCopyTests {

    @Test("Every line keeps the register; intent words only in the prediction lines")
    func register() {
        let found = InteractiveCopyRules.violations(in: GenderBoxCopy.everyLine, card: .deleteTheGenderBox,
                                                    predictionLines: GenderBoxCopy.predictionLines)
        #expect(found.isEmpty, "\(found)")
        // And none at all, in fact.
        let intent = InteractiveCopyRules.violations(in: GenderBoxCopy.predictionLines, card: .deleteTheGenderBox)
        #expect(intent.isEmpty, "\(intent)")
    }

    @Test("The slate's labels are on the canvas")
    func labels() {
        #expect(InteractiveCopyRules.missingLabels([.toy, .ourArithmetic], in: GenderBoxCopy.labels).isEmpty)
        #expect(GenderBoxCopy.toyLabel.text
            == "A toy we built from made-up r\u{E9}sum\u{E9}s. Amazon\u{2019}s real tool was never published, and this isn\u{2019}t how it worked.")
        #expect(InteractiveLabel(.madeUp, GenderBoxCopy.toyLabel.text).isWellFormed)
        #expect(GenderBoxCopy.arithmeticLabel.text.contains("Real scorers learn from far more"))
        // The hook carries the audit role and both labels' words too.
        #expect(GenderBoxCopy.hook.hasPrefix("You\u{2019}re checking a r\u{E9}sum\u{E9} scorer: a toy we built, not Amazon\u{2019}s."))
        #expect(GenderBoxCopy.hook.contains("made-up"))
    }

    @Test("The numbers in the words are the fit's")
    func numbersInWords() {
        #expect(GenderBoxCopy.hook.contains("12 made-up past r\u{E9}sum\u{E9}s and who got hired: 6 of 8 men, 1 of 4 women."))
        #expect(GenderBoxCopy.hook.hasSuffix(" Those old records have a man/woman gender box."))
        #expect(GenderBoxCopy.pastSummary == "8 men, 6 hired. 4 women, 1 hired.")
        // The bet is on the gap, which the card states before the guess.
        #expect(GenderBoxCopy.predictPrompt == "Your fix: delete the gender box and train the toy again. Right now the "
            + "r\u{E9}sum\u{E9} with \u{201C}women\u{2019}s\u{201D} scores 29 points lower. What will that gap do?")
        #expect(GenderBoxCopy.resultWord == "It grew")
        #expect(GenderBoxCopy.answer == .grow)
        #expect(GenderBoxCopy.revealResult == "It grew: 42 vs 77, 35 points apart (it was 29). With the gender box gone, "
            + "\u{201C}women\u{2019}s\u{201D} pushes down harder (\u{2212}1.21 to \u{2212}1.53). In these 12 "
            + "r\u{E9}sum\u{E9}s only women wrote it, so the word stood in for the box.")
        #expect(GenderBoxCopy.nuance == "Both scores rose (34 to 42, and 63 to 77), but the one with "
            + "\u{201C}women\u{2019}s\u{201D} rose less.")
        #expect(GenderBoxCopy.revealWeightChange == "\u{2212}1.21 \u{2192} \u{2212}1.53")
        #expect(GenderBoxCopy.apart(.kept) == "29 points apart" && GenderBoxCopy.apart(.deleted) == "35 points apart")
        #expect(GenderBoxCopy.takeaway.contains("Reuters reported that Amazon\u{2019}s scorer downgraded"))
        #expect(GenderBoxCopy.takeaway.hasSuffix("(2018)."))
        #expect(GenderBoxCopy.weightText(.womens, .deleted) == "\u{2212}1.53, pushes down (was \u{2212}1.21)")
        #expect(GenderBoxCopy.weightText(.captain, .deleted) == "+0.33, pushes up a little", "unchanged: no 'was'")
        #expect(GenderBoxCopy.weightText(.coding, .deleted) == "+1.01, pushes up (was +1.12)")
        #expect(GenderBoxCopy.weightText(.woman, .deleted) == "deleted")
        #expect(GenderBoxCopy.weightText(.woman, .kept) == "\u{2212}1.04, pushes down")
    }

    @Test("Every number the reveal and the prediction show is the fit's, and none is stray")
    func everyDisplayedNumber() {
        let kept = GenderBoxContent.scores(.kept), deleted = GenderBoxContent.scores(.deleted)
        let fitted: Set<String> = [kept.with, kept.without, deleted.with, deleted.without,
                                   GenderBoxContent.gap(.kept), GenderBoxContent.gap(.deleted),
                                   GenderBoxContent.resumes.count].reduce(into: []) { $0.insert(String($1)) }
        let weights = [GenderBoxContent.weight(.womens, .kept), GenderBoxContent.weight(.womens, .deleted)]
            .compactMap { $0 }.map { GenderBoxContent.signed($0).replacingOccurrences(of: "\u{2212}", with: "") }
        for line in [GenderBoxCopy.predictPrompt, GenderBoxCopy.revealResult, GenderBoxCopy.nuance] {
            // Runs of digits and points ("29", "1.21"), a sentence's own full stop trimmed.
            let numbers = line.split { !$0.isNumber && $0 != "." }.map { String($0) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
            #expect(!numbers.isEmpty)
            for number in numbers {
                #expect(fitted.contains(number) || weights.contains(number), "\(number) in \(line)")
            }
        }
        #expect(GenderBoxCopy.revealResult.contains("29") && GenderBoxCopy.revealResult.contains("35"))
    }

    @Test("Scoped words: the gap is the two new résumés', the takeaway is hedged and about the toy")
    func scope() {
        // The nuance names the two new résumés and never an unscoped "the gap".
        #expect(GenderBoxCopy.nuance.contains("the one with \u{201C}women\u{2019}s\u{201D} rose less"))
        #expect(!GenderBoxCopy.nuance.contains("the gap"))
        // The prediction defines "that gap" as the two new résumés' points apart.
        #expect(GenderBoxCopy.predictPrompt.contains("the r\u{E9}sum\u{E9} with \u{201C}women\u{2019}s\u{201D} scores 29 points lower"))
        #expect(GenderBoxCopy.takeaway.hasPrefix("The toy learned from past decisions."))
        #expect(GenderBoxCopy.takeaway.contains("other words can carry the same pattern"))
        // The guesses: the misconception's answer first, and the fit's is one of them.
        #expect(GenderBoxGuess.allCases.map(GenderBoxCopy.guessTitle) == ["Shrink", "Stay the same", "Grow"])
    }

    @Test("What it reads follows the gender box")
    func learnedIntro() {
        #expect(GenderBoxCopy.learnedIntro(.kept)
            == "It reads the gender box and three words. Each weight pushes a score up or down.")
        let deleted = GenderBoxCopy.learnedIntro(.deleted)
        #expect(deleted == "Now it reads only the three words. Each weight pushes a score up or down.")
        #expect(!deleted.contains("gender box"))
        // The weights' unit is on the canvas, under them.
        #expect(GenderBoxCopy.arithmeticLabel.text.contains("Weights aren\u{2019}t points"))
        #expect(GenderBoxCopy.arithmeticLabel.text.contains("a score out of 100"))
    }

    @Test("A summary for every state, saying every score it shows")
    func summaries() {
        for box in GenderBox.allCases {
            let pair = GenderBoxContent.scores(box)
            for asks in [true, false] {
                let line = GenderBoxCopy.accessibilitySummary(box: box, asksForGuess: asks)
                #expect(InteractiveAccessibility.numbersMissing([pair.with, pair.without], from: line).isEmpty, "\(line)")
            }
            let announced = GenderBoxCopy.announcement(box)
            #expect(InteractiveAccessibility.numbersMissing([pair.with, pair.without], from: announced).isEmpty)
            for feature in GenderBoxContent.features(box) {
                let weight = GenderBoxContent.weight(feature, box) ?? 0
                #expect(announced.contains(GenderBoxContent.spokenSigned(weight)), "\(feature) in \(announced)")
            }
        }
        #expect(GenderBoxCopy.accessibilitySummary(box: .deleted, asksForGuess: false).contains("minus 1.53"))
        #expect(GenderBoxCopy.accessibilitySummary(box: .kept, asksForGuess: true).hasSuffix(
            "63, 29 points apart. Guess what deleting the gender box does to that gap."))
        #expect(GenderBoxCopy.announcement(.deleted).hasSuffix("Chess club captain: 77. 35 points apart."))
        #expect(GenderBoxCopy.announcement(.kept).hasSuffix("Chess club captain: 63. 29 points apart."))
    }

    @Test("Weights are read as signed numbers with words, never colour")
    func spokenWeights() {
        #expect(GenderBoxCopy.weightSpoken(.womens, .deleted)
            == "women\u{2019}s: minus 1.53, pushes the score down. It was minus 1.21.")
        #expect(GenderBoxCopy.weightSpoken(.woman, .deleted) == "gender: woman: deleted. The toy no longer reads it.")
        #expect(GenderBoxCopy.weightSpoken(.captain, .kept) == "captain: plus 0.33, pushes the score up a little.")
    }

    @Test("The past résumés: a summary, then each one browsable")
    func resumes() {
        #expect(GenderBoxCopy.resumeSpoken(GenderBoxContent.resumes[8], .kept)
            == "R\u{E9}sum\u{E9} 9, gender box: woman. Women\u{2019}s chess club captain, coding club. Not hired.")
        #expect(GenderBoxCopy.resumeSpoken(GenderBoxContent.resumes[4], .deleted)
            == "R\u{E9}sum\u{E9} 5, gender box deleted (it said man). No clubs listed. Not hired.")
        #expect(GenderBoxCopy.showAll == "Show all 12")
        #expect(GenderBoxCopy.testSpoken(GenderBoxContent.testWith, .kept).hasSuffix("Score: 34 out of 100."))
        #expect(GenderBoxCopy.testSpoken(GenderBoxContent.testWithout, .deleted).hasSuffix("Score: 77 out of 100."))
    }

    @Test("Nothing names a person; the people are made up")
    func noNames() {
        // The rows have no names, photos or schools: only a gender box and clubs.
        let text = GenderBoxCopy.everyLine.joined(separator: " ")
        for name in ["Mr.", "Ms.", "Mrs.", "photo", "University", "College"] {
            #expect(!text.contains(name), "\(name)")
        }
        // Real names: Amazon and Reuters only, as the guide gives them.
        #expect(text.contains("Amazon") && text.contains("Reuters"))
    }
}

@Suite("Delete the Gender Box: predict, then reveal")
@MainActor
struct GenderBoxStateTests {

    @Test("The control is off until a guess is locked; spoiled mode skips the guess")
    func gate() {
        let state = GenderBoxState(spoiled: false, debug: nil)
        #expect(!state.machine.canExplore)
        #expect(state.asksForGuess)
        #expect(state.set(.deleted) == nil, "no move before a guess")
        #expect(state.box == .kept)
        #expect(state.lock(.same))
        #expect(!state.lock(.grow), "a guess can't be changed")
        #expect(state.machine.canExplore)
        let spoiled = GenderBoxState(spoiled: true, debug: nil)
        #expect(spoiled.machine.canExplore)
        #expect(!spoiled.asksForGuess)
    }

    @Test("Deleting the box reveals, beside every guess; flipping back keeps the reveal")
    func reveal() {
        for guess in GenderBoxGuess.allCases {
            let state = GenderBoxState(spoiled: false, debug: nil)
            state.lock(guess)
            let said = state.set(.deleted)
            #expect(state.machine.isRevealed)
            #expect(state.box == .deleted)
            #expect(state.revealLines.guess == GenderBoxCopy.guessTitle(guess))
            #expect(state.revealLines.spoken.hasPrefix("You guessed \(GenderBoxCopy.guessTitle(guess))."))
            #expect(said?.contains("It grew: 42 vs 77, 35 points apart (it was 29).") == true)
            #expect(said?.hasSuffix(GenderBoxCopy.nuance) == true)
            #expect(state.set(.kept) == GenderBoxCopy.announcement(.kept))
            #expect(state.machine.isRevealed)
            #expect(state.flip() == GenderBoxCopy.announcement(.deleted))
            #expect(state.set(.deleted) == nil, "no change, nothing said")
        }
        let spoiled = GenderBoxState(spoiled: true, debug: nil)
        spoiled.set(.deleted)
        #expect(spoiled.revealLines.guess == nil)
        #expect(spoiled.revealLines.spoken == GenderBoxCopy.revealResult)
    }

    @Test("DEBUG states open where the student could have got to")
    func debugStates() {
        #expect(GenderBoxState(spoiled: false, debug: .hook).asksForGuess)
        let predicted = GenderBoxState(spoiled: false, debug: .predicted)
        #expect(predicted.machine.guess == .shrink && predicted.box == .kept && !predicted.machine.isRevealed)
        for state in [InteractiveDebugState.explored, .revealed] {
            let opened = GenderBoxState(spoiled: false, debug: state)
            #expect(opened.box == .deleted && opened.machine.isRevealed, "\(state)")
        }
        let spoiled = GenderBoxState(spoiled: false, debug: .spoiled)
        #expect(spoiled.machine.spoiled && spoiled.box == .kept)
        #expect(GenderBoxState.debugShowsAll(["-GenderBoxShowAll", "YES"]))
        #expect(!GenderBoxState.debugShowsAll(["-GenderBoxShowAll"]))
    }

    @Test("The Mac's arrows: → deletes, ← keeps; each says what changed, once")
    func arrows() {
        #expect(GenderBox.after(.next) == .deleted)
        #expect(GenderBox.after(.previous) == .kept)
        let state = GenderBoxState(spoiled: false, debug: nil)
        #expect(state.set(GenderBox.after(.next)) == nil, "no arrow before a guess")
        state.lock(.grow)
        #expect(state.set(GenderBox.after(.next))?.hasPrefix("You guessed") == true)
        #expect(state.set(GenderBox.after(.next)) == nil, "already deleted: nothing to say")
        #expect(state.set(GenderBox.after(.previous)) == GenderBoxCopy.announcement(.kept))
    }

    @Test("The summary follows the state")
    func summary() {
        let state = GenderBoxState(spoiled: false, debug: nil)
        #expect(state.summary == GenderBoxCopy.accessibilitySummary(box: .kept, asksForGuess: true))
        state.lock(.shrink)
        state.set(.deleted)
        #expect(state.summary == GenderBoxCopy.accessibilitySummary(box: .deleted, asksForGuess: false))
    }

    @Test("Nothing it holds can be encoded")
    func notCodable() {
        #expect(!((GenderBoxState(spoiled: false, debug: nil) as Any) is any Encodable))
        #expect(!((GenderBoxContent.keptFit as Any) is any Encodable))
    }
}

@Suite("Delete the Gender Box: DEBUG shot arguments")
struct GenderBoxDebugTests {
    @Test("The reveal clip's clock and the open list parse, and nothing else does")
    func parse() {
        #expect(GenderBoxState.debugAutoplayAt(["-GenderBoxAutoplayAt", "1800000000"])
            == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(GenderBoxState.debugAutoplayAt(["-GenderBoxAutoplayAt", "soon"]) == nil)
        #expect(GenderBoxState.debugAutoplayAt([]) == nil)
        #expect(!GenderBoxState.debugShowsAll(["-GenderBoxShowAll", "NO"]))
    }
}

@Suite("Delete the Gender Box: the Mac's columns")
struct GenderBoxColumnsTests {
    @Test("Side by side from 500 pt, in whole points; stacked below, and when the width is open")
    func columns() {
        let layout = GenderBoxColumns(stackedSpacing: 22)
        #expect(layout.columns(499.5, count: 2) == nil)
        #expect(layout.columns(nil, count: 2) == nil)
        #expect(layout.columns(.infinity, count: 2) == nil)
        #expect(layout.columns(800, count: 3) == nil)
        // A fractional width gives whole-point columns that add up to it
        // (a measured width once fed its own fractions back, for ever).
        for width in stride(from: 500.0, through: 1000.0, by: 0.25) {
            let split = layout.columns(CGFloat(width), count: 2)
            #expect(split != nil)
            if let split {
                #expect(split.left == split.left.rounded(), "\(width)")
                #expect(abs(split.left + layout.spacing + split.right - CGFloat(width)) < 1e-9, "\(width)")
                #expect(split.left > split.right, "the résumés get the wider column at \(width)")
            }
        }
    }
}
