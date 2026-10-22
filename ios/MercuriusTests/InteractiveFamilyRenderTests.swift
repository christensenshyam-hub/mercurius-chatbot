import XCTest
import SwiftUI
import UIKit
import LessonInteractives

/// Every built wave-1 card on the iPhone, drawn the same way: a 16 Pro
/// Max's row (408 pt) at the default text size, light appearance, in the
/// states a student passes through (before the guess, the guess locked in,
/// and after the reveal). Each render must draw and must keep to its width.
///
/// It is the cross-card family check: set TEST_RUNNER_INTERACTIVE_FAMILY_DIR
/// to a folder to keep each render as a PNG, and lay them side by side
/// (spacing, type, the predict/reveal pattern, labels and colours should
/// read as one family). Nothing is compared against a reference.
@MainActor
final class InteractiveFamilyRenderTests: XCTestCase {

    private static let cards: [InteractiveID] = [
        .doubtDial, .pageWithASecret, .citationThatWasnt, .deleteTheGenderBox, .patchTheReward
    ]
    private static let states: [InteractiveDebugState] = [.hook, .predicted, .revealed]
    private static let width: CGFloat = 408
    /// Pixels per point, at most; a render much over 8,000 px tall comes back
    /// empty, so a tall card gets a smaller scale.
    private static let scale: CGFloat = 2
    private static let tallestRender: CGFloat = 8000

    /// The card's state, made as `-InteractiveState <debug>` makes it.
    private func store(for id: InteractiveID, _ debug: InteractiveDebugState) -> InteractiveStateStore {
        let store = InteractiveStateStore()
        switch id {
        case .doubtDial:
            _ = store.state(for: id) {
                DoubtDialState(spoiled: false,
                               launch: InteractiveLaunchOptions(arguments: ["-InteractiveState", debug.rawValue]),
                               debug: DoubtDialDebug(arguments: []))
            }
        case .pageWithASecret:
            _ = store.state(for: id) { PageWithASecretState(spoiled: false, debug: debug) }
        case .citationThatWasnt:
            _ = store.state(for: id) { CitationState(spoiled: false, debug: debug, rewritten: false) }
        case .deleteTheGenderBox:
            _ = store.state(for: id) { GenderBoxState(spoiled: false, debug: debug) }
        case .patchTheReward:
            _ = store.state(for: id) { PatchTheRewardState(spoiled: false, debug: debug) }
        default:
            break
        }
        return store
    }

    private func card(_ id: InteractiveID, _ debug: InteractiveDebugState) throws -> some View {
        let spec = try XCTUnwrap(InteractiveRegistry.spec(for: id))
        return InteractiveCardViews.card(InteractiveCardContext(spec: spec, spoiled: false,
                                                                store: store(for: id, debug)))
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .light)
            .frame(width: Self.width)
            .padding(16)
            .background(Color(white: 0.97))
    }

    private func render(_ id: InteractiveID, _ debug: InteractiveDebugState) throws -> (image: CGImage, scale: CGFloat) {
        let view = try card(id, debug)
        let fitted = UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: Self.width + 32, height: .greatestFiniteMagnitude))
        let scale = min(Self.scale, Self.tallestRender / max(fitted.height, 1))
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage, "\(id.slug) didn't render in its \(debug) state")
        if let dir = ProcessInfo.processInfo.environment["INTERACTIVE_FAMILY_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(id.slug)-\(debug.rawValue).png")
            try? UIImage(cgImage: image).pngData()?.write(to: url)
        }
        return (image, scale)
    }

    /// The share of pixels that differ from the render's top-left corner: a
    /// blank render (too tall to draw) has none.
    private func drawnShare(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let corner = Array(data[0..<4])
        var drawn = 0
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4 * 7) {
            count += 1
            if Array(data[index..<index + 4]) != corner { drawn += 1 }
        }
        return Double(drawn) / Double(max(count, 1))
    }

    func testEveryWave1CardDrawsInEachStateAtTheSameWidth() throws {
        for id in Self.cards {
            XCTAssertTrue(InteractiveCardViews.built.contains(id), "\(id.slug) has no views yet")
            for debug in Self.states {
                let drawn = try render(id, debug)
                XCTAssertEqual(CGFloat(drawn.image.width) / drawn.scale, Self.width + 32, accuracy: 1,
                               "\(id.slug) in its \(debug) state asked for more than \(Self.width) pt")
                XCTAssertGreaterThan(drawnShare(drawn.image), 0.3, "\(id.slug) in its \(debug) state drew nothing")
            }
        }
    }
}
