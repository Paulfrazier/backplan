import SwiftUI
import WidgetKit

/// The armed plan's Live Activity; the Sleep Left, Day and Countdown widgets
/// (Home Screen, Lock Screen, StandBy); and the Start-morning control.
@main
struct BackplanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlanLiveActivity()
        SleepLeftWidget()
        DayPlanWidget()
        CountdownWidget()
        if #available(iOS 18, *) { StartMorningControl() }
    }
}
