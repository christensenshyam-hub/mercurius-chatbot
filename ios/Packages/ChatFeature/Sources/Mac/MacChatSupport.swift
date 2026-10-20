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
    /// Shift-Return in the composer: a new line at the insertion point. The
    /// field's own Return sends (its `onSubmit`); Option-Return already
    /// inserts a line on the Mac and still does.
    ///
    /// Returns false when the key should go on to the field: there is no
    /// field editor, or an input method is composing (Return then confirms
    /// the composition).
    @MainActor
    static func insertNewline() -> Bool {
        guard let editor = activeFieldEditor, !editor.hasMarkedText() else { return false }
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
    /// composer has focus and the key window's text cursor is in a field
    /// (not, say, the Settings window).
    @MainActor
    static func isComposerPaste(_ event: NSEvent, composerFocused: Bool) -> Bool {
        guard composerFocused,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let window = event.window, window.isKeyWindow,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return false }
        return true
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
