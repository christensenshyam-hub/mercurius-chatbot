import SwiftUI
import DesignSystem

// MARK: - OnboardingStep

/// The linear sequence of first-launch tutorial steps. Ordered by
/// `rawValue` so progress (`progressIndex / total`) is derivable
/// without a separate counter.
///
/// Steps intentionally mirror the real app's core flow so the
/// tutorial doubles as muscle memory for where things are:
/// brand → Home card → prompt picker → response → verification →
/// chat-header Home button → finish.
enum OnboardingStep: Int, CaseIterable {
    case brandIntro
    case startChat
    case askQuestion
    case response
    case critical
    case homeNav
    case finish

    /// 1-based index used for the "Step N of M" progress bar.
    var progressIndex: Int { rawValue + 1 }

    static var total: Int { allCases.count }

    /// Next step in the sequence, or `nil` if this is the terminal
    /// step (the caller handles finish separately).
    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

// MARK: - InteractiveOnboardingView

/// First-launch interactive tutorial. Replaces the static three-page
/// swipe that shipped previously.
///
/// Design intent: the tutorial doesn't just *explain* what Mercurius
/// does — it has the user practice the core actions before they land
/// in the real app. Each step funnels toward one clear action (tap,
/// pick, toggle) so nobody bounces off a wall of explainer text.
///
/// No network calls. Responses are canned client-side so onboarding
/// stays fast, reliable, and private — a user who opens the app on
/// a train with spotty cell service still gets a complete tutorial.
///
/// Persistence uses `@AppStorage("hasSeenOnboarding")` via the
/// shared `storageKey`. On Finish (or Skip) the flag flips and
/// `AppEntryView`'s own @AppStorage observer re-renders into
/// `HomeView`. No callback wiring — SwiftUI and UserDefaults handle
/// the propagation.
public struct InteractiveOnboardingView: View {

    /// Shared UserDefaults key. Exposed so callers that gate on
    /// completion (e.g. `AppEntryView`) don't drift from the same
    /// literal. Keeping the value `"hasSeenOnboarding"` means
    /// existing installs that already completed the old static
    /// onboarding won't see the new tutorial — that's the correct
    /// behavior; the tutorial is for first-launch users.
    public static let storageKey = "hasSeenOnboarding"

    @AppStorage(InteractiveOnboardingView.storageKey)
    private var hasSeenOnboarding: Bool = false

    // Step cursor + per-step local state. All `@State` rather than
    // `@AppStorage` — nothing here is worth persisting across an
    // onboarding abandonment; re-opening the app just starts over.
    @State private var step: OnboardingStep = .brandIntro
    @State private var selectedPrompt: String? = nil
    @State private var typedPrompt: String = ""
    @State private var hasVerifiedCritical: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(step)  // forces SwiftUI to treat each step
                               // as a distinct view so the transition
                               // animates on step changes.
            }
            .animation(.easeInOut(duration: 0.3), value: step)
        }
        .tint(BrandColor.accent)
    }

    // MARK: - Progress bar

    /// Thin progress bar + Skip affordance at the very top. Fixed
    /// height so step content below never re-lays-out as progress
    /// changes.
    private var progressBar: some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack {
                Text("Step \(step.progressIndex) of \(OnboardingStep.total)")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityLabel(
                        "Tutorial step \(step.progressIndex) of \(OnboardingStep.total)"
                    )

                Spacer()

                Button("Skip", action: finish)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityHint("Skips the tutorial and opens the home screen")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BrandColor.surface)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [BrandColor.accent, BrandColor.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * progressFraction,
                            alignment: .leading
                        )
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)  // the "Step N of M" text above
                                         // is the accessible label.
        }
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.md)
    }

    private var progressFraction: CGFloat {
        CGFloat(step.progressIndex) / CGFloat(OnboardingStep.total)
    }

    // MARK: - Step content router

    @ViewBuilder
    private var content: some View {
        switch step {
        case .brandIntro:
            BrandIntroStep(onContinue: advance)
        case .startChat:
            MockHomeStep(onStartChat: advance)
        case .askQuestion:
            PromptPickerStep(
                selectedPrompt: $selectedPrompt,
                typedPrompt: $typedPrompt,
                onContinue: advance
            )
        case .response:
            ResponseStep(
                prompt: resolvedPrompt,
                response: cannedResponse(for: resolvedPrompt),
                onContinue: advance
            )
        case .critical:
            VerificationStep(
                isChecked: $hasVerifiedCritical,
                onContinue: advance
            )
        case .homeNav:
            HomeNavStep(onTapMockHome: advance)
        case .finish:
            FinishStep(onFinish: finish)
        }
    }

    // MARK: - Prompt resolution

    /// The prompt we'll echo in the response step. Prefer the chip the
    /// user picked; fall back to their typed input; fall back to a
    /// harmless default if somehow both are empty.
    private var resolvedPrompt: String {
        if let selectedPrompt, !selectedPrompt.isEmpty {
            return selectedPrompt
        }
        let trimmed = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "What is a good AI prompt?" : trimmed
    }

    /// Canned, pedagogically-styled responses for the three suggested
    /// chips. Any custom typed input falls through to a generic
    /// Socratic opener — the onboarding goal is to demonstrate the
    /// style, not to answer every possible question.
    private func cannedResponse(for prompt: String) -> String {
        switch prompt {
        case "What is a good AI prompt?":
            return """
            Great question — one worth sitting with before the answer.

            What makes a question 'good'? A few things help: being specific about what you actually want, giving context the AI can't guess, and telling it what form the answer should take.

            Want to try rewriting a vague prompt into a sharper one?
            """
        case "How can AI make mistakes?":
            return """
            AI models don't 'know' things the way you do — they predict plausible-sounding text based on patterns in their training data.

            That means they can sound confident even when they're wrong. The dangerous mistakes aren't the obvious ones — they're the confident-sounding wrong ones.

            Can you think of a situation where a confident-wrong answer would matter?
            """
        case "How should I use AI for studying?":
            return """
            Here's a rule of thumb: use AI to *check* your understanding, not *replace* it.

            If you can't explain the answer in your own words afterward, you haven't learned it — you've just copied it.

            What's a topic you're studying right now? I can help you think through it rather than hand you the answer.
            """
        default:
            return """
            Interesting question. Before I answer, let me ask you one back:

            What made you curious about this? Understanding where a question comes from often matters more than the answer itself.
            """
        }
    }

    // MARK: - Actions

    private func advance() {
        if let next = step.next {
            step = next
        } else {
            finish()
        }
    }

    private func finish() {
        hasSeenOnboarding = true
    }
}

// MARK: - TutorialStepContainer

/// Shared chrome for every non-brand step: title + subtitle at the top,
/// a content slot in the middle, and a primary CTA at the bottom.
/// Keeps step layouts consistent without forcing each subview to
/// re-implement padding + typography from scratch.
private struct TutorialStepContainer<Content: View, CTA: View>: View {
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

            // Content area scrolls if it overflows — protects against
            // accessibility Dynamic Type sizes pushing the CTA off-screen.
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, BrandSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            cta()
                .frame(maxWidth: 420)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xl)
        }
    }
}

// MARK: - Step 1: Brand intro

/// Logo-first welcome. No skeumorphic "tutorial" framing — this is
/// the brand splash, and the "Begin Tutorial" CTA sets expectations
/// for what the next screens are.
private struct BrandIntroStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer()

            BrandLogo(style: .full, size: 220)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.md) {
                Text("Welcome to Mercurius AI")
                    .font(BrandFont.largeTitle)
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your AI literacy tutor for learning how to use AI effectively, ethically, and intelligently.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            Spacer()

            BrandButton("Begin Tutorial", style: .primary, action: onContinue)
                .frame(maxWidth: 420)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xl)
                .accessibilityHint("Starts a short interactive walkthrough of Mercurius")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Mercurius AI. Your AI literacy tutor for learning how to use AI effectively, ethically, and intelligently.")
    }
}

// MARK: - Step 2: Mock Home — tap Start Chat

/// Stylized miniature of HomeView. The tutorial's goal here is
/// muscle-memory: "this is the screen you'll see, and this is
/// where you tap to begin."
private struct MockHomeStep: View {
    let onStartChat: () -> Void

    var body: some View {
        TutorialStepContainer(
            title: "Starting a chat",
            subtitle: "Tap Start Chat to open the tutor. We'll walk through one together."
        ) {
            VStack(spacing: BrandSpacing.lg) {
                // Mock Home card: logo + subtitle + pulsing Start Chat.
                // Wrapped in a card-ish surface so it reads as
                // "representation of the real thing," not the real thing.
                VStack(spacing: BrandSpacing.lg) {
                    BrandLogo(style: .full, size: 140)
                        .accessibilityHidden(true)

                    Text("Your AI literacy tutor")
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.textSecondary)

                    PulsingPrimaryButton(title: "Start Chat", action: onStartChat)
                        .accessibilityHint("Advances the tutorial")
                }
                .padding(BrandSpacing.xl)
                .background(BrandColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(BrandColor.border, lineWidth: 1)
                )
            }
            .padding(.vertical, BrandSpacing.lg)
        } cta: {
            // CTA is "inside" the mock card above; the container's
            // bottom slot stays empty so the mock is the full focus.
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Step 3: Prompt picker

/// Three suggested prompts + an optional short TextField for users
/// who want to type their own. Either path advances on Continue.
private struct PromptPickerStep: View {
    @Binding var selectedPrompt: String?
    @Binding var typedPrompt: String
    let onContinue: () -> Void

    private static let suggestions = [
        "What is a good AI prompt?",
        "How can AI make mistakes?",
        "How should I use AI for studying?",
    ]

    private var canContinue: Bool {
        selectedPrompt != nil ||
            !typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        TutorialStepContainer(
            title: "Ask a question",
            subtitle: "Pick a starter prompt, or type one of your own."
        ) {
            VStack(spacing: BrandSpacing.md) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    PromptChipButton(
                        text: suggestion,
                        isSelected: selectedPrompt == suggestion,
                        action: {
                            selectedPrompt = suggestion
                            // Typing and chip-picking are mutually
                            // exclusive. Clearing typed keeps the
                            // downstream prompt resolution clean.
                            typedPrompt = ""
                        }
                    )
                }

                HStack(spacing: BrandSpacing.sm) {
                    TextField("Type a question…", text: $typedPrompt)
                        .textFieldStyle(.plain)
                        .font(BrandFont.body)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.vertical, BrandSpacing.md)
                        .background(BrandColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                        .onChange(of: typedPrompt) { _, newValue in
                            // Typing overrides a prior chip selection.
                            if !newValue.isEmpty { selectedPrompt = nil }
                        }
                        .accessibilityLabel("Type your own question")
                }
            }
        } cta: {
            BrandButton("Continue", style: .primary, action: onContinue)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
                .accessibilityHint(canContinue
                    ? "Shows a sample Mercurius response"
                    : "Pick a prompt or type a question to continue")
        }
    }
}

// MARK: - Step 4: Response demo

/// Shows the user's chosen prompt as a message bubble, followed by
/// a canned Mercurius response. Purely client-side — the onboarding
/// never hits the backend, which keeps first-launch fast and works
/// fine offline.
private struct ResponseStep: View {
    let prompt: String
    let response: String
    let onContinue: () -> Void

    var body: some View {
        TutorialStepContainer(
            title: "Here's how Mercurius responds",
            subtitle: "Notice the tone: it asks questions back instead of just handing you the answer."
        ) {
            VStack(spacing: BrandSpacing.md) {
                // User message
                HStack {
                    Spacer(minLength: BrandSpacing.xxl)
                    Text(prompt)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.userBubbleText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(BrandSpacing.md)
                        .background(
                            LinearGradient(
                                colors: [BrandColor.userBubbleTop, BrandColor.userBubbleBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
                }

                // Assistant message
                HStack(alignment: .top) {
                    Text(response)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.assistantBubbleText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(BrandSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BrandColor.assistantBubble)
                        .overlay(
                            Rectangle()
                                .fill(BrandColor.accent)
                                .frame(width: 3)
                                .accessibilityHidden(true),
                            alignment: .leading
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
                    Spacer(minLength: BrandSpacing.xxl)
                }
            }
        } cta: {
            BrandButton("Continue", style: .primary, action: onContinue)
        }
    }
}

// MARK: - Step 5: Critical-thinking verification

/// A toggle the user must turn on before continuing. Not a dark
/// pattern: if they don't actually believe it, they shouldn't use
/// the product. The wording is deliberately plain.
private struct VerificationStep: View {
    @Binding var isChecked: Bool
    let onContinue: () -> Void

    var body: some View {
        TutorialStepContainer(
            title: "Think critically",
            subtitle: "AI can sound confident and still be wrong. Always verify important information before you act on it."
        ) {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColor.accent, BrandColor.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .accessibilityHidden(true)
                    .padding(.top, BrandSpacing.md)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isChecked.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: BrandSpacing.md) {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(isChecked ? BrandColor.accent : BrandColor.textSecondary)
                            .accessibilityHidden(true)

                        Text("I understand that AI can make mistakes and I should verify important information.")
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(BrandSpacing.md)
                    .background(BrandColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                            .strokeBorder(
                                isChecked ? BrandColor.accent : BrandColor.border,
                                lineWidth: isChecked ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("I understand that AI can make mistakes and I should verify important information.")
                .accessibilityValue(isChecked ? "Checked" : "Not checked")
                .accessibilityAddTraits(.isButton)
            }
        } cta: {
            BrandButton("Continue", style: .primary, action: onContinue)
                .disabled(!isChecked)
                .opacity(isChecked ? 1 : 0.4)
                .accessibilityHint(isChecked
                    ? "Continues the tutorial"
                    : "Check the box above to continue")
        }
    }
}

// MARK: - Step 6: Home nav

/// Mock of the real chat header with the Home button highlighted.
/// Tapping it advances — the point is to show the user where the
/// escape hatch lives, not just tell them about it.
private struct HomeNavStep: View {
    let onTapMockHome: () -> Void

    var body: some View {
        TutorialStepContainer(
            title: "Getting back home",
            subtitle: "You can always return to the home screen from inside a chat. Try it — tap the Home icon."
        ) {
            VStack(spacing: BrandSpacing.lg) {
                // Mock chat header: logo + title block + tools + settings + pulsing Home.
                HStack(spacing: BrandSpacing.md) {
                    BrandLogo(style: .mark, size: 32)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Mercurius AI")
                            .font(BrandFont.subheading)
                            .foregroundStyle(BrandColor.text)
                        Text("AI LITERACY TUTOR")
                            .font(BrandFont.caption)
                            .tracking(1.5)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    .accessibilityHidden(true)

                    Spacer()

                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                    PulsingIconButton(
                        systemImage: "house",
                        accessibilityLabel: "Home",
                        accessibilityHint: "Completes this tutorial step",
                        action: onTapMockHome
                    )
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.sm)
                .background(BrandColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                        .strokeBorder(BrandColor.border, lineWidth: 1)
                )
            }
            .padding(.vertical, BrandSpacing.md)
        } cta: {
            // Action gated inside the mock header — keep the bottom
            // slot empty so the tap target is the only thing drawing
            // attention.
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Step 7: Finish

private struct FinishStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColor.accent, BrandColor.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.md) {
                Text("You're all set")
                    .font(BrandFont.largeTitle)
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ask, think, verify — and keep coming back. Mercurius learns alongside you.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            Spacer()

            BrandButton("Start Using Mercurius AI", style: .primary, action: onFinish)
                .frame(maxWidth: 420)
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.bottom, BrandSpacing.xl)
                .accessibilityHint("Finishes onboarding and opens the home screen")
        }
    }
}

// MARK: - Small building blocks

/// Chip-style selection button used in the prompt picker.
private struct PromptChipButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.sm) {
                Rectangle()
                    .fill(isSelected ? BrandColor.accent : Color.clear)
                    .frame(width: 3)
                    .accessibilityHidden(true)

                Text(text)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BrandSpacing.md)
                    .padding(.trailing, BrandSpacing.md)
            }
            .frame(minHeight: 44)
            .background(isSelected ? BrandColor.accent.opacity(0.1) : BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? BrandColor.accent : BrandColor.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A primary-style button with a subtle always-on pulse — used to
/// draw the user's eye to "this is the thing you tap next" without
/// shouting. Pulse respects Reduce Motion automatically because the
/// animation is wrapped by SwiftUI's implicit sensitivity.
private struct PulsingPrimaryButton: View {
    let title: String
    let action: () -> Void

    @State private var pulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrandButton(title, style: .primary, action: action)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .strokeBorder(BrandColor.accentLight, lineWidth: 2)
                    .opacity(reduceMotion ? 0 : (pulsing ? 0 : 0.7))
                    .scaleEffect(reduceMotion ? 1 : (pulsing ? 1.06 : 1))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: pulsing
                    )
            )
            .onAppear {
                pulsing = true
            }
    }
}

/// Bordered icon button with the same pulse treatment — draws the
/// eye without being loud about it. Used for the mock Home button
/// in the homeNav step.
private struct PulsingIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var pulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(BrandColor.accent)
                .frame(width: 44, height: 44)
                .background(BrandColor.accent.opacity(0.12))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(BrandColor.accent, lineWidth: 2)
                        .opacity(reduceMotion ? 0.9 : (pulsing ? 0 : 0.9))
                        .scaleEffect(reduceMotion ? 1 : (pulsing ? 1.4 : 1))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeOut(duration: 1.3).repeatForever(autoreverses: false),
                            value: pulsing
                        )
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .onAppear {
            pulsing = true
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    InteractiveOnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    InteractiveOnboardingView()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    InteractiveOnboardingView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
