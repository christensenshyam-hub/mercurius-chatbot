import SwiftUI

/// `Font.nunito(_:_:)` — from `MERC_HANDOFF.md` Part B, with the design's
/// nearest in-OS stand-in.
///
/// The spec calls for Nunito (a rounded, heavy sans). Rather than ship without
/// the `.ttf` files (which makes `.custom("Nunito-…")` fall back to plain San
/// Francisco), this maps to **SF Rounded** — the chosen substitute. This helper
/// is the single swap point: drop the Nunito files in the bundle and switch to
/// `.custom("Nunito-\(weight)", size:)` to use the real face.
extension Font {
    static func nunito(_ size: CGFloat, _ w: Weight = .heavy) -> Font {
        .system(size: size, weight: w, design: .rounded)
    }
}
