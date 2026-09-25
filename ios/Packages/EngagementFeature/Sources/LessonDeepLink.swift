import Foundation

/// The `mercurius://lesson/<id>` link a reminder carries, so a tap can open
/// the student's next lesson. Pure (no UserNotifications), so the parsing is
/// unit-testable on the macOS test host; `NotificationScheduler` writes it and
/// `NotificationRouter` reads it.
public enum LessonDeepLink {
    /// Notification `userInfo` key holding the link as a string.
    public static let userInfoKey = "url"

    public static func urlString(forLesson lessonId: String) -> String {
        "mercurius://lesson/\(lessonId)"
    }

    /// The lesson id in `mercurius://lesson/<id>`, or `nil` for any other
    /// scheme, host, or a missing/malformed id.
    public static func lessonId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "mercurius",
              url.host(percentEncoded: false)?.lowercased() == "lesson"
        else { return nil }
        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/", id.allSatisfy(isIdCharacter) else { return nil }
        return id
    }

    /// The lesson id carried by a notification's `userInfo`, if any.
    public static func lessonId(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        guard let raw = userInfo[userInfoKey] as? String,
              let url = URL(string: raw)
        else { return nil }
        return lessonId(from: url)
    }

    /// Lesson ids look like "u1_l3"; anything outside this set can't be one.
    private static func isIdCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-")
    }
}
