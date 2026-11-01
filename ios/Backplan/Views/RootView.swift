import SwiftUI

/// Plan | Day. The selected tab is persisted, and either side can switch it —
/// "Add to Day" jumps to Day, a linked block's "Edit plan" jumps back.
///
/// The Now skin wraps the same two screens behind a Now tab. Classic's tab
/// storage only ever holds "plan" / "day"; whether Now is showing is held
/// separately, so flipping back to Classic can never land on a tag it lacks.
struct RootView: View {
    @AppStorage("backplan.mode") private var mode = "plan"
    @AppStorage(Skin.storageKey) private var skin = Skin.classic
    /// Now tab showing (Now skin only). Entering the skin always opens on it.
    @State private var onNow = true
    /// Kid view takes the whole screen; the `backplan://kid` link sets this too.
    @AppStorage(KidView.storageKey) private var kidView = false
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        Group {
            if skin == Skin.now {
                nowTabs
            } else {
                classicTabs
            }
        }
        // `backplan://now` / `backplan://day`. Initial too: a cold launch from a
        // widget can deliver the link before this view first appears.
        .onChange(of: router.tabRequest, initial: true) { _, request in
            guard let request else { return }
            if request.tab == "now" {
                if skin == Skin.now { onNow = true } else { mode = request.classicTab }
            } else {
                onNow = false
                mode = request.tab
            }
        }
        .fullScreenCover(isPresented: $kidView) { KidView() }
    }

    private var classicTabs: some View {
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

    private var nowTabs: some View {
        // Plan / Day still write `mode` to jump between each other; that only
        // happens from those tabs, i.e. while Now isn't showing.
        let selection = Binding<String>(
            get: { onNow ? "now" : mode },
            set: { tag in
                if tag == "now" { onNow = true } else { onNow = false; mode = tag }
            }
        )
        return TabView(selection: selection) {
            NowView(open: { selection.wrappedValue = $0 })
                .tabItem { Label("Now", systemImage: "timer") }
                .tag("now")
            PlanView()
                .tabItem { Label("Plan", systemImage: "arrow.uturn.backward.circle") }
                .tag("plan")
            DayView()
                .tabItem { Label("Day", systemImage: "calendar.day.timeline.left") }
                .tag("day")
        }
        .environment(\.nowSkin, true)
        .tint(.bpPurpleElectric)
        .onAppear { onNow = true }
    }
}
