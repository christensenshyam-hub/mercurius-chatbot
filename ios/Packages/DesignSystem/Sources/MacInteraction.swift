import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The Mac's pointer-and-window conventions for the shared views, as
/// modifiers that do nothing at all on iOS (each returns the view unchanged
/// there), so a shared view can opt in without any change to the iPhone app.
///
/// - `macReadableColumn()`: a reading column of `MacLayout.readableWidth`,
///   centred in a wide window (the chat, a lesson, the path).
/// - `macHoverHighlight(cornerRadius:)`: a card that can be clicked tints
///   while the pointer is over it. No pointing hand: the Mac keeps that for
///   links.
/// - `macPointingHand()`: the pointing hand, for links only.
public enum MacLayout {
    /// The widest a column of reading text gets in a wide Mac window: about
    /// 80 characters of the Mac's 15 pt body (`MacTypeRamp`) once the
    /// column's own padding is taken off — past that, lines get hard to
    /// track back from. (It was 720 pt for 17 pt text; at 13 pt that ran to
    /// 110 characters a line.)
    public static let readableWidth: CGFloat = 620

    /// The first-run flow's box: about 75 characters of 15 pt body inside
    /// its 24 pt margins.
    public static let gateWidth: CGFloat = 600

    /// The widest a reply's text runs inside that column. On a phone the cap
    /// is 340 pt (MessageBubbleView); on the Mac the bubble may use most of
    /// the column, leaving room for Merc's avatar and the bubble's padding.
    public static let replyMeasure: CGFloat = 580

    /// The learning path's column: about a phone and a half wide, so the
    /// winding path still winds and Merc stands beside the next stop rather
    /// than at the window's far edge.
    public static let pathWidth: CGFloat = 560
}

public extension View {
    /// Mac: at most `width` wide, centred in whatever is offered. iOS: the
    /// view unchanged.
    @ViewBuilder
    func macReadableColumn(_ width: CGFloat = MacLayout.readableWidth) -> some View {
        #if os(macOS)
        self.frame(maxWidth: width).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// Mac: a soft accent tint over the view while the pointer is over it
    /// (the arrow stays an arrow: the Mac shows the pointing hand only over
    /// links). `isEnabled == false` (a locked or answered option) shows no
    /// tint. iOS: the view unchanged.
    @ViewBuilder
    func macHoverHighlight(cornerRadius: CGFloat, isEnabled: Bool = true) -> some View {
        #if os(macOS)
        modifier(MacHoverHighlight(cornerRadius: cornerRadius, isEnabled: isEnabled))
        #else
        self
        #endif
    }

    /// Mac: Return presses this button (a screen's one primary action — a
    /// first-run step's Continue). Disabled, it ignores Return too. iOS: the
    /// view unchanged.
    @ViewBuilder
    func macDefaultAction() -> some View {
        #if os(macOS)
        keyboardShortcut(.defaultAction)
        #else
        self
        #endif
    }

    /// Mac: the pointing-hand cursor while the pointer is over the view —
    /// for links (the HIG keeps it for them). iOS: the view unchanged.
    @ViewBuilder
    func macPointingHand(isEnabled: Bool = true) -> some View {
        #if os(macOS)
        modifier(MacPointingHand(isEnabled: isEnabled))
        #else
        self
        #endif
    }
}

#if os(macOS)
/// The pointing hand while hovered. Pushed and popped in pairs; a view that
/// leaves while hovered (a prompt chip that sends and goes away) pops its own
/// push, so the cursor is never left as a hand.
private struct MacPointingHand: ViewModifier {
    let isEnabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in update(inside && isEnabled) }
            .onChange(of: isEnabled) { _, enabled in if !enabled { update(false) } }
            .onDisappear { update(false) }
    }

    private func update(_ wantsHand: Bool) {
        guard wantsHand != pushed else { return }
        if wantsHand { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        pushed = wantsHand
    }
}

private struct MacHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BrandColor.accent.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(BrandColor.accent.opacity(0.45), lineWidth: 1)
                    )
                    .opacity(hovering && isEnabled ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Copying to the Mac's pasteboard (the shared views' Copy buttons and menu
/// items; iOS uses `UIPasteboard` in place).
public enum MacPasteboard {
    /// Put `text` on the general pasteboard.
    ///
    /// - Parameters:
    ///   - currentHostOnly: keep it off Universal Clipboard (the Mac's
    ///     `localOnly`), for the session id.
    ///   - concealed: mark it as a secret for clipboard managers
    ///     (`org.nspasteboard.ConcealedType`), which then don't keep a history
    ///     of it.
    ///   - clearAfter: wipe it again after this long, unless something else
    ///     was copied in the meantime (the Mac's `expirationDate`).
    @MainActor
    public static func copy(_ text: String, currentHostOnly: Bool = false, concealed: Bool = false,
                            clearAfter: TimeInterval? = nil) {
        let pasteboard = NSPasteboard.general
        if currentHostOnly {
            pasteboard.prepareForNewContents(with: .currentHostOnly)
        } else {
            pasteboard.clearContents()
        }
        pasteboard.setString(text, forType: .string)
        if concealed {
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        guard let clearAfter else { return }
        let stamp = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            if NSPasteboard.general.changeCount == stamp { NSPasteboard.general.clearContents() }
        }
    }
}
#endif
