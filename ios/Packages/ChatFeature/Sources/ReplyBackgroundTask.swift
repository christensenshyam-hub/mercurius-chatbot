import Foundation
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// Keeps a streaming reply alive through a short app switch. iOS suspends a
/// backgrounded app within seconds, which drops the stream and loses the
/// reply; a background task buys about 30 s to finish and save it.
@MainActor
enum ReplyBackgroundTask {
    /// Returns the closure that ends the task. Safe to call more than once.
    static func begin() -> @MainActor () -> Void {
        #if canImport(UIKit) && os(iOS)
        let token = Token()
        token.id = UIApplication.shared.beginBackgroundTask(withName: "merc-reply") {
            // Out of time: hand the task back without cancelling the stream.
            // iOS suspends the app and the reply comes back as interrupted.
            MainActor.assumeIsolated { token.end() }
        }
        return { token.end() }
        #else
        return {}
        #endif
    }

    #if canImport(UIKit) && os(iOS)
    @MainActor private final class Token {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
    #endif
}
