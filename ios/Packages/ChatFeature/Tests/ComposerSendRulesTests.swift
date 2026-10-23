import SwiftUI
import Testing
@testable import ChatFeature

/// When the composer sends. The send button uses this rule on both
/// platforms; on the Mac, Return goes through it too (the field's
/// `onSubmit`), so an empty Return or one pressed mid-reply sends nothing.
@Suite("Composer: when a message can go")
struct ComposerSendRulesTests {

    private func canSend(_ text: String, attachment: Bool = false, sending: Bool = false,
                         preparing: Bool = false) -> Bool {
        ChatInputBar.canSend(text: text, hasAttachment: attachment, isSending: sending,
                             isPreparingAttachment: preparing)
    }

    @Test("Text sends; an empty field, or only spaces and line breaks, doesn't")
    func textNeeded() {
        #expect(canSend("What is a token?"))
        #expect(!canSend(""))
        #expect(!canSend("   "))
        // Shift-Return on its own leaves only line breaks in the field.
        #expect(!canSend("\n\n"))
        #expect(!canSend(" \n\t "))
    }

    @Test("Two lines from Shift-Return send as one message")
    func multilineSends() {
        #expect(canSend("Why do chatbots sound so sure?\nEven when they're wrong?"))
    }

    @Test("A photo alone sends")
    func photoAlone() {
        #expect(canSend("", attachment: true))
    }

    @Test("Nothing sends while a reply is on its way or a photo is still being prepared")
    func busy() {
        #expect(!canSend("Hello", sending: true))
        #expect(!canSend("", attachment: true, sending: true))
        #expect(!canSend("Hello", preparing: true))
        #expect(!canSend("", attachment: true, preparing: true))
    }
}

#if os(macOS)
/// The Mac composer's Return key: Return sends, Shift-Return breaks the
/// line, and the field keeps Return while an input method composes and for
/// Option-Return (the Mac's own line break).
@Suite("Mac composer: the Return key")
struct MacComposerReturnKeyTests {

    @Test("Return on its own sends")
    func plainReturnSends() {
        #expect(MacComposerKeys.returnAction(modifiers: [], isComposing: false) == .send)
    }

    @Test("Shift-Return breaks the line, whatever else is held")
    func shiftReturnBreaksTheLine() {
        #expect(MacComposerKeys.returnAction(modifiers: .shift, isComposing: false) == .newline)
        #expect(MacComposerKeys.returnAction(modifiers: [.shift, .option], isComposing: false) == .newline)
        #expect(MacComposerKeys.returnAction(modifiers: [.shift, .capsLock], isComposing: false) == .newline)
    }

    @Test("Option-Return is left to the field, which breaks the line itself")
    func optionReturnIsTheField() {
        #expect(MacComposerKeys.returnAction(modifiers: .option, isComposing: false) == .field)
    }

    @Test("While an input method is composing, Return confirms the composition — it never sends or breaks the line")
    func composingKeepsReturn() {
        #expect(MacComposerKeys.returnAction(modifiers: [], isComposing: true) == .field)
        #expect(MacComposerKeys.returnAction(modifiers: .shift, isComposing: true) == .field)
        #expect(MacComposerKeys.returnAction(modifiers: .option, isComposing: true) == .field)
    }
}
#endif
