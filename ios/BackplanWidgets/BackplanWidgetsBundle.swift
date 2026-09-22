import SwiftUI
import WidgetKit

/// Backplan ships no Home Screen widgets — this bundle exists solely to host the
/// Live Activity, which has to live in a widget extension.
@main
struct BackplanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlanLiveActivity()
    }
}
