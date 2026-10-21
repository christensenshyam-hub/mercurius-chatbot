import CoreText
import ImageIO
import SwiftUI

/// A certificate, drawn at exactly 792 × 612 pt (US Letter landscape) to
/// match the founder's "B · Laurel" designs: the Deep dive certificate
/// (`Laurel.dc.html`) and AI Basics (`LaurelBasics.dc.html`). Always the
/// light paper, in either appearance. Scale it with `scaleEffect` for a
/// preview; `CertificatePDF` prints it.
///
/// VoiceOver reads it as one image: "Certificate of Completion, AI Literacy
/// Course, awarded to …, October 21, 2026".
public struct CertificateView: View {
    private let kind: CertificateKind
    private let name: String
    private let dateText: String?
    private let paintsPaper: Bool

    /// - Parameters:
    ///   - name: the learner's name; empty shows "Your Name" faintly (the
    ///     sheet's preview before anything is typed).
    ///   - date: the completion date, or nil for a blank line over "Date".
    ///   - paintsPaper: fill the page with the paper's #FDFDFB (on screen).
    ///     The PDF leaves it out: printed, the paper is the paper, and a
    ///     printer turns a 1% tint into a dot pattern that ends in a hard
    ///     edge at its margins.
    public init(kind: CertificateKind, name: String, date: Date?, paintsPaper: Bool = true) {
        self.init(kind: kind, name: name, dateText: date.map { CertificateCopy.dateText($0) },
                  paintsPaper: paintsPaper)
    }

    public init(kind: CertificateKind, name: String, dateText: String?, paintsPaper: Bool = true) {
        self.kind = kind
        self.name = name
        self.dateText = dateText
        self.paintsPaper = paintsPaper
    }

    public var body: some View {
        let layout = CertificateLayout.make(kind: kind, name: name, dateText: dateText)
        CertificatePage {
            if paintsPaper {
                Certificate.Ink.paper
                    .certificatePlacement(.fill)
            }
            CertificateFrame(kind: kind)
                .certificatePlacement(.fill)
            CertificateMark()
                .certificatePlacement(.rect(layout.topMark))
            if let ornament = layout.ornament {
                CertificateOrnament()
                    .certificatePlacement(.rect(ornament))
            }
            Certificate.Ink.gold
                .certificatePlacement(.rect(layout.nameRule))
            Certificate.Ink.navy
                .certificatePlacement(.rect(layout.dateRule))
            Certificate.Ink.navy
                .certificatePlacement(.rect(layout.signatureRule))
            CertificateSeal(kind: kind)
                .certificatePlacement(.rect(layout.seal))
            ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line.text)
                    .font(CertificateType.font(line.face, px: line.sizePx))
                    .tracking(Certificate.pt(line.trackingPx))
                    .foregroundStyle(Self.color(for: line.role))
                    .lineLimit(1)
                    .fixedSize()
                    .certificatePlacement(.baseline(centerX: line.centerX, y: line.baseline))
            }
        }
        .frame(width: Certificate.pageSize.width, height: Certificate.pageSize.height)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CertificateCopy.accessibilitySummary(kind: kind, name: name, dateText: dateText))
        .accessibilityAddTraits(.isImage)
    }

    static func color(for role: CertificateLayout.Role) -> Color {
        switch role {
        case .wordmark: return Certificate.Ink.navy
        case .title, .name, .date: return Certificate.Ink.ink
        case .namePlaceholder: return Certificate.Ink.ink.opacity(0.22)
        case .subtitle: return Certificate.Ink.sealText
        case .presented: return Certificate.Ink.presented
        case .paragraph: return Certificate.Ink.paragraph
        case .units, .label: return Certificate.Ink.caps
        case .footer: return Certificate.Ink.footer
        }
    }
}

// MARK: - Placement

/// Where a certificate element goes, in design pixels.
enum CertificatePlacement: Equatable {
    /// The whole page.
    case fill
    /// A box.
    case rect(CGRect)
    /// A line of text: its first baseline at `y`, its box centred on `centerX`.
    case baseline(centerX: CGFloat, y: CGFloat)
}

private struct CertificatePlacementKey: LayoutValueKey {
    static let defaultValue = CertificatePlacement.fill
}

extension View {
    func certificatePlacement(_ placement: CertificatePlacement) -> some View {
        layoutValue(key: CertificatePlacementKey.self, value: placement)
    }
}

/// Lays the page out by absolute placement: the designs fix every position,
/// and text goes by its baseline, which no stack can promise.
struct CertificatePage: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Certificate.pageSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let k = Certificate.pointsPerPixel
        for subview in subviews {
            switch subview[CertificatePlacementKey.self] {
            case .fill:
                subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
            case .rect(let r):
                subview.place(at: CGPoint(x: bounds.minX + r.minX * k, y: bounds.minY + r.minY * k),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: r.width * k, height: r.height * k))
            case .baseline(let centerX, let y):
                let d = subview.dimensions(in: .unspecified)
                subview.place(at: CGPoint(x: bounds.minX + centerX * k - d.width / 2,
                                          y: bounds.minY + y * k - d[.firstTextBaseline]),
                              anchor: .topLeading, proposal: .unspecified)
            }
        }
    }
}

// MARK: - Pieces

/// The two borders: navy at 40 px (2 px on the Deep dive, 1.5 px on AI
/// Basics), gold at 50 px (1 px), and on the Deep dive a gold diamond (a
/// 14 px square turned 45°) on each corner.
struct CertificateFrame: View {
    let kind: CertificateKind

    var body: some View {
        let outerWidth: CGFloat = kind == .deepDive ? 2 : 1.5
        Canvas { context, _ in
            func inset(_ px: CGFloat) -> CGRect {
                let p = Certificate.pt(px)
                return CGRect(x: p, y: p, width: Certificate.pageSize.width - 2 * p,
                              height: Certificate.pageSize.height - 2 * p)
            }
            // A CSS border is inside its box: the stroke's centre is half
            // its width in from the inset.
            context.stroke(Path(inset(40 + outerWidth / 2)), with: .color(Certificate.Ink.navy),
                           lineWidth: Certificate.pt(outerWidth))
            context.stroke(Path(inset(50.5)), with: .color(Certificate.Ink.gold), lineWidth: Certificate.pt(1))
            guard kind == .deepDive else { return }
            for (x, y) in [(50, 50), (1006, 50), (50, 766), (1006, 766)] as [(CGFloat, CGFloat)] {
                context.fill(Self.diamond(centerX: x, centerY: y, side: 14), with: .color(Certificate.Ink.gold))
            }
        }
        .frame(width: Certificate.pageSize.width, height: Certificate.pageSize.height)
    }

    /// A square of `side` design pixels turned 45° about its centre.
    static func diamond(centerX: CGFloat, centerY: CGFloat, side: CGFloat) -> Path {
        let half = Certificate.pt(side) * 0.5.squareRoot() // half the diagonal: side / √2
        let c = CGPoint(x: Certificate.pt(centerX), y: Certificate.pt(centerY))
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - half))
        path.addLine(to: CGPoint(x: c.x + half, y: c.y))
        path.addLine(to: CGPoint(x: c.x, y: c.y + half))
        path.addLine(to: CGPoint(x: c.x - half, y: c.y))
        path.closeSubpath()
        return path
    }
}

/// The Deep dive's ornament under the title: two 88 px gold hairlines and a
/// 10 px diamond between them, in a 200 × 12 box.
struct CertificateOrnament: View {
    var body: some View {
        Canvas { context, _ in
            let y = Certificate.pt(6)
            var lines = Path()
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: Certificate.pt(88), y: y))
            lines.move(to: CGPoint(x: Certificate.pt(112), y: y))
            lines.addLine(to: CGPoint(x: Certificate.pt(200), y: y))
            context.stroke(lines, with: .color(Certificate.Ink.gold), lineWidth: Certificate.pt(1))
            context.fill(CertificateFrame.diamond(centerX: 100, centerY: 6, side: 10),
                         with: .color(Certificate.Ink.gold))
        }
        .frame(width: Certificate.pt(200), height: Certificate.pt(12))
    }
}

/// The Mercurius mark (the winged Hermes), from DesignSystem's resources at
/// its full 470 × 415 px, contained in a 62 × 55 px box as the design's
/// `object-fit: contain` does.
struct CertificateMark: View {
    var body: some View {
        if let image = CertificateArt.mark {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: Certificate.pt(62), height: Certificate.pt(55))
        } else {
            Color.clear.frame(width: Certificate.pt(62), height: Certificate.pt(55))
        }
    }
}

/// The seal: a 1.5 px gold ring at r 68, a 1 px ring at r 45, the course's
/// words set around a circle of r 56 (Cormorant Garamond SemiBold 12 px,
/// letter-spacing 2, spaced to a 345 px run, as the design's `textPath`
/// with `textLength="345"`), and the mark in the middle.
struct CertificateSeal: View {
    let kind: CertificateKind

    var body: some View {
        let ring = CertificateSealRing.glyphs(for: CertificateCopy.sealRing(kind))
        let font = CertificateType.font(.display, px: CertificateSealRing.fontSize)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let c = CGPoint(x: Certificate.pt(70), y: Certificate.pt(70))
                func circle(_ r: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - Certificate.pt(r), y: c.y - Certificate.pt(r),
                                           width: Certificate.pt(2 * r), height: Certificate.pt(2 * r)))
                }
                context.stroke(circle(68), with: .color(Certificate.Ink.gold), lineWidth: Certificate.pt(1.5))
                context.stroke(circle(45), with: .color(Certificate.Ink.gold), lineWidth: Certificate.pt(1))
                for glyph in ring where !glyph.character.isWhitespace {
                    let resolved = context.resolve(
                        Text(verbatim: String(glyph.character)).font(font).foregroundStyle(Certificate.Ink.sealText)
                    )
                    let size = resolved.measure(in: CGSize(width: 1000, height: 1000))
                    let baseline = resolved.firstBaseline(in: size)
                    var g = context
                    g.translateBy(x: Certificate.pt(glyph.point.x), y: Certificate.pt(glyph.point.y))
                    g.rotate(by: .radians(glyph.rotation))
                    // The glyph's advance centred on the path point, its
                    // baseline on the circle.
                    let advance = Certificate.pt(glyph.advance)
                    g.draw(resolved, in: CGRect(x: -advance / 2, y: -baseline, width: size.width, height: size.height))
                }
            }
            .frame(width: Certificate.pt(140), height: Certificate.pt(140))
            CertificateMark()
                .offset(x: Certificate.pt(39), y: Certificate.pt(43))
        }
        .frame(width: Certificate.pt(140), height: Certificate.pt(140), alignment: .topLeading)
    }
}

/// The seal's words on their circle, laid out as SVG lays text on a path:
/// each glyph's advance centred on its point of the path, turned to the
/// path's direction. The path starts at 9 o'clock and runs clockwise over
/// the top (`M14,70 a56,56 0 1,1 112,0 …`); `textLength` spreads the run's
/// extra room evenly between the characters (SVG 2 `lengthAdjust=spacing`).
enum CertificateSealRing {
    static let fontSize: CGFloat = 12
    static let letterSpacing: CGFloat = 2
    static let textLength: CGFloat = 345
    static let radius: CGFloat = 56
    static let center = CGPoint(x: 70, y: 70)

    struct Glyph: Equatable {
        let character: Character
        /// The glyph's own advance (kerning included), design px.
        let advance: CGFloat
        /// Where the middle of its advance sits on the circle, design px in
        /// the 140 × 140 seal.
        let point: CGPoint
        /// The glyph's turn, radians (0 = upright, at 12 o'clock).
        let rotation: Double
    }

    static func glyphs(for text: String) -> [Glyph] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        let advances = self.advances(text)
        let natural = advances.reduce(0, +) + letterSpacing * CGFloat(characters.count)
        let delta = characters.count > 1 ? (textLength - natural) / CGFloat(characters.count - 1) : 0
        var start: CGFloat = 0
        var glyphs: [Glyph] = []
        for (i, character) in characters.enumerated() {
            let advance = advances[i]
            let mid = Double(start + advance / 2)
            let theta = mid / Double(radius)
            let point = CGPoint(x: center.x - radius * CGFloat(cos(theta)),
                                y: center.y - radius * CGFloat(sin(theta)))
            glyphs.append(Glyph(character: character, advance: advance, point: point, rotation: theta - Double.pi / 2))
            start += advance + letterSpacing + delta
        }
        return glyphs
    }

    /// Each character's advance in the set line (kerning included), design px.
    static func advances(_ text: String) -> [CGFloat] {
        let font = CertificateType.ctFont(.display, points: fontSize)
        let attributed = NSAttributedString(string: text,
                                            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let total = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // String offset (UTF-16) → x of the glyph that starts there.
        var starts: [Int: CGFloat] = [:]
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            for i in 0..<count where starts[indices[i]] == nil {
                starts[indices[i]] = positions[i].x
            }
        }
        var offsets: [Int] = []
        var utf16 = 0
        for character in text {
            offsets.append(utf16)
            utf16 += character.utf16.count
        }
        return offsets.enumerated().map { i, offset in
            let x = starts[offset] ?? 0
            let next = i + 1 < offsets.count ? (starts[offsets[i + 1]] ?? total) : total
            return max(0, next - x)
        }
    }
}

/// The certificate's art from DesignSystem's resources.
enum CertificateArt {
    /// DesignSystem's resources (the fonts and the mark).
    static var bundle: Bundle { .module }

    /// The mark, 470 × 415 px with transparency.
    static let mark: CGImage? = {
        guard let url = bundle.url(forResource: "certificate-mark", withExtension: "png",
                                          subdirectory: "CertificateArt"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
}

// MARK: - Preview

/// A certificate scaled to the width it's given (the name sheet, the
/// Certificates list, the course-complete card), on its paper with a soft
/// shadow. One image for VoiceOver, with the certificate's summary.
public struct CertificatePreview: View {
    private let kind: CertificateKind
    private let name: String
    private let date: Date?
    private let shadow: Bool

    public init(kind: CertificateKind, name: String, date: Date?, shadow: Bool = true) {
        self.kind = kind
        self.name = name
        self.date = date
        self.shadow = shadow
    }

    public var body: some View {
        let page = Certificate.pageSize
        Color.clear
            .aspectRatio(page.width / page.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    CertificateView(kind: kind, name: name, date: date)
                        .scaleEffect(geo.size.width / page.width, anchor: .topLeading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .clipShape(Rectangle())
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(shadow ? 0.16 : 0), radius: 10, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CertificateCopy.accessibilitySummary(
                kind: kind, name: name, dateText: date.map { CertificateCopy.dateText($0) }))
            .accessibilityAddTraits(.isImage)
    }
}
