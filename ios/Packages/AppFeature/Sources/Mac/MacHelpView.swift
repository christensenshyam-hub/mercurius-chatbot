#if os(macOS)
import SwiftUI
import DesignSystem
import SettingsFeature

/// Help ▸ Mercurius Help (⌘?): a window of three tabs.
///
/// - How Mercurius teaches: the same page as Settings ▸ About on the iPhone.
/// - On a Mac: the keyboard shortcuts, attaching an image, and why progress
///   on this Mac is separate from a phone's.
/// - Get help: the support site, feedback and email, and the crisis lines —
///   numbers as selectable text, as the crisis support screen shows them.
///
/// Static content and links only: nothing here talks to Mercurius's server,
/// so it opens before the consent gate too.
public struct MacHelpView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var tab = Tab.teaching

    enum Tab: String, Hashable {
        case teaching, mac, help
    }

    public init() {
        #if DEBUG
        // `-MacHelpTab teaching|mac|help`, for screenshots.
        if let raw = UserDefaults.standard.string(forKey: "MacHelpTab"), let debugTab = Tab(rawValue: raw) {
            _tab = State(initialValue: debugTab)
        }
        #endif
    }

    public var body: some View {
        // A segmented control rather than a TabView: on macOS 26 this
        // window's TabView showed no tabs at all, only a toolbar overflow
        // button (docs/mac-app/02-mac-native.md).
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("How Mercurius Teaches").tag(Tab.teaching)
                Text("On a Mac").tag(Tab.mac)
                Text("Get Help").tag(Tab.help)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, BrandSpacing.md)
            Divider()
            Group {
                switch tab {
                case .teaching: HowMercuriusTeachesView()
                case .mac: onTheMac
                case .help: getHelp
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
        .background(BrandColor.background)
        .navigationTitle(Self.title(tab))
        .preferredColorScheme(env.themeStore.theme.colorScheme)
        .tint(BrandColor.accent)
    }

    private static func title(_ tab: Tab) -> String {
        switch tab {
        case .teaching: return "How Mercurius Teaches"
        case .mac: return "Mercurius on a Mac"
        case .help: return "Get Help"
        }
    }

    // MARK: - On a Mac

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { action }
    }

    private static let shortcuts: [Shortcut] = [
        Shortcut(keys: "Return", action: "Send your message"),
        Shortcut(keys: "⇧ Return", action: "New line in your message"),
        Shortcut(keys: "⌘N", action: "New chat"),
        Shortcut(keys: "⌘1  ⌘2  ⌘3", action: "Socratic, Debate or Discussion mode"),
        Shortcut(keys: "⌘R", action: "Retry a reply that didn't arrive"),
        Shortcut(keys: "⇧⌘E", action: "Ask Merc to explain more"),
        Shortcut(keys: "⇧⌘A", action: "Attach an image"),
        Shortcut(keys: "⌥⌘1  ⌥⌘2  ⌥⌘3", action: "Today, Learning Path, Chat"),
        Shortcut(keys: "⌘,", action: "Settings"),
    ]

    private var onTheMac: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                section("Keyboard shortcuts") {
                    Grid(alignment: .leading, horizontalSpacing: BrandSpacing.lg, verticalSpacing: BrandSpacing.sm) {
                        ForEach(Self.shortcuts) { shortcut in
                            GridRow {
                                Text(shortcut.keys)
                                    .font(BrandFont.mono)
                                    .foregroundStyle(BrandColor.accentText)
                                Text(shortcut.action)
                                    .font(BrandFont.body)
                                    .foregroundStyle(BrandColor.text)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                section("Homework photos") {
                    paragraph("Click the image button beside the message box, drag a picture onto the chat, or copy one and paste it into the message box. Merc sees it with your next message.")
                }
                section("Your progress on this Mac") {
                    paragraph("Mercurius has no accounts. This Mac has its own anonymous session, so its lessons, streak and chats are separate from Mercurius on your phone.")
                }
            }
            .padding(BrandSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Get help

    private var getHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                section("Questions about Mercurius") {
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        ForEach(MacHelpLinks.all + [MacHelpLinks.privacy, MacHelpLinks.terms]) { link in
                            Link(link.title, destination: link.url)
                                .font(BrandFont.body)
                                .foregroundStyle(BrandColor.accentText)
                                .macPointingHand()
                        }
                    }
                }
                section("If you need to talk to someone now") {
                    VStack(alignment: .leading, spacing: BrandSpacing.md) {
                        paragraph("Mercurius is an AI tutor, not a support person. If you're struggling, these people are ready to listen, any time. Please tell a trusted adult too, like a parent or school counselor.")
                        MacCrisisNumbers()
                    }
                }
            }
            .padding(BrandSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text(title)
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.body)
            .foregroundStyle(BrandColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
