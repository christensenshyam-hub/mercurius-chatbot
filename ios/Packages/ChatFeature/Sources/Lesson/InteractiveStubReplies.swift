#if DEBUG
import Foundation
import LessonInteractives

/// DEBUG only: authored stand-ins for Merc's replies in a lesson that has
/// no recording (only Unit 1, Lesson 1 was recorded: `LessonReplay`), so a
/// card can be seen in its lesson with no server (`-Interactive <slug>`).
///
/// Every stub says it is a stub, in its first line and in its check, and
/// carries no lesson content. Each is shaped so the lesson's card lands
/// where its real anchor rule puts it, through the real placement code:
///
/// - `.firstExample`: the first reply has an [EX] part, then a check.
/// - `.teachReply(n)`: n replies with a check; the nth has the [EX] part.
/// - `.firstReplyMentioning(terms, …)`: a first reply with a check and no
///   term; the second says the first term, with the [EX] part.
///
/// With `spoiled` (`-InteractiveStubSpoiled YES`) the card's reply names the
/// card's first spoiler term above the card, so the spoiled mode is reached
/// by the real spoiler scan. A lesson without a card gets the
/// `.firstExample` shape.
enum InteractiveStubReplies {
    static func replies(forLesson lessonID: String, spoiled: Bool) -> [String] {
        let spec = InteractiveRegistry.all.first { $0.lessonID == lessonID }
        let anchor = spec?.anchor ?? .firstExample
        let spoiler = spoiled ? spec?.spoilers.first : nil
        let card = spec?.id.slug ?? "none"
        let mention: String?
        let anchorReply: Int
        switch anchor {
        case .firstExample:
            anchorReply = 1
            mention = nil
        case .teachReply(let n):
            anchorReply = max(n, 1)
            mention = nil
        case .firstReplyMentioning(let terms, _):
            anchorReply = anchor.repliesToReach
            mention = terms.first
        }
        let total = anchorReply + 1
        var replies: [String] = []
        for number in 1..<total {
            if number == anchorReply {
                replies.append(cardReply(number, of: total, lessonID: lessonID, card: card, mention: mention,
                                         spoiler: spoiler))
            } else {
                replies.append(teachReply(number, of: total, lessonID: lessonID))
            }
        }
        replies.append(closingReply(total, lessonID: lessonID))
        return replies
    }

    private static func heading(_ number: Int, of total: Int) -> String {
        "**Debug stub, reply \(number) of \(total).**"
    }

    private static let check = """
    [Q]
    Stub check: what is this reply?
    A) A stand-in for Merc\u{2019}s reply
    B) Lesson content
    ANS: A
    [/Q]
    """

    /// The reply that holds the card.
    private static func cardReply(_ number: Int, of total: Int, lessonID: String, card: String, mention: String?,
                                  spoiler: String?) -> String {
        var extra: [String] = []
        if let mention {
            extra.append("Stub mention: this reply says \u{201C}\(mention)\u{201D}, the word the card\u{2019}s anchor looks for.")
        }
        if let spoiler {
            extra.append("Stub spoiler: this line says \u{201C}\(spoiler)\u{201D} above the card, so it opens in its spoiled mode.")
        }
        return """
        \(heading(number, of: total)) This stands in for Merc\u{2019}s reply in lesson \(lessonID), so its interactive (\(card)) can be seen without a server. It is not lesson content.

        ---

        **Stub example**

        [EX]Stub example. A real lesson\u{2019}s example goes here.[/EX]

        \((extra + ["The interactive goes after this part, before the check."]).joined(separator: " "))

        ---

        \(check)
        """
    }

    /// A reply with a check and no card (it comes before the card's).
    private static func teachReply(_ number: Int, of total: Int, lessonID: String) -> String {
        """
        \(heading(number, of: total)) This stands in for Merc\u{2019}s reply in lesson \(lessonID). It is not lesson content, and the interactive waits for a later reply.

        ---

        \(check)
        """
    }

    private static func closingReply(_ number: Int, lessonID: String) -> String {
        "\(heading(number, of: number)) The stub replies for lesson \(lessonID) end here. Nothing after this is stubbed."
    }
}
#endif
