import Foundation
import NetworkingKit
import SettingsFeature

/// The lesson player pilot's switch (docs/lesson-player-pilot/HANDOFF.md).
///
/// On only when BOTH hold:
/// - this build allows it (`clientAllowed`, compile time), and
/// - the server says so (`GET /api/lesson-player/config`, from the
///   `LESSON_PLAYER_ENABLED` env var, off by default), for that lesson.
///
/// The server's answer is cached, so the last known value holds offline; an
/// app that has never heard from the server treats it as off. Turning the
/// server flag off needs no app release: new attempts open the legacy lesson
/// from the next refresh (launch). An attempt already under way keeps its
/// experience (`ExperienceResolver`), so nothing swaps mid-lesson.
///
/// DEBUG builds can force it with the launch argument `-LessonPlayer YES`
/// (or `NO`), which wins over the server.
@MainActor
public final class LessonPlayerFlag {
    /// The compile-time half of the double gate. True so the server flag can
    /// turn the pilot on remotely; set false to compile it out of a build.
    public static let clientAllowed = true

    static let cacheKey = "com.mayoailiteracy.mercurius.lessonPlayer.serverConfig"
    static let debugArgument = "-LessonPlayer"

    private let preferences: PreferenceStore
    private let debugOverride: Bool?
    private(set) var cached: LessonPlayerConfig?

    public init(preferences: PreferenceStore, arguments: [String]) {
        self.preferences = preferences
        self.debugOverride = Self.override(in: arguments)
        if let raw = preferences.string(for: Self.cacheKey), let data = raw.data(using: .utf8) {
            cached = try? JSONDecoder().decode(LessonPlayerConfig.self, from: data)
        }
    }

    /// Whether a NEW attempt at this lesson should use the player.
    public func isEnabled(for lessonId: String) -> Bool {
        if let forced = debugOverride { return forced }
        guard Self.clientAllowed, let config = cached else { return false }
        return config.enabled && config.lessons.contains(lessonId)
    }

    /// Fetch the server's answer. A failure keeps the last known value.
    public func refresh(using fetch: () async throws -> LessonPlayerConfig) async {
        guard Self.clientAllowed, let config = try? await fetch() else { return }
        cached = config
        if let data = try? JSONEncoder().encode(config) {
            preferences.set(String(decoding: data, as: UTF8.self), for: Self.cacheKey)
        }
    }

    /// `-LessonPlayer YES|NO` in DEBUG builds only (`testHookArguments` is
    /// empty in Release).
    static func override(in arguments: [String]) -> Bool? {
        guard let i = arguments.firstIndex(of: debugArgument), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1].uppercased() {
        case "YES", "1", "TRUE": return true
        case "NO", "0", "FALSE": return false
        default: return nil
        }
    }
}
