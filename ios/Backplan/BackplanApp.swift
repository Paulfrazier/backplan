import SwiftUI

@main
struct BackplanApp: App {
    @State private var store = PlanStore()
    @State private var timer = TimerController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PlanView()
                .environment(store)
                .environment(timer)
                // Palette is an intentionally light "paper" neobrutalist look with no
                // dark variants — pin to light so native controls don't render as
                // unreadable dark boxes on the white cards.
                .preferredColorScheme(.light)
                // A Live Activity can only be updated while the app is running,
                // so returning to the foreground is our one guaranteed chance to
                // catch up on boundaries that went by while we were suspended.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { timer.syncLiveActivity() }
                }
        }
    }
}
