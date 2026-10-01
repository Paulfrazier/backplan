import SwiftUI

@main
struct BackplanApp: App {
    @State private var store: PlanStore
    @State private var timer = TimerController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        DebugSeed.applyIfRequested()
        #endif
        let store = PlanStore()
        #if DEBUG
        DebugSeed.afterLaunch(store)
        #endif
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
                #if DEBUG
                .task {
                    // -BPArmDay: arm the Day at launch, for screenshots.
                    if ProcessInfo.processInfo.arguments.contains("-BPArmDay") {
                        await timer.armDay(store.day, result: DayPlanner.armable(store.dayResult()))
                    }
                }
                #endif
        }
    }
}
