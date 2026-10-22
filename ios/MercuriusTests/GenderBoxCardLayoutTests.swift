import XCTest
import SwiftUI
import UIKit
import LessonInteractives

/// Delete the Gender Box (U3L1) on the iPhone: the card at an SE's and a
/// 16 Pro Max's width, at every text size the lesson is checked at, before
/// the guess and after the reveal, rendered by the real views on iOS (where
/// Dynamic Type applies). Nothing of it may land outside its width (no card
/// scrolls sideways), and at the accessibility sizes the table goes behind
/// "Show all 12" (the shared rules are in the SPM tests: GenderBoxTests).
///
/// Set TEST_RUNNER_GENDERBOX_RENDER_DIR to a folder to keep each render as a
/// PNG (for review; nothing is compared against a reference).
@MainActor
final class GenderBoxCardLayoutTests: XCTestCase {

    private static let widths: [CGFloat] = [343, 408]
    private static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]
    /// Room around the card in a render, where nothing of it may land.
    private static let margin: CGFloat = 120
    /// Pixels per point, at most. A render much over 8,000 px tall comes
    /// back empty (and would pass the overflow check without showing
    /// anything), and the whole card at AX5 with the list open is far
    /// taller than that in points, so each render picks its own scale from
    /// the card's height, and `opaqueShare` proves it drew.
    private static let scale: CGFloat = 0.5
    private static let tallestRender: CGFloat = 8000

    private struct Render {
        let image: CGImage
        let scale: CGFloat
    }

    private func card(_ debug: InteractiveDebugState, showAll: Bool, size: DynamicTypeSize,
                      width: CGFloat) throws -> some View {
        let spec = try XCTUnwrap(InteractiveRegistry.spec(for: .deleteTheGenderBox))
        let store = InteractiveStateStore()
        let state = store.state(for: .deleteTheGenderBox) { GenderBoxState(spoiled: false, debug: debug) }
        state.showsAllResumes = showAll
        return InteractiveCardViews.card(InteractiveCardContext(spec: spec, spoiled: false, store: store))
            .environment(\.dynamicTypeSize, size)
            // Dark: the card draws no shadow, so anything outside it is a
            // piece of the card that left it.
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .padding(Self.margin)
    }

    private func render(_ debug: InteractiveDebugState, showAll: Bool = false, size: DynamicTypeSize,
                        width: CGFloat) throws -> Render {
        let view = try card(debug, showAll: showAll, size: size, width: width)
        let fitted = UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width + 2 * Self.margin, height: .greatestFiniteMagnitude))
        let scale = min(Self.scale, Self.tallestRender / max(fitted.height, 1))
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage, "the card didn't render at \(size), \(width) pt")
        if let dir = ProcessInfo.processInfo.environment["GENDERBOX_RENDER_DIR"] {
            // In slices of 3,000 px: a whole AX5 card is too tall to encode
            // as one PNG.
            let name = "genderbox-\(Int(width))-\(size)-\(debug.rawValue)\(showAll ? "-all" : "")"
            let slice = 3000
            var top = 0
            var part = 1
            while top < image.height {
                let rect = CGRect(x: 0, y: top, width: image.width, height: min(slice, image.height - top))
                if let piece = image.cropping(to: rect) {
                    let suffix = image.height > slice ? "-\(part)" : ""
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png")
                    try? UIImage(cgImage: piece).pngData()?.write(to: url)
                }
                top += slice
                part += 1
            }
        }
        return Render(image: image, scale: scale)
    }

    /// The render's pixels as RGBA bytes.
    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The opaque pixels outside the card's own frame (alpha above 40).
    private func strayPixels(in render: Render, width: CGFloat) -> Int {
        let image = render.image
        let data = pixels(image)
        guard !data.isEmpty else { return -1 }
        let w = image.width, h = image.height
        let left = Int(Self.margin * render.scale) - 1
        let right = Int((Self.margin + width) * render.scale) + 1
        var stray = 0
        for y in 0..<h {
            for x in 0..<w where x < left || x > right {
                if data[(y * w + x) * 4 + 3] > 40 { stray += 1 }
            }
        }
        return stray
    }

    /// The share of the card's own frame that is drawn (alpha above 40): near 1 for
    /// a real render, 0 for an empty one.
    private func opaqueShare(in render: Render, width: CGFloat) -> Double {
        let image = render.image
        let data = pixels(image)
        guard !data.isEmpty else { return 0 }
        let w = image.width
        let x0 = Int(Self.margin * render.scale) + 2, x1 = Int((Self.margin + width) * render.scale) - 2
        let y0 = Int(Self.margin * render.scale) + 2, y1 = image.height - Int(Self.margin * render.scale) - 2
        guard x1 > x0, y1 > y0 else { return 0 }
        var opaque = 0
        for y in y0..<y1 {
            for x in x0..<x1 where data[(y * w + x) * 4 + 3] > 40 { opaque += 1 }
        }
        return Double(opaque) / Double((x1 - x0) * (y1 - y0))
    }

    func testNothingLeavesTheCardAtAnyWidthOrTextSize() throws {
        for width in Self.widths {
            for size in Self.sizes {
                var cases: [(InteractiveDebugState, Bool)] = [(.hook, false), (.revealed, false)]
                if size.isAccessibilitySize { cases.append((.revealed, true)) }
                for (debug, showAll) in cases {
                    let drawn = try render(debug, showAll: showAll, size: size, width: width)
                    XCTAssertEqual(CGFloat(drawn.image.width), ((width + 2 * Self.margin) * drawn.scale).rounded(.up),
                                   accuracy: 1, "the card at \(size), \(debug) asked for more than \(width) pt")
                    XCTAssertGreaterThan(opaqueShare(in: drawn, width: width), 0.9,
                                         "the card at \(size), \(width) pt, \(debug) didn't render")
                    XCTAssertEqual(strayPixels(in: drawn, width: width), 0,
                                   "something of the card at \(size), \(width) pt, \(debug), lands outside it")
                }
            }
        }
    }

    func testTheCardGrowsWithTheTextAndTheListOpensAtAccessibilitySizes() throws {
        func height(_ debug: InteractiveDebugState, showAll: Bool = false, _ size: DynamicTypeSize) throws -> CGFloat {
            let drawn = try render(debug, showAll: showAll, size: size, width: 343)
            return CGFloat(drawn.image.height) / drawn.scale - 2 * Self.margin
        }
        let large = try height(.hook, .large)
        XCTAssertGreaterThan(try height(.hook, .xxxLarge), large, "the card grows with the text")
        XCTAssertGreaterThan(try height(.revealed, .large), large, "the reveal adds to the card")
        // At AX5 the table is folded: opening it adds the 12 résumés as text.
        let folded = try height(.revealed, .accessibility5)
        let open = try height(.revealed, showAll: true, .accessibility5)
        XCTAssertGreaterThan(open, folded + 600, "Show all 12 adds the résumés as text")
        // A sanity floor: the table, the weights and the test résumés at Large on an SE.
        XCTAssertGreaterThan(large, 900)
    }
}
