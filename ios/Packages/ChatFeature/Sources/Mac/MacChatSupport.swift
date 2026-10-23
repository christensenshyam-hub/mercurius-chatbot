#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DesignSystem
import NetworkingKit

// The Mac's ways into the chat and lesson screens: menu commands that act on
// whichever one the window shows, an image dropped or pasted onto it, and
// Copy on a message. iOS has none of this; every file here is macOS-only.

/// What the menu bar can do to the chat or lesson in the key window: Retry
/// (⌘R), Explain More (⇧⌘E), Attach Image… (⇧⌘A). The screen publishes it
/// with `focusedSceneValue`, so the commands follow whichever is showing and
/// are off when neither is.
public struct ChatCommandTarget {
    /// The free chat's mode, for the Chat menu's checkmark; nil in a lesson.
    public let currentMode: ChatMode?
    /// The last reply failed and can be tried again.
    public let canRetry: Bool
    public let retry: () -> Void
    /// Merc has finished a reply and nothing is in flight (the "Explain
    /// more" footer is showing).
    public let canExplainMore: Bool
    public let explainMore: () -> Void
    /// The composer can take a photo (nothing is sending).
    public let canAttach: Bool
    public let attachImage: () -> Void
    /// Chat ▸ Write a Reply (⌘L): the composer takes the keyboard.
    public var canWriteReply = false
    public var writeReply: () -> Void = {}
}

private struct ChatCommandTargetKey: FocusedValueKey {
    typealias Value = ChatCommandTarget
}

public extension FocusedValues {
    /// The chat or lesson the menu commands act on.
    var chatCommandTarget: ChatCommandTarget? {
        get { self[ChatCommandTargetKey.self] }
        set { self[ChatCommandTargetKey.self] = newValue }
    }
}

// MARK: - Images from the Mac (drop, paste, file)

/// Reading an image the student hands over on a Mac: a dropped file or
/// picture, a pasted one, or a file from the open panel. Every path ends in
/// `ChatViewModel.attachImage(data:)`, the same downsample-and-upload path
/// as the iPhone's photo picker.
enum MacImageIntake {
    /// The types an image drop or paste may arrive as.
    static let dropTypes: [UTType] = [.image, .fileURL]

    /// The image on `pasteboard`, if pasting should attach one instead of
    /// pasting text: an image file copied in Finder, or picture data with no
    /// text alongside it (a screenshot copied with ⌃⇧⌘4, an image copied
    /// from Preview, Photos or a web page). Text wins whenever there is any,
    /// so an ordinary paste is never hijacked.
    @MainActor
    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first,
           let data = try? Data(contentsOf: url) {
            return data
        }
        if pasteboard.string(forType: .string) != nil { return nil }
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
        ]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type) { return data }
        }
        return nil
    }

    /// Whether a drop offers something that may be an image.
    static func mayHoldImage(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    /// The first image among dropped items, as data (a picture dragged from
    /// Photos or a browser, or an image file from Finder — whose provider
    /// also conforms to its image type).
    static func loadImage(from providers: [NSItemProvider], completion: @escaping @MainActor (Data?) -> Void) {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            Task { @MainActor in completion(nil) }
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            Task { @MainActor in completion(data) }
        }
    }

    /// A file the student picked in the open panel. The sandbox grants it
    /// through the security scope (`files.user-selected.read-only`).
    static func readPickedFile(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

extension View {
    /// The whole chat or lesson takes an image dropped on it, with a
    /// highlight while one is held over it. Off while a reply is on its way
    /// (the attach button is too).
    func macImageDrop(isEnabled: Bool, onImage: @escaping (Data) -> Void) -> some View {
        modifier(MacImageDrop(isEnabled: isEnabled, onImage: onImage))
    }
}

private struct MacImageDrop: ViewModifier {
    let isEnabled: Bool
    let onImage: (Data) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: MacImageIntake.dropTypes, isTargeted: $targeted) { providers in
                guard isEnabled, MacImageIntake.mayHoldImage(providers) else { return false }
                MacImageIntake.loadImage(from: providers) { data in
                    if let data { onImage(data) }
                }
                return true
            }
            .overlay {
                if targeted && isEnabled {
                    ZStack {
                        BrandColor.background.opacity(0.85)
                        VStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(BrandColor.accentText)
                            Text("Drop to attach this image")
                                .font(BrandFont.bodyEmphasized)
                                .foregroundStyle(BrandColor.text)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                            .strokeBorder(BrandColor.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .padding(BrandSpacing.sm)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

// MARK: - Composer keys

enum MacComposerKeys {
    /// What Return does in the composer.
    enum ReturnAction: Equatable {
        /// The field's own Return: it sends through `onSubmit`, when
        /// `ChatInputBar.canSend` allows (an empty field or a reply on its
        /// way sends nothing).
        case send
        /// A line break at the insertion point (Shift-Return).
        case newline
        /// The key is the field's to handle as it always does: an input
        /// method that is composing takes Return to confirm the composition,
        /// and Option-Return already breaks the line on the Mac.
        case field
    }

    /// The decision, from the keys held and whether an input method is
    /// composing. Only `.newline` is the composer's own work; the other two
    /// pass the key on to the field.
    static func returnAction(modifiers: EventModifiers, isComposing: Bool) -> ReturnAction {
        if isComposing { return .field }
        if modifiers.contains(.shift) { return .newline }
        if modifiers.contains(.option) { return .field }
        return .send
    }

    /// Return pressed in the composer: Shift-Return puts a new line at the
    /// insertion point and is handled here. Everything else returns false
    /// and goes on to the field (whose Return sends, its `onSubmit`) — also
    /// when there is no field editor to insert into.
    @MainActor
    static func handleReturn(modifiers: EventModifiers) -> Bool {
        guard let editor = activeFieldEditor,
              returnAction(modifiers: modifiers, isComposing: editor.hasMarkedText()) == .newline
        else { return false }
        editor.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    /// The field being typed in: the key window's. (DEBUG: the snapshot
    /// harness types into a window it never makes key, so it falls back to
    /// the window that has a field editor.)
    @MainActor
    private static var activeFieldEditor: NSTextView? {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor { return editor }
        #if DEBUG
        for window in NSApp.windows {
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor }
        }
        #endif
        return nil
    }

    /// Whether ⌘V should attach an image rather than paste text: the
    /// composer has focus, and the key press is in the composer's own window
    /// with the text cursor in a field (a ⌘V in the Settings window, whose
    /// selectable session ID also takes a field editor, is not the
    /// composer's).
    @MainActor
    static func isComposerPaste(_ event: NSEvent, composerFocused: Bool, composerWindow: NSWindow?) -> Bool {
        guard composerFocused,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let window = event.window, window === composerWindow, window.isKeyWindow,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return false }
        return true
    }
}

extension MacComposerKeys {
    /// Whether a key typed in the composer's window should focus the
    /// composer and go into it (a lesson's type to focus): the composer
    /// hasn't focus, the window is key, the key is a printable character
    /// with no ⌘, ⌃ or ⌥ (not a space, which scrolls and presses buttons,
    /// nor an arrow or function key), and nothing else takes typing there
    /// (a text field, or the sidebar's list and its type-to-select).
    @MainActor
    static func isTypeToFocus(_ event: NSEvent, composerFocused: Bool, composerWindow: NSWindow?) -> Bool {
        guard !composerFocused, let window = event.window, window === composerWindow, window.isKeyWindow,
              typesIntoComposer(modifiers: event.modifierFlags, characters: event.characters)
        else { return false }
        if let responder = window.firstResponder, responder is NSText || responder is NSTableView { return false }
        return true
    }

    /// The key-press half of `isTypeToFocus`, testable without a window.
    static func typesIntoComposer(modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock])
        guard flags.isEmpty, let characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                // The function keys' private-use range (arrows, F1…).
                && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    /// Puts `characters` at the end of the composer once its field editor
    /// has focus (it arrives a moment after the focus change), never over
    /// a draft the field selected on focus.
    @MainActor
    static func insertWhenFocused(_ characters: String, in window: NSWindow, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.02)) {
            guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else {
                if attempt < 10 { insertWhenFocused(characters, in: window, attempt: attempt + 1) }
                return
            }
            let end = NSRange(location: (editor.string as NSString).length, length: 0)
            editor.setSelectedRange(end)
            editor.insertText(characters, replacementRange: end)
        }
    }
}

/// What the composer's ⌘V watcher reads when a key arrives: a reference the
/// view keeps current, because the watcher's closure outlives the view value
/// that installed it.
@MainActor
final class ComposerPasteContext {
    weak var window: NSWindow?
    var isFocused = false
    var isSending = false
    /// A printable key typed elsewhere in the window focuses the composer.
    var typeToFocus = false
}

/// Reports the window a view is in (the composer's, for its ⌘V watcher).
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

// MARK: - Copy

enum MacMessageCopy {
    /// What Copy puts on the pasteboard for a message: the student's text
    /// as typed; Merc's reply as plain text — the lesson markers gone, a
    /// [Q]'s options kept, its answer key never.
    static func text(for message: ChatMessage) -> String {
        switch message.role {
        case .user: return message.content
        case .assistant: return BlockParser.plainText(message.content)
        }
    }
}
#endif
