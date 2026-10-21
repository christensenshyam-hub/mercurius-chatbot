#if os(macOS)
import SwiftUI
import DesignSystem

/// The toolbar's Progress button, trailing on every screen past the gate
/// (SPEC.md D8): a standard toolbar button — the system draws it, as glass
/// on macOS 26 — in place of the streak's flame and count, which Night
/// Studio keeps off the chrome. The streak stays on Today, as one quiet
/// line, and in Progress. ⌘4 does the same from the View menu.
struct MacProgressButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(Self.title, systemImage: Self.symbol)
        }
        // Undo the detail column's borderless default: a toolbar item.
        .buttonStyle(.automatic)
        .help(Self.help)
        .accessibilityLabel(Self.title)
    }

    static let title = "Progress"
    static let symbol = "chart.bar.xaxis"
    static let help = "Progress and achievements (⌘4)"
}
#endif
