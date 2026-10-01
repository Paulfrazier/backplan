import SwiftUI

/// Plan | Day. The selected tab is persisted, and either side can switch it —
/// "Add to Day" jumps to Day, a linked block's "Edit plan" jumps back.
struct RootView: View {
    @AppStorage("backplan.mode") private var mode = "plan"

    var body: some View {
        TabView(selection: $mode) {
            PlanView()
                .tabItem { Label("Plan", systemImage: "arrow.uturn.backward.circle") }
                .tag("plan")
            DayView()
                .tabItem { Label("Day", systemImage: "calendar.day.timeline.left") }
                .tag("day")
        }
        .tint(.bpPurpleElectric)
    }
}
