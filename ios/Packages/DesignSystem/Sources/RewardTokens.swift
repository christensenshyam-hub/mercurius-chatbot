import SwiftUI

/// Reward-flavored tokens for the "Duolingo-blueprint" surfaces (the learning
/// path, the gamified top bar, the reshaped profile).
///
/// ADDITIVE + OPT-IN. These live in their own file and are layered on top of the
/// brand palette — nothing here changes an existing token, so the flat
/// `BrandButton`, chat, and lessons are untouched. The hues stay brand-coherent:
/// the gold echoes the cord/confetti already in the `Merc` mascot, and the flame
/// matches the orange the streak chip already uses.
public extension BrandColor {
    /// Warm gold — XP pills, level chips, the `DuoButton` `.reward` style.
    static let xpGold = Color(red: 0xF2 / 255, green: 0xB5 / 255, blue: 0x3C / 255)

    /// Deeper gold — the pressed/base plate beneath a gold reward button.
    static let xpGoldDeep = Color(red: 0xC9 / 255, green: 0x8A / 255, blue: 0x16 / 255)

    /// Named streak flame — the same warm orange the streak chip already uses,
    /// promoted to a token so the top bar and profile agree on one color.
    static let streakFlame = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x1A / 255)
}

// MARK: - Elevation

/// Soft-shadow presets for the reward surfaces. Cards, nodes, and the top bar
/// read as gently raised without inventing new colors — just black at low
/// opacity, the standard iOS material-shadow approach.
public enum Elevation {
    /// Resting cards and banners.
    case card
    /// A path node sitting above its connector trail.
    case node
    /// The most lifted surface — the gamified top bar / current node.
    case raised

    var color: Color {
        switch self {
        case .card:   return Color.black.opacity(0.08)
        case .node:   return Color.black.opacity(0.12)
        case .raised: return Color.black.opacity(0.16)
        }
    }

    var radius: CGFloat {
        switch self {
        case .card:   return 12
        case .node:   return 8
        case .raised: return 16
        }
    }

    var offset: CGSize {
        switch self {
        case .card:   return CGSize(width: 0, height: 4)
        case .node:   return CGSize(width: 0, height: 3)
        case .raised: return CGSize(width: 0, height: 6)
        }
    }
}

public extension View {
    /// Apply one of the brand elevation presets.
    func brandShadow(_ elevation: Elevation) -> some View {
        shadow(
            color: elevation.color,
            radius: elevation.radius,
            x: elevation.offset.width,
            y: elevation.offset.height
        )
    }
}
