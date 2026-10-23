import Foundation
import CoreGraphics

/// How the learner's name sets: on one line at the design's 72 px when it
/// fits the 864 px column, otherwise a little smaller on one line, otherwise
/// on two balanced lines (never more), never wider than the column.
///
/// Pure: it measures through `widthAtDesignSize`, so the tests drive it with
/// a fake measure and the view with the real font.
public struct CertificateNameFit: Equatable, Sendable {
    /// One or two lines, as they print.
    public let lines: [String]
    /// The name's size in design pixels.
    public let sizePx: CGFloat

    public init(lines: [String], sizePx: CGFloat) {
        self.lines = lines
        self.sizePx = sizePx
    }

    /// The design's size: Cormorant Garamond SemiBold Italic, 72 px.
    public static let designSize: CGFloat = 72
    /// The design's column: the content box between the 96 px side insets.
    public static let maxWidth: CGFloat = 864
    /// A name that would have to shrink past this to stay on one line
    /// breaks onto two instead (80% of the design size).
    public static let singleLineFloor: CGFloat = 57.5
    /// The longest name the sheet takes. Names up to about 60 characters
    /// keep a generous size; past that the size keeps falling to fit.
    public static let maxLength = 80

    /// The name as it prints: no leading or trailing space, inner runs of
    /// white space (tabs, new lines) as single spaces, at most `maxLength`
    /// characters.
    public static func normalized(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(words.joined(separator: " ").prefix(maxLength))
    }

    /// - Parameters:
    ///   - maxTwoLineSize: the largest size two lines may take (the room the
    ///     certificate has below the name, in design pixels per line).
    ///   - widthAtDesignSize: a line's width at `designSize`, in design pixels.
    public static func fit(
        _ raw: String,
        maxTwoLineSize: CGFloat,
        widthAtDesignSize: (String) -> CGFloat
    ) -> CertificateNameFit {
        let name = normalized(raw)
        guard !name.isEmpty else { return CertificateNameFit(lines: [""], sizePx: designSize) }
        let width = widthAtDesignSize(name)
        if width <= maxWidth {
            return CertificateNameFit(lines: [name], sizePx: designSize)
        }
        let oneLine = quantized(designSize * maxWidth / width)
        if oneLine >= singleLineFloor {
            return CertificateNameFit(lines: [name], sizePx: oneLine)
        }
        // Two lines: the break that lets the name set largest, the more
        // balanced pair winning a tie, as CSS `text-wrap: balance` would set
        // it. A break after a hyphen splits a double-barrelled surname (it
        // reads as another name), so it is taken only when no break at a
        // space sets the name at `spaceBreakFloor` or more.
        var bestAtSpace: (split: Split, size: CGFloat, widest: CGFloat)?
        var bestAtHyphen: (split: Split, size: CGFloat, widest: CGFloat)?
        for split in breakOpportunities(in: name) {
            let widest = max(widthAtDesignSize(split.first), widthAtDesignSize(split.second))
            let size = quantized(min(maxTwoLineSize, designSize * maxWidth / widest))
            let current = split.atHyphen ? bestAtHyphen : bestAtSpace
            if let current, size < current.size || (size == current.size && widest >= current.widest) {
                continue
            }
            if split.atHyphen { bestAtHyphen = (split, size, widest) } else { bestAtSpace = (split, size, widest) }
        }
        let best: (split: Split, size: CGFloat, widest: CGFloat)?
        switch (bestAtSpace, bestAtHyphen) {
        case let (space?, hyphen?):
            best = space.size < spaceBreakFloor && hyphen.size > space.size ? hyphen : space
        case let (space?, nil):
            best = space
        case let (nil, hyphen):
            best = hyphen
        }
        guard let best else {
            // One unbreakable word: it shrinks on its line.
            return CertificateNameFit(lines: [name], sizePx: oneLine)
        }
        if best.size > oneLine {
            return CertificateNameFit(lines: [best.split.first, best.split.second], sizePx: best.size)
        }
        return CertificateNameFit(lines: [name], sizePx: oneLine)
    }

    /// A break at a space that sets the name at least this large (two
    /// thirds of the design size) always beats a break after a hyphen, so
    /// the Deep dive and AI Basics break a name alike. Only a name whose
    /// every space break leaves a line far too long (a long hyphenated run)
    /// breaks at a hyphen instead.
    static let spaceBreakFloor: CGFloat = 48

    struct Split: Equatable {
        let first: String
        let second: String
        /// Broken after a hyphen (it stays at the end of the first line).
        let atHyphen: Bool
    }

    /// Every place a name may break: at a space (the space goes), or after a
    /// hyphen (it stays at the end of the first line), as a browser breaks.
    ///
    /// A space break whose first line ends on a lowercase word is left out:
    /// that word is a particle (de, los, van, von, der, da, bin, al, y…) and
    /// belongs with the surname after it ("Maria Fernanda de los" /
    /// "Santos…" strands it). If that leaves no space break at all (a name
    /// typed in lowercase), every space break is back in.
    static func breakOpportunities(in name: String) -> [Split] {
        var atSpaces: [Split] = []
        var atParticles: [Split] = []
        var atHyphens: [Split] = []
        let chars = Array(name)
        for i in chars.indices where i > 0 && i < chars.count - 1 {
            if chars[i] == " " {
                let split = Split(first: String(chars[..<i]), second: String(chars[(i + 1)...]), atHyphen: false)
                if split.first.split(separator: " ").last?.first?.isLowercase == true {
                    atParticles.append(split)
                } else {
                    atSpaces.append(split)
                }
            } else if chars[i] == "-" || chars[i] == "\u{2010}" {
                atHyphens.append(Split(first: String(chars[...i]), second: String(chars[(i + 1)...]), atHyphen: true))
            }
        }
        let splits = (atSpaces.isEmpty ? atParticles : atSpaces) + atHyphens
        return splits.filter {
            !$0.first.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.second.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Sizes step in quarter pixels, rounded down so a line never overflows.
    static func quantized(_ size: CGFloat) -> CGFloat {
        (size * 4).rounded(.down) / 4
    }
}
