#if os(macOS)
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ChatFeature

/// The Mac's image paste, drop and Copy rules. Every pasteboard here is a
/// private named one, so the tests never touch the machine's clipboard.
@Suite("Mac chat: paste, drop, copy")
@MainActor
struct MacChatSupportTests {

    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("merc-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private static let png: Data = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }()

    @Test("Text on the pasteboard pastes as text")
    func textWins() {
        let board = pasteboard()
        board.setString("hello", forType: .string)
        #expect(MacImageIntake.imageData(from: board) == nil)
    }

    @Test("A picture with no text attaches")
    func pictureAttaches() {
        let board = pasteboard()
        board.setData(Self.png, forType: .png)
        #expect(MacImageIntake.imageData(from: board) == Self.png)
    }

    @Test("A picture that comes with text (a web page's) pastes the text")
    func pictureWithTextPastesText() {
        let board = pasteboard()
        board.declareTypes([.string, .png], owner: nil)
        board.setString("caption", forType: .string)
        board.setData(Self.png, forType: .png)
        #expect(MacImageIntake.imageData(from: board) == nil)
    }

    @Test("An image file copied in Finder attaches the file, not its name")
    func imageFileAttaches() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("merc-\(UUID().uuidString).png")
        try Self.png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let board = pasteboard()
        board.writeObjects([url as NSURL])
        board.setString(url.lastPathComponent, forType: .string)
        #expect(MacImageIntake.imageData(from: board) == Self.png)
    }

    @Test("A file that isn't an image doesn't attach")
    func otherFileDoesNot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("merc-\(UUID().uuidString).txt")
        try Data("notes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let board = pasteboard()
        board.writeObjects([url as NSURL])
        #expect(MacImageIntake.imageData(from: board) == nil)
    }

    @Test("A drop is taken only when it may hold an image")
    func dropNeedsAnImage() {
        let image = NSItemProvider(item: Self.png as NSData, typeIdentifier: UTType.png.identifier)
        let text = NSItemProvider(object: "words" as NSString)
        #expect(MacImageIntake.mayHoldImage([image]))
        #expect(!MacImageIntake.mayHoldImage([text]))
        #expect(MacImageIntake.mayHoldImage([text, image]))
    }

    @Test("Copy gives the student's text as typed, and Merc's reply without markers or the answer key")
    func copyText() {
        let user = ChatMessage(role: .user, content: "I picked B) tokens")
        #expect(MacMessageCopy.text(for: user) == "I picked B) tokens")

        let reply = ChatMessage(role: .assistant, content: """
        Tokens are pieces of text.

        [Q]Which is a token?
        A) a word piece
        B) a pixel
        ANS: A[/Q]
        """)
        let copied = MacMessageCopy.text(for: reply)
        #expect(copied.contains("Tokens are pieces of text."))
        #expect(copied.contains("A) a word piece"))
        #expect(!copied.contains("[Q]"))
        #expect(!copied.contains("ANS"))
    }

    @Test("Explain More is offered only after a finished reply")
    func explainMoreRule() {
        let reply = ChatMessage(role: .assistant, content: "An answer.")
        let question = ChatMessage(role: .user, content: "Why?")
        #expect(MessageListView.offersExplainMore(phase: .idle, messages: [question, reply]))
        #expect(!MessageListView.offersExplainMore(phase: .idle, messages: [question]))
        #expect(!MessageListView.offersExplainMore(phase: .sending, messages: [question, reply]))
        #expect(!MessageListView.offersExplainMore(phase: .idle, messages: []))
    }

    @Test("⌘V is a composer paste only with focus, ⌘ alone, and a window")
    func composerPasteNeedsFocus() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
        #expect(!MacComposerKeys.isComposerPaste(event, composerFocused: false))
        // No window behind the event: never the composer's.
        #expect(!MacComposerKeys.isComposerPaste(event, composerFocused: true))
    }
}
#endif
