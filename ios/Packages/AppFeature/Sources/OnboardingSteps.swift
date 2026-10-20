import SwiftUI
import DesignSystem

// The individual screens of `OnboardingFlow`. Every accessibility identifier
// here is an `onboarding.*` anchor the XCUITests drive — keep them stable.

// MARK: - Shared chrome

/// Title + subtitle up top, a scrolling content slot, and the CTAs pinned
/// below so Dynamic Type can never push them off-screen. At accessibility
/// text sizes the title and subtitle scroll with the content (AUD-12): pinned
/// above it, they could fill the screen and leave the content an 11 pt strip.
struct GateStepContainer<Content: View, CTA: View>: View {
    let title: String
    let subtitle: String?
    /// The heading scrolls with the content at every size, not only at
    /// accessibility sizes. For a screen whose pinned controls are tall
    /// (the disclosure's consent switch), so its rows get the room.
    let headingAlwaysScrolls: Bool
    /// The scroll content's required control (`.id`), and a counter the step
    /// bumps to bring it into view: a tap on a pinned button that is still
    /// disabled because that control is off-screen (accessibility sizes).
    let revealID: String?
    let revealRequest: Int
    let content: () -> Content
    let cta: () -> CTA

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String? = nil,
        headingAlwaysScrolls: Bool = false,
        revealID: String? = nil,
        revealRequest: Int = 0,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headingAlwaysScrolls = headingAlwaysScrolls
        self.revealID = revealID
        self.revealRequest = revealRequest
        self.content = content
        self.cta = cta
    }

    static var edgeFadeHeight: CGFloat { 20 }

    /// Whether the heading scrolls with the content rather than sitting
    /// above it. It starts in the same place either way; it only differs
    /// once the student scrolls.
    static func headingScrolls(at size: DynamicTypeSize, always: Bool = false) -> Bool {
        always || size.isAccessibilitySize
    }

    var body: some View {
        #if os(macOS)
        // A Mac window is taller than a step: the step keeps its own height,
        // centred, with its buttons right under it — and scrolls only in a
        // window too short for it.
        ViewThatFits(in: .vertical) {
            VStack(spacing: BrandSpacing.xl) {
                heading
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, BrandSpacing.xl)
                GatePinnedCTA(content: cta)
            }
            scrollingBody
        }
        #else
        scrollingBody
        #endif
    }

    private var scrollingBody: some View {
        let headingScrolls = Self.headingScrolls(at: dynamicTypeSize, always: headingAlwaysScrolls)
        return VStack(spacing: BrandSpacing.xl) {
            if !headingScrolls {
                heading
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: BrandSpacing.xl) {
                        if headingScrolls {
                            heading
                        }
                        content()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, BrandSpacing.xl)
                    }
                    // Lets the last line clear the edge fade at the end.
                    .padding(.bottom, Self.edgeFadeHeight)
                }
                .scrollBounceBehavior(.basedOnSize)
                // A line running on under the pinned controls fades out
                // rather than being sliced mid-line (the SE's retention row
                // under the pinned consent switch): it reads as "more below".
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [BrandColor.background.opacity(0), BrandColor.background],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.edgeFadeHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // On a short screen the rows run on under the pinned controls
                // (the consent switch, AUD-50): flash the indicator so it's clear
                // there's more to read.
                .scrollIndicatorsFlash(onAppear: true)
                .onChange(of: revealRequest) { _, _ in
                    guard let revealID else { return }
                    // Bottom, not centre: the control then sits right above
                    // the button it enables, and a consent row taller than
                    // the screen (AX5) shows its foot, where the switch is.
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        proxy.scrollTo(revealID, anchor: .bottom)
                    }
                }
            }

            GatePinnedCTA(content: cta)
        }
    }

    private var heading: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text(title)
                #if os(macOS)
                .nightFont(.display)
                #else
                .font(BrandFont.title)
                #endif
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    #if os(macOS)
                    .nightFont(.body)
                    #else
                    .font(BrandFont.body)
                    #endif
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.top, BrandSpacing.xxl)
    }
}

/// The CTAs under a gate screen, pinned below its scrolling content.
private struct GatePinnedCTA<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            content()
        }
        .frame(maxWidth: 420)
        // Pin to ideal height: spare vertical space must go to the scroll
        // area, not into DuoButton's flexible 3D plate (see HomeView).
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.bottom, BrandSpacing.xl)
    }
}

/// Why a pinned button is still dimmed, when the control that enables it
/// may be scrolled out of sight (accessibility sizes, AUD-12/AUD-50). Only
/// VoiceOver heard the button's hint before; a student tapping the dimmed
/// button saw nothing happen. The line says what to do, and tapping it (or
/// the dimmed button, see `revealsOnTap`) scrolls to the control and
/// outlines it.
struct GateRequiredControlHint: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: "arrow.up.circle")
                .font(BrandFont.caption.weight(.semibold))
                .foregroundStyle(BrandColor.accentText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Pinned chrome on a screen already short of room: it stops growing
        // at AX2 (long-press shows it large).
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityShowsLargeContentViewer()
        .accessibilityHint("Scrolls to it")
    }
}

/// How long a revealed control stays outlined.
enum GateReveal {
    static let highlightSeconds: Double = 1.6
}

extension View {
    /// While `active`, a tap anywhere on this (disabled) button runs `reveal`
    /// instead of doing nothing. Hidden from VoiceOver, which reads the
    /// button's own hint.
    func revealsOnTap(_ active: Bool, reveal: @escaping () -> Void) -> some View {
        overlay {
            if active {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: reveal)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A scroll view whose content sits centred while it fits, and scrolls from
/// the top once it doesn't — so Merc and the copy hold their resting layout
/// at standard sizes, yet the largest text sizes can still reach every line
/// (AUD-12).
private struct CenteredScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A centred hero with its buttons pinned below (Meet Merc, the resting
/// screens). On a Mac the two stay together at their own height, centred in
/// the window, and scroll only when the window is too short for them; on a
/// phone the hero centres in the space above the pinned buttons.
private struct GateHeroLayout<Hero: View, CTA: View>: View {
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let cta: () -> CTA

    var body: some View {
        #if os(macOS)
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                hero()
                GatePinnedCTA(content: cta)
            }
            pinned
        }
        #else
        pinned
        #endif
    }

    private var pinned: some View {
        VStack(spacing: 0) {
            CenteredScroll { hero() }
            GatePinnedCTA(content: cta)
        }
    }
}

/// A dead-end or resting screen: Merc, a title, one line of explanation and
/// an optional single action.
private struct GateRestScreen<CTA: View>: View {
    let mercState: MercState
    let title: String
    let titleIdentifier: String
    let message: String
    let cta: () -> CTA
    #if os(macOS)
    @NightSettings private var night
    #endif

    init(
        mercState: MercState,
        title: String,
        titleIdentifier: String,
        message: String,
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.mercState = mercState
        self.title = title
        self.titleIdentifier = titleIdentifier
        self.message = message
        self.cta = cta
    }

    var body: some View {
        GateHeroLayout {
            VStack(spacing: BrandSpacing.xl) {
                // On the Mac a plain Merc, smaller, with no lamp: these are
                // resting screens and stay calm (SPEC.md §5.7).
                #if os(macOS)
                MercMascot(mercState, size: 112, idleLife: !night.reduceMotion)
                    .accessibilityHidden(true)
                #else
                MercMascot(mercState, size: 150)
                    .accessibilityHidden(true)
                #endif

                VStack(spacing: BrandSpacing.md) {
                    Text(title)
                        #if os(macOS)
                        .nightFont(.display)
                        #else
                        .font(BrandFont.title)
                        #endif
                        .foregroundStyle(BrandColor.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(titleIdentifier)

                    Text(message)
                        #if os(macOS)
                        .nightFont(.body)
                        #else
                        .font(BrandFont.body)
                        #endif
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BrandSpacing.xl)
            }
            .padding(.vertical, BrandSpacing.xl)
        } cta: {
            cta()
        }
    }
}

// MARK: - Meet Merc (full mode only)

/// The same hero choreography as `HomeView`: Merc pops in with a spring,
/// waves, then settles into idle antics. Reduce Motion renders it settled.
struct MeetMercStep: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var entered = false
    @State private var mercState: MercState = .idle

    var body: some View {
        // Scrolls once the copy outgrows the screen, with Continue pinned
        // below it: at AX4-AX5 the fixed stack pushed Continue off-screen and
        // a new student could go no further (AUD-12).
        GateHeroLayout {
            VStack(spacing: BrandSpacing.xl) {
                #if os(macOS)
                // Night Studio: Merc in his lamp, at the Mac's size (§5.7).
                NightMercLamp(mercState, size: 120, antics: true)
                    .scaleEffect(entered ? 1 : 0.4, anchor: .bottom)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 36)
                    .accessibilityHidden(true)
                #else
                MercMascot(mercState, size: dynamicTypeSize.isAccessibilitySize ? 150 : 216,
                           emphasis: .softGlow, idleAntics: true, pokeable: true)
                    .scaleEffect(entered ? 1 : 0.4, anchor: .bottom)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 36)
                    .accessibilityHidden(true)
                #endif

                VStack(spacing: BrandSpacing.md) {
                    Text("Meet Merc")
                        #if os(macOS)
                        .nightFont(.display)
                        #else
                        .font(BrandFont.title)
                        #endif
                        .foregroundStyle(BrandColor.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your AI literacy tutor. Merc asks questions back instead of handing you answers, so you learn how AI works — and when not to trust it.")
                        #if os(macOS)
                        .nightFont(.body)
                        #else
                        .font(BrandFont.body)
                        #endif
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BrandSpacing.xl)
            }
            .padding(.vertical, BrandSpacing.xl)
        } cta: {
            DuoButton("Continue", style: .primary, action: onContinue)
                .macDefaultAction()
                .accessibilityIdentifier("onboarding.continue")
        }
        .onAppear(perform: enter)
    }

    private func enter() {
        #if os(macOS)
        let reduceMotion = self.reduceMotion || Night.debugReduceMotion
        #endif
        guard !reduceMotion else {
            entered = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            entered = true
        }
        mercState = .wave
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            mercState = .idle
        }
    }
}

// MARK: - Age

/// A neutral wheel: it opens on a placeholder, not on any age, and Continue
/// waits for a pick — so a fast tap can't answer for the student. The caller
/// decides eligibility. The selection lives only in this view's `@State`.
struct AgeStep: View {
    let onContinue: (Int) -> Void

    /// Room for the selected row and one neighbour on each side.
    static let wheelMinHeight: CGFloat = 150

    @State private var selectedAge: Int?
    @State private var revealRequest = 0
    @State private var highlightsWheel = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    // The Mac's picker is a pop-up menu, not a wheel.
    static let wheelHint = "Pick your age from the menu to continue"
    static let continueHint = "Pick your age from the menu first"
    #else
    static let wheelHint = "Pick your age on the wheel to continue"
    static let continueHint = "Pick your age on the wheel first"
    #endif

    /// At accessibility sizes the heading can push the wheel out of sight
    /// (an SE at AX5 opens with no wheel and a dimmed Continue), so until an
    /// age is picked a visible line says what Continue is waiting for.
    static func showsWheelHint(hasPick: Bool, at size: DynamicTypeSize) -> Bool {
        !hasPick && size.isAccessibilitySize
    }

    var body: some View {
        let showsHint = Self.showsWheelHint(hasPick: selectedAge != nil, at: dynamicTypeSize)
        GateStepContainer(
            title: "How old are you?",
            subtitle: "Checked on this device only — your age isn't saved or sent anywhere.",
            revealID: Self.wheelID,
            revealRequest: revealRequest
        ) {
            Picker("Age", selection: $selectedAge) {
                Text("Select your age").tag(Int?.none)
                ForEach(AgeGate.choices, id: \.self) { age in
                    Text(AgeGate.label(for: age)).tag(Int?.some(age))
                }
            }
#if os(iOS)
            .pickerStyle(.wheel)
#endif
            .labelsHidden()
#if os(macOS)
            // A pop-up menu at its own size (a wheel's 150 pt only centred
            // it in empty space), with its bezel: the window's borderless
            // button style would otherwise draw it as bare text.
            .buttonStyle(.automatic)
            .controlSize(.large)
            .fixedSize()
#else
            // The wheel keeps a usable height however large the text: at
            // AX5 it had shrunk to an 11 pt strip (AUD-12).
            .frame(minHeight: AgeStep.wheelMinHeight)
#endif
            .accessibilityIdentifier("onboarding.agePicker")
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .strokeBorder(BrandColor.accent, lineWidth: 3)
                    .opacity(highlightsWheel ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .id(Self.wheelID)
        } cta: {
            DuoButton("Continue", style: .primary, isEnabled: selectedAge != nil) {
                if let selectedAge { onContinue(selectedAge) }
            }
            .macDefaultAction()
            .revealsOnTap(showsHint, reveal: revealWheel)
            .accessibilityIdentifier("onboarding.ageContinue")
            .accessibilityHint(selectedAge == nil ? Self.continueHint : "")

            if showsHint {
                GateRequiredControlHint(text: Self.wheelHint, action: revealWheel)
                    .accessibilityIdentifier("onboarding.ageHint")
            }
        }
    }

    private static let wheelID = "onboarding.ageWheel"

    private func revealWheel() {
        revealRequest += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { highlightsWheel = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + GateReveal.highlightSeconds) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { highlightsWheel = false }
        }
    }
}

/// Terminal: no control moves the flow, and the device remembers the block
/// (`AgeBlock`) so going back or relaunching can't undo it.
struct UnderThirteenView: View {
    var body: some View {
        GateRestScreen(
            mercState: .idle,
            title: "Mercurius is for ages 13 and up",
            titleIdentifier: "onboarding.underThirteen",
            message: "Come back when you're 13. This device stays blocked for "
                + "\(AgeBlock.coolOffDays) days — your age itself isn't saved. If it's a "
                + "mistake, ask a teacher or parent."
        ) {
            EmptyView()
        }
    }
}

// MARK: - Disclosure

struct DisclosureStep: View {
    let onAgree: () -> Void
    let onNotNow: () -> Void

    @State private var agreed = false
    @State private var revealRequest = 0
    @State private var highlightsSwitch = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let switchHint = "Turn on the switch above to continue"

    /// Where the switch scrolls with the rows (accessibility sizes) it is
    /// usually out of sight when the screen opens, so until it's on a
    /// visible line under "Agree" says what Agree is waiting for.
    static func showsSwitchHint(agreed: Bool, at size: DynamicTypeSize) -> Bool {
        !agreed && !pinsConsentToggle(at: size)
    }

    private static let switchID = "onboarding.consentRow"

    /// What the disclosure says, row by row, in order. Plain data so the
    /// copy is pinned by a test; changing it is a consent-copy change (see
    /// `ConsentGate.currentVersion`).
    static let rows: [(symbol: String, text: String)] = [
        ("paperplane",
         "Your messages — and any photos you attach — are sent through our server to Anthropic's Claude to generate replies."),
        ("clock.arrow.circlepath",
         "Our server keeps your messages for 90 days and photos for 24 hours, then deletes them. "
            + "You can delete them sooner in Settings → Delete my data & start over. "
            + "Deleting the app doesn't delete them."),
        ("person.crop.circle.badge.questionmark",
         "There's no account. Mercurius uses an anonymous ID stored on this device to keep your chats together."),
    ]

    /// The agreement itself. Unchanged by AUD-27.
    static let toggleText =
        "I understand my messages and photos are sent to Anthropic's Claude to generate replies"

    /// Whether the consent switch sits pinned right above "Agree and
    /// continue" (AUD-50), rather than at the foot of the scrolling rows.
    /// On an iPhone SE the rows pushed it below the fold, cut in half, with
    /// "Agree" disabled for no visible reason. At accessibility sizes its
    /// label alone can fill the screen, so there it scrolls with the rows
    /// and the pinned area stays small.
    static func pinsConsentToggle(at size: DynamicTypeSize) -> Bool {
        !size.isAccessibilitySize
    }

    var body: some View {
        let pinsToggle = Self.pinsConsentToggle(at: dynamicTypeSize)
        let showsHint = Self.showsSwitchHint(agreed: agreed, at: dynamicTypeSize)
        GateStepContainer(
            title: "Before you start",
            subtitle: "Here's exactly what happens with what you type.",
            // With the switch pinned, the heading scrolls away so the rows
            // get its room: on an SE at xxxLarge the rows had a ~75 pt window.
            headingAlwaysScrolls: pinsToggle,
            revealID: Self.switchID,
            revealRequest: revealRequest
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                ForEach(Self.rows, id: \.symbol) { row in
                    disclosureRow(symbol: row.symbol, text: row.text)
                }

                if let url = URL(string: "https://trymercurius.com/privacy") {
                    Link("Read the privacy policy", destination: url)
                        #if os(macOS)
                        .nightFont(.headline)
                        .foregroundStyle(BrandColor.accentText)
                        .macPointingHand()
                        #else
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.accentText)
                        #endif
                }

                if !pinsToggle {
                    consentToggle
                        .id(Self.switchID)
                }
            }
            .padding(.top, BrandSpacing.sm)
        } cta: {
            if pinsToggle {
                consentToggle
            }

            DuoButton("Agree and continue", style: .primary, isEnabled: agreed, action: onAgree)
                .macDefaultAction()
                .revealsOnTap(showsHint, reveal: revealSwitch)
                .accessibilityIdentifier("onboarding.agree")
                .accessibilityHint(agreed ? "Continues to what Merc can't do"
                                          : "Turn on the switch above to continue")

            if showsHint {
                GateRequiredControlHint(text: Self.switchHint, action: revealSwitch)
                    .accessibilityIdentifier("onboarding.consentHint")
            }

            #if os(macOS)
            NightTextButton("Not now", color: Night.ink2, action: onNotNow)
                .accessibilityIdentifier("onboarding.notNow")
            #else
            Button(action: onNotNow) {
                Text("Not now")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.notNow")
            #endif
        }
    }

    /// The agreement row. The sentence is part of the tap target, as a
    /// checkbox label is: a SwiftUI `Toggle` only flips on its switch, and a
    /// student who taps the sentence they just read got nothing. VoiceOver
    /// meets one switch, labelled with the sentence (the visible copy is
    /// hidden from it so it isn't read twice).
    private var consentToggle: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: BrandSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: BrandSpacing.md))
        return layout {
            Text(Self.toggleText)
                #if os(macOS)
                .nightFont(.body)
                #else
                .font(BrandFont.body)
                #endif
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { agreed.toggle() }
                .accessibilityHidden(true)

            Toggle(Self.toggleText, isOn: $agreed)
                .labelsHidden()
                #if os(macOS)
                // The native checkbox, in Night's prominent indigo.
                .tint(Night.prominent)
                #else
                .tint(BrandColor.accent)
                #endif
                .accessibilityIdentifier("onboarding.consentToggle")
        }
        .padding(BrandSpacing.md)
        #if os(macOS)
        // A lit row (SPEC.md §5.7).
        .nightLit(radius: Night.Radius.row)
        #else
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        #endif
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                .strokeBorder(agreed || highlightsSwitch ? BrandColor.accent : BrandColor.border,
                              lineWidth: highlightsSwitch ? 3 : (agreed ? 1.5 : 1))
        )
    }

    private func revealSwitch() {
        revealRequest += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { highlightsSwitch = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + GateReveal.highlightSeconds) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { highlightsSwitch = false }
        }
    }

    private func disclosureRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                #if os(macOS)
                .foregroundStyle(Night.accentText)
                #else
                .foregroundStyle(BrandColor.accent)
                #endif
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                #if os(macOS)
                .nightFont(.body)
                #else
                .font(BrandFont.body)
                #endif
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PausedView: View {
    let onReview: () -> Void

    var body: some View {
        GateRestScreen(
            mercState: .sleep,
            title: "Mercurius is paused",
            titleIdentifier: "onboarding.paused",
            message: "You can agree any time — nothing is sent until you do."
        ) {
            DuoButton("Review the agreement", style: .primary, action: onReview)
                .macDefaultAction()
                .accessibilityIdentifier("onboarding.review")
        }
    }
}

// MARK: - Limits

struct LimitsStep: View {
    let onAcknowledge: () -> Void

    /// The rows, in order. Plain data so the copy is pinned by a test.
    static let rows: [(symbol: String, text: String)] = [
        ("exclamationmark.triangle",
         "It can be wrong. Check important claims against a real source."),
        ("hand.raised",
         "It isn't a counselor, doctor or lawyer."),
        ("lock",
         "Don't share your full name, address or anything private."),
        ("phone",
         "If you're in crisis, call or text 988, or text HOME to 741741."),
    ]

    static let subtitle = "Four things to keep in mind every time you chat."

    var body: some View {
        GateStepContainer(
            title: "What Merc can't do",
            subtitle: Self.subtitle
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                ForEach(Self.rows, id: \.symbol) { row in
                    limitRow(symbol: row.symbol, text: row.text)
                }
            }
            .padding(BrandSpacing.lg)
            #if os(macOS)
            .nightLit(radius: Night.Radius.card)
            #else
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            #endif
            .padding(.top, BrandSpacing.sm)
        } cta: {
            DuoButton("Got it", style: .primary, action: onAcknowledge)
                .macDefaultAction()
                .accessibilityIdentifier("onboarding.limitsAck")
        }
    }

    private func limitRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                #if os(macOS)
                .foregroundStyle(Night.accentText)
                #else
                .foregroundStyle(BrandColor.accent)
                #endif
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                #if os(macOS)
                .nightFont(.body)
                #else
                .font(BrandFont.body)
                #endif
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
