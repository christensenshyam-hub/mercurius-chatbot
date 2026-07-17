import DesignSystem
import MarkdownUI

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
