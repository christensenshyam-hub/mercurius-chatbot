import Foundation

/// A boolean flag however the server spells it: JSON `true`, or the string
/// `"true"` (any case). Anything else — `false`, `null`, an absent key, a
/// number, a different string — reads as false. Used for the crisis signal,
/// where a strict `Bool` would make the whole body undecodable over a quoted
/// `"true"` and the student would see a generic error instead of support.
@propertyWrapper
struct LenientFlag: Decodable, Equatable, Sendable {
    var wrappedValue: Bool

    init(wrappedValue: Bool) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = Self.flag(in: container)
    }

    private static func flag(in container: SingleValueDecodingContainer) -> Bool {
        if let value = try? container.decode(Bool.self) { return value }
        if let text = try? container.decode(String.self) {
            return text.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        }
        return false
    }
}

extension KeyedDecodingContainer {
    /// Synthesized `Decodable` calls `decode`, not `decodeIfPresent`, for a
    /// wrapped property — an absent or `null` key must still read as false.
    func decode(_ type: LenientFlag.Type, forKey key: Key) throws -> LenientFlag {
        try decodeIfPresent(type, forKey: key) ?? LenientFlag(wrappedValue: false)
    }
}
