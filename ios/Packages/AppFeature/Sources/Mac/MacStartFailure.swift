#if os(macOS)
import SwiftUI
import DesignSystem

/// The window when the app couldn't start (no session ID could be made on
/// this Mac), in Night Studio (SPEC.md §5.10): the existing words and one
/// way forward, on a flat canvas. No sad Merc, no illustration, no colour
/// wash.
struct MacStartFailure: View {
    let reason: String
    let onRetry: () -> Void

    static let title = "Couldn't start"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Night.errorText)
                    .accessibilityHidden(true)
                Text(Self.title)
                    .nightFont(.title2)
                    .foregroundStyle(Night.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(reason)
                .nightFont(.body)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
            NightPrimaryButton("Try again", action: onRetry)
                .keyboardShortcut(.defaultAction)
                .help("Try again (Return)")
                .padding(.top, 4)
        }
        .padding(Night.Space.card)
        .frame(maxWidth: 440, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NightCanvas(pools: .flat, stars: false))
    }
}
#endif
