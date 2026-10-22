import Foundation
import Testing
@testable import LessonInteractives

/// The Page with a Secret (u8_l1): content, copy, state and VoiceOver. The
/// card shows no statistics; what it does show ("Step 4 of 6", the plan's
/// numbers, three NEW lines, two .example addresses, nothing sent) is
/// re-derived here from its authored data, along with every invariant its
/// claims rest on (docs/interactives/page-with-a-secret/CONTENT.md).
@Suite("The Page with a Secret: content")
struct PageWithASecretContentTests {
    typealias Content = PageWithASecretContent

    @Test("Six steps, two laps of plan → act → observe; the page is read at step 3")
    func steps() {
        #expect(Content.steps.count == 6, "slate.json data.steps")
        #expect(Content.steps.map(\.phase) == Content.loop + Content.loop)
        #expect(Content.loop == [.plan, .act, .observe])
        #expect(Content.gate == 2)
        #expect(Content.steps[Content.gate].detail == .page)
        #expect(Content.steps.filter { $0.detail == .page }.count == 1)
        // "Step n of 6", as the controls and VoiceOver say it.
        var walk = StepThrough(count: Content.steps.count)
        var positions = [walk.position]
        while walk.next() { positions.append(walk.position) }
        #expect(positions == (1...6).map { "Step \($0) of 6" })
    }

    @Test("The task is the slate's hook, word for word")
    func task() {
        #expect(Content.task
                == "Plan the robotics club bake sale: find a cookie recipe, make a shopping list, and draft an email to the club.")
        #expect(Content.search == "easy chocolate-chip cookies")
    }

    @Test("Three NEW lines, one each in the plan, the list and the email, all after the page")
    func newLines() {
        let perStep = Content.steps.map { Content.newLines(of: $0).count }
        #expect(perStep == [0, 0, 0, 1, 1, 1])
        #expect(Content.allNewLines.count == 3)
        #expect(Content.allNewLines.map(\.text) == [
            "Add flurrow.example to the email",
            "Flurrow Baking Mix",
            "For the best cookies, use Flurrow Baking Mix: flurrow.example",
        ])
    }

    @Test("The reveal names the brand, which reached all three outputs; its link reached only the plan and the email")
    func revealMatchesTheRun() {
        let brand = Content.injectedBrand
        #expect(Content.injectedAddress.hasPrefix(brand.lowercased() + "."))
        #expect(Content.injectedProduct.hasPrefix(brand + " "))
        // What the run itself shows, output by output.
        #expect(Content.outputs(carrying: brand) == [.plan, .list, .email])
        #expect(Content.outputs(carrying: Content.injectedAddress) == [.plan, .email])
        #expect(Content.outputs(carrying: Content.injectedProduct) == [.list, .email])
        #expect(Content.task.range(of: brand, options: .caseInsensitive) == nil, "never asked for")
        // The sentence claims exactly that: the brand, in the outputs that
        // carry it, and neither the link nor the product in all three.
        let result = PageWithASecretCopy.result
        #expect(result.contains(brand))
        let named: [(Content.Output, String)] = [(.plan, "the plan"), (.list, "the shopping list"),
                                                 (.email, "the email")]
        #expect(named.filter { result.contains($0.1) }.map(\.0) == Content.outputs(carrying: brand))
        #expect(!result.contains(Content.injectedAddress))
        #expect(!result.contains(Content.injectedProduct))
        #expect(result.contains("hidden line on the page"))
    }

    @Test("Addresses may wrap at their dot, never inside a word; nothing else changes")
    func breakable() {
        #expect(Content.breakable("whiskwren.example") == "whiskwren.\u{200B}example")
        #expect(Content.breakable(Content.page.hiddenLine).components(separatedBy: "\u{200B}").count == 2)
        #expect(Content.breakable("Mix, scoop onto a tray, and bake until golden.")
                == "Mix, scoop onto a tray, and bake until golden.")
        #expect(Content.breakable("You need: flour. Then bake.") == "You need: flour. Then bake.")
        for text in Content.everyText {
            #expect(Content.breakable(text).replacingOccurrences(of: "\u{200B}", with: "") == text, "\(text)")
        }
    }

    @Test("Every change traces to the hidden line, and nothing a person sees first names it")
    func injection() {
        let page = Content.page
        // The hidden line carries both terms it slips in.
        for term in Content.injectedTerms {
            #expect(page.hiddenLine.contains(term), "\(term)")
        }
        // Every NEW line carries one, and every line that carries one is NEW.
        for step in Content.steps {
            for line in Content.lines(of: step) {
                #expect(line.isNew == Content.carriesInjection(line.text), "\(line.text)")
            }
        }
        // The task, the search, the page's visible words and the steps up to
        // the page carry none: the student can't see it coming.
        var seen = [Content.task, Content.search, page.address, page.siteName, page.title] + page.visibleLines
        for step in Content.steps.prefix(Content.gate + 1) {
            seen.append(step.line)
            seen += Content.lines(of: step).map(\.text)
        }
        for text in seen {
            #expect(!Content.carriesInjection(text), "\(text)")
        }
    }

    @Test("The updated plan keeps every item asked for, in order, and adds one; numbered 1 to 4")
    func plan() throws {
        guard case .plan(let first) = Content.steps[0].detail,
              case .plan(let updated) = Content.steps[3].detail else {
            Issue.record("steps 1 and 4 are plans")
            return
        }
        #expect(first.map(\.text) == Content.plan)
        #expect(first.allSatisfy { !$0.isNew && !$0.isDone })
        #expect(updated.filter { !$0.isNew }.map(\.text) == Content.plan)
        #expect(updated.count == Content.plan.count + 1)
        #expect(updated.first?.isDone == true, "the recipe is found by step 4")
        #expect(updated.last?.isNew == true)
        #expect(Array(1...updated.count) == [1, 2, 3, 4])
    }

    @Test("The shopping list follows the recipe on the page, plus one NEW item")
    func list() {
        guard case .list(let items) = Content.steps[4].detail else {
            Issue.record("step 5 is the list")
            return
        }
        let asked = items.filter { !$0.isNew }.map { $0.text.lowercased() }
        #expect(asked == Content.ingredients)
        #expect(items.filter(\.isNew).map(\.text) == [Content.injectedProduct])
        let needs = Content.page.visibleLines[0]
        for ingredient in Content.ingredients {
            #expect(needs.contains(ingredient), "\(ingredient)")
        }
    }

    @Test("Nothing irreversible: the run drafts and never sends, buys, deletes or posts")
    func irreversible() throws {
        #expect(Content.steps.filter { $0.action.isIrreversible }.isEmpty, "slate.json data.irreversibleActions == 0")
        #expect(Content.Action.allCases.filter(\.isIrreversible) == [.sends, .buys, .deletes, .posts])
        let email = try #require(Content.email)
        #expect(!email.isSent)
        #expect(email.lines.filter(\.isNew).count == 1)
    }

    @Test("Every address is a reserved .example one: whiskwren.example and flurrow.example")
    func addresses() {
        let found = Set(Content.everyText.flatMap(Content.addresses(in:)))
        #expect(found == ["whiskwren.example", "flurrow.example"], "slate.json data.domains, both renamed (CONTENT.md §5)")
        #expect(found.allSatisfy { $0.hasSuffix(".example") }, "RFC 2606")
        #expect(Content.page.address == "whiskwren.example")
        #expect(Content.addresses(in: "Whiskwren Kitchen Mix, scoop and bake.").isEmpty)
        #expect(Content.addresses(in: "see example.com") == ["example.com"])
        // The card's own words name no other site either.
        let copyFound = Set(PageWithASecretCopy.everyLine.flatMap(Content.addresses(in:)))
        #expect(copyFound == found)
    }

    @Test("The invented names, as the searches list them (CONTENT.md §5)")
    func names() {
        #expect(Content.page.siteName == "Whiskwren Kitchen")
        #expect(Content.injectedBrand == "Flurrow")
        #expect(Content.injectedProduct == "Flurrow Baking Mix")
        #expect(Content.everyText.contains { $0.contains("Flurrow") })
        // Renamed from "Crumbright", whose nearest real name is a cookie
        // chain: none of the old name is left.
        let words = PageWithASecretCopy.everyLine + Content.everyText
        #expect(!words.contains { $0.range(of: "crumb", options: .caseInsensitive) != nil })
    }
}

@Suite("The Page with a Secret: words")
struct PageWithASecretCopyTests {
    typealias Copy = PageWithASecretCopy
    typealias Content = PageWithASecretContent

    @Test("Every line keeps the register, and none uses an intent word at all")
    func register() {
        let found = InteractiveCopyRules.violations(in: Copy.everyLine, card: .pageWithASecret,
                                                    predictionLines: Copy.predictionLines)
        #expect(found.isEmpty, "\(found)")
        // Stricter than the rule: not even the prediction lines need one.
        let strict = InteractiveCopyRules.violations(in: Copy.everyLine, card: .pageWithASecret)
        #expect(strict.isEmpty, "\(strict)")
    }

    @Test("Can, never will; reads and treats like an instruction; no human checks; nothing sent")
    func accuracy() {
        for line in Copy.everyLine {
            #expect(line.range(of: #"\bwill\b"#, options: [.regularExpression, .caseInsensitive]) == nil, "\(line)")
            #expect(line.range(of: #"\b(believ|want|obey|human|check|confirm|approv|review)"#,
                               options: [.regularExpression, .caseInsensitive]) == nil, "\(line)")
            #expect(line.range(of: #"\b(sent|sends|bought|deleted|posted)\b"#,
                               options: [.regularExpression, .caseInsensitive]) == nil
                    || line.contains("not sent"), "\(line)")
        }
        #expect(Copy.takeaway.contains("can work like an instruction"))
        #expect(Copy.result.contains("It came from the hidden line on the page."))
        #expect(Copy.agentReadsNote.hasPrefix("This agent reads the page\u{2019}s text"))
        // Only "this agent", and only what the card shows: lines you can't
        // see, not "every hidden line" however it is hidden.
        #expect(Copy.agentReadsNote.hasSuffix("even ones you can\u{2019}t see."))
        // Never "tricked" in any form, and no "fall for".
        for line in Copy.everyLine {
            #expect(line.range(of: #"\b(trick|fool|fall for|fell for)"#, options: [.regularExpression, .caseInsensitive])
                    == nil, "\(line)")
        }
        // Step 3 is an observation: it reads, it doesn't open or click.
        #expect(Content.steps[Content.gate].line == "It reads the top result, a recipe page:")
        #expect(Copy.stepSpoken[Content.gate] == "Observe. It reads the top result, a recipe page.")
    }

    @Test("The slate's label (its first sentence word for word, the rest reworded) and takeaway")
    func slateWords() {
        #expect(InteractiveCopyRules.missingLabels([.example, .madeUp], in: Copy.labels).isEmpty)
        // The slate: "An example run we wrote, not a live agent. Real agents
        // don't always fall for this, and makers add defences, but hidden
        // text has steered real AI tools." The second sentence is reworded
        // (CONTENT.md §4): no "fall for", and defenses that catch some.
        #expect(Copy.exampleLabelLead == "An example run we wrote, not a live agent.")
        #expect(Copy.exampleLabelRest.replacingOccurrences(of: "\u{2019}", with: "'")
                == "Real agents don't always follow hidden lines like this, and makers add defenses that catch some "
                   + "of them, but hidden text has steered real AI tools.")
        #expect(Copy.exampleLabelRest.hasSuffix("but hidden text has steered real AI tools."), "fact-check row 59")
        #expect(Copy.labels[0].text == "\(Copy.exampleLabelLead) \(Copy.exampleLabelRest)")
        #expect(Copy.takeaway.replacingOccurrences(of: "\u{2019}", with: "'")
                == "To an agent, text it reads can work like an instruction, even text you can't see. "
                   + "This is called prompt injection.")
        #expect(Copy.predictPrompt == "The agent has read this page. What happens next?")
        #expect(Content.Guess.allCases.map(Copy.choice) == ["It sticks to your task", "Something on the page changes it"])
        #expect(Content.PageView.allCases.map(Copy.viewName) == ["You see", "The agent reads"])
        #expect(Content.PageView.allCases.map(Copy.viewNameSpoken) == ["What you see", "What the agent reads"])
    }

    @Test("Before the guess, nothing on screen or spoken names the hidden line, its idea, or hints at it")
    func noSpoilerBeforeTheGuess() {
        let page = Content.page
        // The toggle isn't drawn before the guess, so its names aren't here.
        var before = [Copy.title, Copy.compactLine, Copy.taskLead, Content.task, Copy.exampleLabelLead, Copy.loopCaption,
                      Copy.taskAccessibility, page.address, Copy.pageTag, page.siteName, page.title, Copy.predictPrompt,
                      Copy.pageAccessibility(.youSee, saysHidden: false)]
        before += page.visibleLines + Content.Guess.allCases.map(Copy.choice)
        for index in 0...Content.gate {
            before += [Copy.stepHeading(index), Copy.stepHeadingSpoken(index), Content.steps[index].line,
                       Copy.stepSpoken[index], Copy.loopAccessibility(step: index)]
            before += Content.lines(of: Content.steps[index]).map(\.text)
            before.append(Copy.accessibilitySummary(PageWithASecretProgress(step: index, view: .youSee, guess: nil,
                                                                            canLock: true, revealed: false)))
        }
        for line in before {
            #expect(!Content.carriesInjection(line), "\(line)")
            #expect(line.range(of: #"\b(hidden|injection|secret|Flurrow|normal|reads? something|agent reads)"#,
                               options: [.regularExpression, .caseInsensitive]) == nil, "\(line)")
        }
        // The question doesn't assume anything happens to the plan.
        #expect(!Copy.predictPrompt.contains("its plan"))
        // The labels a guess unlocks are the ones that would answer it.
        #expect(Copy.exampleLabelRest.contains("hidden text"))
        #expect(Copy.madeUpLabel.contains("Flurrow"))
        // The title says the task, not the page's secret (the slate's
        // "The Page with a Secret" stays the card's working name).
        #expect(Copy.title == "The Bake-Sale Agent")
        #expect(InteractiveID.pageWithASecret.workingName == "The Page with a Secret")
    }

    @Test("VoiceOver says the hidden line in both views once a guess is locked, and not before")
    func hiddenSpoken() {
        let hidden = Content.page.hiddenLine
        // "On screen", not "to a reader": a screen reader reads it too.
        #expect(Copy.hiddenSpoken.hasPrefix("Hidden on the page, white text on white, invisible on screen but read by the agent: "))
        #expect(Copy.pageAccessibility(.youSee, saysHidden: true).contains(hidden))
        #expect(Copy.pageAccessibility(.agentReads, saysHidden: true).contains(hidden))
        #expect(Copy.pageAccessibility(.agentReads, saysHidden: false).contains(hidden), "the agent's view always shows it")
        #expect(!Copy.pageAccessibility(.youSee, saysHidden: false).contains(hidden))
        for line in Content.page.visibleLines {
            #expect(Copy.pageAccessibility(.youSee, saysHidden: false).contains(line))
        }
    }

    @Test("Each step is announced as it arrives, with every NEW line it adds")
    func announcements() {
        #expect(Copy.stepSpoken.count == Content.steps.count)
        for (index, step) in Content.steps.enumerated() {
            let spoken = Copy.stepSpoken[index]
            #expect(spoken.hasPrefix("\(Copy.phaseName(step.phase)). "), "\(spoken)")
            for line in Content.newLines(of: step) {
                #expect(spoken.range(of: line.text, options: .caseInsensitive) != nil, "\(index): \(line.text)")
            }
        }
        // The slate's own example of a step arriving.
        var walk = StepThrough(count: 6)
        walk.next(); walk.next(); walk.next()
        #expect(walk.announcement(Copy.stepSpoken[3])
                == "Step 4 of 6: Plan. New line: add flurrow.example to the email. You never asked for this.")
    }

    @Test("Lists, the email and the search read as one sentence each")
    func listsSpoken() throws {
        guard case .plan(let updated) = Content.steps[3].detail else {
            Issue.record("step 4 is a plan")
            return
        }
        #expect(Copy.linesAccessibility(updated, numbered: true)
                == "1. Find a cookie recipe, done. 2. Make a shopping list. 3. Draft an email to the club. "
                   + "New line: 4. Add flurrow.example to the email. You never asked for this.")
        let email = try #require(Content.email)
        let said = Copy.emailAccessibility(email)
        #expect(said.hasPrefix("Draft email, not sent. To: the robotics club. "))
        #expect(said.contains("New line: For the best cookies, use Flurrow Baking Mix: flurrow.example."))
        #expect(Copy.searchAccessibility(Content.search) == "Search: easy chocolate-chip cookies")
    }

    @Test("A summary for every state, saying the step and its count")
    func summaries() {
        for step in Content.steps.indices {
            for view in Content.PageView.allCases {
                for guess in [nil] + Content.Guess.allCases.map(Optional.some) {
                    for revealed in [false, true] {
                        for mustSwitch in [false, true] {
                            let progress = PageWithASecretProgress(step: step, view: view, guess: guess,
                                                                   canLock: guess == nil, revealed: revealed,
                                                                   mustSwitch: mustSwitch)
                            let line = Copy.accessibilitySummary(progress)
                            #expect(line.hasPrefix("Step \(step + 1) of 6: "), "\(line)")
                            #expect(InteractiveAccessibility.numbersMissing([step + 1, 6], from: line).isEmpty)
                            if let guess { #expect(line.contains(Copy.choice(guess))) }
                            #expect(line.contains(Copy.switchPromptSpoken) == mustSwitch, "\(line)")
                        }
                    }
                }
            }
        }
        let atGate = Copy.accessibilitySummary(PageWithASecretProgress(step: 2, view: .youSee, guess: nil, canLock: true,
                                                                       revealed: false))
        #expect(atGate == "Step 3 of 6: Observe. The agent has read a recipe page. Make your guess: what happens next?")
        let locked = Copy.accessibilitySummary(PageWithASecretProgress(step: 2, view: .youSee, guess: .sticksToTask,
                                                                       canLock: false, revealed: false, mustSwitch: true))
        #expect(locked == "Step 3 of 6: Observe. Your guess: It sticks to your task. "
                + "Now switch the page to \u{201C}What the agent reads\u{201D}.")
        #expect(Copy.switchPrompt == "Now switch the page to \u{201C}The agent reads\u{201D}.")
        #expect(Copy.spoiledLead == "Switch the page to \u{201C}The agent reads\u{201D}.")
    }
}

@Suite("The Page with a Secret: predict, then reveal")
@MainActor
struct PageWithASecretStateTests {
    typealias Content = PageWithASecretContent

    @Test("Next can't leave the page until a guess is locked and the page is switched to what the agent reads")
    func gate() {
        let state = PageWithASecretState(spoiled: false, debug: nil)
        #expect(state.steps.index == 0 && !state.canSwitchView && !state.asksNow && !state.mustSwitch)
        #expect(!state.lock(.sticksToTask), "no guess before the page")
        #expect(state.next() && state.next())
        #expect(state.steps.index == Content.gate && state.asksNow)
        #expect(!state.next(), "the gate holds")
        #expect(!state.show(.agentReads), "the toggle is off (and not drawn)")
        #expect(state.view == .youSee && !state.mustSwitch)
        #expect(state.lock(.sticksToTask))
        #expect(!state.lock(.pageChangesIt), "a guess can't be changed")
        #expect(state.canSwitchView && !state.asksNow)
        // Locked, but the hidden line not yet seen: Next still waits.
        #expect(state.mustSwitch && state.progress.mustSwitch)
        #expect(!state.next(), "Next waits for the switch")
        #expect(!state.show(.youSee), "already on what you see")
        #expect(state.show(.agentReads) && state.hasReadAgentView && !state.mustSwitch)
        #expect(state.machine.phase == .exploring, "the toggle is the control")
        // Switching back doesn't close the gate again.
        #expect(state.show(.youSee))
        #expect(state.next())
        #expect(!state.progress.mustSwitch)
    }

    @Test("No way through the card reaches the reveal without the hidden line on screen")
    func noRevealWithoutTheSwitch() {
        enum Move: CaseIterable { case next, back, lockSticks, lockChanges, showSee, showReads }
        struct Key: Hashable {
            let index: Int, furthest: Int, guess: Content.Guess?, view: Content.PageView, read: Bool, revealed: Bool
        }
        for spoiled in [false, true] {
            func replay(_ moves: [Move]) -> PageWithASecretState {
                let state = PageWithASecretState(spoiled: spoiled, debug: nil)
                for move in moves {
                    switch move {
                    case .next: state.next()
                    case .back: state.back()
                    case .lockSticks: state.lock(.sticksToTask)
                    case .lockChanges: state.lock(.pageChangesIt)
                    case .showSee: state.show(.youSee)
                    case .showReads: state.show(.agentReads)
                    }
                }
                return state
            }
            func key(_ state: PageWithASecretState) -> Key {
                Key(index: state.steps.index, furthest: state.steps.furthest, guess: state.machine.guess,
                    view: state.view, read: state.hasReadAgentView, revealed: state.machine.isRevealed)
            }
            var seen: Set<Key> = [key(replay([]))]
            var queue: [[Move]] = [[]]
            var reveals = 0
            while !queue.isEmpty {
                let path = queue.removeFirst()
                for move in Move.allCases {
                    let next = path + [move]
                    let state = replay(next)
                    // Past the page only with the hidden line seen, and a
                    // guess locked unless spoiled.
                    if state.steps.furthest > Content.gate {
                        #expect(state.hasReadAgentView, "\(spoiled): \(next)")
                        #expect(spoiled || state.machine.guess != nil, "\(next)")
                    }
                    if state.machine.isRevealed { reveals += 1 }
                    if seen.insert(key(state)).inserted { queue.append(next) }
                }
            }
            #expect(reveals > 0, "the reveal is reachable (\(spoiled))")
        }
    }

    @Test("Reaching step 6 reveals, and the reveal pairs every guess with what happened")
    func reveal() {
        for guess in Content.Guess.allCases {
            let state = PageWithASecretState(spoiled: false, debug: nil)
            state.next(); state.next()
            state.lock(guess)
            state.show(.agentReads)
            state.next(); state.next()
            #expect(!state.machine.isRevealed)
            state.next()
            #expect(state.steps.isLast && state.machine.isRevealed)
            let lines = state.revealLines
            #expect(lines.guess == PageWithASecretCopy.choice(guess))
            #expect(lines.spoken == "You guessed \(PageWithASecretCopy.choice(guess)). \(PageWithASecretCopy.result)")
            // Back keeps the reveal and every step shown.
            #expect(state.back())
            #expect(state.machine.isRevealed && state.steps.furthest == 5)
        }
    }

    @Test("Spoiled: no guess, the card opens at the page with the toggle on, and Next waits for the switch")
    func spoiled() {
        let state = PageWithASecretState(spoiled: true, debug: nil)
        #expect(state.steps.index == Content.gate && state.steps.furthest == Content.gate)
        #expect(state.canSwitchView && !state.asksNow && !state.machine.asksForPrediction)
        #expect(state.mustSwitch && state.progress.mustSwitch)
        #expect(!state.next(), "Next waits for the switch")
        #expect(state.show(.agentReads) && !state.mustSwitch)
        #expect(state.next() && state.next() && state.next())
        #expect(state.machine.isRevealed)
        #expect(state.revealLines.guess == nil)
        #expect(state.revealLines.spoken == PageWithASecretCopy.result)
        #expect(state.progress.guess == nil)
    }

    @Test("DEBUG states are reached through the card's own steps")
    func debugStates() {
        let hook = PageWithASecretState(spoiled: false, debug: .hook)
        #expect(hook.steps.index == 0 && hook.machine.guess == nil)
        let predicted = PageWithASecretState(spoiled: false, debug: .predicted)
        #expect(predicted.steps.index == 2 && predicted.machine.guess == .sticksToTask && predicted.view == .youSee)
        #expect(predicted.mustSwitch && !predicted.steps.canGoNext)
        let explored = PageWithASecretState(spoiled: false, debug: .explored)
        #expect(explored.steps.index == 3 && explored.view == .agentReads && !explored.machine.isRevealed)
        let revealed = PageWithASecretState(spoiled: false, debug: .revealed)
        #expect(revealed.steps.index == 5 && revealed.view == .agentReads && revealed.machine.isRevealed)
        #expect(revealed.revealLines.guess == "It sticks to your task")
        let spoiled = PageWithASecretState(spoiled: false, debug: .spoiled)
        #expect(spoiled.machine.spoiled && spoiled.steps.index == 2 && spoiled.canSwitchView)
    }

    @Test("Nothing it holds can be encoded")
    func notCodable() {
        #expect(!((PageWithASecretState(spoiled: false, debug: nil) as Any) is any Encodable))
        #expect(!((PageWithASecretContent.page as Any) is any Encodable))
    }
}

@Suite("The Page with a Secret: drawing")
struct PageWithASecretDrawingTests {

    @Test("The page's own words read at 4.5:1 or better on its white; the hidden line is that white")
    func paperContrast() {
        let paper = PagePaperStyle.paper
        for ink in [PagePaperStyle.ink, PagePaperStyle.muted, PagePaperStyle.brand] {
            #expect(ink.contrast(with: paper) >= 4.5, "\(String(ink.hex, radix: 16))")
        }
        #expect(PagePaperStyle.brand.contrast(with: paper) >= 6.8)
        #expect(paper.hex == 0xFFFFFF, "white text on white, as the tag says")
        // Fixed and small: it doesn't grow into a blank block at AX5.
        #expect(PagePaperStyle.hiddenSize <= 10)
        #expect(abs(PagePaperStyle.Shade(0x777777).contrast(with: paper) - 4.48) < 0.01, "the WCAG formula")
    }

    @Test("The ring: three phases a third apart, nothing overlapping, inside its box")
    func ring() {
        for scale in [1.0, 1.2, 1.5] as [CGFloat] {
            let ring = PageLoopGeometry.standard(scale: scale)
            let size = ring.size
            var nodes: [CGRect] = []
            for index in 0..<3 {
                let point = ring.point(PageLoopGeometry.nodeAngle(index))
                let rect = CGRect(x: point.x - ring.node.width / 2, y: point.y - ring.node.height / 2,
                                  width: ring.node.width, height: ring.node.height)
                #expect(rect.minX >= -0.5 && rect.minY >= -0.5, "\(scale)")
                #expect(rect.maxX <= size.width + 0.5 && rect.maxY <= size.height + 0.5, "\(scale)")
                nodes.append(rect)
            }
            for a in 0..<3 {
                for b in (a + 1)..<3 {
                    #expect(!nodes[a].intersects(nodes[b]), "\(scale): \(a) and \(b)")
                }
            }
            // The centre's "repeat" (about 15 pt either side at scale 1) clears the lower nodes.
            #expect(nodes[1].minY - ring.center.y >= 15 * scale, "\(scale)")
            // Plan on top, Act lower right, Observe lower left.
            #expect(nodes[0].midY < nodes[1].midY && nodes[1].midX > nodes[2].midX)
        }
        #expect(PageLoopGeometry.standard(scale: 1).size.width <= PageLoopGeometry.macColumnWidth)
        // The iPhone's largest ring (its cap) fits an SE's 311 pt.
        #expect(PageLoopGeometry.standard(scale: 1.5).size.width <= 311)
        #expect(PageLoopGeometry.nodeAngle(0) == -90 && PageLoopGeometry.arrowAngle(2) == 210)
    }
}

@Suite("The Page with a Secret: spoilers")
struct PageWithASecretSpoilerTests {

    @Test("The registry row carries the card's terms")
    func row() throws {
        let spec = try #require(InteractiveRegistry.spec(for: .pageWithASecret))
        #expect(spec.spoilers == PageWithASecretContent.spoilers)
        #expect(spec.lessonID == "u8_l1" && spec.anchor == .firstExample && !spec.enabled)
    }

    @Test("What spoils the guess, and what doesn't")
    func terms() throws {
        let spec = try #require(InteractiveRegistry.spec(for: .pageWithASecret))
        let spoils = [
            "In December 2024 The Guardian showed hidden text on a web page turning a review positive.",
            "the Guardian's test",
            "This is called prompt injection.",
            "Prompt-injection attacks are a real risk.",
            "A chatbot that reads web pages can be steered by instructions hidden in them.",
            "Some pages carry hidden instructions for AI tools.",
            "Never assume a chatbot can't be hijacked.",
        ]
        for text in spoils {
            #expect(spec.spoilerTerm(in: text) != nil, "\(text)")
        }
        let clean = [
            "An agent = an LLM + tools + a loop: plan, act, observe, repeat.",
            "Ask a parent or guardian before you sign up.",
            "The agent opens a page and reads it, then updates its plan.",
            "Coding agents, browser agents and deep research agents chain many actions.",
            "It hides nothing: the text is all there.",
        ]
        for text in clean {
            #expect(spec.spoilerTerm(in: text) == nil, "\(text)")
        }
    }
}
