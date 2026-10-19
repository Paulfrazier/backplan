import SwiftUI
import UIKit

@main
struct BackplanApp: App {
    @State private var store: PlanStore
    @State private var timer: TimerController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before anything can be scheduled, so a boundary that fires while the
        // app is open is shown rather than dropped.
        NotificationService.shared.installDelegate()
        #if DEBUG
        DebugSeed.applyIfRequested()
        #endif
        let store = PlanStore()
        let timer = TimerController()
        // The launch case. After the armed snapshot is restored, because a roll
        // has to wait while its plan is the armed one.
        store.normalizeDates(hold: timer.dateHold)
        #if DEBUG
        DebugSeed.afterLaunch(store)
        #endif
        _store = State(initialValue: store)
        _timer = State(initialValue: timer)
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
                    if phase == .active {
                        // Back from overnight: "tomorrow" may now be today.
                        store.normalizeDates(hold: timer.dateHold)
                        timer.syncLiveActivity()
                    }
                }
                // Midnight (or a clock / time-zone change) while the app is open.
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: DispatchQueue.main)) { _ in store.normalizeDates(hold: timer.dateHold) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
                    .receive(on: DispatchQueue.main)) { _ in store.normalizeDates(hold: timer.dateHold) }
                // A held date (the armed plan, or last night's linked evening)
                // rolls once the hold lifts — a disarm, this morning's target
                // going by — which no notification announces. The web catches
                // it on its 1s tick; a minute is plenty, and it's a string
                // compare until something is actually stale.
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        store.normalizeDates(hold: timer.dateHold)
                    }
                }
                #if DEBUG
                .task {
                    // -BPArmDay: arm the Day at launch, for screenshots.
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-BPArmDay") {
                        await timer.armDay(store.day, result: DayPlanner.armable(store.dayResult()))
                    }
                    // Now skin: -BPArmPlan arms the open plan; -BPDone and
                    // -BPLate N then drive Done / Running late, since the
                    // simulator can't take injected taps. -BPNowDemo alone
                    // means "preview": clear any countdown the timer restored.
                    if args.contains("-BPArmPlan") {
                        await timer.arm(key: store.activeKey, plan: store.resolved(store.activeKey))
                    } else if args.contains("-BPNowDemo") && timer.armed {
                        timer.disarm()
                    }
                    if args.contains("-BPDone") { await timer.finishCurrentStep() }
                    if let i = args.firstIndex(of: "-BPLate"), args.indices.contains(i + 1),
                       let n = Int(args[i + 1]) {
                        await timer.slip(minutes: n)
                    }
                    if timer.armed, let r = timer.armedResult {
                        let segs = r.segments.map { "\($0.name)@\(Fmt.time($0.start))-\(Fmt.time($0.end))" }
                        print("BPDEBUG armed slack=\(String(describing: timer.armedResult?.slack(at: Date()))) adj=\(String(describing: timer.adjustments)) alerts=\(timer.scheduledCount) segs=\(segs)")
                        fflush(stdout)
                    }
                }
                #endif
        }
    }
}
