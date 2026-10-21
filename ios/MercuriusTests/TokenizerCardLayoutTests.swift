import XCTest
import SwiftUI
import UIKit
@testable import ChatFeature

/// Lesson 1.1's interactive on the iPhone ("How a model reads “bank”"):
/// the card at an SE's and a 16 Pro Max's width, at every text size the
/// lesson is checked at, and its place in the lesson's bubble. Rendered by
/// the real views on iOS, where Dynamic Type applies (the shared rules are
/// in the SPM tests: TokenizerInteractiveTests).
///
/// Set TEST_RUNNER_TOKENIZER_RENDER_DIR to a folder to keep each render as
/// a PNG (for review; nothing is compared against a reference).
@MainActor
final class TokenizerCardLayoutTests: XCTestCase {

    /// The card's width: an SE's row (375 pt less its 16 pt margins) and a
    /// 16 Pro Max's (440 pt less them).
    private static let widths: [CGFloat] = [343, 408]
    private static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]
    /// Room around the card in a render, where nothing of it may land.
    private static let margin: CGFloat = 120

    private func card(_ context: TokenizerContext?, size: DynamicTypeSize, width: CGFloat) -> some View {
        LessonTokenizerCard()
            .environment(TokenizerState(context: context))
            .environment(\.dynamicTypeSize, size)
            // Dark: the card draws no shadow, so anything outside it is a
            // piece of the card that left it.
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .padding(Self.margin)
    }

    private func render(_ context: TokenizerContext?, size: DynamicTypeSize, width: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: card(context, size: size, width: width))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage, "the card didn't render at \(size), \(width) pt")
        if let dir = ProcessInfo.processInfo.environment["TOKENIZER_RENDER_DIR"] {
            let name = "card-\(Int(width))-\(size)-\(context?.rawValue ?? "none").png"
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            try? UIImage(cgImage: image).pngData()?.write(to: url)
        }
        return image
    }

    /// The opaque pixels outside the card's own frame (alpha above `floor`).
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
                for context in [nil, .money, .river] as [TokenizerContext?] {
                    let image = try render(context, size: size, width: width)
                    XCTAssertEqual(CGFloat(image.width), width + 2 * Self.margin,
                                   "the card at \(size) asked for more than \(width) pt")
                    XCTAssertEqual(strayPixels(in: image, width: width), 0,
                                   "something of the card at \(size), \(width) pt, lands outside it")
                }
            }
        }
    }

    func testTheCardGrowsWithTheTextAndTheMapFoldsAtAccessibilitySizes() throws {
        func height(_ size: DynamicTypeSize, _ width: CGFloat = 343) throws -> CGFloat {
            CGFloat(try render(nil, size: size, width: width).height) - 2 * Self.margin
        }
        let large = try height(.large)
        let xxxLarge = try height(.xxxLarge)
        XCTAssertGreaterThan(xxxLarge, large, "the card grows with the text")
        XCTAssertGreaterThan(try height(.accessibility3), xxxLarge)
        XCTAssertGreaterThan(try height(.accessibility5), try height(.accessibility3))
        // A sanity floor: four steps and a map at Large on an SE.
        XCTAssertGreaterThan(large, 900)
    }

    // MARK: Its place in the lesson's bubble

    private func bubbleHeight(_ position: LessonInteractivePosition?, width: CGFloat = 375) -> CGFloat {
        let reply = ChatMessage(role: .assistant, content: LessonReplay.replies[0])
        let view = MessageBubbleView(message: reply, lessonStyle: true, interactiveAfter: position)
            .environment(TokenizerState())
            .frame(width: width)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 4000)
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func testTheRecordedReplyHoldsTheCardOnlyWhereThePlacementSays() throws {
        let reply = ChatMessage(role: .assistant, content: LessonReplay.replies[0])
        let placement = try XCTUnwrap(LessonInteractiveAnchor.placement(
            lessonID: TokenizerInteractive.lessonID, messages: [reply], crisisReplies: []
        ) { LessonParts.sections(of: $0.content, isStreaming: false) })
        let without = bubbleHeight(nil)
        let with = bubbleHeight(placement.position)
        // The card (well over 900 pt on an SE) sits between the two halves;
        // the reply's own text loses only the break the card stands on.
        XCTAssertGreaterThan(with - without, 900, "the card is in the bubble")
        // Another lesson's reply, or a position that isn't in this reply,
        // draws exactly as before.
        XCTAssertEqual(bubbleHeight(LessonInteractivePosition(section: 9, afterBlock: 0)), without)
    }
}
