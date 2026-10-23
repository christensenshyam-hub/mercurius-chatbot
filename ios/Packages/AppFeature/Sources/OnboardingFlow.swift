import SwiftUI
import DesignSystem
import EngagementFeature
import PersistenceKit

/// The first-run flow and the versioned consent gate, as one small state
/// machine that `AppEntryView` mounts ahead of Home and the shell.
///
/// Nothing here touches the network, and nothing is persisted until the
/// user acts: `consentVersion` is written when "Got it" is tapped on the
/// limits screen (and cleared on the under-13 and paused dead ends),
/// `hasSeenOnboarding` when the full flow finishes, and the `AgeBlock`
/// marker when the age check blocks. The self-declared age is compared
/// on-device and dropped.
///
/// - `.full` (first run): Meet Merc → age → disclosure → limits → Your path.
/// - `.gateOnly` (an install whose stored consent is older than
///   `ConsentGate.currentVersion`, or that withdrew consent in Settings):
///   age → disclosure → limits, then the flow unmounts and Home shows.
/// - Either mode opens on the under-13 screen while a block is in force.
/// - A full run that already recorded consent (the app was closed on Your
///   path) reopens on Your path rather than replaying Meet Merc, the age
///   check and the agreement (AUD-35).
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
    let ageBlockStore: AgeBlockStore
    let reminderStore: ReminderStore
    /// The entry view's scheduler, so "Your path"'s switches queue behind its
    /// re-plans instead of racing them.
    let scheduler: NotificationScheduler
    let streakStore: StreakStore
    /// "Your path" asks about reminders, so Home never repeats the question.
    let reminderCardStore: ReminderCardStore
    /// Full mode: the two exits from "Your path".
    let onStartLesson1: () -> Void
    let onJustChat: () -> Void
    /// Gate-only mode: fired at "Got it", right after consent is recorded,
    /// so the host can fall through to Home in this launch.
    let onGateCleared: () -> Void

    @AppStorage(ConsentGate.storageKey) private var consentVersion: Int = 0
    @AppStorage(OnboardingFlow.storageKey) private var hasSeenOnboarding: Bool = false

    @State private var step: Step
    #if os(macOS)
    @NightSettings private var night
    #endif

    init(
        mode: Mode,
        ageBlockStore: AgeBlockStore,
        reminderStore: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore,
        reminderCardStore: ReminderCardStore,
        onStartLesson1: @escaping () -> Void,
        onJustChat: @escaping () -> Void,
        onGateCleared: @escaping () -> Void
    ) {
        self.mode = mode
        self.ageBlockStore = ageBlockStore
        self.reminderStore = reminderStore
        self.scheduler = scheduler
        self.streakStore = streakStore
        self.reminderCardStore = reminderCardStore
        self.onStartLesson1 = onStartLesson1
        self.onJustChat = onJustChat
        self.onGateCleared = onGateCleared
        _step = State(initialValue:
            Self.debugStartStep(arguments: ProcessInfo.processInfo.arguments)
            ?? Self.initialStep(
                for: mode,
                ageBlocked: ageBlockStore.isActive(),
                consentCurrent: Self.consentIsCurrent(defaults: .standard)
            ))
    }

    /// Whether the agreement on record is the current one, read from the
    /// same defaults `@AppStorage` reads (argument domain included).
    static func consentIsCurrent(defaults: UserDefaults) -> Bool {
        !ConsentGate.needsGate(storedVersion: defaults.integer(forKey: ConsentGate.storageKey))
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            // The Mac shell draws Night Studio's canvas behind the gate's box
            // (SPEC.md §5.7): a fill here would cut its light off at the box.
            Color.clear
            #else
            BrandColor.background.ignoresSafeArea()
            #endif

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(macOS)
                // Reduce Motion: a crossfade, no slide.
                .transition(night.reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                #else
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                #endif
                // Each step is its own view identity: the slide animates, and
                // per-step state (the age wheel, the consent toggle) starts
                // fresh every time a step is entered.
                .id(step)
        }
        #if os(macOS)
        .animation(night.reduceMotion ? Night.Motion.fade : .easeInOut(duration: 0.3), value: step)
        // Night's prominent indigo for the checkbox and the pop-up.
        .tint(Night.prominent)
        #else
        .animation(.easeInOut(duration: 0.3), value: step)
        // Night's readable indigo for text buttons and links; the consent
        // switch tints itself with the fill indigo.
        .tint(BrandAppearance.tint)
        #endif
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
                show(Self.step(afterAgeEligible: eligible))
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
                    show(.paused)
                }
            )
        case .paused:
            PausedView(onReview: { step = .disclosure })
        case .limits:
            LimitsStep(onAcknowledge: acknowledgeLimits)
        case .path:
            YourPathStep(
                reminderStore: reminderStore,
                scheduler: scheduler,
                streakStore: streakStore,
                reminderCardStore: reminderCardStore,
                onStartLesson1: { finish(startingLesson: true) },
                onJustChat: { finish(startingLesson: false) }
            )
        }
    }

    // MARK: - Actions

    /// Move to `next`. The dead ends also drop consent a previous launch
    /// recorded (an install that agreed but never finished the full flow),
    /// so nothing that waits for consent — the reminders included — runs
    /// behind the under-13 or paused screen.
    private func show(_ next: Step) {
        if Self.dropsConsent(next) { consentVersion = 0 }
        if next == .underThirteen { ageBlockStore.record() }
        step = next
    }

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

    /// Where the flow opens. Consent is recorded at "Got it", one screen
    /// before the full flow ends, so a full run that finds it current was
    /// interrupted on Your path and resumes there (AUD-35). A block always
    /// wins: the under-13 screen also drops consent, so both can't hold
    /// unless a clock was set back.
    static func initialStep(for mode: Mode, ageBlocked: Bool = false, consentCurrent: Bool = false) -> Step {
        if ageBlocked { return .underThirteen }
        switch mode {
        case .full: return consentCurrent ? .path : .meet
        case .gateOnly: return .age
        }
    }

    static func step(afterAgeEligible eligible: Bool) -> Step {
        eligible ? .disclosure : .underThirteen
    }

    /// `nil` means the flow is done (gate-only installs fall through to Home).
    static func stepAfterLimits(mode: Mode) -> Step? {
        mode == .full ? .path : nil
    }

    /// The screens that block the student: consent can't stand behind them.
    static func dropsConsent(_ step: Step) -> Bool {
        step == .underThirteen || step == .paused
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
