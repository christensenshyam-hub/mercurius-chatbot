import CoreText
import Foundation
import SwiftUI

/// The certificate's four faces, all from the bundled variable fonts
/// (`Fonts/CormorantGaramond-*.ttf`, `Fonts/EBGaramond-*.ttf`, SIL OFL 1.1),
/// each picked by its named instance so the weight axis is set: Cormorant
/// Garamond SemiBold (wght 600) upright and italic, EB Garamond Regular
/// (wght 400) and Italic.
public enum CertificateFace: CaseIterable, Sendable {
    /// The wordmark, title, unit lines, seal ring and AI Basics' subtitle.
    case display
    /// The learner's name.
    case displayItalic
    /// The paragraph, the date, the labels and the footer.
    case body
    /// "is proudly presented to".
    case bodyItalic

    /// The named instance's PostScript name (what the PDF embeds).
    public var postScriptName: String {
        switch self {
        case .display: return "CormorantGaramond-SemiBold"
        case .displayItalic: return "CormorantGaramond-SemiBoldItalic"
        case .body: return "EBGaramond-Regular"
        case .bodyItalic: return "EBGaramond-Italic"
        }
    }

    /// The `wght` the named instance sets.
    public var weight: Int {
        switch self {
        case .display, .displayItalic: return 600
        case .body, .bodyItalic: return 400
        }
    }

    /// Cormorant's "fi" ligature has no Unicode mapping a PDF can carry: with
    /// it, a PDF's text reads "Certi!cate". Its f and i set apart look the
    /// same at these sizes, so common ligatures are off for Cormorant (EB
    /// Garamond's map correctly and stay on, as in the design).
    var disablesLigatures: Bool {
        switch self {
        case .display, .displayItalic: return true
        case .body, .bodyItalic: return false
        }
    }
}

/// Fonts and metrics for the certificate. Sizes are in design pixels (the
/// designs are 1056 × 816 CSS px); `Certificate.pt` turns them into points.
public enum CertificateType {
    /// A Core Text font for a face at a size in points.
    public static func ctFont(_ face: CertificateFace, points: CGFloat) -> CTFont {
        BrandFontRegistrar.registerCertificateFonts()
        var attributes: [CFString: Any] = [kCTFontNameAttribute: face.postScriptName]
        if face.disablesLigatures {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [kCTFontOpenTypeFeatureTag: "liga", kCTFontOpenTypeFeatureValue: 0]
            ]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, points, nil)
    }

    /// The SwiftUI font for a face at a size in design pixels. Fixed size:
    /// the certificate is a printed page, not UI, so Dynamic Type doesn't
    /// reach it.
    public static func font(_ face: CertificateFace, px: CGFloat) -> Font {
        Font(ctFont(face, points: Certificate.pt(px)))
    }

    /// The width a line sets at, in design pixels, with CSS letter-spacing
    /// (`trackingPx`, added after every character, the last one included, as
    /// Chrome and SwiftUI's `tracking` both do).
    public static func width(_ text: String, face: CertificateFace, px: CGFloat, trackingPx: CGFloat = 0) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = ctFont(face, points: px)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        )
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return width + trackingPx * CGFloat(text.count)
    }

    /// A face's ascent and descent at a size, rounded to whole pixels the way
    /// Chrome rounds them for its line boxes.
    public static func metrics(_ face: CertificateFace, px: CGFloat) -> (ascent: CGFloat, descent: CGFloat) {
        let font = ctFont(face, points: 100)
        let ascent = CTFontGetAscent(font) / 100
        let descent = CTFontGetDescent(font) / 100
        return ((ascent * px).rounded(), (descent * px).rounded())
    }

    /// Where a line's baseline sits in a CSS line box of height `lineHeight`
    /// (nil = `normal`) whose top is at `top`, all in design pixels: the
    /// half-leading is floored, as Chrome does, then the ascent added.
    public static func baseline(_ face: CertificateFace, px: CGFloat, lineTop top: CGFloat,
                                lineHeight: CGFloat? = nil) -> CGFloat {
        let m = metrics(face, px: px)
        let content = m.ascent + m.descent
        let height = lineHeight.map(Certificate.layoutUnit) ?? content
        return top + ((height - content) / 2).rounded(.down) + m.ascent
    }

    /// The height of a `normal` CSS line box for a face at a size.
    public static func normalLineHeight(_ face: CertificateFace, px: CGFloat) -> CGFloat {
        let m = metrics(face, px: px)
        return m.ascent + m.descent
    }
}
