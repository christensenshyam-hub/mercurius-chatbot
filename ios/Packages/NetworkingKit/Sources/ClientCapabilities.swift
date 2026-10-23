import Foundation

/// Rendering capabilities this build declares on POST /api/chat. The server
/// only includes block-markup prompt instructions for clients that declare
/// them — this is the ENTIRE backward-compat story for blocks_v1: shipped
/// builds never send the field, so the server never emits new markers at
/// them. Never remove a token a shipped renderer depends on.
public enum ClientCapabilities {
    /// blocks_v1: [KEY]/[EX] cards + tappable [Q] multiple-choice checks
    /// rendered natively by ChatFeature's BlockParser/CheckQuizCard.
    ///
    /// Plus the device, as the Basics guide reads it (`platform_ios` or
    /// `platform_mac`): its first lesson tells a phone to "tap the microphone
    /// on your keyboard" and a Mac to type, and its email lesson's copy steps
    /// differ. Only the Basics guide reads the platform token; every other
    /// request is answered exactly as without it, and a server from before
    /// Basics accepts any well-formed token and ignores it.
    public static let current = ["blocks_v1", platform]

    /// This build's platform token.
    public static var platform: String {
        #if os(macOS)
        return "platform_mac"
        #else
        return "platform_ios"
        #endif
    }
}
