import Foundation

/// Owns the per-device session identifier used by the Mercurius backend.
///
/// Constraints imposed by the server (`isValidSessionId` in server.js):
/// - length between 1 and 64
/// - characters limited to `[a-zA-Z0-9_-]`
///
/// We pick a cryptographically random 32-character identifier (URL-safe
/// base64 of 24 bytes, stripped of padding and `+`/`/`) on first launch
/// and persist it in the Keychain so it survives app reinstalls on the
/// same device? No — Keychain **does** survive reinstalls on iOS, which
/// is what we want for streak / leaderboard continuity.
public final class SessionIdentity: @unchecked Sendable {
    private let keychain: KeychainStore
    private let key = "session_id"
    private let lock = NSLock()
    private var cached: String?

    public init(keychain: KeychainStore = Keychain()) {
        self.keychain = keychain
    }

    /// Returns the current session id, generating and persisting one on
    /// first use. Thread-safe.
    public func current() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        do {
            let stored = try keychain.get(key)
            if Self.isValid(stored) {
                cached = stored
                return stored
            }
        } catch Keychain.KeychainError.itemNotFound {
            // fall through to generate
        } catch {
            throw error
        }

        let fresh = Self.generate()
        try keychain.set(fresh, for: key)
        cached = fresh
        return fresh
    }

    /// Deletes the current session id. Used only when the user explicitly
    /// resets their identity (e.g. "Start over" in settings).
    public func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        try keychain.delete(key)
        cached = nil
    }

    // MARK: - Generation

    static func generate() -> String {
        // 24 bytes = 32 chars base64 (4 * ceil(24/3)).
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fallback — unlikely in practice but we must not crash.
            bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
