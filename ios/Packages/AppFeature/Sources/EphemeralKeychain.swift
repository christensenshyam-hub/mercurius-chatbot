#if DEBUG
import Foundation
import NetworkingKit

/// DEBUG `-EphemeralSession`: a session id held in memory for one process.
/// Screenshot and preview runs use it so they never write a Keychain item on
/// the machine (on a Mac, the developer's own login keychain) or reuse a
/// real student session.
final class EphemeralKeychain: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key] = value
    }

    func get(_ key: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let value = items[key] else { throw Keychain.KeychainError.itemNotFound }
        return value
    }

    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key] = nil
    }
}
#endif
