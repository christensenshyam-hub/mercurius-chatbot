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
    let content: () -> Content
    let cta: () -> CTA

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.cta = cta
    }

    /// Whether the heading scrolls with the content rather than sitting
    /// above it.
    static func headingScrolls(at size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }

    var body: some View {
        let headingScrolls = Self.headingScrolls(at: dynamicTypeSize)
        VStack(spacing: BrandSpacing.xl) {
            if !headingScrolls {
                heading
            }

            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    if headingScrolls {
                        heading
                    }
                    content()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, BrandSpacing.xl)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // On a short screen the rows run on under the pinned controls
            // (the consent switch, AUD-50): flash the indicator so it's clear
            // there's more to read.
            .scrollIndicatorsFlash(onAppear: true)

            GatePinnedCTA(content: cta)
        }
    }

    private var heading: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text(title)
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(BrandFont.body)
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

/// A dead-end or resting screen: Merc, a title, one line of explanation and
/// an optional single action.
private struct GateRestScreen<CTA: View>: View {
    let mercState: MercState
    let title: String
    let titleIdentifier: String
    let message: String
    let cta: () -> CTA

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
        VStack(spacing: 0) {
            CenteredScroll {
                VStack(spacing: BrandSpacing.xl) {
                    MercMascot(mercState, size: 150)
                        .accessibilityHidden(true)

                    VStack(spacing: BrandSpacing.md) {
                        Text(title)
                            .font(BrandFont.title)
                            .foregroundStyle(BrandColor.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(titleIdentifier)

                        Text(message)
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, BrandSpacing.xl)
                }
                .padding(.vertical, BrandSpacing.xl)
            }

            GatePinnedCTA(content: cta)
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
        VStack(spacing: 0) {
            CenteredScroll {
                VStack(spacing: BrandSpacing.xl) {
                    MercMascot(mercState, size: dynamicTypeSize.isAccessibilitySize ? 150 : 216,
                               emphasis: .softGlow, idleAntics: true, pokeable: true)
                        .scaleEffect(entered ? 1 : 0.4, anchor: .bottom)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 36)
                        .accessibilityHidden(true)

                    VStack(spacing: BrandSpacing.md) {
                        Text("Meet Merc")
                            .font(BrandFont.title)
                            .foregroundStyle(BrandColor.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text("Your AI literacy tutor. Merc asks questions back instead of handing you answers, so you learn how AI works — and when not to trust it.")
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, BrandSpacing.xl)
                }
                .padding(.vertical, BrandSpacing.xl)
            }

            GatePinnedCTA {
                DuoButton("Continue", style: .primary, action: onContinue)
                    .accessibilityIdentifier("onboarding.continue")
            }
        }
        .onAppear(perform: enter)
    }

    private func enter() {
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

    var body: some View {
        GateStepContainer(
            title: "How old are you?",
            subtitle: "Checked on this device only — your age isn't saved or sent anywhere."
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
            // The wheel keeps a usable height however large the text: at
            // AX5 it had shrunk to an 11 pt strip (AUD-12).
            .frame(minHeight: AgeStep.wheelMinHeight)
            .accessibilityIdentifier("onboarding.agePicker")
        } cta: {
            DuoButton("Continue", style: .primary, isEnabled: selectedAge != nil) {
                if let selectedAge { onContinue(selectedAge) }
            }
            .accessibilityIdentifier("onboarding.ageContinue")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// What the disclosure says, row by row, in order. Plain data so the
    /// copy is pinned by a test; changing it is a consent-copy change (see
    /// `ConsentGate.currentVersion`).
    static let rows: [(symbol: String, text: String)] = [
        ("paperplane",
         "Your messages — and any photos you attach — are sent through our server to Anthropic's Claude to generate replies."),
        ("clock.arrow.circlepath",
         "Our server keeps your messages for 90 days and photos for 24 hours, then deletes them. "
            + "You can delete them sooner in Settings → Delete my data. Deleting the app doesn't."),
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
        GateStepContainer(
            title: "Before you start",
            subtitle: "Here's exactly what happens with what you type."
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                ForEach(Self.rows, id: \.symbol) { row in
                    disclosureRow(symbol: row.symbol, text: row.text)
                }

                if let url = URL(string: "https://trymercurius.com/privacy") {
                    Link("Read the privacy policy", destination: url)
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.accentText)
                }

                if !pinsToggle {
                    consentToggle
                }
            }
            .padding(.top, BrandSpacing.sm)
        } cta: {
            if pinsToggle {
                consentToggle
            }

            DuoButton("Agree and continue", style: .primary, isEnabled: agreed, action: onAgree)
                .accessibilityIdentifier("onboarding.agree")
                .accessibilityHint(agreed ? "Continues to what Merc can't do"
                                          : "Turn on the switch above to continue")

            Button(action: onNotNow) {
                Text("Not now")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.notNow")
        }
    }

    private var consentToggle: some View {
        Toggle(isOn: $agreed) {
            Text(Self.toggleText)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(BrandColor.accent)
        .accessibilityIdentifier("onboarding.consentToggle")
        .padding(BrandSpacing.md)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                .strokeBorder(agreed ? BrandColor.accent : BrandColor.border,
                              lineWidth: agreed ? 1.5 : 1)
        )
    }

    private func disclosureRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(BrandColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(BrandFont.body)
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
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .padding(.top, BrandSpacing.sm)
        } cta: {
            DuoButton("Got it", style: .primary, action: onAcknowledge)
                .accessibilityIdentifier("onboarding.limitsAck")
        }
    }

    private func limitRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(BrandColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
