import SwiftUI
import WidgetKit

/// The armed plan's Live Activity, plus the Sleep Left and Day widgets (Home Screen,
/// Lock Screen, StandBy).
@main
struct BackplanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlanLiveActivity()
        SleepLeftWidget()
        DayPlanWidget()
    }
}
