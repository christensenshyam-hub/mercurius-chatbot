import SwiftUI

/// The reading face for the tutor's replies — the one typography decision the
/// chat surfaces consume. `.system` covers SF / SF Rounded / New York;
/// `.custom` names a family bundled in DesignSystem/Sources/Fonts and
/// registered by `BrandFontRegistrar`.
public enum BrandReadingFace: Equatable, Sendable {
    case system(Font.Design)
    case custom(String)
}

public extension BrandFont {
    /// Single switch point for the assistant-reply typeface. The gallery
    /// (`-ReplyFontGallery`) evaluates candidates; once one wins, it is set
    /// here and every reply surface follows.
    ///
    /// Currently: SF (the pre-exploration default).
    static var readingFace: BrandReadingFace {
        // Ensure bundled candidates are resolvable before any consumer asks
        // for a custom family (no-op after the first call).
        BrandFontRegistrar.registerReadingFonts()
        return .system(.default)
    }

    /// Plain-`Text` counterpart of the reading face for non-Markdown surfaces.
    ///
    /// Note: `Font.custom(_:size:relativeTo:)` is the ONE sanctioned use of a
    /// point size in this file — custom families require one, and
    /// `relativeTo: .body` keeps Dynamic Type scaling intact (the fixed-size
    /// prohibition in `BrandTypography.swift` is about `Font.system(size:)`).
    static var reading: Font {
        switch readingFace {
        case .system(let design):
            return .system(.body, design: design)
        case .custom(let name):
            return .custom(name, size: 17, relativeTo: .body)
        }
    }
}
