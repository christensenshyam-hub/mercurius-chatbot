#if os(macOS) && DEBUG
import CoreGraphics
import Foundation

/// The DEBUG screenshot harness's launch arguments, read in one place.
///
/// The harness itself (`MacSnapshot`, in the MercuriusMac app target) renders
/// the app's own window to a PNG and quits; this is what it was asked to do.
/// It lives here, beside the shell's other DEBUG launch flags, so `swift
/// test` covers the parsing, and so the screenshot scripts
/// (`ios/scripts/mac-snapshots.sh`, `mac-store-screenshots.sh`) can be
/// checked against `flags` (`MacSnapshotOptionsTests`).
///
/// `-MacSnapshot <dir>` turns the harness on. Every other flag is read the
/// way the app reads it — through the argument domain of `UserDefaults`, so
/// `-MacSnapshotDelay 9` arrives as the string "9" — via `value`.
public struct MacSnapshotOptions: Equatable, Sendable {

    public enum Appearance: String, Sendable, CaseIterable {
        case light, dark
    }

    /// Which window to photograph. `sheet`: the sheet attached to the
    /// main window (a sheet is a window of its own).
    public enum Target: String, Sendable, CaseIterable {
        case main, settings, help, sheet
    }

    /// Where the PNG goes (the sandbox may send it to the container's
    /// temporary folder instead; the harness says where).
    public var directory: URL
    /// `-MacSnapshotName`: the file name, without `.png`.
    public var name = "window"
    /// `-MacSnapshotDelay`: seconds to let the window settle first.
    public var delay: Double = 4
    /// `-MacSnapshotSize <w>x<h>`: the window's content size, in points.
    public var size = MacSnapshotOptions.defaultSize
    /// `-MacSnapshotAppearance light|dark`; nil follows the system.
    public var appearance: Appearance?
    /// `-MacSnapshotWindow main|settings|help|sheet`.
    public var target: Target = .main
    /// The window is moved almost entirely off screen unless
    /// `-MacSnapshotOnScreen YES`.
    public var offscreen = true
    /// `-MacSnapshotDumpControls YES`: list the window's AppKit controls.
    public var dumpsControls = false
    /// `-MacSnapshotType <text>`: typed into the composer with real key
    /// events; `|` is Shift-Return.
    public var typedText: String?
    /// `-MacSnapshotSubmit YES`: press Return after typing.
    public var submitsTypedText = false
    /// `-MacSnapshotOpaque YES`: fill the window's transparent rounded
    /// corners, so the PNG has no alpha (the App Store's screenshots).
    public var opaque = false
    /// The app is activated and the photographed window made key first, so
    /// it looks as it does in use (red traffic lights, full-contrast
    /// sidebar), and an inactive picture is a problem. `-MacSnapshotActivate
    /// NO` leaves the keyboard where it was and accepts an inactive window.
    public var activates = true

    /// What was asked for but couldn't be honoured, in words, for the
    /// harness to print (`MacSnapshot: problem …`) — a script can fail on it
    /// instead of shipping a picture of the wrong size.
    public var problems: [String] = []

    /// The main window's size when none is given.
    public static let defaultSize = CGSize(width: 1280, height: 800)
    /// The main window's minimum (`MercuriusMacApp`'s `.frame(minWidth:
    /// 700, minHeight: 600)`): the window can't be made smaller, so a
    /// smaller size isn't what the picture would show.
    public static let minimumWindowSize = CGSize(width: 700, height: 600)

    /// Every flag the harness reads. Each takes a value: AppKit opens a bare
    /// word after a value-less flag as a document, and SwiftUI then shows no
    /// window.
    public static let flags: Set<String> = [
        "-MacSnapshot", "-MacSnapshotName", "-MacSnapshotDelay", "-MacSnapshotSize",
        "-MacSnapshotAppearance", "-MacSnapshotWindow", "-MacSnapshotOnScreen",
        "-MacSnapshotDumpControls", "-MacSnapshotType", "-MacSnapshotSubmit",
        "-MacSnapshotOpaque", "-MacSnapshotActivate",
    ]

    public init(directory: URL) {
        self.directory = directory
    }

    /// The options in `arguments`, or nil when there is no `-MacSnapshot
    /// <dir>` (the harness stays off). `value(key)` is the argument-domain
    /// string for a key without its dash (`UserDefaults.standard.string`).
    public init?(arguments: [String], value: (String) -> String?) {
        guard let flag = arguments.firstIndex(of: "-MacSnapshot"), flag + 1 < arguments.count,
              !arguments[flag + 1].hasPrefix("-") else { return nil }
        self.init(directory: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))

        if let name = value("MacSnapshotName"), !name.isEmpty {
            if name.contains("/") {
                problems.append("MacSnapshotName '\(name)' has a '/'; using '\(self.name)'")
            } else {
                self.name = name
            }
        }

        if let raw = value("MacSnapshotDelay") {
            if let seconds = Double(raw), seconds > 0 {
                delay = seconds
            } else {
                problems.append("MacSnapshotDelay '\(raw)' isn't a positive number of seconds; waiting \(Self.format(delay))")
            }
        }

        if let raw = value("MacSnapshotSize") {
            if let parsed = Self.parseSize(raw) {
                size = parsed
            } else {
                problems.append("MacSnapshotSize '\(raw)' isn't <width>x<height> in points; using \(Self.format(size))")
            }
        }

        if let raw = value("MacSnapshotAppearance") {
            if let parsed = Appearance(rawValue: raw) {
                appearance = parsed
            } else {
                problems.append("MacSnapshotAppearance '\(raw)' isn't light or dark; following the system")
            }
        }

        if let raw = value("MacSnapshotWindow") {
            if let parsed = Target(rawValue: raw) {
                target = parsed
            } else {
                problems.append("MacSnapshotWindow '\(raw)' isn't main, settings, help or sheet; photographing the main window")
            }
        }

        // The main window can't go below its minimum, so a smaller size would
        // silently give a bigger picture. (Settings sizes itself; Help takes
        // the size as asked.)
        if target == .main,
           size.width < Self.minimumWindowSize.width || size.height < Self.minimumWindowSize.height {
            problems.append("MacSnapshotSize \(Self.format(size)) is below the main window's minimum \(Self.format(Self.minimumWindowSize)); the picture will be the minimum")
        }

        offscreen = !Self.isYes(value("MacSnapshotOnScreen"))
        dumpsControls = Self.isYes(value("MacSnapshotDumpControls"))
        if let text = value("MacSnapshotType"), !text.isEmpty { typedText = text }
        submitsTypedText = Self.isYes(value("MacSnapshotSubmit"))
        if submitsTypedText && typedText == nil {
            problems.append("MacSnapshotSubmit YES without MacSnapshotType: nothing to submit")
        }
        opaque = Self.isYes(value("MacSnapshotOpaque"))
        if let raw = value("MacSnapshotActivate") { activates = Self.isYes(raw) }
    }

    /// The options in this process's own launch arguments.
    public static func fromProcess() -> MacSnapshotOptions? {
        MacSnapshotOptions(arguments: ProcessInfo.processInfo.arguments) {
            UserDefaults.standard.string(forKey: $0)
        }
    }

    /// The PNG's size in pixels for the main window at this backing scale
    /// (the capture is the window's frame at the display's resolution).
    public func pixelSize(scale: CGFloat) -> CGSize {
        let width = max(size.width, Self.minimumWindowSize.width)
        let height = max(size.height, Self.minimumWindowSize.height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    /// "1440x900" → 1440 × 900 points. Positive whole or decimal numbers
    /// either side of a lowercase x.
    public static func parseSize(_ text: String) -> CGSize? {
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    /// `UserDefaults.bool(forKey:)`'s reading of a string: YES, true or a
    /// non-zero number.
    static func isYes(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        if text == "yes" || text == "true" { return true }
        if let number = Double(text) { return number != 0 }
        return false
    }

    private static func format(_ size: CGSize) -> String {
        "\(format(Double(size.width)))x\(format(Double(size.height)))"
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }
}

/// What the harness checks in its own picture before it writes it, so a
/// script (and CI's launch smoke test) can't count a picture that shows
/// nothing as a screenshot. Each problem comes back in words; the harness
/// prints them as `MacSnapshot: problem …`, which fails the run.
public enum MacSnapshotCheck {
    /// Problems with `image`, a capture of a window whose frame is
    /// `pointSize` at `scale`.
    ///
    /// - The size: a locked or sleeping screen gives a picture at a
    ///   fractional scale (2306 × 1442 px for a 1280 × 800 pt window at 2×).
    /// - One colour: the window server drew nothing (all black when locked).
    /// - `expectsKeyWindow`: the close button must be red. An inactive
    ///   window's traffic lights are grey and its sidebar text washed out,
    ///   which isn't how the app looks in use.
    public static func problems(in image: CGImage, pointSize: CGSize, scale: CGFloat,
                                expectsKeyWindow: Bool) -> [String] {
        var problems: [String] = []
        let expected = CGSize(width: (pointSize.width * scale).rounded(), height: (pointSize.height * scale).rounded())
        if abs(CGFloat(image.width) - expected.width) > 2 || abs(CGFloat(image.height) - expected.height) > 2 {
            problems.append("the picture is \(image.width)x\(image.height) px, not the window's "
                + "\(Int(pointSize.width))x\(Int(pointSize.height)) pt at \(scale)x "
                + "(\(Int(expected.width))x\(Int(expected.height)) px): the window server didn't draw it at the "
                + "display's scale (a locked or sleeping screen does this)")
        }
        guard let pixels = Pixels(image) else {
            problems.append("the picture couldn't be read back to check it")
            return problems
        }
        if pixels.isOneColour() {
            problems.append("the picture is a single colour: nothing was drawn (a locked or sleeping screen does this)")
        }
        if expectsKeyWindow, !pixels.hasRedCloseButton(scale: scale) {
            problems.append("the window wasn't the key window (its close button isn't red): an inactive window's "
                + "traffic lights are grey and its sidebar text washed out. Run on an unlocked Mac with nothing "
                + "else taking the keyboard, or pass -MacSnapshotActivate NO to accept it")
        }
        return problems
    }

    /// The image as 8-bit sRGB RGBA, top row first.
    struct Pixels {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            bytes = buffer
        }

        /// (r, g, b, a) at x, y (y = 0 is the top row).
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let offset = (y * width + x) * 4
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
        }

        /// Every sample on a grid over the middle of the picture (clear of
        /// the rounded corners) is within a few levels of the first.
        func isOneColour(tolerance: Int = 4) -> Bool {
            let columns = 48, rows = 32
            let x0 = width / 10, y0 = height / 10
            let spanX = max(width - 2 * x0 - 1, 0), spanY = max(height - 2 * y0 - 1, 0)
            let first = pixel(x0, y0)
            for row in 0...rows {
                for column in 0...columns {
                    let p = pixel(x0 + spanX * column / columns, y0 + spanY * row / rows)
                    if abs(p.r - first.r) > tolerance || abs(p.g - first.g) > tolerance
                        || abs(p.b - first.b) > tolerance || abs(p.a - first.a) > tolerance {
                        return false
                    }
                }
            }
            return true
        }

        /// A red pixel where a key window's close button sits: within the
        /// first 48 pt of the top-left corner. (#FF5F57 in light and dark;
        /// an inactive window's is grey.)
        func hasRedCloseButton(scale: CGFloat) -> Bool {
            let reach = min(Int((48 * max(scale, 1)).rounded()), width, height)
            for y in 0..<reach {
                for x in 0..<reach {
                    let p = pixel(x, y)
                    guard p.a > 200 else { continue }
                    if p.r >= 190, p.g <= 140, p.b <= 140, p.r - p.g >= 80 { return true }
                }
            }
            return false
        }
    }
}

/// The harness's picture as the Mac App Store wants it (`-MacSnapshotOpaque`).
public enum MacSnapshotImage {
    /// The image with its transparent corners filled and no alpha channel.
    /// Each corner takes the colour found a little inside it (the sidebar's
    /// at the left, the detail's at the right), so the window reads as a
    /// square-cornered picture of itself.
    public static func flattened(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        source.draw(image, in: full)
        guard let pixels = source.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bytesPerRow = source.bytesPerRow
        // 24 px covers the corner radius at 2x with room to spare; the colour
        // is read from inside it.
        let corner = min(24, width / 4, height / 4)
        let probe = min(corner * 2, width / 2, height / 2)
        func color(x: Int, y: Int) -> CGColor {
            // Row 0 of the buffer is the top of the picture.
            let offset = y * bytesPerRow + x * 4
            let alpha = CGFloat(pixels[offset + 3]) / 255
            guard alpha > 0 else { return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }
            return CGColor(srgbRed: CGFloat(pixels[offset]) / 255 / alpha,
                           green: CGFloat(pixels[offset + 1]) / 255 / alpha,
                           blue: CGFloat(pixels[offset + 2]) / 255 / alpha, alpha: 1)
        }
        guard let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Corners in buffer terms (top-left origin) and their drawing rects
        // (bottom-left origin).
        let corners: [(probeX: Int, probeY: Int, rect: CGRect)] = [
            (probe, probe, CGRect(x: 0, y: height - corner, width: corner, height: corner)),
            (width - 1 - probe, probe, CGRect(x: width - corner, y: height - corner, width: corner, height: corner)),
            (probe, height - 1 - probe, CGRect(x: 0, y: 0, width: corner, height: corner)),
            (width - 1 - probe, height - 1 - probe, CGRect(x: width - corner, y: 0, width: corner, height: corner)),
        ]
        output.setFillColor(color(x: width / 2, y: height / 2))
        output.fill(full)
        for item in corners {
            output.setFillColor(color(x: item.probeX, y: item.probeY))
            output.fill(item.rect)
        }
        output.draw(image, in: full)
        return output.makeImage()
    }
}
#endif
