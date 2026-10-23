import Foundation
import SwiftUI
import Testing
@testable import LessonInteractives

@Suite("Interactives: DEBUG launch arguments")
struct LaunchOptionsTests {

    @Test("Each argument parses, by slug or raw value")
    func parse() {
        let options = InteractiveLaunchOptions(arguments: [
            "Mercurius", "-Interactive", "doubt-dial", "-InteractiveState", "revealed", "-InteractiveScroll", "reveal",
            "-InteractiveStubSpoiled", "YES", "-InteractiveReduceMotion", "YES", "-InteractiveCompact", "1",
        ])
        #expect(options.card == .doubtDial)
        #expect(options.gallery == nil)
        #expect(options.state == .revealed)
        #expect(options.scroll == .reveal)
        #expect(options.stubSpoiled)
        #expect(options.reduceMotion)
        #expect(!options.reduceTransparency)
        #expect(!options.increaseContrast)
        #expect(options.macCompact)

        let gallery = InteractiveLaunchOptions(arguments: ["-InteractiveGallery", "pageWithASecret",
                                                           "-NightTokenizerIncreaseContrast", "YES"])
        #expect(gallery.gallery == .pageWithASecret)
        #expect(gallery.card == nil)
        #expect(gallery.increaseContrast, "the tokenizer's shot flags count too")
        #expect(gallery.runSeconds == nil)
    }

    @Test("-InteractiveRunSeconds takes a positive number of seconds")
    func runSeconds() {
        #expect(InteractiveLaunchOptions(arguments: ["-InteractiveRunSeconds", "60"]).runSeconds == 60)
        #expect(InteractiveLaunchOptions(arguments: ["-InteractiveRunSeconds", "0"]).runSeconds == nil)
        #expect(InteractiveLaunchOptions(arguments: ["-InteractiveRunSeconds", "soon"]).runSeconds == nil)
        for wild in ["inf", "nan", "1e30", "3601", "-5"] {
            #expect(InteractiveLaunchOptions(arguments: ["-InteractiveRunSeconds", wild]).runSeconds == nil, "\(wild)")
        }
        #expect(InteractiveLaunchOptions().runSeconds == nil)
        #expect(PatchTheRewardContent.playDuration == 6, "the test host passes no flag")
    }

    @Test("A flag without a value, a value that is another flag, or an unknown slug: nothing")
    func malformed() {
        #expect(InteractiveLaunchOptions(arguments: ["-Interactive"]) == InteractiveLaunchOptions())
        #expect(InteractiveLaunchOptions(arguments: ["-Interactive", "-LessonPreview"]).card == nil)
        #expect(InteractiveLaunchOptions(arguments: ["-Interactive", "nope"]).card == nil)
        #expect(InteractiveLaunchOptions(arguments: ["-InteractiveState", "sideways"]).state == nil)
        #expect(!InteractiveLaunchOptions(arguments: ["-InteractiveStubSpoiled", "NO"]).stubSpoiled)
    }

    @Test("The test host was launched with none of them")
    func current() {
        #expect(InteractiveLaunchOptions.current.card == nil)
        #expect(InteractiveLaunchOptions.current.gallery == nil)
    }

    @Test("Scroll ids: one per target, all distinct")
    func scrollIDs() {
        let ids = InteractiveScrollTarget.allCases.map(InteractiveScrollID.id(for:))
            + [InteractiveScrollID.card, InteractiveScrollID.stage, InteractiveScrollID.panel]
        #expect(Set(ids).count == ids.count)
        #expect(InteractiveScrollID.id(for: .reveal) == InteractiveScrollID.reveal)
    }

    @Test("The scroll action: nothing outside a lesson; equal by its key, so a host's re-render doesn't redraw the card")
    @MainActor
    func scrollAction() {
        var asked: [String] = []
        let lesson = InteractiveScrollAction(key: "lesson-list") { id, animated in asked.append("\(id) \(animated)") }
        let again = InteractiveScrollAction(key: "lesson-list") { _, _ in }
        #expect(lesson == again && lesson != .none)
        lesson(InteractiveScrollID.stage, animated: true)
        #expect(asked == ["\(InteractiveScrollID.stage) true"])
        InteractiveScrollAction.none(InteractiveScrollID.stage, animated: false)
        #expect(EnvironmentValues().interactiveScrollIntoView == .none)
    }
}

@Suite("Interactives: layout and motion")
struct LayoutTests {

    @Test("Tables replace charts from the first accessibility size")
    func tables() {
        for size in DynamicTypeSize.allCases {
            #expect(InteractiveLayout.usesTables(size) == (size >= .accessibility1), "\(size)")
        }
    }

    @Test("The Mac's compact card below 440 pt, unless opened; unmeasured is full")
    func macCompact() {
        #expect(InteractiveLayout.isMacCompact(width: 390, expanded: false))
        #expect(!InteractiveLayout.isMacCompact(width: 390, expanded: true))
        #expect(!InteractiveLayout.isMacCompact(width: 580, expanded: false))
        #expect(!InteractiveLayout.isMacCompact(width: 0, expanded: false))
        #expect(InteractiveLayout.isMacCompact(width: 580, expanded: false, forced: true))
        #expect(!InteractiveLayout.isMacCompact(width: 580, expanded: true, forced: true))
    }

    @Test("An SE's card leaves 311 pt; five 44 pt stops fit it, side by side")
    func phoneWidths() {
        #expect(InteractiveLayout.contentWidth(cardWidth: InteractiveLayout.phoneCardWidths[0]) == 311)
        #expect(InteractiveLayout.contentWidth(cardWidth: InteractiveLayout.phoneCardWidths[1]) == 376)
        #expect(InteractiveLayout.fitsInOneRow(Array(repeating: InteractiveLayout.phoneMinTarget, count: 5),
                                               spacing: 0, in: 311))
        #expect(!InteractiveLayout.fitsInOneRow([160, 160], spacing: 8, in: 311))
        #expect(InteractiveLayout.fitsInOneRow([], spacing: 8, in: 0))
        #expect(InteractiveLayout.phoneMinTarget == 44)
    }

    @Test("Reduce Motion: a crossfade, and nothing plays by itself")
    func motion() {
        #expect(!InteractiveMotion.autoplays(reduceMotion: true))
        #expect(InteractiveMotion.autoplays(reduceMotion: false))
        let theme = InteractiveTheme.standard
        #expect(!theme.reduceMotion)
        #expect(theme.lit)
        #if os(macOS)
        #expect(theme.platform == .mac && theme.minTarget == 36 && !theme.usesTables)
        #else
        #expect(theme.platform == .phone && theme.minTarget == 44)
        #endif
    }

    @Test("The iPhone's theme: 44 pt targets, tables at AX sizes, no light under Increase Contrast")
    func phoneTheme() {
        let ax5 = InteractiveTheme.phone(increasedContrast: true, reduceTransparency: false, reduceMotion: true,
                                         typeSize: .accessibility5)
        #expect(ax5.platform == .phone && ax5.minTarget == 44 && ax5.usesTables && ax5.reduceMotion && !ax5.lit)
        #expect(ax5.focusRingWidth == 3)
        let large = InteractiveTheme.phone(increasedContrast: false, reduceTransparency: true, reduceMotion: false,
                                           typeSize: .large)
        #expect(!large.usesTables && !large.lit)
    }

    @Test("A locked-in chip reads at full strength: white on the pick, ink2 on the others, never dimmed")
    func lockedChipInk() {
        // Locked (a guess is in): the pick keeps white on `prominent`, the
        // others step back to reading text, not to `ink3` (the theme holds
        // each pair at 4.5:1 or better; a disabled button's dimming doesn't
        // apply, since a locked chip is no longer a button).
        #expect(InteractiveChip.ink(isSelected: true, isEnabled: false, isLocked: true) == .white)
        #expect(InteractiveChip.ink(isSelected: false, isEnabled: false, isLocked: true) == .ink2)
        // Not locked: the ordinary states.
        #expect(InteractiveChip.ink(isSelected: false, isEnabled: true, isLocked: false) == .ink)
        #expect(InteractiveChip.ink(isSelected: false, isEnabled: false, isLocked: false) == .ink3)
        #expect(InteractiveChip.ink(isSelected: true, isEnabled: true, isLocked: false) == .white)
    }
}
