import Foundation
import LessonPlayer
import OSLog
import SettingsFeature

/// Where pilot events go. The app has no telemetry pipeline (see
/// docs/lesson-player-pilot/METRICS.md), so the only sink is the device log.
/// A later pipeline would be one more implementation of this, after review.
protocol LessonEventSink {
    func write(name: String, fields: [String: String])
}

/// Local only: Console.app (or `log stream`) under subsystem
/// `com.mayoailiteracy.mercurius`, category `lessonPlayer`. Nothing leaves
/// the device.
struct OSLogLessonEventSink: LessonEventSink {
    private let log = Logger(subsystem: "com.mayoailiteracy.mercurius", category: "lessonPlayer")
    func write(name: String, fields: [String: String]) {
        let line = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log.info("\(name, privacy: .public) \(line, privacy: .public)")
    }
}

/// The pilot's events (METRICS.md): ids, versions, enums, counts and times,
/// never answer text, option text or chat content. Adds the fields every
/// event carries: a pseudonymous install id (random, on this device only,
/// not the server session id, replaced by "delete my data") and the app
/// version.
@MainActor
final class LessonPlayerTelemetry {
    static let shared = LessonPlayerTelemetry(
        preferences: AppEnvironment.curriculumProgressPreferences,
        sink: OSLogLessonEventSink()
    )

    static let installIdKey = "com.mayoailiteracy.mercurius.lessonPlayer.installId"
    static let firstOpenKey = "com.mayoailiteracy.mercurius.lessonPlayer.firstOpenRecorded"

    private let preferences: PreferenceStore
    private let sink: LessonEventSink
    private let appVersion: String

    init(preferences: PreferenceStore, sink: LessonEventSink,
         appVersion: String = LessonPlayerTelemetry.bundleVersion()) {
        self.preferences = preferences
        self.sink = sink
        self.appVersion = appVersion
    }

    var installId: String {
        if let id = preferences.string(for: Self.installIdKey) { return id }
        let id = UUID().uuidString
        preferences.set(id, for: Self.installIdKey)
        return id
    }

    func record(_ event: LessonPlayerEvent) {
        sink.write(name: event.name, fields: event.fields.merging(common) { a, _ in a })
    }

    /// `first_open`, once per install (and again after "delete my data",
    /// which makes a new learner). `playerEligible` says whether the pilot was
    /// on for this device then, so activation can be split by experience.
    func recordFirstOpenIfNeeded(playerEligible: Bool) {
        guard preferences.string(for: Self.firstOpenKey) == nil else { return }
        preferences.set("1", for: Self.firstOpenKey)
        sink.write(name: "first_open", fields: common.merging([
            "experience": playerEligible ? Experience.player.rawValue : Experience.legacy.rawValue,
        ]) { a, _ in a })
    }

    /// The legacy lesson's start and completion, so the two experiences can
    /// be compared on the same events. Logging only: the legacy lesson itself
    /// is unchanged.
    func recordLegacy(_ name: String, lessonId: String, extra: [String: String] = [:]) {
        sink.write(name: name, fields: common.merging([
            "lesson_id": lessonId,
            "experience": Experience.legacy.rawValue,
        ].merging(extra) { a, _ in a }) { a, _ in a })
    }

    /// A new learner: forget the install id and the first-open mark.
    func reset() {
        preferences.set(nil, for: Self.installIdKey)
        preferences.set(nil, for: Self.firstOpenKey)
    }

    private var common: [String: String] {
        ["install_id": installId, "app_version": appVersion]
    }

    nonisolated static func bundleVersion() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
