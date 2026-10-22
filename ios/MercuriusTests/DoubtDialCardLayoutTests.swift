import XCTest
import SwiftUI
import UIKit
import LessonInteractives

/// The Doubt Dial on the iPhone (U6L4): the whole card at an SE's and a 16
/// Pro Max's width, at every text size the lesson is checked at, in each of
/// its states, rendered by the real views on iOS (where Dynamic Type
/// applies). Nothing of it may land outside its width: no card scrolls
/// sideways. The card's rules are in the SPM tests (DoubtDialTests).
///
/// Set TEST_RUNNER_DOUBT_DIAL_RENDER_DIR to a folder to keep each render as
/// a PNG (for review; nothing is compared against a reference).
@MainActor
final class DoubtDialCardLayoutTests: XCTestCase {

    /// An SE's row (375 pt less its 16 pt margins) and a 16 Pro Max's.
    private static let widths: [CGFloat] = [343, 408]
    private static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]
    /// Room around the card in a render, where nothing of it may land.
    private static let margin: CGFloat = 120

    /// The states a student passes through, reached as the shots reach them.
    private static let states: [(name: String, state: [String], debug: [String])] = [
        ("hook", [], []),
        ("explored", ["-InteractiveState", "explored"], []),
        ("revealed", ["-InteractiveState", "revealed"], []),
        ("checked", ["-InteractiveState", "revealed"], ["-DoubtDialCheckFirst", "YES"]),
        ("middle", ["-InteractiveState", "revealed"], ["-DoubtDialGuess", "middle"]),
        ("spoiled", ["-InteractiveState", "spoiled"], []),
    ]

    private func card(_ index: Int, size: DynamicTypeSize, width: CGFloat) throws -> some View {
        let entry = Self.states[index]
        let spec = try XCTUnwrap(InteractiveRegistry.spec(for: .doubtDial))
        let spoiled = entry.name == "spoiled"
        let store = InteractiveStateStore()
        let state = DoubtDialState(spoiled: spoiled, launch: InteractiveLaunchOptions(arguments: entry.state),
                                   debug: DoubtDialDebug(arguments: entry.debug))
        _ = store.state(for: .doubtDial) { state }
        return DoubtDialPhoneCard(InteractiveCardContext(spec: spec, spoiled: spoiled, store: store))
            .environment(\.dynamicTypeSize, size)
            // Dark: the card draws no shadow, so anything outside it is a
            // piece of the card that left it.
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .padding(Self.margin)
    }

    private func render(_ index: Int, size: DynamicTypeSize, width: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: try card(index, size: size, width: width))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage, "the card didn't render at \(size), \(width) pt")
        if let dir = ProcessInfo.processInfo.environment["DOUBT_DIAL_RENDER_DIR"] {
            let name = "doubt-dial-\(Int(width))-\(size)-\(Self.states[index].name).png"
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

    func testNothingLeavesTheCardAtAnyWidthTextSizeOrState() throws {
        for width in Self.widths {
            for size in Self.sizes {
                for index in Self.states.indices {
                    let image = try render(index, size: size, width: width)
                    let name = Self.states[index].name
                    XCTAssertEqual(CGFloat(image.width), width + 2 * Self.margin,
                                   "the \(name) card at \(size) asked for more than \(width) pt")
                    XCTAssertEqual(strayPixels(in: image, width: width), 0,
                                   "something of the \(name) card at \(size), \(width) pt, lands outside it")
                }
            }
        }
    }

    func testTheCardGrowsWithTheTextAndWithEachStep() throws {
        func height(_ index: Int, _ size: DynamicTypeSize) throws -> CGFloat {
            CGFloat(try render(index, size: size, width: 343).height) - 2 * Self.margin
        }
        XCTAssertGreaterThan(try height(0, .accessibility5), try height(0, .accessibility3))
        XCTAssertGreaterThan(try height(0, .accessibility3), try height(0, .large))
        // The reveal and Check first add to the card; nothing replaces the feed.
        XCTAssertGreaterThan(try height(2, .large), try height(1, .large))
        XCTAssertGreaterThan(try height(3, .large), try height(2, .large))
    }
}
