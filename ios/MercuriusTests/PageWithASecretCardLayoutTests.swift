import XCTest
import SwiftUI
import UIKit
@testable import ChatFeature
import LessonInteractives

/// The Page with a Secret (u8_l1) on the iPhone: the whole card, in every
/// state a student reaches (the hook, a locked guess, the agent's view, the
/// reveal, and the spoiled mode), at an SE's and a 16 Pro Max's width and at
/// every text size the lesson is checked at. Rendered by the real views on
/// iOS, where Dynamic Type applies (the card's rules are in the SPM tests:
/// PageWithASecretTests). The TokenizerCardLayoutTests pattern.
///
/// Set TEST_RUNNER_PAGE_SECRET_RENDER_DIR to a folder to keep each render as
/// a PNG (for review; nothing is compared against a reference).
@MainActor
final class PageWithASecretCardLayoutTests: XCTestCase {

    /// The card's width: an SE's row (375 pt less its 16 pt margins) and a
    /// 16 Pro Max's (440 pt less them).
    private static let widths: [CGFloat] = [343, 408]
    private static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]
    private static let states: [InteractiveDebugState] = [.hook, .predicted, .explored, .revealed, .spoiled]
    /// Room around the card in a render, where nothing of it may land.
    private static let margin: CGFloat = 120

    private func card(_ state: InteractiveDebugState, size: DynamicTypeSize, width: CGFloat) throws -> some View {
        let spec = try XCTUnwrap(InteractiveRegistry.spec(for: .pageWithASecret))
        let store = InteractiveStateStore()
        let spoiled = state == .spoiled
        _ = store.state(for: .pageWithASecret) { PageWithASecretState(spoiled: spoiled, debug: state) }
        return InteractiveCardViews.card(InteractiveCardContext(spec: spec, spoiled: spoiled, store: store))
            .environment(store)
            .environment(\.dynamicTypeSize, size)
            // Dark: the card draws no shadow, so anything outside it is a
            // piece of the card that left it.
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .padding(Self.margin)
    }

    private func render(_ state: InteractiveDebugState, size: DynamicTypeSize, width: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: try card(state, size: size, width: width))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage, "the card didn't render at \(size), \(width) pt, \(state)")
        if let dir = ProcessInfo.processInfo.environment["PAGE_SECRET_RENDER_DIR"] {
            let name = "page-\(Int(width))-\(size)-\(state.rawValue).png"
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            try? UIImage(cgImage: image).pngData()?.write(to: url)
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

    func testNothingLeavesTheCardInAnyStateWidthOrTextSize() throws {
        for width in Self.widths {
            for size in Self.sizes {
                for state in Self.states {
                    let image = try render(state, size: size, width: width)
                    XCTAssertEqual(CGFloat(image.width), width + 2 * Self.margin,
                                   "the card (\(state)) at \(size) asked for more than \(width) pt")
                    XCTAssertEqual(strayPixels(in: image, width: width), 0,
                                   "something of the card (\(state)) at \(size), \(width) pt, lands outside it")
                }
            }
        }
    }

    func testTheCardGrowsWithTheTextAndWithTheRun() throws {
        func height(_ state: InteractiveDebugState, _ size: DynamicTypeSize, _ width: CGFloat = 343) throws -> CGFloat {
            CGFloat(try render(state, size: size, width: width).height) - 2 * Self.margin
        }
        // Every word stays at the accessibility sizes, so the card only grows.
        let large = try height(.revealed, .large)
        let xxxLarge = try height(.revealed, .xxxLarge)
        XCTAssertGreaterThan(xxxLarge, large, "the card grows with the text")
        XCTAssertGreaterThan(try height(.revealed, .accessibility5), try height(.revealed, .accessibility3))
        // Each state shows more of the run than the one before.
        let hook = try height(.hook, .large)
        let predicted = try height(.predicted, .large)
        let explored = try height(.explored, .large)
        XCTAssertGreaterThan(predicted, hook, "steps 2 and 3 and the page arrive")
        XCTAssertGreaterThan(explored, predicted, "step 4 arrives")
        XCTAssertGreaterThan(large, explored, "steps 5 and 6 and the reveal arrive")
    }
}
