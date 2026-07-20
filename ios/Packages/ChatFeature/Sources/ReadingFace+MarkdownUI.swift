import DesignSystem
import MarkdownUI
import SwiftUI

/// Bridge from the DesignSystem reading-face token to MarkdownUI's font
/// family. Lives in ChatFeature (not DesignSystem) because DesignSystem must
/// not depend on MarkdownUI — the token stays framework-agnostic and each
/// Markdown-rendering feature maps it locally.
extension BrandReadingFace {
    var markdownFamily: FontProperties.Family {
        switch self {
        case .system(let design): return .system(design)
        case .custom(let name): return .custom(name)
        }
    }
}

private struct ReadingFaceOverrideKey: EnvironmentKey {
    static let defaultValue: BrandReadingFace? = nil
}

extension EnvironmentValues {
    /// Per-subtree override of the reply typeface. Production leaves it nil
    /// (bubbles follow `BrandFont.readingFace`); the DEBUG font gallery sets
    /// it per candidate so faces can still be compared side by side now that
    /// the bubbles pin their own family.
    var readingFaceOverride: BrandReadingFace? {
        get { self[ReadingFaceOverrideKey.self] }
        set { self[ReadingFaceOverrideKey.self] = newValue }
    }
}
