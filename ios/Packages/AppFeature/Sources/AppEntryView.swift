import SwiftUI
import DesignSystem
import NetworkingKit
import ChatFeature
import CurriculumFeature
import SettingsFeature

/// Post-bootstrap entry flow. Owns the consent gate / first-run flow and
/// the Home → AppShell handoff so that `RootView` can stay focused on
/// bootstrap concerns (session resolve, container readiness).
///
/// Three mutually exclusive states:
///
/// 1. **Gate** — the stored `consentVersion` is older than
///    `ConsentGate.currentVersion`, or `!hasSeenOnboarding`. `OnboardingFlow`
///    runs in `.full` mode on a first run and `.gateOnly` for an existing
///    install (a version bump or a consent withdrawal in Settings). It
///    writes both flags through `@AppStorage`; the shared UserDefaults
///    values propagate here automatically. This branch is evaluated FIRST
///    so no network call can happen before consent: the shell — and its
///    launch-time session fetch — is unreachable until the gate clears.
///
/// 2. **Home** — gate cleared, `!hasEnteredApp`. The branded entry screen
///    with the Start learning / Chat with Merc / How it works affordances.
///    Not persisted: every cold launch begins here.
///
/// 3. **App shell** — `hasEnteredApp`. The main `TabView`. Shown once the
///    user taps a CTA (or finishes the full first-run flow, which routes
///    straight in). The chat header carries a Home button that flips
///    `hasEnteredApp` back to false so the user always has a way back.
///
/// The animations are declared once at this view's root so the
/// child views can each use a bare `.transition(.opacity)` and
/// get a consistent crossfade.
struct AppEntryView: View {
    @EnvironmentObject private var env: AppEnvironment

    @AppStorage(OnboardingFlow.storageKey) private var hasSeenOnboarding: Bool = false
    @AppStorage(ConsentGate.storageKey) private var consentVersion: Int = 0

    /// The flow completed in this launch. The persisted flags decide at
    /// launch; this covers the same launch, because a value pinned through
    /// the UserDefaults argument domain (`-consentVersion 0` in the UI
    /// tests) shadows the flow's own writes for the whole process.
    @State private var gateClearedThisLaunch = false

    private var showsGate: Bool {
        Self.showsGate(
            consentVersion: consentVersion,
            hasSeenOnboarding: hasSeenOnboarding,
            clearedThisLaunch: gateClearedThisLaunch
        )
    }

    /// Pure gate decision (covered by AppEntryGateTests).
    static func showsGate(consentVersion: Int, hasSeenOnboarding: Bool, clearedThisLaunch: Bool) -> Bool {
        !clearedThisLaunch
            && (ConsentGate.needsGate(storedVersion: consentVersion) || !hasSeenOnboarding)
    }

    /// Flips true when the user taps a CTA on HomeView.
    /// In-memory only: every cold launch restarts at Home (by design
    /// — Merc greets the learner every launch rather than dropping
    /// straight into a mid-conversation chat).
    /// DEBUG `-EnterShell` / `-EnterShellCurriculum` skip the Home doorman
    /// so screenshot tooling can reach the shell (no CLI way to tap CTAs).
    @State private var hasEnteredApp: Bool = Self.debugEntersShell

    /// Which tab the shell should open on — set by the Home CTA the user
    /// chose ("Chat with Merc" → .chat, "Start learning" → .curriculum).
    @State private var entryTab: AppShellView.Tab =
        Self.debugEntersCurriculum ? .curriculum : .chat

    /// The lesson the shell should open on arrival — set only by the
    /// first-run flow's "Start Lesson 1". Cleared when the user goes Home so
    /// a later "Start learning" doesn't re-open it.
    @State private var entryLesson: Lesson?

    private static var debugEntersShell: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-EnterShell") || args.contains("-EnterShellCurriculum")
        #else
        return false
        #endif
    }

    private static var debugEntersCurriculum: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-EnterShellCurriculum")
        #else
        return false
        #endif
    }

    /// Drives the "How it works" sheet presented from HomeView.
    @State private var showHowItWorks: Bool = false

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: hasSeenOnboarding)
            .animation(.easeInOut(duration: 0.25), value: consentVersion)
            .animation(.easeInOut(duration: 0.25), value: gateClearedThisLaunch)
            .animation(.easeInOut(duration: 0.25), value: hasEnteredApp)
            .sheet(isPresented: $showHowItWorks) {
                HowItWorksView(dismiss: { showHowItWorks = false })
            }
            // `mercurius://session` — the Live Activity's tap target. Skip
            // the Home doorman and land on the learning path, where the
            // in-progress lesson is the highlighted node. Never shortcuts
            // the gate: the `content` order below checks it first.
            .onOpenURL { url in
                guard url.scheme == "mercurius", url.host == "session" else { return }
                entryTab = .curriculum
                hasEnteredApp = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if showsGate {
            OnboardingFlow(
                mode: hasSeenOnboarding ? .gateOnly : .full,
                reminderStore: env.reminderStore,
                streakStore: env.streakStore,
                onStartLesson1: {
                    entryTab = .curriculum
                    entryLesson = MercuriusCurriculum.units.first?.lessons.first
                    hasEnteredApp = true
                    gateClearedThisLaunch = true
                },
                onJustChat: {
                    entryTab = .chat
                    hasEnteredApp = true
                    gateClearedThisLaunch = true
                },
                onGateCleared: { gateClearedThisLaunch = true }
            )
            .transition(.opacity)
        } else if hasEnteredApp {
            AppShellView(
                apiClient: env.apiClient,
                sessionIdentity: env.sessionIdentity,
                chatStore: env.chatStore,
                themeStore: env.themeStore,
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                reminderStore: env.reminderStore,
                initialTab: entryTab,
                initialLesson: entryLesson,
                onGoHome: {
                    hasEnteredApp = false
                    entryLesson = nil
                },
                // Withdrawing consent in Settings drops the user back onto the
                // gate (gate-only mode, since the first run already happened).
                // The entry lesson/tab are cleared too — otherwise a first-run
                // "Start Lesson 1" would re-open Lesson 1 from "Chat with Merc"
                // after re-consenting.
                onConsentWithdrawn: {
                    consentVersion = 0
                    gateClearedThisLaunch = false
                    hasEnteredApp = false
                    entryLesson = nil
                    entryTab = .chat
                }
            )
            .transition(.opacity)
        } else {
            HomeView(
                onStartChat: {
                    entryTab = .chat
                    hasEnteredApp = true
                },
                onStartLearning: {
                    entryTab = .curriculum
                    hasEnteredApp = true
                },
                onHowItWorks: { showHowItWorks = true },
                // Only feed the greeting a streak the server confirmed
                // recently — a weeks-old cache would make Merc claim a
                // streak that has already died ("Day 5 — keep it alive!").
                streak: env.streakStore.isCurrentFresh ? env.streakStore.current : 0
            )
            .transition(.opacity)
        }
    }
}
