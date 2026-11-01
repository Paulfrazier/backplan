import AppIntents
import Foundation

/// The app side of the widget / Live Activity / Siri buttons. `BackplanApp`
/// installs this into `IntentRouter` at launch — including a background launch
/// made just to run one of the `LiveActivityIntent`s — so a tap reaches the
/// same `TimerController` the Now screen drives. From there the ordinary path
/// does the rest: the timer persists (republishing the widget's chain and
/// reloading it if it changed), reschedules the alerts and pushes the Live
/// Activity a new state.
@MainActor
enum IntentHandler {
    static func install(store: PlanStore, timer: TimerController) {
        IntentRouter.handler = { action in
            await handle(action, store: store, timer: timer)
        }
    }

    static func handle(_ action: IntentAction, store: PlanStore, timer: TimerController,
                       now: Date = Date()) async -> String {
        switch action {
        case .done:
            guard timer.armed else { return "Nothing is running." }
            guard let current = timer.armedResult?.runningIndex(at: now)
                .flatMap({ timer.armedResult?.segments[$0].name }) else {
                return "No step is running right now."
            }
            await timer.finishCurrentStep(now: now)
            let next = timer.countdown(now: Date())?.detail
            return next.map { "Done with \(current). Now: \($0)." } ?? "Done with \(current)."
        case .late(let minutes):
            guard timer.armed else { return "Nothing is running." }
            guard timer.armedResult?.currentRun(at: now) != nil else { return "Nothing left to push." }
            await timer.slip(minutes: minutes, now: now)
            return "Pushed back \(minutes) min." + slackSentence(timer)
        case .startMorning:
            guard store.link.enabled else {
                return "Turn on \u{201C}Chain tomorrow morning\u{201D} in Backplan first."
            }
            // `resolved`, not `pair.morning`: chained, the morning's date comes
            // from the evening (`BackwardsPlanner.compute` alone ignores it).
            let plan = store.resolved(.morning, now: now)
            await timer.arm(key: .morning, plan: plan)
            guard timer.armed, timer.armedKey == .morning, !timer.armedIsDay,
                  let start = timer.armedResult?.overallStart else {
                return "Couldn't start the morning \u{2014} its time may have passed."
            }
            let name = plan.eventName.isEmpty ? "the morning" : plan.eventName
            return "Counting down to \(name). Wake at \(Fmt.time(start))."
        }
    }

    private static func slackSentence(_ timer: TimerController) -> String {
        guard let slack = timer.slackMinutes() else { return "" }
        if slack == 0 { return " On time." }
        if slack > 0 { return " \(Fmt.duration(slack)) to spare." }
        return " \(Fmt.duration(-slack)) behind."
    }
}

/// Siri and Shortcuts. The phrases must name the app, and are what a user can
/// say with no setup at all.
struct BackplanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMorningIntent(),
            phrases: ["Start school morning in \(.applicationName)",
                      "Start the morning in \(.applicationName)"],
            shortTitle: "Start school morning",
            systemImageName: "sunrise.fill"
        )
        AppShortcut(
            intent: RunningLateIntent(),
            phrases: ["I'm running late in \(.applicationName)",
                      "Running late in \(.applicationName)"],
            shortTitle: "Running late",
            systemImageName: "tortoise.fill"
        )
        AppShortcut(
            intent: FinishStepIntent(),
            phrases: ["Done with this step in \(.applicationName)",
                      "Next step in \(.applicationName)"],
            shortTitle: "Done with this step",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
