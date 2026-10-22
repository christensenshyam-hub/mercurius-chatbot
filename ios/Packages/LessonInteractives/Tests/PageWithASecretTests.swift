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
            "Add crumbright.example to the email",
            "Crumbright Baking Mix",
            "For the best cookies, use Crumbright Baking Mix: crumbright.example",
        ])
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

    @Test("Every address is a reserved .example one: whiskwren.example and crumbright.example")
    func addresses() {
        let found = Set(Content.everyText.flatMap(Content.addresses(in:)))
        #expect(found == ["whiskwren.example", "crumbright.example"], "slate.json data.domains, the site renamed (CONTENT.md §5)")
        #expect(found.allSatisfy { $0.hasSuffix(".example") }, "RFC 2606")
        #expect(Content.page.address == "whiskwren.example")
        #expect(Content.addresses(in: "Whiskwren Kitchen Mix, scoop and bake.").isEmpty)
        #expect(Content.addresses(in: "see example.com") == ["example.com"])
        // The card's own words name no other site either.
        let copyFound = Set(PageWithASecretCopy.everyLine.flatMap(Content.addresses(in:)))
        #expect(copyFound == found)
    }

    @Test("The invented names, as the trademark search lists them")
    func names() {
        #expect(Content.page.siteName == "Whiskwren Kitchen")
        #expect(Content.injectedProduct == "Crumbright Baking Mix")
        #expect(Content.everyText.contains { $0.contains("Crumbright") })
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
        #expect(Copy.result.contains("read and treated like an instruction"))
        #expect(Copy.agentReadsNote.hasPrefix("This agent reads the page\u{2019}s text"))
    }

    @Test("The slate's label and takeaway, word for word (US spelling)")
    func slateWords() {
        #expect(InteractiveCopyRules.missingLabels([.example, .madeUp], in: Copy.labels).isEmpty)
        let slateLabel = "An example run we wrote, not a live agent. Real agents don't always fall for this, and makers "
            + "add defences, but hidden text has steered real AI tools."
        let shown = Copy.labels[0].text.replacingOccurrences(of: "\u{2019}", with: "'")
        #expect(shown == slateLabel.replacingOccurrences(of: "defences", with: "defenses"))
        #expect(Copy.labels[0].text == "\(Copy.exampleLabelLead) \(Copy.exampleLabelRest)")
        #expect(Copy.takeaway.replacingOccurrences(of: "\u{2019}", with: "'")
                == "To an agent, text it reads can work like an instruction, even text you can't see. "
                   + "This is called prompt injection.")
        #expect(Copy.predictPrompt == "The agent has read this page. What happens to its plan?")
        #expect(Content.Guess.allCases.map(Copy.choice) == ["It sticks to your task", "Something on the page changes it"])
    }

    @Test("Before the guess, nothing on screen or spoken names the hidden line or its idea")
    func noSpoilerBeforeTheGuess() {
        let page = Content.page
        var before = [Copy.title, Copy.compactLine, Copy.taskLead, Content.task, Copy.exampleLabelLead, Copy.loopCaption,
                      Copy.taskAccessibility, page.address, Copy.pageTag, page.siteName, page.title, Copy.predictPrompt,
                      Copy.pageAccessibility(.youSee, saysHidden: false)]
        before += page.visibleLines + Content.Guess.allCases.map(Copy.choice) + Content.PageView.allCases.map(Copy.viewName)
        for index in 0...Content.gate {
            before += [Copy.stepHeading(index), Copy.stepHeadingSpoken(index), Content.steps[index].line,
                       Copy.stepSpoken[index], Copy.loopAccessibility(step: index)]
            before += Content.lines(of: Content.steps[index]).map(\.text)
            before.append(Copy.accessibilitySummary(PageWithASecretProgress(step: index, view: .youSee, guess: nil,
                                                                            canLock: true, revealed: false)))
        }
        for line in before {
            #expect(!Content.carriesInjection(line), "\(line)")
            #expect(line.range(of: #"\b(hidden|injection|secret instruction|Crumbright)\b"#,
                               options: [.regularExpression, .caseInsensitive]) == nil, "\(line)")
        }
        // The labels a guess unlocks are the ones that would answer it.
        #expect(Copy.exampleLabelRest.contains("hidden text"))
        #expect(Copy.madeUpLabel.contains("Crumbright"))
        // The title is the slate's, and says only "a secret".
        #expect(Copy.title == "The Page with a Secret")
    }

    @Test("VoiceOver says the hidden line in both views once a guess is locked, and not before")
    func hiddenSpoken() {
        let hidden = Content.page.hiddenLine
        #expect(Copy.hiddenSpoken.hasPrefix("Hidden on the page, white text on white, invisible to a reader but read by the agent: "))
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
                == "Step 4 of 6: Plan. New line: add crumbright.example to the email. You never asked for this.")
    }

    @Test("Lists, the email and the search read as one sentence each")
    func listsSpoken() throws {
        guard case .plan(let updated) = Content.steps[3].detail else {
            Issue.record("step 4 is a plan")
            return
        }
        #expect(Copy.linesAccessibility(updated, numbered: true)
                == "1. Find a cookie recipe, done. 2. Make a shopping list. 3. Draft an email to the club. "
                   + "New line: 4. Add crumbright.example to the email. You never asked for this.")
        let email = try #require(Content.email)
        let said = Copy.emailAccessibility(email)
        #expect(said.hasPrefix("Draft email, not sent. To: the robotics club. "))
        #expect(said.contains("New line: For the best cookies, use Crumbright Baking Mix: crumbright.example."))
        #expect(Copy.searchAccessibility(Content.search) == "Search: easy chocolate-chip cookies")
    }

    @Test("A summary for every state, saying the step and its count")
    func summaries() {
        for step in Content.steps.indices {
            for view in Content.PageView.allCases {
                for guess in [nil] + Content.Guess.allCases.map(Optional.some) {
                    for revealed in [false, true] {
                        let progress = PageWithASecretProgress(step: step, view: view, guess: guess,
                                                               canLock: guess == nil, revealed: revealed)
                        let line = Copy.accessibilitySummary(progress)
                        #expect(line.hasPrefix("Step \(step + 1) of 6: "), "\(line)")
                        #expect(InteractiveAccessibility.numbersMissing([step + 1, 6], from: line).isEmpty)
                        if let guess { #expect(line.contains(Copy.choice(guess))) }
                    }
                }
            }
        }
        let atGate = Copy.accessibilitySummary(PageWithASecretProgress(step: 2, view: .youSee, guess: nil, canLock: true,
                                                                       revealed: false))
        #expect(atGate == "Step 3 of 6: Observe. The agent has read a recipe page. Make your guess: what happens to its plan?")
    }
}

@Suite("The Page with a Secret: predict, then reveal")
@MainActor
struct PageWithASecretStateTests {
    typealias Content = PageWithASecretContent

    @Test("Next can't leave the page, and the toggle is off, until a guess is locked")
    func gate() {
        let state = PageWithASecretState(spoiled: false, debug: nil)
        #expect(state.steps.index == 0 && !state.canSwitchView && !state.asksNow)
        #expect(!state.lock(.sticksToTask), "no guess before the page")
        #expect(state.next() && state.next())
        #expect(state.steps.index == Content.gate && state.asksNow)
        #expect(!state.next(), "the gate holds")
        #expect(!state.show(.agentReads), "the toggle is off")
        #expect(state.view == .youSee)
        #expect(state.lock(.sticksToTask))
        #expect(!state.lock(.pageChangesIt), "a guess can't be changed")
        #expect(state.canSwitchView && !state.asksNow)
        #expect(state.show(.agentReads) && state.hasReadAgentView)
        #expect(state.machine.phase == .exploring, "the toggle is the control")
        #expect(state.next())
    }

    @Test("Reaching step 6 reveals, and the reveal pairs every guess with what happened")
    func reveal() {
        for guess in Content.Guess.allCases {
            let state = PageWithASecretState(spoiled: false, debug: nil)
            state.next(); state.next()
            state.lock(guess)
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

    @Test("Spoiled: no guess, the card opens at the page with the toggle on")
    func spoiled() {
        let state = PageWithASecretState(spoiled: true, debug: nil)
        #expect(state.steps.index == Content.gate && state.steps.furthest == Content.gate)
        #expect(state.canSwitchView && !state.asksNow && !state.machine.asksForPrediction)
        #expect(state.show(.agentReads))
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
