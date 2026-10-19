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
