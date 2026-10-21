#if os(macOS) && DEBUG
import CoreGraphics
import Foundation
import Testing
@testable import AppFeature

/// The DEBUG screenshot harness's launch arguments (`MacSnapshotOptions`),
/// and the two scripts that pass them: every flag the scripts use is one the
/// app reads, every flag has a value, and the store script's size is a Mac
/// App Store size.
@Suite("Mac snapshot harness: launch arguments")
struct MacSnapshotOptionsTests {

    /// Launch arguments as the app sees them, with the argument domain's
    /// reading (`-Key value` → "value" for "Key").
    private func options(_ arguments: [String]) -> MacSnapshotOptions? {
        let all = ["/Applications/Mercurius.app/Contents/MacOS/Mercurius"] + arguments
        return MacSnapshotOptions(arguments: all) { key in
            guard let index = all.firstIndex(of: "-" + key), index + 1 < all.count else { return nil }
            return all[index + 1]
        }
    }

    @Test("Without -MacSnapshot <dir> the harness stays off")
    func offWithoutDirectory() {
        #expect(options([]) == nil)
        #expect(options(["-EnterShell", "YES"]) == nil)
        #expect(options(["-MacSnapshot"]) == nil)
        // A flag where the directory should be is a forgotten value, not a folder.
        #expect(options(["-MacSnapshot", "-MacSnapshotName", "x"]) == nil)
    }

    @Test("Defaults: window.png of the main window at 1280×800 after 4 s, off screen, system appearance")
    func defaults() throws {
        let parsed = try #require(options(["-MacSnapshot", "/tmp/shots"]))
        #expect(parsed.directory.path == "/tmp/shots")
        #expect(parsed.name == "window")
        #expect(parsed.delay == 4)
        #expect(parsed.size == CGSize(width: 1280, height: 800))
        #expect(parsed.appearance == nil)
        #expect(parsed.target == .main)
        #expect(parsed.offscreen)
        #expect(!parsed.dumpsControls)
        #expect(parsed.typedText == nil)
        #expect(!parsed.submitsTypedText)
        #expect(!parsed.opaque)
        #expect(parsed.activates, "activated by default, so the window is photographed as the key window")
        #expect(parsed.problems.isEmpty)
    }

    @Test("Every flag is read")
    func everyFlag() throws {
        let parsed = try #require(options([
            "-MacSnapshot", "/tmp/shots", "-MacSnapshotName", "chat-typing", "-MacSnapshotDelay", "6.5",
            "-MacSnapshotSize", "1440x900", "-MacSnapshotAppearance", "dark", "-MacSnapshotWindow", "main",
            "-MacSnapshotOnScreen", "YES", "-MacSnapshotDumpControls", "YES",
            "-MacSnapshotType", "Why?|Really?", "-MacSnapshotSubmit", "YES", "-MacSnapshotOpaque", "YES",
            "-MacSnapshotActivate", "NO",
        ]))
        #expect(parsed.name == "chat-typing")
        #expect(parsed.delay == 6.5)
        #expect(parsed.size == CGSize(width: 1440, height: 900))
        #expect(parsed.appearance == .dark)
        #expect(!parsed.offscreen)
        #expect(parsed.dumpsControls)
        #expect(parsed.typedText == "Why?|Really?")
        #expect(parsed.submitsTypedText)
        #expect(parsed.opaque)
        #expect(!parsed.activates)
        #expect(parsed.problems.isEmpty)
    }

    @Test("Sizes are <width>x<height> in points")
    func sizes() {
        #expect(MacSnapshotOptions.parseSize("1440x900") == CGSize(width: 1440, height: 900))
        #expect(MacSnapshotOptions.parseSize("600x640") == CGSize(width: 600, height: 640))
        #expect(MacSnapshotOptions.parseSize("1440×900") == nil)   // a multiplication sign
        #expect(MacSnapshotOptions.parseSize("1440X900") == nil)
        #expect(MacSnapshotOptions.parseSize("1440x") == nil)
        #expect(MacSnapshotOptions.parseSize("0x900") == nil)
        #expect(MacSnapshotOptions.parseSize("-1440x900") == nil)
        #expect(MacSnapshotOptions.parseSize("1440x900x2") == nil)
    }

    @Test("What can't be honoured is said, and the default kept")
    func problems() throws {
        let parsed = try #require(options([
            "-MacSnapshot", "/tmp/shots", "-MacSnapshotSize", "1440×900", "-MacSnapshotDelay", "soon",
            "-MacSnapshotAppearance", "sepia", "-MacSnapshotWindow", "inspector", "-MacSnapshotName", "a/b",
            "-MacSnapshotSubmit", "YES",
        ]))
        #expect(parsed.size == MacSnapshotOptions.defaultSize)
        #expect(parsed.delay == 4)
        #expect(parsed.appearance == nil)
        #expect(parsed.target == .main)
        #expect(parsed.name == "window")
        #expect(parsed.problems.count == 6)
    }

    @Test("Below the main window's 700×600 minimum is a problem; the Help window takes any size")
    func minimum() throws {
        let small = try #require(options(["-MacSnapshot", "/tmp", "-MacSnapshotSize", "640x500"]))
        #expect(small.problems.count == 1)
        #expect(small.pixelSize(scale: 2) == CGSize(width: 1400, height: 1200))

        let atMinimum = try #require(options(["-MacSnapshot", "/tmp", "-MacSnapshotSize", "700x600"]))
        #expect(atMinimum.problems.isEmpty)

        let help = try #require(options(["-MacSnapshot", "/tmp", "-MacSnapshotWindow", "help",
                                         "-MacSnapshotSize", "600x640"]))
        #expect(help.target == .help)
        #expect(help.problems.isEmpty)
    }

    @Test("YES, true and non-zero numbers are yes — as UserDefaults.bool reads them")
    func booleans() {
        for yes in ["YES", "yes", "true", "TRUE", "1", "2"] { #expect(MacSnapshotOptions.isYes(yes), "\(yes)") }
        for no in ["NO", "no", "false", "0", "", "maybe"] { #expect(!MacSnapshotOptions.isYes(no), "\(no)") }
        #expect(!MacSnapshotOptions.isYes(nil))
    }

    @Test("The store size is 2880×1800 at 2x and 1440×900 at 1x — both Mac App Store sizes")
    func storeSize() throws {
        let store = try #require(options(["-MacSnapshot", "/tmp", "-MacSnapshotSize", "1440x900",
                                          "-MacSnapshotAppearance", "light", "-MacSnapshotOpaque", "YES"]))
        #expect(store.pixelSize(scale: 2) == CGSize(width: 2880, height: 1800))
        #expect(Self.appStoreSizes.contains(store.pixelSize(scale: 2)))
        #expect(Self.appStoreSizes.contains(store.pixelSize(scale: 1)))
    }

    /// A window-like picture: the left half one colour (the sidebar), the
    /// right half another (the detail), its four corners transparent.
    private func windowPicture(width: Int = 200, height: Int = 100, corner: Int = 10) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        for origin in [(0, 0), (width - corner, 0), (0, height - corner), (width - corner, height - corner)] {
            context.clear(CGRect(x: origin.0, y: origin.1, width: corner, height: corner))
        }
        return try #require(context.makeImage())
    }

    /// RGBA bytes of `image`, row 0 at the top.
    private func pixels(_ image: CGImage) throws -> (bytes: [UInt8], bytesPerRow: Int) {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        let count = context.bytesPerRow * image.height
        return (Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count)),
                context.bytesPerRow)
    }

    @Test("An opaque picture has no alpha channel and keeps its size")
    func opaqueHasNoAlpha() throws {
        let flat = try #require(MacSnapshotImage.flattened(try windowPicture()))
        #expect(flat.width == 200 && flat.height == 100)
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(flat.alphaInfo))
    }

    @Test("Each transparent corner takes the colour just inside it; the rest is unchanged")
    func cornersFilled() throws {
        let flat = try #require(MacSnapshotImage.flattened(try windowPicture()))
        let (bytes, row) = try pixels(flat)
        func rgb(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * row + x * 4)..<(y * row + x * 4 + 3)]) }
        let sidebar = rgb(50, 50), detail = rgb(150, 50)
        #expect(sidebar != detail)
        // Corners: left ones the sidebar's colour, right ones the detail's.
        #expect(rgb(0, 0) == sidebar)
        #expect(rgb(0, 99) == sidebar)
        #expect(rgb(199, 0) == detail)
        #expect(rgb(199, 99) == detail)
        // Every pixel is opaque.
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }

    // MARK: The harness's checks on its own picture

    /// A window picture with its close button: red when the window is key,
    /// grey when not, at 2x.
    private func pictureWithCloseButton(red: Bool, width: Int = 400, height: Int = 300) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: width / 2, y: height / 3, width: width / 3, height: 20))   // some text
        // The close button: 12 pt across, centred 26 pt in from the top-left
        // (bottom-left origin here).
        context.setFillColor(red ? CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)
                                 : CGColor(srgbRed: 0.82, green: 0.82, blue: 0.83, alpha: 1))
        context.fillEllipse(in: CGRect(x: 40, y: height - 64, width: 24, height: 24))
        return try #require(context.makeImage())
    }

    private func blank(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("A key window's picture at the right size passes")
    func goodPicture() throws {
        let problems = MacSnapshotCheck.problems(in: try pictureWithCloseButton(red: true),
                                                 pointSize: CGSize(width: 200, height: 150), scale: 2,
                                                 expectsKeyWindow: true)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("A locked screen's picture — black, at a fractional scale — fails on size and on colour")
    func lockedScreenPicture() throws {
        // What step 04 got for a 1280×800 pt window at 2x: 2306×1442, black.
        let problems = MacSnapshotCheck.problems(in: try blank(width: 2306, height: 1442),
                                                 pointSize: CGSize(width: 1280, height: 800), scale: 2,
                                                 expectsKeyWindow: false)
        #expect(problems.count == 2, "\(problems)")
        #expect(problems.contains { $0.contains("2306x1442") })
        #expect(problems.contains { $0.contains("single colour") })
    }

    @Test("An inactive window (grey close button) fails when a key window was asked for, and only then")
    func inactiveWindow() throws {
        let grey = try pictureWithCloseButton(red: false)
        let size = CGSize(width: 200, height: 150)
        let strict = MacSnapshotCheck.problems(in: grey, pointSize: size, scale: 2, expectsKeyWindow: true)
        #expect(strict.count == 1 && strict[0].contains("key window"), "\(strict)")
        #expect(MacSnapshotCheck.problems(in: grey, pointSize: size, scale: 2, expectsKeyWindow: false).isEmpty)
    }

    /// The Mac App Store's screenshot sizes (16:10), in pixels.
    static let appStoreSizes: [CGSize] = [
        CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900),
        CGSize(width: 2560, height: 1600), CGSize(width: 2880, height: 1800),
    ]
}

// MARK: - The scripts

private let scriptsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // AppFeature
    .deletingLastPathComponent()   // Packages
    .deletingLastPathComponent()   // ios
    .appendingPathComponent("scripts", isDirectory: true)

private func script(_ name: String) -> String? {
    try? String(contentsOf: scriptsDir.appendingPathComponent(name), encoding: .utf8)
}

/// The shell words on each non-comment line, quotes removed; unquoted `(`,
/// `)` and `;` split words (array literals, case patterns, `;;`).
func shellWords(_ text: String) -> [[String]] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        var words: [String] = []
        var current = ""
        var hasWord = false
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                hasWord = true
            case " ", "\t", "(", ")", ";":
                if hasWord { words.append(current) }
                current = ""
                hasWord = false
            case "#" where !hasWord:
                // A comment after the words (a `#` inside a word, as in
                // `${#ARRAY[@]}`, is part of it).
                return words
            default:
                current.append(character)
                hasWord = true
            }
        }
        if hasWord { words.append(current) }
        return words
    }
}

/// The app's launch flags are camel-cased words after a dash
/// (`-EnterShell`, `-MacSnapshotSize`, `-consentVersion`); shell options
/// (`-x`, `-eq`, `-print`) never have a capital.
private func isAppFlag(_ word: String) -> Bool {
    guard word.count > 3, word.hasPrefix("-") else { return false }
    let name = word.dropFirst()
    return name.first?.isLetter == true
        && name.allSatisfy { $0.isLetter || $0.isNumber }
        && name.contains { $0.isUppercase }
}

/// The Mac-only DEBUG flags read outside the harness: `-MacOpenWindow`
/// (MercuriusMacApp), `-MacSettingsTab` (MacSettingsWindowView),
/// `-MacHelpTab` (MacHelpView).
private let otherMacFlags: Set<String> = ["-MacOpenWindow", "-MacSettingsTab", "-MacHelpTab"]

@Suite("Mac snapshot scripts pass flags the app reads",
       .enabled(if: script("mac-snapshots.sh") != nil && script("mac-store-screenshots.sh") != nil))
struct MacSnapshotScriptTests {

    private static let names = ["mac-snapshots.sh", "mac-store-screenshots.sh"]

    /// (flag, the word after it) for every app flag in both scripts.
    private var flagUses: [(script: String, flag: String, value: String?)] {
        Self.names.flatMap { name in
            shellWords(script(name) ?? "").flatMap { words in
                words.indices.compactMap { index in
                    guard isAppFlag(words[index]) else { return nil }
                    let next = index + 1 < words.count ? words[index + 1] : nil
                    return (name, words[index], next)
                }
            }
        }
    }

    @Test("The word splitter reads quotes, arrays and case arms")
    func splitter() {
        #expect(shellWords(#"ISOLATED=(-UITests YES -EphemeralSession YES)"#)
            == [["ISOLATED=", "-UITests", "YES", "-EphemeralSession", "YES"]])
        #expect(shellWords(#"  chat) window_shot "$1" -MacSnapshotType "Why so sure?|Really?" ;;"#)
            == [["chat", "window_shot", "$1", "-MacSnapshotType", "Why so sure?|Really?"]])
        #expect(shellWords("# a comment -EnterShell").isEmpty)
    }

    @Test("Both scripts pass harness flags")
    func found() {
        let flags = Set(flagUses.map(\.flag))
        #expect(flags.contains("-MacSnapshot"))
        #expect(flags.contains("-MacSnapshotSize"))
        #expect(flags.contains("-MacSnapshotOpaque"))
    }

    @Test("Every flag has a value (a bare flag makes AppKit open the next word as a document, and no window shows)")
    func everyFlagHasAValue() {
        for use in flagUses {
            let value = use.value ?? ""
            #expect(!value.isEmpty && !isAppFlag(value),
                    "\(use.script): \(use.flag) is followed by \(use.value.map { "'\($0)'" } ?? "nothing")")
        }
    }

    @Test("Every -Mac… flag is one the app reads")
    func knownMacFlags() {
        let known = MacSnapshotOptions.flags.union(otherMacFlags)
        for use in flagUses where use.flag.hasPrefix("-Mac") {
            #expect(known.contains(use.flag), "\(use.script): unknown flag \(use.flag)")
        }
    }

    @Test("Every size, appearance and window the scripts ask for parses")
    func valuesParse() {
        for use in flagUses {
            guard let value = use.value, !value.hasPrefix("$") else { continue }
            switch use.flag {
            case "-MacSnapshotSize":
                #expect(MacSnapshotOptions.parseSize(value) != nil, "\(use.script): size \(value)")
            case "-MacSnapshotAppearance":
                #expect(MacSnapshotOptions.Appearance(rawValue: value) != nil, "\(use.script): appearance \(value)")
            case "-MacSnapshotWindow":
                #expect(MacSnapshotOptions.Target(rawValue: value) != nil, "\(use.script): window \(value)")
            default:
                break
            }
        }
    }

    @Test("The store variant is light and opaque, at a size that is a Mac App Store size on a Retina display")
    func storeVariant() throws {
        let text = try #require(script("mac-snapshots.sh"))
        // STORE_SIZE=${STORE_SIZE:-1280x800}
        let assignment = try #require(text.split(separator: "\n").first { $0.hasPrefix("STORE_SIZE=") })
        // Two steps: Swift 6.0's #require can't take an optional chain that
        // ends in a collection (CI, Xcode 16.2).
        let tail = try #require(assignment.split(separator: "-").last)
        let fallback = try #require(tail.split(separator: "}").first)
        let line = try #require(shellWords(text).first { $0.first == "store" })
        let arguments = ["-MacSnapshot", "/tmp"]
            + line.map { $0 == "$STORE_SIZE" ? String(fallback) : $0 }.filter { !$0.hasPrefix("$") }
        let parsed = try #require(MacSnapshotOptions(arguments: arguments) { key in
            guard let index = arguments.firstIndex(of: "-" + key), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        })
        #expect(parsed.size == CGSize(width: 1280, height: 800))
        #expect(parsed.appearance == .light)
        #expect(parsed.opaque)
        #expect(parsed.problems.isEmpty)
        #expect(MacSnapshotOptionsTests.appStoreSizes.contains(parsed.pixelSize(scale: 2)))
        #expect(MacSnapshotOptionsTests.appStoreSizes.contains(parsed.pixelSize(scale: 1)))
    }

    @Test("The store script accepts exactly the Mac App Store's four sizes")
    func storeScriptSizes() throws {
        let text = try #require(script("mac-store-screenshots.sh"))
        let arm = try #require(text.split(separator: "\n").first { $0.contains("2880x1800|") })
        // "    2880x1800|2560x1600|1440x900|1280x800) ;;"
        let pattern = try #require(arm.split(separator: ")").first).trimmingCharacters(in: .whitespaces)
        let accepted = Set(pattern.split(separator: "|")
            .compactMap { MacSnapshotOptions.parseSize(String($0)) }.map { "\(Int($0.width))x\(Int($0.height))" })
        let expected = Set(MacSnapshotOptionsTests.appStoreSizes.map { "\(Int($0.width))x\(Int($0.height))" })
        #expect(accepted == expected)
    }
}
#endif
