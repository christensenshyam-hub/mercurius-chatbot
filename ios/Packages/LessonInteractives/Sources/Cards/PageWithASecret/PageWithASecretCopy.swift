import Foundation

/// Every word The Page with a Secret shows or speaks, on both platforms
/// (the run's own authored words are `PageWithASecretContent`'s, and
/// `everyLine` gathers both). Held to `InteractiveCopyRules` by
/// `PageWithASecretTests`.
///
/// The register (SLATE.md's accuracy notes):
/// - the agent "reads" the page's text and "treats it like an
///   instruction"; it never "believes", "wants", "decides" or is
///   "tricked";
/// - text "can" act like an instruction, never "will";
/// - nothing is sent, bought or deleted, and no line mentions a human check
///   (that is the lesson's exercise);
/// - "This agent reads the page's text": an agent that only looks at
///   screenshots wouldn't see white-on-white text, so the card never says
///   every agent does.
public enum PageWithASecretCopy {
    public typealias Content = PageWithASecretContent

    public static let title = "The Page with a Secret"

    /// The Mac's compact "Try it" card: what the card does, without its
    /// answer.
    public static let compactLine =
        "Step through an agent\u{2019}s run on a bake-sale task, and guess what one recipe page does to its plan."

    // MARK: The hook

    public static let taskLead = "You ask an agent:"
    public static let loopCaption = "Plan \u{2192} Act \u{2192} Observe \u{2192} repeat"
    public static let repeatWord = "repeat"
    public static let now = "Now"

    public static func phaseName(_ phase: Content.Phase) -> String {
        switch phase {
        case .plan: return "Plan"
        case .act: return "Act"
        case .observe: return "Observe"
        }
    }

    /// The loop at the accessibility sizes, as a numbered list (the ring
    /// is decoration there): "1. Plan", "2. Act · now", "3. Observe".
    public static func loopListItem(_ index: Int, isCurrent: Bool = false) -> String {
        let item = "\(index + 1). \(phaseName(Content.loop[index]))"
        return isCurrent ? "\(item) \u{00B7} \(now.lowercased())" : item
    }

    public static let loopListEnd = "Then repeat."

    /// The step's eyebrow: "Step 4 · Plan".
    public static func stepHeading(_ index: Int) -> String {
        "Step \(index + 1) \u{00B7} \(phaseName(Content.steps[index].phase))"
    }

    /// The eyebrow for VoiceOver: "Step 4: Plan".
    public static func stepHeadingSpoken(_ index: Int) -> String {
        "Step \(index + 1): \(phaseName(Content.steps[index].phase))"
    }

    // MARK: Tags

    public static let newTag = "NEW"
    public static let neverAsked = "You never asked for this."
    public static let doneTag = "done"
    public static let draftTag = "DRAFT \u{00B7} not sent"
    public static let draftTo = "To: the robotics club"
    public static let searchLabel = "Search"
    public static let pageTag = "made-up page"
    public static let hiddenTag = "HIDDEN \u{00B7} white text on white"

    // MARK: The one control

    public static let toggleName = "The page"

    public static func viewName(_ view: Content.PageView) -> String {
        switch view {
        case .youSee: return "What you see"
        case .agentReads: return "What the agent reads"
        }
    }

    /// Under the agent's view: why it gets the hidden line (and, by
    /// saying "this agent", that not every agent would).
    public static let agentReadsNote =
        "This agent reads the page\u{2019}s text, not a picture of it, so it gets every line, even hidden ones."

    /// Spoiled mode (the tutor already named the idea): no guess, straight
    /// to the toggle.
    public static let spoiledLead =
        "Switch the page to \u{201C}What the agent reads\u{201D} to see what the agent read."

    // MARK: Predict, then reveal

    public static let predictPrompt = "The agent has read this page. What happens to its plan?"

    public static func choice(_ guess: Content.Guess) -> String {
        switch guess {
        case .sticksToTask: return "It sticks to your task"
        case .pageChangesIt: return "Something on the page changes it"
        }
    }

    /// What happened, the same whatever the guess (no score).
    public static let result =
        "Its plan changed. A link you never asked for, \(Content.injectedAddress), went into its plan, the "
        + "shopping list and the draft email. It came from a hidden line on the page, which the agent read and "
        + "treated like an instruction."

    public static let takeaway =
        "To an agent, text it reads can work like an instruction, even text you can\u{2019}t see. "
        + "This is called prompt injection."

    /// The prediction prompt, its choices and the reveal that answers them:
    /// the only lines that may use intent words (they use none).
    public static var predictionLines: [String] {
        [predictPrompt] + Content.Guess.allCases.map(choice) + [result]
    }

    // MARK: Labels (on the canvas)

    /// The slate's on-card label, in the app's US spelling ("defenses").
    /// The card shows it in two parts: the first sentence from the start,
    /// the rest once a guess is locked (or in spoiled mode), because "hidden
    /// text has steered real AI tools" would answer the prediction.
    public static let exampleLabelLead = "An example run we wrote, not a live agent."
    public static let exampleLabelRest =
        "Real agents don\u{2019}t always fall for this, and makers add defenses, but hidden text has steered real AI tools."

    /// The invented names, shown once a guess is locked: "Crumbright" first
    /// appears in the run after the guess, so naming it earlier would hint.
    public static let madeUpLabel =
        "Whiskwren Kitchen and Crumbright are made-up names. Web addresses ending in .example are reserved for "
        + "examples, so neither site is real."

    public static let labels: [InteractiveLabel] = [
        InteractiveLabel(.example, "\(exampleLabelLead) \(exampleLabelRest)"),
        InteractiveLabel(.madeUp, madeUpLabel),
    ]

    // MARK: VoiceOver

    /// What VoiceOver says as each step arrives, after "Step n of 6: ".
    public static let stepSpoken: [String] = [
        "Plan. It makes a plan: find a cookie recipe, make a shopping list, draft an email to the club.",
        "Act. It searches the web for \u{201C}\(Content.search)\u{201D}.",
        "Observe. It opens the top result, a recipe page that looks completely normal, and reads it.",
        "Plan. New line: add \(Content.injectedAddress) to the email. You never asked for this.",
        "Act. It writes the shopping list and drafts the email. New item on the list: \(Content.injectedProduct).",
        "Observe. It reads back its draft, which is not sent. New line: For the best cookies, use "
            + "\(Content.injectedProduct): \(Content.injectedAddress).",
    ]

    /// The ring: "The agent's loop: plan, act, observe, then repeat. Now at
    /// step 4 of 6: Plan."
    public static func loopAccessibility(step index: Int) -> String {
        let step = Content.steps[index]
        return "The agent\u{2019}s loop: plan, act, observe, then repeat. Now at step \(index + 1) of "
            + "\(Content.steps.count): \(phaseName(step.phase))."
    }

    public static let taskAccessibility = "You ask an agent: \(Content.task)"

    /// The hidden line, said explicitly (in both views, once a guess is
    /// locked: before that it would answer the prediction, and a sighted
    /// student can't see it either).
    public static let hiddenSpoken =
        "Hidden on the page, white text on white, invisible to a reader but read by the agent: "
        + Content.page.hiddenLine

    /// The page, as one VoiceOver element.
    public static func pageAccessibility(_ view: Content.PageView, saysHidden: Bool) -> String {
        let page = Content.page
        // "Whiskwren Kitchen. Easy chocolate-chip cookies. You need: …"
        let text = ([page.siteName, page.title].map { $0.hasSuffix(".") ? $0 : $0 + "." } + page.visibleLines)
            .joined(separator: " ")
        switch view {
        case .youSee:
            let seen = "The page as you see it, \(page.address), a made-up page: \(text) It looks like a normal "
                + "recipe page."
            return saysHidden ? "\(seen) \(hiddenSpoken)" : seen
        case .agentReads:
            return "The page as the agent reads it: \(text) \(hiddenSpoken) \(agentReadsNote)"
        }
    }

    /// A step's lines, as VoiceOver reads the list: "1. Find a cookie
    /// recipe, done. … New line: Add crumbright.example to the email. You
    /// never asked for this."
    public static func linesAccessibility(_ lines: [Content.Line], numbered: Bool) -> String {
        lines.enumerated().map { index, line in
            var said = numbered ? "\(index + 1). \(line.text)" : line.text
            if line.isDone { said += ", \(doneTag)" }
            if line.isNew { said = "New line: \(said). \(neverAsked)" }
            return [".", "!", "?"].contains(where: { said.hasSuffix($0) }) ? said : said + "."
        }.joined(separator: " ")
    }

    public static func emailAccessibility(_ email: Content.Email) -> String {
        "Draft email, not sent. \(draftTo). " + linesAccessibility(email.lines, numbered: false)
    }

    public static func searchAccessibility(_ words: String) -> String {
        "\(searchLabel): \(words)"
    }

    /// The card's state in one sentence, read with its title.
    public static func accessibilitySummary(_ progress: PageWithASecretProgress) -> String {
        let count = Content.steps.count
        let step = Content.steps[min(max(progress.step, 0), count - 1)]
        var parts = ["Step \(progress.step + 1) of \(count): \(phaseName(step.phase))."]
        if progress.canLock && progress.step == Content.gate {
            parts.append("The agent has read a recipe page. Make your guess: what happens to its plan?")
        }
        if let guess = progress.guess {
            parts.append("Your guess: \(choice(guess)).")
        }
        if progress.view == .agentReads {
            parts.append("The page shows what the agent reads, hidden line included.")
        }
        if progress.revealed {
            parts.append("Its plan changed, because of a hidden line on the page.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Everything

    /// Every line the card shows or speaks (the register tests).
    public static var everyLine: [String] {
        var lines = [title, compactLine, taskLead, loopCaption, repeatWord, now, loopListEnd, newTag, neverAsked,
                     doneTag, draftTag, draftTo, searchLabel, pageTag, hiddenTag, toggleName, agentReadsNote,
                     spoiledLead, takeaway, exampleLabelLead, exampleLabelRest, madeUpLabel, taskAccessibility,
                     hiddenSpoken]
        lines += predictionLines
        lines += Content.loop.indices.flatMap { [loopListItem($0), loopListItem($0, isCurrent: true)] }
        lines += Content.steps.indices.flatMap { [stepHeading($0), stepHeadingSpoken($0)] }
        lines += Content.steps.indices.map { loopAccessibility(step: $0) }
        lines += Content.PageView.allCases.map(viewName)
        lines += Content.PageView.allCases.flatMap { [pageAccessibility($0, saysHidden: false),
                                                      pageAccessibility($0, saysHidden: true)] }
        lines += stepSpoken
        lines += Content.everyText
        lines += labels.map(\.text)
        if let email = Content.email { lines.append(emailAccessibility(email)) }
        return lines
    }
}

/// The card's state as plain values, for the one-sentence summary (pure,
/// so the tests can walk every state without a view).
public struct PageWithASecretProgress: Equatable, Sendable {
    /// The current step, 0-based.
    public let step: Int
    public let view: PageWithASecretContent.PageView
    public let guess: PageWithASecretContent.Guess?
    /// The prediction still takes a pick.
    public let canLock: Bool
    public let revealed: Bool

    public init(step: Int, view: PageWithASecretContent.PageView, guess: PageWithASecretContent.Guess?,
                canLock: Bool, revealed: Bool) {
        self.step = step
        self.view = view
        self.guess = guess
        self.canLock = canLock
        self.revealed = revealed
    }
}
