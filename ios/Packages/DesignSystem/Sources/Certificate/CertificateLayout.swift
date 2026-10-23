import CoreGraphics
import Foundation
import SwiftUI

/// The page: US Letter landscape. The designs are 1056 × 816 CSS px (11 ×
/// 8.5 in at 96 px/in); the PDF is 792 × 612 pt (72 pt/in), so every design
/// pixel is 0.75 pt. All geometry below is in design pixels, as the designs
/// state it, and converted once with `pt(_:)`.
public enum Certificate {
    public static let pageWidthPx: CGFloat = 1056
    public static let pageHeightPx: CGFloat = 816
    public static let pointsPerPixel: CGFloat = 0.75
    /// 792 × 612 pt.
    public static let pageSize = CGSize(width: pageWidthPx * pointsPerPixel, height: pageHeightPx * pointsPerPixel)

    public static func pt(_ px: CGFloat) -> CGFloat { px * pointsPerPixel }

    /// Chrome lays out in 1/64 px units; a computed line height (1.05 ×
    /// 72 px = 75.6 px) is floored to one.
    static func layoutUnit(_ px: CGFloat) -> CGFloat { (px * 64).rounded(.down) / 64 }

    /// The design's colours.
    public enum Ink {
        public static let paper = Color(certificateHex: 0xFDFDFB)
        public static let navy = Color(certificateHex: 0x1B2350)
        public static let ink = Color(certificateHex: 0x141A3D)
        public static let gold = Color(certificateHex: 0x8A6D2F)
        public static let sealText = Color(certificateHex: 0x7A5F27)
        public static let presented = Color(certificateHex: 0x3A4068)
        public static let paragraph = Color(certificateHex: 0x2A3058)
        public static let caps = Color(certificateHex: 0x4B5280)
        public static let footer = Color(certificateHex: 0x5A6080)
    }
}

extension Color {
    /// An sRGB colour from 0xRRGGBB.
    init(certificateHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Where everything on a certificate goes, worked out the way Chrome lays
/// the design's flex column out: a stack from the top (mark, wordmark,
/// title, ornament or subtitle, "is proudly presented to", the name, its
/// rule, the paragraph, the unit lines) and a block pinned to the bottom
/// (date, seal, signature, footer). Text is placed by its baseline and the
/// centre of its line box (letter-spacing included, as CSS centres it).
/// Design pixels throughout.
public struct CertificateLayout: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let text: String
        public let face: CertificateFace
        public let sizePx: CGFloat
        public let trackingPx: CGFloat
        public let role: Role
        public let centerX: CGFloat
        public let baseline: CGFloat
    }

    /// What a line is, for its colour (and the tests).
    public enum Role: Equatable, Sendable {
        case wordmark, title, subtitle, presented, name, namePlaceholder, paragraph, units
        case date, label, footer
    }

    public let kind: CertificateKind
    public let lines: [Line]
    public let name: CertificateNameFit
    /// The mark at the top (62 × 55, contained).
    public let topMark: CGRect
    /// The Deep dive's ornament under the title (200 × 12).
    public let ornament: CGRect?
    /// The gold rule under the name (440 × 1).
    public let nameRule: CGRect
    /// The navy rules over "Date" and the signature label (250 × 1 on the
    /// Deep dive, 290 × 1 on AI Basics).
    public let dateRule: CGRect
    public let signatureRule: CGRect
    /// The seal (140 × 140) and its mark (62 × 55 at 39, 43 inside it).
    public let seal: CGRect
    /// The gap between the top stack and the bottom block (69.7 px on the
    /// Deep dive with a one-line name).
    public let slack: CGFloat

    // MARK: The design's numbers

    static let contentTop: [CertificateKind: CGFloat] = [.deepDive: 78, .basics: 86]
    static let contentLeft: CGFloat = 96
    static let contentRight: CGFloat = 960
    static let contentBottom: CGFloat = 744
    static let centerX: CGFloat = 528
    /// The date and signature columns: the design's 250 px on the Deep dive.
    /// AI Basics' are 290 px, so "INSTRUCTOR OR FAMILY MEMBER" (274.8 px at
    /// 14 px with 0.12em) sits on one line and both rules line up; in a
    /// 250 px column it wraps after "Family" and its rule rides 18 px higher
    /// than the date's. 72 px still separate each column from the seal.
    static func columnWidth(_ kind: CertificateKind) -> CGFloat {
        kind == .basics ? 290 : 250
    }
    /// Two lines of name sit 1.12 em apart, not the design's 1.05: at 1.05
    /// an accented capital on line 2 (Á, Ö, Å reach 0.79–0.82 em) runs into
    /// a g or y on line 1 (0.28 em down). The design only ever sets one line.
    static let twoLineHeight: CGFloat = 1.12
    /// The smallest gap left between the paragraph block and the seal when a
    /// two-line name pushes the stack down.
    static let minimumSlack: CGFloat = 16

    /// - Parameters:
    ///   - name: the learner's name as typed (normalized here). Empty shows
    ///     the placeholder.
    ///   - dateText: the date line ("October 21, 2026"), or nil for a blank
    ///     line over "Date".
    public static func make(kind: CertificateKind, name rawName: String, dateText: String?) -> CertificateLayout {
        let name = CertificateNameFit.normalized(rawName)
        let shown = name.isEmpty ? CertificateCopy.namePlaceholder : name
        let oneLineHeight = Certificate.layoutUnit(1.05 * CertificateNameFit.designSize)
        // The room under the stack with a one-line name decides how big two
        // lines may get.
        let baseSlack = slack(kind: kind, nameBlockHeight: oneLineHeight)
        let maxTwoLineSize = ((oneLineHeight + baseSlack - minimumSlack) / 2 / twoLineHeight).rounded(.down)
        let fit = CertificateNameFit.fit(shown, maxTwoLineSize: maxTwoLineSize) {
            CertificateType.width($0, face: .displayItalic, px: CertificateNameFit.designSize)
        }
        return build(kind: kind, fit: fit, isPlaceholder: name.isEmpty, dateText: dateText)
    }

    /// The height of the name's block: the design's one line box (75.6 px)
    /// for one line, whatever its size, so a slightly smaller name doesn't
    /// move the rest of the page; 1.12 × size per line for two.
    static func nameBlockHeight(_ fit: CertificateNameFit) -> CGFloat {
        if fit.lines.count <= 1 { return Certificate.layoutUnit(1.05 * CertificateNameFit.designSize) }
        return CGFloat(fit.lines.count) * Certificate.layoutUnit(twoLineHeight * fit.sizePx)
    }

    static func slack(kind: CertificateKind, nameBlockHeight: CGFloat) -> CGFloat {
        let probe = CertificateNameFit(lines: ["x"], sizePx: CertificateNameFit.designSize)
        return build(kind: kind, fit: probe, isPlaceholder: false, dateText: nil,
                     nameBlockOverride: nameBlockHeight).slack
    }

    // swiftlint:disable:next function_body_length
    static func build(kind: CertificateKind, fit: CertificateNameFit, isPlaceholder: Bool, dateText: String?,
                      nameBlockOverride: CGFloat? = nil) -> CertificateLayout {
        var lines: [Line] = []
        var y = contentTop[kind] ?? 78
        let mid = centerX

        func add(_ text: String, _ face: CertificateFace, _ px: CGFloat, tracking: CGFloat = 0, role: Role,
                 centerX: CGFloat = mid, lineTop: CGFloat, lineHeight: CGFloat? = nil) {
            let baseline = CertificateType.baseline(face, px: px, lineTop: lineTop, lineHeight: lineHeight)
            lines.append(Line(text: text, face: face, sizePx: px, trackingPx: tracking, role: role,
                              centerX: centerX, baseline: baseline))
        }

        // The mark.
        let topMark = CGRect(x: mid - 31, y: y, width: 62, height: 55)
        y += 55

        // MERCURIUS AI: 14 px, 0.34em.
        y += 10
        add(CertificateCopy.wordmark.uppercased(), .display, 14, tracking: 14 * 0.34, role: .wordmark, lineTop: y)
        y += CertificateType.normalLineHeight(.display, px: 14)

        // The title: 52 px, line-height 1.05.
        y += kind == .deepDive ? 16 : 18
        let titleHeight = Certificate.layoutUnit(52 * 1.05)
        add(CertificateCopy.title, .display, 52, role: .title, lineTop: y, lineHeight: 52 * 1.05)
        y += titleHeight

        // The ornament (Deep dive) or AI BASICS (Basics).
        var ornament: CGRect?
        switch kind {
        case .deepDive:
            y += 12
            ornament = CGRect(x: mid - 100, y: y, width: 200, height: 12)
            y += 12
            y += 14
        case .basics:
            y += 10
            add(CertificateCopy.basicsSubtitle.uppercased(), .display, 20, tracking: 20 * 0.3, role: .subtitle,
                lineTop: y)
            y += CertificateType.normalLineHeight(.display, px: 20)
            y += 26
        }

        // is proudly presented to: EB Garamond Italic 20 px.
        add(CertificateCopy.presentedTo, .bodyItalic, 20, role: .presented, lineTop: y)
        y += CertificateType.normalLineHeight(.bodyItalic, px: 20)

        // The name.
        y += 2
        let nameTop = y
        let nameHeight = nameBlockOverride ?? nameBlockHeight(fit)
        if fit.lines.count <= 1 {
            add(fit.lines.first ?? "", .displayItalic, fit.sizePx, role: isPlaceholder ? .namePlaceholder : .name,
                lineTop: nameTop, lineHeight: CertificateNameFit.designSize * 1.05)
        } else {
            let lineHeight = Certificate.layoutUnit(twoLineHeight * fit.sizePx)
            for (i, text) in fit.lines.enumerated() {
                add(text, .displayItalic, fit.sizePx, role: isPlaceholder ? .namePlaceholder : .name,
                    lineTop: nameTop + CGFloat(i) * lineHeight, lineHeight: twoLineHeight * fit.sizePx)
            }
        }
        y = nameTop + nameHeight

        // The rule under the name.
        y += 10
        let nameRule = CGRect(x: mid - 220, y: y, width: 440, height: 1)
        y += 1

        // The paragraph: EB Garamond 19 px / 1.45 (Deep dive), 20 px / 1.45
        // (Basics).
        y += kind == .deepDive ? 16 : 18
        let paragraphSize: CGFloat = kind == .deepDive ? 19 : 20
        let paragraphLine = Certificate.layoutUnit(paragraphSize * 1.45)
        for (i, text) in CertificateCopy.paragraphLines(kind).enumerated() {
            add(text, .body, paragraphSize, role: .paragraph, lineTop: y + CGFloat(i) * paragraphLine,
                lineHeight: paragraphSize * 1.45)
        }
        y += CGFloat(CertificateCopy.paragraphLines(kind).count) * paragraphLine

        // The unit names: Cormorant SemiBold 14 px, 0.14em, 4 px apart.
        let units = CertificateCopy.unitLines(kind)
        if !units.isEmpty {
            y += 14
            let unitLine = CertificateType.normalLineHeight(.display, px: 14)
            for (i, text) in units.enumerated() {
                add(text.uppercased(), .display, 14, tracking: 14 * 0.14, role: .units,
                    lineTop: y + CGFloat(i) * (unitLine + 4))
            }
            y += CGFloat(units.count) * unitLine + CGFloat(units.count - 1) * 4
        }
        let stackBottom = y

        // The bottom block, from the content box's bottom up.
        let footerHeight = CertificateType.normalLineHeight(.body, px: 14)
        let footerTop = contentBottom - footerHeight
        add(CertificateCopy.footer, .body, 14, role: .footer, lineTop: footerTop)
        let rowBottom = footerTop - 10
        let seal = CGRect(x: mid - 70, y: rowBottom - 140, width: 140, height: 140)

        // A column: its value line (20 px), 6, a 1 px rule, 6, its label
        // (14 px, 0.12em, one line or more), aligned to the row's bottom.
        let labelLine = CertificateType.normalLineHeight(.body, px: 14)
        let valueLine = CertificateType.normalLineHeight(.body, px: 20)
        let columnWidth = Self.columnWidth(kind)
        func column(centerX: CGFloat, value: String?, label: [String]) -> CGRect {
            let labelTop = rowBottom - CGFloat(label.count) * labelLine
            for (i, text) in label.enumerated() {
                add(text.uppercased(), .body, 14, tracking: 14 * 0.12, role: .label, centerX: centerX,
                    lineTop: labelTop + CGFloat(i) * labelLine)
            }
            let ruleY = labelTop - 6 - 1
            if let value, !value.isEmpty {
                add(value, .body, 20, role: .date, centerX: centerX, lineTop: ruleY - 6 - valueLine)
            }
            return CGRect(x: centerX - columnWidth / 2, y: ruleY, width: columnWidth, height: 1)
        }
        let leftCenter = contentLeft + columnWidth / 2
        let rightCenter = contentRight - columnWidth / 2
        let dateRule = column(centerX: leftCenter, value: dateText, label: [CertificateCopy.dateLabel])
        let signatureRule = column(centerX: rightCenter, value: nil, label: CertificateCopy.signatureLabel(kind))

        return CertificateLayout(
            kind: kind,
            lines: lines,
            name: fit,
            topMark: topMark,
            ornament: ornament,
            nameRule: nameRule,
            dateRule: dateRule,
            signatureRule: signatureRule,
            seal: seal,
            slack: seal.minY - stackBottom
        )
    }
}
