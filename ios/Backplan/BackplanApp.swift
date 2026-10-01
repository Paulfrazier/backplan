import SwiftUI

@main
struct BackplanApp: App {
    @State private var store: PlanStore
    @State private var timer = TimerController()

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
        }
    }
}
