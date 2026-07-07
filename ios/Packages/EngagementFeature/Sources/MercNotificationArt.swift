import SwiftUI
import DesignSystem
#if os(macOS)
import AppKit
#endif

/// Renders the procedural Merc into a PNG tile for notification-banner
/// attachments — one pose per planned reminder, so the banner shows a waving
/// Merc for hellos and a dozing Merc when the streak is at risk.
///
/// Rendered on demand (no bundled raster assets): the same vector art the app
/// draws, on a brand-gradient tile so the thumbnail reads as intentional
/// artwork rather than a floating cutout. `ambient: false` pins the static
/// baseline pose, so output is deterministic.
@MainActor
enum MercNotificationArt {

    /// PNG data for a pose tile. `size` is the tile's point size; rendered
    /// at 3x for banner crispness.
    static func pngData(for pose: ReminderPlanner.Pose, size: CGFloat = 220) -> Data? {
        let renderer = ImageRenderer(content: tile(for: pose, size: size))
        renderer.scale = 3
        #if os(iOS)
        return renderer.uiImage?.pngData()
        #elseif os(macOS)
        // macOS path exists so the SPM test host can pin "renders non-empty
        // data" — notifications themselves are iOS-only.
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    private static func tile(for pose: ReminderPlanner.Pose, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.29, green: 0.23, blue: 0.93),
                                 Color(red: 0.49, green: 0.23, blue: 0.93)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Merc(state: mercState(for: pose), size: size * 0.74, ambient: false)
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
    }

    private static func mercState(for pose: ReminderPlanner.Pose) -> MercState {
        switch pose {
        case .wave:      return .wave
        case .happy:     return .happy
        case .thinking:  return .thinking
        case .celebrate: return .celebrate
        case .sleep:     return .sleep
        }
    }
}
