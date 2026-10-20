#if DEBUG
import AppKit
import AppFeature

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
/// - `-MacSnapshotWindow settings|help`: photograph that window instead of
///   the main one (pair with `-MacOpenWindow settings|help`, which opens
///   it; `-MacSettingsTab general|privacy|about` picks the Settings tab).
/// - `-MacSnapshotType <text>`: halfway through the delay, put the cursor
///   in the composer and type `text` into it with real key events (`|`
///   types Shift-Return); `-MacSnapshotSubmit YES` then presses Return. The
///   field's text is printed as `COMPOSER <text>` after each, so a run
///   shows what Shift-Return and Return did.
/// - `-MacSnapshotOpaque YES`: fill the window's transparent rounded
///   corners with the colour just inside each one, and write the PNG with
///   no alpha channel (the Mac App Store's screenshots;
///   `ios/scripts/mac-store-screenshots.sh`).
///
/// The flags are parsed by `MacSnapshotOptions` (AppFeature, unit-tested).
/// Anything it can't honour — a size it can't read, a size below the
/// window's minimum — is printed as `MacSnapshot: problem <what>`, and the
/// scripts fail on it.
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
        guard let options = MacSnapshotOptions.fromProcess() else { return }
        for problem in options.problems {
            log("MacSnapshot: problem \(problem)")
        }
        let directory = options.directory
        let name = options.name
        let delay = options.delay
        let size = NSSize(width: options.size.width, height: options.size.height)
        let offscreen = options.offscreen
        let dumpsControls = options.dumpsControls

        switch options.appearance {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case nil: break
        }

        let target = options.target.rawValue

        // SwiftUI has made the main window by now
        // (applicationDidFinishLaunching): size it and move it before it is
        // first drawn on screen. A Settings or Help window opens a moment
        // later; `placeNewWindows` moves it as it appears.
        //
        // Sized while still on its screen: AppKit keeps it within that
        // screen's visible frame, so a size taller than the screen can't be
        // had (1440×900 on a 14-inch MacBook Pro, whose visible frame is
        // 888 pt tall). Resizing it once it is off screen doesn't work
        // either: the window server then returns a blank picture at a
        // fractional scale. So a size that doesn't fit is a problem, said
        // out loud, and the scripts fail on it.
        if let window = mainWindow() {
            if target == "main" {
                window.setContentSize(size)
                if !hasContentSize(window, size) {
                    let got = window.contentRect(forFrameRect: window.frame).size
                    let visible = window.screen?.visibleFrame.size ?? .zero
                    log("MacSnapshot: problem the main window can't be \(Int(size.width))x\(Int(size.height)) pt on this display "
                        + "(visible area \(Int(visible.width))x\(Int(visible.height)) pt); it came out "
                        + "\(Int(got.width))x\(Int(got.height)). Use a smaller -MacSnapshotSize or a bigger display.")
                }
            }
            place(window, offscreen: offscreen)
        }
        placeNewWindows(offscreen: offscreen, helpSize: target == "help" ? size : nil)

        if let text = options.typedText {
            let submits = options.submitsTypedText
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay / 2))
                typeIntoComposer(text, submit: submits)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if let window = snapshotWindow(target) {
                let content = window.contentRect(forFrameRect: window.frame).size
                log("MacSnapshot: content \(Int(content.width))x\(Int(content.height)) pt, scale \(window.backingScaleFactor)")
            }
            if let window = snapshotWindow(target),
               let png = windowServerImage(window, opaque: options.opaque) ?? cachedDisplay(window) {
                if dumpsControls, let root = window.contentView {
                    dumpControls(root)
                }
                write(png, name: name, preferred: directory)
            } else {
                log("MacSnapshot: no \(target) window to render; windows: "
                    + NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") visible=\($0.isVisible)" }.joined(separator: ", "))
            }
            forgetFrames()
            NSApp.terminate(nil)
        }
    }

    private static func hasContentSize(_ window: NSWindow, _ size: NSSize) -> Bool {
        let content = window.contentRect(forFrameRect: window.frame).size
        return abs(content.width - size.width) < 0.5 && abs(content.height - size.height) < 0.5
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil && isMain($0) }
    }

    private static func isMain(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("main") ?? false
    }

    /// The window to photograph: the main one, or the Settings / Help window.
    private static func snapshotWindow(_ target: String) -> NSWindow? {
        switch target {
        case "settings":
            return NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue.contains("Settings") ?? false) }
        case "help":
            return NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue.hasPrefix("help") ?? false) }
        default:
            return mainWindow() ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
        }
    }

    /// Windows already moved (by number), so each is placed once.
    private static var placed: Set<Int> = []
    /// The autosave names of the windows moved, to forget their frames.
    private static var autosaveNames: Set<String> = []

    /// Move a window off screen (or centre it), and keep its frame out of
    /// the app's saved window frames — or the next real launch would open
    /// it off screen.
    private static func place(_ window: NSWindow, offscreen: Bool) {
        guard placed.insert(window.windowNumber).inserted else { return }
        if !window.frameAutosaveName.isEmpty { autosaveNames.insert(window.frameAutosaveName) }
        window.setFrameAutosaveName("")
        if offscreen {
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        } else {
            window.center()
        }
    }

    /// Place every window that appears from now on, as it appears.
    private static func placeNewWindows(offscreen: Bool, helpSize: NSSize?) {
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil,
                                               queue: .main) { note in
            // Delivered on the main queue, so the window is used on the
            // main actor.
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let window = object as? NSWindow, window.isVisible,
                      !placed.contains(window.windowNumber) else { return }
                if let helpSize, window.identifier?.rawValue.hasPrefix("help") == true {
                    window.setContentSize(helpSize)
                }
                place(window, offscreen: offscreen)
            }
        }
    }

    private static func forgetFrames() {
        for name in autosaveNames {
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
        }
    }

    // MARK: - Typing into the composer

    /// Type into the main window's message field with real key events, so
    /// the composer's own key handling runs (Return sends, Shift-Return
    /// breaks the line). The window isn't key (the harness never activates
    /// the app), so the field is made first responder directly.
    private static func typeIntoComposer(_ text: String, submit: Bool) {
        guard let window = mainWindow(), let root = window.contentView,
              let field = editableField(in: root) else {
            log("MacSnapshot: no composer to type into")
            return
        }
        window.makeFirstResponder(field)
        for character in text {
            if character == "|" {
                press("\r", keyCode: 36, flags: .shift, in: window)
            } else {
                press(String(character), keyCode: 0, flags: [], in: window)
            }
        }
        log("COMPOSER \(composerText(window).debugDescription)")
        if submit {
            press("\r", keyCode: 36, flags: [], in: window)
            log("COMPOSER after Return \(composerText(window).debugDescription)")
        }
    }

    private static func press(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode) else { continue }
            window.sendEvent(event)
        }
    }

    private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews {
            if let field = editableField(in: sub) { return field }
        }
        return nil
    }

    private static func composerText(_ window: NSWindow) -> String {
        (window.firstResponder as? NSTextView)?.string
            ?? window.contentView.flatMap(editableField(in:))?.stringValue
            ?? ""
    }

    /// The window server's image of this process's own window, at the
    /// display's resolution, without the shadow. `opaque` fills the rounded
    /// corners and drops the alpha channel.
    private static func windowServerImage(_ window: NSWindow, opaque: Bool) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3                     // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)                // BoundsIgnoreFraming | BestResolution
        guard let image = create(.null, includingWindow, UInt32(window.windowNumber), options)?
            .takeRetainedValue() else { return nil }
        let output = opaque ? (flattened(image) ?? image) : image
        log("MacSnapshot: pixels \(output.width)x\(output.height)")
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    /// The image with its transparent corners filled and no alpha channel.
    /// Each corner takes the colour found a little inside it (the sidebar's
    /// at the left, the detail's at the right), so the window reads as a
    /// square-cornered picture of itself.
    private static func flattened(_ image: CGImage) -> CGImage? {
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

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
