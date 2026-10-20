#if DEBUG
import AppKit

/// DEBUG `-MacSnapshot <dir>`: render the app's own window to a PNG, write
/// it, and quit. No `screencapture`, no Screen Recording permission. Pair it
/// with the state arguments (`-EnterShell`, `-EnterShellCurriculum`,
/// `-LessonPreview -LessonReplay -LessonSkipIntro`, `-ChatPreview`,
/// `-GateStep <step>`) and, for screenshot runs, `-UITests YES` (in-memory
/// chats), `-EphemeralSession` (no Keychain item) and `-UseLocalServer`
/// (nothing reaches production). `ios/scripts/mac-snapshots.sh` runs the set.
///
/// How it draws: SwiftUI on macOS 26 renders through Metal-backed layers that
/// `NSView.cacheDisplay` and `CALayer.render(in:)` can't read — both give the
/// window chrome around blank content — and `ImageRenderer` can't draw the
/// AppKit-backed lists and scroll views. So it asks the window server for the
/// image of THIS process's own window (`CGWindowListCreateImage` with
/// `.optionIncludingWindow`), which needs no permission for the caller's own
/// windows (`CGPreflightScreenCaptureAccess()` is false on the machine that
/// made the docs/mac-app shots, and tccd logged no screen-capture request
/// during the runs). That function is
/// obsoleted in the macOS 15 SDK, so it is looked up at run time; if it is
/// ever missing, `cacheDisplay` is the fallback.
///
/// - `-MacSnapshotName <name>`: the file name, without `.png` (default
///   `window`).
/// - `-MacSnapshotDelay <seconds>`: how long to let the window settle
///   first (default 4).
/// - `-MacSnapshotSize <width>x<height>`: the window's content size in
///   points (default 1280x800).
/// - `-MacSnapshotAppearance light|dark`: force an appearance.
/// - `-MacSnapshotOnScreen YES`: keep the window centred on screen. By
///   default it is moved almost entirely off screen before it is first
///   drawn, so a run barely shows on the machine it runs on (the window
///   server still renders it).
/// - `-MacSnapshotDumpControls YES`: also print every AppKit control in the
///   window (class, frame, title) as `CONTROL …` lines — evidence for the
///   controls the capture can't show (below).
///
/// What the capture can't show: Liquid Glass surfaces that blend with what is
/// behind the window. With only this window in the picture they come out
/// dark (the sidebar, a toolbar's scroll-edge band) or not at all (the
/// bezels of a checkbox or a pop-up menu, leaving its title alone). The
/// controls are there — `-MacSnapshotDumpControls` lists them — but their
/// on-screen look has to be checked by eye.
///
/// Give every flag a value (`-EnterShell YES`, as the iOS UI tests pass
/// `-UITests YES`). A bare word after a flag — `-EnterShell -MacSnapshotDelay
/// 9` — is taken by AppKit as a document to open at launch, and SwiftUI then
/// opens no window at all.
///
/// The window is never activated (the keyboard stays where it was), so it
/// photographs as an inactive window.
///
/// The app is sandboxed: when `<dir>` isn't writable from the sandbox, the
/// PNG goes to the container's temporary directory instead. Either way the
/// path written is printed to standard error as `MacSnapshot: wrote <path>`.
@MainActor
enum MacSnapshot {
    static func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-MacSnapshot"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "MacSnapshotName") ?? "window"
        let delay = defaults.double(forKey: "MacSnapshotDelay") > 0 ? defaults.double(forKey: "MacSnapshotDelay") : 4
        let size = parseSize(defaults.string(forKey: "MacSnapshotSize")) ?? NSSize(width: 1280, height: 800)
        let offscreen = defaults.string(forKey: "MacSnapshotOnScreen") != "YES"
        let dumpsControls = defaults.bool(forKey: "MacSnapshotDumpControls")

        switch defaults.string(forKey: "MacSnapshotAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }

        // SwiftUI has made the window by now (applicationDidFinishLaunching):
        // size it and move it before it is first drawn on screen.
        if let window = mainWindow() {
            window.setContentSize(size)
            if offscreen {
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            } else {
                window.center()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if let window = mainWindow(), let png = windowServerImage(window) ?? cachedDisplay(window) {
                if dumpsControls, let root = window.contentView {
                    dumpControls(root)
                }
                write(png, name: name, preferred: directory)
            } else {
                log("MacSnapshot: no window to render")
            }
            NSApp.terminate(nil)
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
    }

    /// The window server's image of this process's own window, at the
    /// display's resolution, without the shadow.
    private static func windowServerImage(_ window: NSWindow) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3                     // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)                // BoundsIgnoreFraming | BestResolution
        guard let image = create(.null, includingWindow, UInt32(window.windowNumber), options)?
            .takeRetainedValue() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Fallback: the view hierarchy drawn into a bitmap. On macOS 26 this
    /// draws the window chrome but not SwiftUI's content.
    private static func cachedDisplay(_ window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(_ png: Data, name: String, preferred: URL) {
        let fileName = name + ".png"
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MacSnapshot", isDirectory: true)
        for directory in [preferred, fallback] {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(fileName)
                try png.write(to: url, options: .atomic)
                log("MacSnapshot: wrote \(url.path)")
                return
            } catch {
                continue
            }
        }
        log("MacSnapshot: could not write \(fileName)")
    }

    /// Every AppKit control under `view`, frames in window coordinates
    /// (origin bottom-left).
    private static func dumpControls(_ view: NSView) {
        if view is NSControl || view is NSTextView {
            let title = (view as? NSButton)?.title ?? (view as? NSPopUpButton)?.titleOfSelectedItem ?? ""
            log("CONTROL \(type(of: view)) frame=\(view.convert(view.bounds, to: nil)) hidden=\(view.isHiddenOrHasHiddenAncestor) alpha=\(view.alphaValue) title=\(title)")
        }
        for sub in view.subviews { dumpControls(sub) }
    }

    private static func parseSize(_ text: String?) -> NSSize? {
        guard let parts = text?.split(separator: "x"), parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]) else { return nil }
        return NSSize(width: width, height: height)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
