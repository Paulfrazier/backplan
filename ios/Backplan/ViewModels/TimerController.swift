import Foundation
import Observation

/// Holds the armed state for a plan and snapshots what was scheduled so the
/// live countdown and the notifications agree. The ticking clock that drives
/// the countdown UI lives in the views (TimelineView(.periodic)); this object
/// just owns arm/disarm and the scheduled snapshot.
@MainActor
@Observable
final class TimerController {
    private(set) var armed = false
    /// The plan + resolved result captured at arm time.
    private(set) var armedPlan: Plan?
    private(set) var armedResult: PlanResult?
    private(set) var scheduledCount = 0

    /// True when the captured chain has already started (plan armed late / in the past).
    var startedInPast: Bool {
        guard let start = armedResult?.overallStart else { return false }
        return start < Date()
    }

    func arm(plan: Plan) async {
        // Ask for notification permission the first time the user arms a plan.
        await NotificationService.shared.requestAuthorization()
        let result = BackwardsPlanner.compute(plan)
        // Never arm a plan whose target has already passed — there's nothing to
        // schedule and a "0 alerts" armed state is a silent no-op. The UI also
        // disables the button in this case; this is the belt-and-suspenders guard.
        guard !result.isPast else { return }
        let count = await NotificationService.shared.arm(plan: plan, result: result)
        armedPlan = plan
        armedResult = result
        scheduledCount = count
        armed = true
    }

    func disarm() {
        NotificationService.shared.cancelAll()
        armed = false
        armedPlan = nil
        armedResult = nil
        scheduledCount = 0
    }
}
