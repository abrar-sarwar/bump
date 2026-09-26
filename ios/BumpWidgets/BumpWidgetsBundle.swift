import SwiftUI
import WidgetKit

/// The widget extension's entry point. It contains only the Live Activity:
/// no home screen widgets, no sensors, no transport.
@main
struct BumpWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 17.0, *) {
            BumpLiveActivity()
        }
    }
}
