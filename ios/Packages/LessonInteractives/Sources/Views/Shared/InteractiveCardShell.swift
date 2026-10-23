import SwiftUI
import DesignSystem

/// Every card's frame, on each platform (BUILD_PLAN.md §1.5): the
/// "Interactive" eyebrow, the title as a header that also says the card's
/// state in one sentence (`summary`), and the card's content under it, with
/// the platform's theme handed down (`\.interactiveTheme`).
///
/// - **iPhone:** today's lesson design, as Lesson 1.1's card draws it: a
///   self-contained night-sky island (it looks the same in the app's light
///   and dark appearances), the iPhone's type and spacing, a soft shadow in
///   light mode only. Decoration (the eyebrow's icon) goes at the
///   accessibility sizes. Increase Contrast and Reduce Transparency draw
///   it solid, with no light or stars.
/// - **Mac:** Night Studio's lit card. Narrower than 440 pt it starts as a
///   compact "Try it" card (`compactLine` and a button) that opens in place:
///   VoiceOver moves to the title, and the keyboard (when it opened it) to
///   the card's first control (`isFirst`).
///
/// The shell sends, stores and draws nothing of the lesson's: the card's
/// state is in the lesson's `InteractiveStateStore`.
public struct InteractiveCardShell<Content: View>: View {
    private let id: InteractiveID
    private let title: String
    private let accessibilityTitle: String
    private let summary: String
    private let compactLine: String
    private let content: Content

    /// - Parameters:
    ///   - title: the card's title (its Copy enum's).
    ///   - accessibilityTitle: what VoiceOver says for the title (default
    ///     "Interactive: <title>").
    ///   - summary: the card's state in one sentence, read after the title.
    ///   - compactLine: the Mac's compact card: one sentence of what the
    ///     card does.
    public init(id: InteractiveID, title: String, accessibilityTitle: String? = nil, summary: String = "",
                compactLine: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.accessibilityTitle = accessibilityTitle ?? "\(InteractiveShellCopy.eyebrow): \(title)"
        self.summary = summary
        self.compactLine = compactLine
        self.content = content()
    }

    public var body: some View {
        #if os(macOS)
        MacInteractiveShell(id: id, title: title, accessibilityTitle: accessibilityTitle, summary: summary,
                            compactLine: compactLine, content: content)
        #else
        PhoneInteractiveShell(title: title, accessibilityTitle: accessibilityTitle, summary: summary,
                              content: content)
        #endif
    }
}

#if os(iOS)
/// The iPhone's frame: Lesson 1.1's night-sky island.
struct PhoneInteractiveShell<Content: View>: View {
    let title: String
    let accessibilityTitle: String
    let summary: String
    let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption2) private var eyebrowIcon: CGFloat = 11

    private var theme: InteractiveTheme {
        let debug = InteractiveLaunchOptions.current
        return .phone(increasedContrast: contrast == .increased || debug.increaseContrast,
                      reduceTransparency: systemReduceTransparency || debug.reduceTransparency,
                      reduceMotion: systemReduceMotion || debug.reduceMotion,
                      typeSize: typeSize)
    }

    var body: some View {
        let theme = theme
        let shape = RoundedRectangle(cornerRadius: BrandRadius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            header(theme)
            content
        }
        .padding(theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                theme.surface
                if theme.lit {
                    // A little light from the top corner and a few stars:
                    // decoration, so none under Increase Contrast or
                    // Reduce Transparency.
                    RadialGradient(colors: [theme.lumen.opacity(0.16), theme.lumen.opacity(0)],
                                   center: .topLeading, startRadius: 0, endRadius: 320)
                    NightStarField(count: 26, brightness: 0.55)
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(theme.edge, lineWidth: 1))
        // The lesson bubble's soft shadow, in light mode only: in dark the
        // lit edge separates the card from the screen.
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.16), radius: 14, y: 8)
        .environment(\.interactiveTheme, theme)
        // The title (a header) names the card: no label here, or VoiceOver
        // says it twice.
        .accessibilityElement(children: .contain)
    }

    private func header(_ theme: InteractiveTheme) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                if !theme.usesTables {
                    Image(systemName: "hand.tap")
                        .font(.system(size: eyebrowIcon, weight: .bold))
                }
                Text(InteractiveShellCopy.eyebrow.uppercased())
                    .interactiveText(.eyebrow)
            }
            .foregroundStyle(theme.accentText)
            Text(title)
                .interactiveText(.title)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(summary)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif

#if os(macOS)
/// The Mac's frame: Night Studio's lit card, compact below 440 pt.
struct MacInteractiveShell<Content: View>: View {
    let id: InteractiveID
    let title: String
    let accessibilityTitle: String
    let summary: String
    let compactLine: String
    let content: Content

    @Environment(InteractiveStateStore.self) private var store: InteractiveStateStore?
    @Environment(\.interactiveKeyRouter) private var router
    @NightSettings private var night
    @State private var width: CGFloat = 0
    @State private var localExpanded = false
    @State private var focusFirst = 0
    @State private var focusOnOpen: (voiceOver: Bool, keyboard: Bool) = (false, false)
    @AccessibilityFocusState private var titleHasVoiceOver: Bool

    private var expanded: Bool { store?.isExpanded(id) ?? localExpanded }

    private var compact: Bool {
        InteractiveLayout.isMacCompact(width: width, expanded: expanded,
                                       forced: InteractiveLaunchOptions.current.macCompact)
    }

    var body: some View {
        Group {
            if compact {
                compactCard
            } else {
                fullCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .onGeometryChange(for: CGFloat.self) { geo in
            geo.size.width
        } action: { newWidth in
            width = newWidth
        }
        .environment(\.interactiveTheme, .mac(night))
        .environment(\.interactiveFocusFirst, focusFirst)
        // The title (a header) names the card: no label here, or VoiceOver
        // says it twice.
        .accessibilityElement(children: .contain)
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(NightTypography.curlQuotes(compactLine))
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
            // In the Tab loop whatever the Full Keyboard Access setting.
            MacTryItControl { open(fromKeyboard: $0) }
        }
        .padding(Night.Space.card)
    }

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            content
        }
        .padding(Night.Space.card)
        .onAppear(perform: focusAfterOpening)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            NightEyebrow(InteractiveShellCopy.eyebrow, systemImage: "hand.tap")
            Text(title)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(summary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($titleHasVoiceOver)
    }

    /// Opens the compact card in place.
    private func open(fromKeyboard: Bool) {
        focusOnOpen = (true, fromKeyboard)
        withAnimation(night.animation(Night.Motion.layout)) {
            if let store { store.expand(id) } else { localExpanded = true }
        }
    }

    /// The full card is on screen after "Try it": VoiceOver to its title,
    /// the keyboard (when it opened it) to its first control.
    private func focusAfterOpening() {
        guard focusOnOpen.voiceOver else { return }
        let keyboard = focusOnOpen.keyboard
        focusOnOpen = (false, false)
        DispatchQueue.main.async {
            titleHasVoiceOver = true
            if keyboard { focusFirst += 1 }
        }
    }
}

/// "Try it": Lesson 1.1's compact card's control.
private struct MacTryItControl: View {
    /// `true`: opened from the keyboard.
    let onOpen: (Bool) -> Void
    @Environment(\.interactiveKeyRouter) private var router
    @NightSettings private var night
    @FocusState private var focused: Bool
    @State private var holder = UUID()
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        Label(InteractiveShellCopy.tryIt, systemImage: "hand.tap")
            .nightFont(.headline)
            .foregroundStyle(Night.accentText)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background {
                shape.fill(Night.surfaceRaised)
                shape.fill(Night.lumen.opacity(hovering ? Night.Tint.hover : 0))
            }
            .overlay(shape.strokeBorder(night.increasedContrast ? Night.hairline : Night.ink3.opacity(0.5), lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture { release(); onOpen(false) }
            .focusable(true, interactions: .edit)
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape.inset(by: -3 - night.focusRingWidth / 2)
                        .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                release()
                onOpen(true)
                return .handled
            }
            .onChange(of: focused) { _, now in router?.hold(holder, now) }
            .onChange(of: router?.checkPicks) { _, _ in if focused { focused = false } }
            .onDisappear { router?.hold(holder, false) }
            .help(InteractiveShellCopy.tryItHint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InteractiveShellCopy.tryIt)
            .accessibilityHint(InteractiveShellCopy.tryItHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen(false) }
    }

    /// "Try it" goes when the card opens: it lets go of the keyboard (and
    /// of Return) first.
    private func release() {
        if focused { focused = false }
        router?.hold(holder, false)
    }
}
#endif
