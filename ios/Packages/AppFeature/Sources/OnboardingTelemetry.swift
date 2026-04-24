import Foundation
import OSLog

/// Local-only OSLog sink for the first-launch onboarding flow.
///
/// Why this exists: once the app is in front of real users we want
/// to know — without shipping an analytics SDK — where they drop off
/// in the tutorial, which starter prompt they pick, whether they
/// Skip vs Finish. `os_log` events are visible in Console.app under
/// subsystem `com.mayoailiteracy.mercurius`, category `Onboarding`,
/// and are captured by `log stream` / `log show` for offline review.
/// Nothing leaves the device.
///
/// Privacy posture: every dynamic value is logged with the default
/// (public) `privacy` attribute because the fields are all short,
/// non-PII state markers (step name, chip label). If a future event
/// ever includes user text, mark that field `.private` explicitly.
///
/// Keep method names terse — they read as the event name in logs.
enum OnboardingTelemetry {
    private static let log = Logger(
        subsystem: "com.mayoailiteracy.mercurius",
        category: "Onboarding"
    )

    /// Fired when the user first sees the tutorial (i.e. on first
    /// launch, before they tap Begin Tutorial).
    static func started() {
        log.info("onboarding.started")
    }

    /// One step advanced to the next. `from` and `to` are the raw
    /// step names ("brandIntro", "startChat", …) — matching
    /// `OnboardingStep` rawValue-ish semantics without coupling.
    static func stepAdvanced(from: String, to: String) {
        log.info("onboarding.step_advanced from=\(from, privacy: .public) to=\(to, privacy: .public)")
    }

    /// User tapped one of the three starter prompt chips, or typed
    /// their own. `source` = "chip" or "typed". `prompt` is the
    /// full chip text when source=="chip"; "<typed>" otherwise so
    /// we never inadvertently log what the user wrote.
    static func promptSelected(source: String, prompt: String) {
        log.info("onboarding.prompt_selected source=\(source, privacy: .public) prompt=\(prompt, privacy: .public)")
    }

    /// User toggled the critical-thinking acknowledgement on.
    /// Fired once per checkbox-on transition (not on toggle-off).
    static func criticalThinkingAcknowledged() {
        log.info("onboarding.critical_thinking_acknowledged")
    }

    /// User tapped the pulsing mock Home button in step 6.
    static func mockHomeTapped() {
        log.info("onboarding.mock_home_tapped")
    }

    /// Reached the Finish step and tapped "Start Using Mercurius AI".
    /// Distinct from `skipped` so drop-off by exit path is
    /// distinguishable.
    static func completed() {
        log.info("onboarding.completed")
    }

    /// User tapped Skip at any step. `atStep` = rawValue-ish step
    /// name at which they skipped.
    static func skipped(atStep: String) {
        log.info("onboarding.skipped at_step=\(atStep, privacy: .public)")
    }
}
