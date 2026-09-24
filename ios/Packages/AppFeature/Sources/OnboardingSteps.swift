import SwiftUI
import DesignSystem

// The individual screens of `OnboardingFlow`. Every accessibility identifier
// here is an `onboarding.*` anchor the XCUITests drive — keep them stable.

// MARK: - Shared chrome

/// Title + subtitle up top, a scrolling content slot, and the CTAs pinned
/// below so Dynamic Type can never push them off-screen.
struct GateStepContainer<Content: View, CTA: View>: View {
    let title: String
    let subtitle: String?
    let content: () -> Content
    let cta: () -> CTA

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

    var body: some View {
        VStack(spacing: BrandSpacing.xl) {
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

            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, BrandSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: BrandSpacing.md) {
                cta()
            }
            .frame(maxWidth: 420)
            // Pin to ideal height: spare vertical space must go to the scroll
            // area, not into DuoButton's flexible 3D plate (see HomeView).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.bottom, BrandSpacing.xl)
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
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

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

            Spacer()

            cta()
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xl)
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
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

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
                    .accessibilityAddTraits(.isHeader)

                Text("Your AI literacy tutor. Merc asks questions back instead of handing you answers, so you learn how AI works — and when not to trust it.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, BrandSpacing.xl)

            Spacer()

            DuoButton("Continue", style: .primary, action: onContinue)
                .accessibilityIdentifier("onboarding.continue")
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xl)
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

/// A neutral wheel: it opens on the youngest row and the caller decides
/// eligibility. The selection lives only in this view's `@State`.
struct AgeStep: View {
    let onContinue: (Int) -> Void

    @State private var selectedAge: Int = AgeGate.choices.first ?? AgeGate.minimumAge

    var body: some View {
        GateStepContainer(
            title: "How old are you?",
            subtitle: "Checked on this device only — your age isn't saved or sent anywhere."
        ) {
            Picker("Age", selection: $selectedAge) {
                ForEach(AgeGate.choices, id: \.self) { age in
                    Text(AgeGate.label(for: age)).tag(age)
                }
            }
#if os(iOS)
            .pickerStyle(.wheel)
#endif
            .labelsHidden()
            .accessibilityIdentifier("onboarding.agePicker")
        } cta: {
            DuoButton("Continue", style: .primary) { onContinue(selectedAge) }
                .accessibilityIdentifier("onboarding.ageContinue")
        }
    }
}

/// Terminal: no way forward, and nothing was written. The one control goes
/// back to the wheel — it opens on "12 or younger", so a 13+ student who
/// tapped Continue too fast must not be stuck here for the session.
struct UnderThirteenView: View {
    let onWrongAge: () -> Void

    var body: some View {
        GateRestScreen(
            mercState: .idle,
            title: "Mercurius is for ages 13 and up",
            titleIdentifier: "onboarding.underThirteen",
            message: "Come back when you're 13 — nothing you entered was saved."
        ) {
            Button(action: onWrongAge) {
                Text("I picked the wrong age")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.ageRetry")
        }
    }
}

// MARK: - Disclosure

struct DisclosureStep: View {
    let onAgree: () -> Void
    let onNotNow: () -> Void

    @State private var agreed = false

    var body: some View {
        GateStepContainer(
            title: "Before you start",
            subtitle: "Here's exactly what happens with what you type."
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                disclosureRow(
                    symbol: "paperplane",
                    text: "Your messages — and any photos you attach — are sent through our server to Anthropic's Claude to generate replies."
                )
                disclosureRow(
                    symbol: "person.crop.circle.badge.questionmark",
                    text: "There's no account. Mercurius uses an anonymous ID stored on this device to keep your chats together."
                )

                if let url = URL(string: "https://trymercurius.com/privacy") {
                    Link("Read the privacy policy", destination: url)
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.accent)
                }

                Toggle(isOn: $agreed) {
                    Text("I understand my messages and photos are sent to Anthropic's Claude to generate replies")
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
            .padding(.top, BrandSpacing.sm)
        } cta: {
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

    var body: some View {
        GateStepContainer(
            title: "What Merc can't do",
            subtitle: "Three things to keep in mind every time you chat."
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                limitRow(
                    symbol: "exclamationmark.triangle",
                    text: "It can be wrong. Check important claims against a real source."
                )
                limitRow(
                    symbol: "hand.raised",
                    text: "It isn't a counselor, doctor or lawyer."
                )
                limitRow(
                    symbol: "phone",
                    text: "If you're in crisis, call or text 988, or text HOME to 741741."
                )
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
