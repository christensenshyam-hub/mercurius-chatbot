import SwiftUI
import DesignSystem
import PersistenceKit

/// The first-run flow and the versioned consent gate, as one small state
/// machine that `AppEntryView` mounts ahead of Home and the shell.
///
/// Nothing here touches the network, and nothing is persisted until the
/// user acts: `consentVersion` is written when "Got it" is tapped on the
/// limits screen, `hasSeenOnboarding` when the full flow finishes. The
/// self-declared age is compared on-device and dropped.
///
/// - `.full` (first run): Meet Merc → age → disclosure → limits → Your path.
/// - `.gateOnly` (an install whose stored consent is older than
///   `ConsentGate.currentVersion`, or that withdrew consent in Settings):
///   age → disclosure → limits, then the flow unmounts and Home shows.
struct OnboardingFlow: View {
    enum Mode {
        case full
        case gateOnly
    }

    /// Raw values double as the DEBUG `-GateStep <step>` launch-arg spelling.
    enum Step: String, CaseIterable {
        case meet, age, underThirteen, disclosure, paused, limits, path
    }

    /// Kept as the pre-2.3.0 literal so installs that finished the old
    /// tutorial only see the consent gate, not Meet Merc / Your path again.
    static let storageKey = "hasSeenOnboarding"

    let mode: Mode
    let reminderStore: ReminderStore
    let streakStore: StreakStore
    /// Full mode: the two exits from "Your path".
    let onStartLesson1: () -> Void
    let onJustChat: () -> Void
    /// Gate-only mode: fired at "Got it", right after consent is recorded,
    /// so the host can fall through to Home in this launch.
    let onGateCleared: () -> Void

    @AppStorage(ConsentGate.storageKey) private var consentVersion: Int = 0
    @AppStorage(OnboardingFlow.storageKey) private var hasSeenOnboarding: Bool = false

    @State private var step: Step

    init(
        mode: Mode,
        reminderStore: ReminderStore,
        streakStore: StreakStore,
        onStartLesson1: @escaping () -> Void,
        onJustChat: @escaping () -> Void,
        onGateCleared: @escaping () -> Void
    ) {
        self.mode = mode
        self.reminderStore = reminderStore
        self.streakStore = streakStore
        self.onStartLesson1 = onStartLesson1
        self.onJustChat = onJustChat
        self.onGateCleared = onGateCleared
        _step = State(initialValue:
            Self.debugStartStep(arguments: ProcessInfo.processInfo.arguments)
            ?? Self.initialStep(for: mode))
    }

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                // Each step is its own view identity: the slide animates, and
                // per-step state (the age wheel, the consent toggle) starts
                // fresh every time a step is entered.
                .id(step)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .tint(BrandColor.accent)
        .onAppear { OnboardingTelemetry.gateShown(mode: mode == .full ? "full" : "gateOnly") }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .meet:
            MeetMercStep(onContinue: { step = .age })
        case .age:
            AgeStep(onContinue: { age in
                let eligible = AgeGate.isEligible(age: age)
                if eligible {
                    OnboardingTelemetry.agePassed()
                } else {
                    OnboardingTelemetry.ageBlocked()
                }
                step = Self.step(afterAgeEligible: eligible)
            })
        case .underThirteen:
            UnderThirteenView()
        case .disclosure:
            DisclosureStep(
                onAgree: {
                    OnboardingTelemetry.disclosureAccepted()
                    step = .limits
                },
                onNotNow: {
                    OnboardingTelemetry.disclosurePaused()
                    step = .paused
                }
            )
        case .paused:
            PausedView(onReview: { step = .disclosure })
        case .limits:
            LimitsStep(onAcknowledge: acknowledgeLimits)
        case .path:
            YourPathStep(
                reminderStore: reminderStore,
                streakStore: streakStore,
                onStartLesson1: { finish(startingLesson: true) },
                onJustChat: { finish(startingLesson: false) }
            )
        }
    }

    // MARK: - Actions

    /// The one place consent is recorded.
    private func acknowledgeLimits() {
        OnboardingTelemetry.limitsAcked()
        consentVersion = ConsentGate.currentVersion
        if let next = Self.stepAfterLimits(mode: mode) {
            step = next
        } else {
            onGateCleared()
        }
    }

    /// Route first, then flip the flag: `AppEntryView` re-renders on the flag
    /// change and must already know which tab / lesson to open.
    private func finish(startingLesson: Bool) {
        if startingLesson {
            OnboardingTelemetry.startLesson1()
            onStartLesson1()
        } else {
            OnboardingTelemetry.justChat()
            onJustChat()
        }
        hasSeenOnboarding = true
    }

    // MARK: - Routing (pure; covered by OnboardingFlowRoutingTests)

    static func initialStep(for mode: Mode) -> Step {
        mode == .full ? .meet : .age
    }

    static func step(afterAgeEligible eligible: Bool) -> Step {
        eligible ? .disclosure : .underThirteen
    }

    /// `nil` means the flow is done (gate-only installs fall through to Home).
    static func stepAfterLimits(mode: Mode) -> Step? {
        mode == .full ? .path : nil
    }

    /// DEBUG `-GateStep <meet|age|underThirteen|disclosure|paused|limits|path>`
    /// starts the flow on that step so each screen can be screenshotted
    /// without tapping through (pair with `-ResetConsent`).
    static func debugStartStep(arguments: [String]) -> Step? {
        #if DEBUG
        guard let flag = arguments.firstIndex(of: "-GateStep"),
              arguments.indices.contains(flag + 1) else { return nil }
        return Step(rawValue: arguments[flag + 1])
        #else
        return nil
        #endif
    }
}
