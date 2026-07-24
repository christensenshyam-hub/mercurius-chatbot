import Foundation

/// Rendering capabilities this build declares on POST /api/chat. The server
/// only includes block-markup prompt instructions for clients that declare
/// them — this is the ENTIRE backward-compat story for blocks_v1: shipped
/// builds never send the field, so the server never emits new markers at
/// them. Never remove a token a shipped renderer depends on.
public enum ClientCapabilities {
    /// blocks_v1: [KEY]/[EX] cards + tappable [Q] multiple-choice checks
    /// rendered natively by ChatFeature's BlockParser/CheckQuizCard.
    public static let current = ["blocks_v1"]
}
