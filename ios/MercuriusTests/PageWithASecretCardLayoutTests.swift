import XCTest
import SwiftUI
import UIKit
@testable import ChatFeature
@testable import LessonInteractives

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

    // MARK: Contrast of a locked guess

    /// One chip, alone, on the card's surface, at 2x.
    private func chipImage(selected: Bool, enabled: Bool) throws -> CGImage {
        let theme = InteractiveTheme.standard
        let chip = InteractiveChip("Something on the page changes it", isSelected: selected, isEnabled: enabled) {}
            .environment(\.interactiveTheme, theme)
            .fixedSize()
            .padding(10)
            .background(theme.surface)
        let renderer = ImageRenderer(content: chip)
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private struct RGB: Equatable {
        let r: Double, g: Double, b: Double
        var luminance: Double {
            func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(_ other: RGB) -> Double {
            let pair = [luminance, other.luminance].sorted()
            return (pair[1] + 0.05) / (pair[0] + 0.05)
        }
    }

    private func pixels(_ image: CGImage) -> [RGB] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 0, to: data.count, by: 4).map {
            RGB(r: Double(data[$0]) / 255, g: Double(data[$0 + 1]) / 255, b: Double(data[$0 + 2]) / 255)
        }
    }

    /// The chip's fill (its commonest colour other than the surface) and
    /// the contrast of its words (the pixel furthest from the fill).
    private func fillAndTextContrast(_ image: CGImage) -> (fill: RGB, contrast: Double) {
        let all = pixels(image)
        let surface = all[0]
        var counts: [String: (RGB, Int)] = [:]
        for pixel in all where pixel != surface {
            let key = "\(Int(pixel.r * 255))-\(Int(pixel.g * 255))-\(Int(pixel.b * 255))"
            counts[key, default: (pixel, 0)].1 += 1
        }
        let fill = counts.values.max { $0.1 < $1.1 }?.0 ?? surface
        let best = all.map { $0.contrast(fill) }.max() ?? 1
        return (fill, best)
    }

    func testALockedGuessKeepsItsContrastOnTheIPhone() throws {
        // The picked chip, off once the guess is locked: the same fill as
        // when it was live (no fade), white words at 4.5:1 or better.
        let lockedPick = fillAndTextContrast(try chipImage(selected: true, enabled: false))
        let livePick = fillAndTextContrast(try chipImage(selected: true, enabled: true))
        XCTAssertEqual(lockedPick.fill.r, livePick.fill.r, accuracy: 0.02, "the locked guess's fill faded")
        XCTAssertEqual(lockedPick.fill.b, livePick.fill.b, accuracy: 0.02, "the locked guess's fill faded")
        XCTAssertGreaterThanOrEqual(lockedPick.contrast, 4.5, "the locked guess's words")
        // The other choice, off: its own off colours, still 4.5:1.
        let other = fillAndTextContrast(try chipImage(selected: false, enabled: false))
        XCTAssertGreaterThanOrEqual(other.contrast, 4.5, "the choice not picked")
    }

    // MARK: No word breaks at AX5 on an SE

    /// Every word of the run's lines fits the room its line has on an SE at
    /// AX5, so none breaks inside itself: addresses may wrap at their dot
    /// (`breakable`), a hyphenated word after its hyphen.
    func testNoWordOfThePageBreaksAtAX5OnAnSE() throws {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let callout = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits)
        let rounded = UIFont.systemFont(ofSize: callout.pointSize, weight: .semibold).fontDescriptor
            .withDesign(.rounded).map { UIFont(descriptor: $0, size: callout.pointSize) }
            ?? UIFont.systemFont(ofSize: callout.pointSize, weight: .semibold)
        let mono = UIFont.monospacedSystemFont(ofSize: callout.pointSize, weight: .regular)

        func width(_ text: String, _ font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        /// The pieces a line can't break inside.
        func pieces(_ text: String) -> [String] {
            PageWithASecretContent.breakable(text)
                .components(separatedBy: CharacterSet(charactersIn: " \u{200B}"))
                .flatMap { word -> [String] in
                    let parts = word.components(separatedBy: "-")
                    return parts.enumerated().map { $0.offset < parts.count - 1 ? $0.element + "-" : $0.element }
                }
                .filter { !$0.isEmpty }
        }

        // The SE's card, less its padding; a step's row; a well (the page,
        // the email) in it; the hidden line's box; the search field.
        let content = InteractiveLayout.contentWidth(cardWidth: 343)
        let row = content - PageMetrics.stepInset
        let well = row - 2 * PageMetrics.phoneWellPadding
        let hiddenBox = well - 2 * PageMetrics.hiddenBoxPadding
        let search = row - 2 * PageMetrics.searchPadding
        let page = PageWithASecretContent.page
        var checks: [(String, UIFont, CGFloat)] = []
        for line in [page.address, page.siteName, page.title] + page.visibleLines {
            checks.append((line, callout, well))
        }
        checks.append((page.hiddenLine, callout, hiddenBox))
        checks.append((PageWithASecretContent.search, callout, search))
        for step in PageWithASecretContent.steps {
            let lines = PageWithASecretContent.lines(of: step)
            // The plan's and the list's words sit after a number or bullet;
            // the email's in its well.
            let room: CGFloat
            switch step.detail {
            case .plan: room = row - width("\(lines.count).", callout) - PageMetrics.markerSpacing
            case .list: room = row - width("\u{2022}", callout) - PageMetrics.markerSpacing
            default: room = well
            }
            for line in lines {
                checks.append((line.text, line.isNew ? rounded : callout, room))
            }
        }
        for (text, font, room) in checks {
            for piece in pieces(text) {
                XCTAssertLessThanOrEqual(width(piece, font), room,
                                         "\"\(piece)\" (from \"\(text)\") breaks inside itself at AX5 in \(room) pt")
            }
        }
        // The old monospaced agent's view would: "assistants:" alone was
        // wider than the hidden line's box.
        XCTAssertGreaterThan(width("assistants:", mono), hiddenBox)
    }
}
