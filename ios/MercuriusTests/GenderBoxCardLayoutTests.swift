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
                        width: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: try card(debug, showAll: showAll, size: size, width: width))
        renderer.scale = 1
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
        return image
    }

    /// The opaque pixels outside the card's own frame (alpha above 40).
    private func strayPixels(in image: CGImage, width: CGFloat) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let left = Int(Self.margin) - 1
        let right = Int(Self.margin + width) + 1
        var stray = 0
        for y in 0..<h {
            for x in 0..<w where x < left || x > right {
                if data[(y * w + x) * 4 + 3] > 40 { stray += 1 }
            }
        }
        return stray
    }

    func testNothingLeavesTheCardAtAnyWidthOrTextSize() throws {
        for width in Self.widths {
            for size in Self.sizes {
                var cases: [(InteractiveDebugState, Bool)] = [(.hook, false), (.revealed, false)]
                if size.isAccessibilitySize { cases.append((.revealed, true)) }
                for (debug, showAll) in cases {
                    let image = try render(debug, showAll: showAll, size: size, width: width)
                    XCTAssertEqual(CGFloat(image.width), width + 2 * Self.margin,
                                   "the card at \(size), \(debug) asked for more than \(width) pt")
                    XCTAssertEqual(strayPixels(in: image, width: width), 0,
                                   "something of the card at \(size), \(width) pt, \(debug), lands outside it")
                }
            }
        }
    }

    func testTheCardGrowsWithTheTextAndTheListOpensAtAccessibilitySizes() throws {
        func height(_ debug: InteractiveDebugState, showAll: Bool = false, _ size: DynamicTypeSize) throws -> CGFloat {
            CGFloat(try render(debug, showAll: showAll, size: size, width: 343).height) - 2 * Self.margin
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
