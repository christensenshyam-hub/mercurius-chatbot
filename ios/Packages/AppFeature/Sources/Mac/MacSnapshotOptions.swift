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

    /// Which window to photograph.
    public enum Target: String, Sendable, CaseIterable {
        case main, settings, help
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
    /// `-MacSnapshotWindow main|settings|help`.
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
    /// What was asked for but couldn't be honoured, in words, for the
    /// harness to print (`MacSnapshot: problem …`) — a script can fail on it
    /// instead of shipping a picture of the wrong size.
    public var problems: [String] = []

    /// The main window's size when none is given.
    public static let defaultSize = CGSize(width: 1280, height: 800)
    /// The main window's minimum (`MercuriusMacApp`'s `.frame(minWidth:
    /// 860, minHeight: 600)`): the window can't be made smaller, so a
    /// smaller size isn't what the picture would show.
    public static let minimumWindowSize = CGSize(width: 860, height: 600)

    /// Every flag the harness reads. Each takes a value: AppKit opens a bare
    /// word after a value-less flag as a document, and SwiftUI then shows no
    /// window.
    public static let flags: Set<String> = [
        "-MacSnapshot", "-MacSnapshotName", "-MacSnapshotDelay", "-MacSnapshotSize",
        "-MacSnapshotAppearance", "-MacSnapshotWindow", "-MacSnapshotOnScreen",
        "-MacSnapshotDumpControls", "-MacSnapshotType", "-MacSnapshotSubmit",
        "-MacSnapshotOpaque",
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
                problems.append("MacSnapshotWindow '\(raw)' isn't main, settings or help; photographing the main window")
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
#endif
