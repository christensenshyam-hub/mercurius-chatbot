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
///   `-MacSnapshotWindow sheet`: the sheet attached to the main window.
/// - `-MacSnapshotType <text>`: halfway through the delay, put the cursor
///   in the composer and type `text` into it with real key events (`|`
///   types Shift-Return); `-MacSnapshotSubmit YES` then presses Return. The
///   field's text is printed as `COMPOSER <text>` after each, so a run
///   shows what Shift-Return and Return did.
/// - `-MacSnapshotOpaque YES`: fill the window's transparent rounded
///   corners with the colour just inside each one, and write the PNG with
///   no alpha channel (the Mac App Store's screenshots;
///   `ios/scripts/mac-store-screenshots.sh`).
/// - `-MacSnapshotActivate NO`: don't activate the app. By default it is
///   activated and the photographed window made key, so the picture shows
///   the window as it looks in use: red traffic lights, full-contrast
///   sidebar text (an inactive window's sidebar labels come out washed out,
///   lighter than their captions). An inactive picture is then a problem.
///
/// Before writing, the harness checks its own picture
/// (`MacSnapshotCheck`): the pixel size is the window's at the display's
/// scale, it isn't one colour, and (activated) the close button is red.
/// While the screen is locked the app can't become active, so an activated
/// run fails the last check; with the display asleep as well the window
/// server draws nothing, which fails the first two. (Locked with the
/// display awake — `caffeinate -u` — and `-MacSnapshotActivate NO`, the
/// window is drawn, as an inactive window.)
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
/// Activating takes the keyboard from whatever app had it for the few
/// seconds of each run: run the set when nobody is typing.
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
        let activates = options.activates
        if activates { NSApp.activate() }

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
            // Made key a moment before the picture, so it is drawn as the
            // key window (a Settings or Help window opens after launch).
            let settle = min(0.8, delay / 2)
            try? await Task.sleep(for: .seconds(delay - settle))
            if activates, let window = snapshotWindow(target) {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .seconds(settle))
            if let window = snapshotWindow(target) {
                let content = window.contentRect(forFrameRect: window.frame).size
                log("MacSnapshot: content \(Int(content.width))x\(Int(content.height)) pt, scale \(window.backingScaleFactor)")
                log("MacSnapshot: app active \(NSApp.isActive), window key \(window.isKeyWindow)")
                if isScreenLocked() {
                    // Not a problem by itself: with the display awake the
                    // window is still drawn (the checks below catch the
                    // blank picture a sleeping display gives). But the app
                    // can't become active behind the lock screen.
                    log("MacSnapshot: note the screen is locked: the app can't become active, so the "
                        + "window is drawn as an inactive one; with the display asleep nothing is drawn at all")
                }
            }
            if let window = snapshotWindow(target),
               let png = windowServerImage(window, opaque: options.opaque, expectsKeyWindow: activates)
                ?? cachedDisplay(window) {
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
            // A SwiftUI sheet attached to the window can hold the quit up
            // (the mode explainer, the Quiz me sheet). The picture is
            // written: leave anyway.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                UserDefaults.standard.synchronize()
                exit(0)
            }
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
        case "sheet":
            // The sheet attached to the main window (the mode explainer, the
            // Quiz me sheet): a window of its own, which the main window's
            // picture doesn't include.
            return mainWindow()?.attachedSheet
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
    /// breaks the line). The field is made first responder directly, so
    /// this works whether or not the window is key yet.
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

    /// The login session says its screen is locked.
    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// The window server's image of this process's own window, at the
    /// display's resolution, without the shadow, after the harness's own
    /// checks (`MacSnapshotCheck`; each problem is printed). `opaque` fills
    /// the rounded corners and drops the alpha channel.
    private static func windowServerImage(_ window: NSWindow, opaque: Bool, expectsKeyWindow: Bool) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3                     // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)                // BoundsIgnoreFraming | BestResolution
        guard let image = create(.null, includingWindow, UInt32(window.windowNumber), options)?
            .takeRetainedValue() else { return nil }
        let output = opaque ? (MacSnapshotImage.flattened(image) ?? image) : image
        log("MacSnapshot: pixels \(output.width)x\(output.height)")
        // What the picture should measure: the window's frame at the
        // display's scale (the script checks the PNG against it too).
        log("MacSnapshot: expect \(Int((window.frame.width * window.backingScaleFactor).rounded()))x"
            + "\(Int((window.frame.height * window.backingScaleFactor).rounded()))")
        for problem in MacSnapshotCheck.problems(in: output, pointSize: window.frame.size,
                                                 scale: window.backingScaleFactor,
                                                 expectsKeyWindow: expectsKeyWindow) {
            log("MacSnapshot: problem \(problem)")
        }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }

    /// Fallback: the view hierarchy drawn into a bitmap. On macOS 26 this
    /// draws the window chrome but not SwiftUI's content, so a picture made
    /// this way is reported as a problem.
    private static func cachedDisplay(_ window: NSWindow) -> Data? {
        log("MacSnapshot: problem the window server gave no picture; the fallback draws only the window's frame")
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
        if let scroll = view as? NSScrollView {
            log("SCROLL frame=\(scroll.convert(scroll.bounds, to: nil)) hidden=\(scroll.isHiddenOrHasHiddenAncestor) "
                + "document=\(scroll.documentView?.frame ?? .zero) visible=\(scroll.documentVisibleRect)")
        }
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
