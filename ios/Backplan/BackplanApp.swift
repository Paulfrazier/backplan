import SwiftUI

@main
struct BackplanApp: App {
    @State private var store = PlanStore()
    @State private var timer = TimerController()

    var body: some Scene {
        WindowGroup {
            PlanView()
                .environment(store)
                .environment(timer)
                // Palette is an intentionally light "paper" neobrutalist look with no
                // dark variants — pin to light so native controls don't render as
                // unreadable dark boxes on the white cards.
                .preferredColorScheme(.light)
        }
    }
}
