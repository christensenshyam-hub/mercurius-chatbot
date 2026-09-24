import Foundation
import OSLog

/// Local-only OSLog sink for the first-run flow and consent gate.
///
/// Visible in Console.app under subsystem `com.mayoailiteracy.mercurius`,
/// category `Onboarding`; nothing leaves the device. Every value logged is
/// a short, non-PII state marker. The self-declared age is never logged —
/// only whether the check passed.
enum OnboardingTelemetry {
    private static let log = Logger(
        subsystem: "com.mayoailiteracy.mercurius",
        category: "Onboarding"
    )

    /// The flow mounted. `mode` is "full" (first run) or "gateOnly".
    static func gateShown(mode: String) {
        log.info("onboarding.gate_shown mode=\(mode, privacy: .public)")
    }

    static func agePassed() {
        log.info("onboarding.age_passed")
    }

    static func ageBlocked() {
        log.info("onboarding.age_blocked")
    }

    static func disclosureAccepted() {
        log.info("onboarding.disclosure_accepted")
    }

    static func disclosurePaused() {
        log.info("onboarding.disclosure_paused")
    }

    /// "Got it" on the limits screen — the moment consent is recorded.
    static func limitsAcked() {
        log.info("onboarding.limits_acked")
    }

    static func pathShown() {
        log.info("onboarding.path_shown")
    }

    static func startLesson1() {
        log.info("onboarding.start_lesson_1")
    }

    static func justChat() {
        log.info("onboarding.just_chat")
    }
}
