import Foundation
import Testing
@testable import LessonInteractives

private enum Guess: String, CaseIterable, Sendable {
    case believe, middle, doubt
}

@Suite("Interactives: predict, then reveal")
struct PredictRevealTests {

    @Test("Nothing explores or reveals before a guess is locked")
    func lockBeforeExplore() {
        var machine = PredictReveal(choices: Guess.allCases, showMeAfter: 2)
        #expect(machine.phase == .hook)
        #expect(machine.asksForPrediction)
        #expect(machine.canLock)
        #expect(!machine.canExplore)
        let r1 = machine.recordMove()
        #expect(!r1)
        #expect(machine.moves == 0)
        let r2 = machine.reveal()
        #expect(!r2)
        #expect(!machine.isRevealed)
        #expect(!machine.showsShowMe)

        let r3 = machine.lock(.doubt)
        #expect(r3)
        #expect(machine.phase == .locked)
        #expect(machine.guess == .doubt)
        #expect(machine.canExplore)
        #expect(!machine.canLock)
    }

    @Test("A locked guess can't be changed, and only offered choices lock")
    func lockIsFinal() {
        var machine = PredictReveal(choices: [Guess.believe, .doubt])
        let r4 = machine.lock(.middle)
        #expect(!r4, "not one of the options")
        #expect(machine.guess == nil)
        let r5 = machine.lock(.believe)
        #expect(r5)
        let r6 = machine.lock(.doubt)
        #expect(!r6)
        #expect(machine.guess == .believe)
    }

    @Test("\"Show me\" appears after the card's set number of moves")
    func showMe() {
        var machine = PredictReveal(choices: Guess.allCases, showMeAfter: 2)
        machine.lock(.middle)
        #expect(!machine.showsShowMe)
        machine.recordMove()
        #expect(machine.phase == .exploring)
        #expect(!machine.showsShowMe)
        machine.recordMove()
        #expect(machine.showsShowMe)
        let r7 = machine.reveal()
        #expect(r7)
        #expect(machine.isRevealed)
        #expect(!machine.showsShowMe, "gone once revealed")
        // Moves after the reveal count, and the reveal stays.
        let r8 = machine.recordMove()
        #expect(r8)
        #expect(machine.isRevealed)

        var immediate = PredictReveal(choices: Guess.allCases, showMeAfter: 0)
        #expect(!immediate.showsShowMe)
        immediate.lock(.believe)
        #expect(immediate.showsShowMe, "0: as soon as the guess is locked")
    }

    @Test("Spoiled mode: no prediction, the control on from the start, no \"You guessed\"")
    func spoiled() {
        var machine = PredictReveal(choices: Guess.allCases, showMeAfter: 1, spoiled: true)
        #expect(!machine.asksForPrediction)
        #expect(!machine.canLock)
        let r9 = machine.lock(.doubt)
        #expect(!r9)
        #expect(machine.canExplore)
        let r10 = machine.recordMove()
        #expect(r10)
        #expect(machine.showsShowMe)
        let r11 = machine.reveal()
        #expect(r11)
        let lines = machine.revealLines(guessText: \.rawValue, result: "Every setting makes 4 mistakes.")
        #expect(lines.guess == nil)
        #expect(lines.spoken == "Every setting makes 4 mistakes.")
        #expect(!lines.spoken.contains(InteractiveShellCopy.youGuessed))
    }

    @Test("The reveal pairs the guess with the result, for every choice")
    func revealSentence() {
        for choice in Guess.allCases {
            var machine = PredictReveal(choices: Guess.allCases)
            machine.lock(choice)
            machine.recordMove()
            machine.reveal()
            let lines = machine.revealLines(guessText: { "\($0.rawValue) everything" }, result: "It waved away 5 real stories.")
            #expect(lines.guess == "\(choice.rawValue) everything")
            #expect(lines.spoken == "You guessed \(choice.rawValue) everything. It waved away 5 real stories.")
        }
    }

    @Test("DEBUG states are reached through the real transitions")
    func debugStates() {
        let hook = PredictReveal.debugStarting(.hook, choices: Guess.allCases, showMeAfter: 2)
        #expect(hook.phase == .hook && hook.guess == nil)
        let none = PredictReveal.debugStarting(nil, choices: Guess.allCases)
        #expect(none == PredictReveal(choices: Guess.allCases))

        let predicted = PredictReveal.debugStarting(.predicted, choices: Guess.allCases, showMeAfter: 2)
        #expect(predicted.phase == .locked && predicted.guess == .believe)

        let explored = PredictReveal.debugStarting(.explored, choices: Guess.allCases, showMeAfter: 2, guess: .doubt)
        #expect(explored.phase == .exploring && explored.guess == .doubt && explored.moves == 2)
        #expect(explored.showsShowMe)

        let revealed = PredictReveal.debugStarting(.revealed, choices: Guess.allCases, showMeAfter: 0)
        #expect(revealed.isRevealed && revealed.moves == 1)

        let spoiled = PredictReveal.debugStarting(.spoiled, choices: Guess.allCases)
        #expect(spoiled.spoiled && spoiled.guess == nil && spoiled.phase == .hook && spoiled.canExplore)
        // A spoiled card opened "revealed" skips the guess.
        let spoiledRevealed = PredictReveal.debugStarting(.revealed, choices: Guess.allCases, spoiled: true)
        #expect(spoiledRevealed.isRevealed && spoiledRevealed.guess == nil)
    }
}
