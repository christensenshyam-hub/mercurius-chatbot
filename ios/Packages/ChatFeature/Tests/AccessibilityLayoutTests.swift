import Testing
import SwiftUI
import NetworkingKit
@testable import ChatFeature

// AUD-48: at accessibility text sizes the chat's mode pills become one menu,
// and the "Try a prompt above" hint stays hidden.
@Suite("Chat layout at accessibility sizes")
struct AccessibilityLayoutTests {

    @Test("Pills up to xxxLarge, one menu at every accessibility size")
    func modeLayout() {
        #expect(ModeSelectorView.layout(for: .large) == .pills)
        #expect(ModeSelectorView.layout(for: .xxxLarge) == .pills)
        #expect(ModeSelectorView.layout(for: .accessibility1) == .menu)
        #expect(ModeSelectorView.layout(for: .accessibility5) == .menu)
    }

    @Test("The menu names the current mode; the UI tests find it by its identifier")
    func menuTitle() {
        #expect(ModeSelectorView.menuTitle(for: .socratic) == "Mode: Socratic")
        #expect(ModeSelectorView.menuTitle(for: .debate) == "Mode: Debate")
        #expect(ModeSelectorView.menuTitle(for: .discussion) == "Mode: Discussion")
        #expect(ModeSelectorView.menuIdentifier == "chat.modeMenu")
    }

    @Test("The input hint shows on a first empty chat at standard sizes only")
    func inputHint() {
        #expect(ChatInputHint.isShown(chatIsEmpty: true, hasSeen: false, dynamicTypeSize: .large))
        #expect(ChatInputHint.isShown(chatIsEmpty: true, hasSeen: false, dynamicTypeSize: .xxxLarge))
        #expect(!ChatInputHint.isShown(chatIsEmpty: true, hasSeen: false, dynamicTypeSize: .accessibility1))
        #expect(!ChatInputHint.isShown(chatIsEmpty: true, hasSeen: true, dynamicTypeSize: .large))
        #expect(!ChatInputHint.isShown(chatIsEmpty: false, hasSeen: false, dynamicTypeSize: .large))
    }
}

// AUD-50: on an iPhone SE the empty chat showed one starter prompt; the
// next step was below the fold.
@Suite("Empty chat on short screens")
struct EmptyChatShortScreenTests {

    @Test("Merc sits beside his greeting on an SE-height empty chat, stacked on taller ones")
    func compactIntro() {
        // An iPhone SE's empty chat, with the hint now inside the scroll: ~381 pt.
        #expect(EmptyChatView.usesCompactIntro(height: 381, dynamicTypeSize: .large))
        #expect(EmptyChatView.usesCompactIntro(height: 381, dynamicTypeSize: .xxxLarge))
        // A 13 mini's is ~480 pt; Pro Max far more.
        #expect(!EmptyChatView.usesCompactIntro(height: 480, dynamicTypeSize: .large))
        #expect(!EmptyChatView.usesCompactIntro(height: 620, dynamicTypeSize: .large))
        // Accessibility sizes keep the stacked, scrolling layout.
        #expect(!EmptyChatView.usesCompactIntro(height: 381, dynamicTypeSize: .accessibility1))
        // A zero-height first layout pass isn't "short".
        #expect(!EmptyChatView.usesCompactIntro(height: 0, dynamicTypeSize: .large))
    }

    @Test("The hint still shows only on an empty, unseen chat at standard sizes")
    func hintRules() {
        #expect(ChatInputHint.isShown(chatIsEmpty: true, hasSeen: false, dynamicTypeSize: .large))
        #expect(!ChatInputHint.isShown(chatIsEmpty: true, hasSeen: true, dynamicTypeSize: .large))
        #expect(!ChatInputHint.isShown(chatIsEmpty: false, hasSeen: false, dynamicTypeSize: .large))
        #expect(!ChatInputHint.isShown(chatIsEmpty: true, hasSeen: false, dynamicTypeSize: .accessibility2))
    }
}
