import Foundation
import Network

/// The device's current network path, so a failed request can tell "the
/// phone is offline" from "this network won't let us through".
final class NetworkPathMonitor: @unchecked Sendable {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var started = false
    private var satisfied: Bool?

    private init() {}

    /// Idempotent.
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.satisfied = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.mayoailiteracy.mercurius.network-path", qos: .utility))
    }

    /// Nil until the first path update arrives.
    var isSatisfied: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return satisfied
    }
}
