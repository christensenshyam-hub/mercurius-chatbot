import Foundation
@testable import NetworkingKit

extension LocalClock {
    /// A clock stopped at `utc` (ISO 8601), reading time in `zone`, in US
    /// English, so copy that names a local time is deterministic.
    static func pinned(utc: String, zone: String, locale: String = "en_US") -> LocalClock {
        let instant = ISO8601DateFormatter().date(from: utc)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return LocalClock(now: { instant }, calendar: calendar, locale: Locale(identifier: locale))
    }
}

/// The formatter puts a narrow no-break space before AM/PM; compare with a
/// plain one.
func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ")
}
