import WidgetKit
import SwiftUI
import MercuriusActivity

/// The widget-extension entry point. Deliberately a thin shell: the Live
/// Activity itself (views, theme, attributes) lives in the shared
/// `MercuriusActivity` package so the app target can start/update it with
/// the same types.
@main
struct MercuriusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MercuriusLiveActivityWidget()
    }
}
