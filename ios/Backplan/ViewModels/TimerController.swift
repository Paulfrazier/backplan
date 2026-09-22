import Foundation
import Observation

/// Holds the armed state for a plan and snapshots what was scheduled so the
/// live countdown, the notifications and the Live Activity all agree.
///
/// The snapshot is the whole point. Re-deriving the chain on every tick would
/// let an edit — or a midnight rollover — silently slide the countdown under the
/// user while they were relying on it. Freezing it means any divergence gets
/// *reported* (the stale banner) rather than absorbed.
///
/// The per-second clock that draws the countdown lives in the views
/// (`TimelineView(.periodic)`); this object owns arm/disarm, the frozen
/// snapshot, and the boundary-driven refresh of the Live Activity.
@MainActor
@Observable
final class TimerController {
    private(set) var armed = false
    /// The plan + resolved result captured at arm time.
    private(set) var armedPlan: Plan?
    private(set) var armedResult: PlanResult?
    /// Which half of the night pair was armed. The editor can be pointed at the
    /// other one, so "has the plan changed" has to be asked of this one.
    private(set) var armedKey: PlanKey = .evening
    private(set) var armedAt = Date()
    private(set) var scheduledCount = 0

    /// Wakes exactly at each boundary rather than polling — see `startSyncLoop`.
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    private let storageKey = "backplan.armed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    /// True when the captured chain has already started (plan armed late / in the past).
    var startedInPast: Bool {
        guard let start = armedResult?.overallStart else { return false }
        return start < Date()
    }

    /// The live countdown, from the frozen snapshot. `nil` when disarmed.
    func countdown(now: Date = Date()) -> PlanCountdown? {
        guard let armedResult else { return nil }
        return PlanCountdown.make(result: armedResult, now: now, armedAt: armedAt)
    }

    func arm(key: PlanKey, plan: Plan) async {
        // Ask for notification permission the first time the user arms a plan.
        await NotificationService.shared.requestAuthorization()
        let result = BackwardsPlanner.compute(plan)
        // Never arm a plan whose target has already passed, or one with no timed
        // steps — there's nothing to schedule and a "0 alerts" armed state is a
        // silent no-op. The UI also disables the button in both cases; this is
        // the belt-and-suspenders guard. KEEP IN SYNC with the web `canArmPlan`.
        guard !result.isPast, !result.segments.isEmpty else { return }
        let count = await NotificationService.shared.arm(plan: plan, result: result)
        armedPlan = plan
        armedResult = result
        armedKey = key
        armedAt = Date()
        scheduledCount = count
        armed = true
        persist()
        await LiveActivityService.start(plan: plan, result: result, armedAt: armedAt)
        startSyncLoop()
    }

    func disarm() {
        NotificationService.shared.cancelAll()
        syncTask?.cancel()
        syncTask = nil
        armed = false
        armedPlan = nil
        armedResult = nil
        scheduledCount = 0
        defaults.removeObject(forKey: storageKey)
        Task { await LiveActivityService.end() }
    }

    /// Push the current state at whatever moment we happen to be running —
    /// called when the app returns to the foreground, which is the one time we
    /// can be sure a missed boundary gets caught up.
    func syncLiveActivity() {
        guard armed, let armedResult else { return }
        let at = armedAt
        Task { await LiveActivityService.sync(result: armedResult, armedAt: at) }
        startSyncLoop()
    }

    // MARK: - Boundary-driven refresh

    /// Sleeps until the next moment the copy goes out of date, pushes once, and
    /// repeats. A one-second timer would push ~3,000 identical updates across a
    /// typical plan and get rate-limited; a plan with seven steps needs eight.
    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.armed, let result = self.armedResult else { return }
                let at = self.armedAt
                await LiveActivityService.sync(result: result, armedAt: at)
                guard let next = PlanCountdown.nextChange(result: result, now: Date()) else {
                    // Nothing left to say. Hand the card an expiry rather than
                    // leaving "running over" pinned for the system's 8-hour max.
                    await LiveActivityService.finish(
                        dismissAfter: result.target.addingTimeInterval(60 * 60)
                    )
                    return
                }
                // +0.2s so we wake just *after* the boundary, not on the edge of
                // it — landing a hair early renders the state we're leaving.
                let delay = max(0.2, next.timeIntervalSinceNow + 0.2)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // MARK: - Persistence

    /// Web parity: reopening resumes the same countdown rather than quietly
    /// re-deriving a different one.
    private struct ArmedSnapshot: Codable {
        var v: Int = 1
        var key: PlanKey
        var armedAt: Date
        var scheduledCount: Int
        var plan: Plan
        var result: PlanResult
    }

    /// A snapshot whose target is this far behind us is debris from a session
    /// nobody disarmed — restoring it would open the app onto a dead countdown
    /// claiming you're nine hours late for yesterday. Matches the web's
    /// `ARMED_MAX_AGE_MS`.
    private static let maxAge: TimeInterval = 6 * 60 * 60

    private func persist() {
        guard let armedPlan, let armedResult else { return }
        let snap = ArmedSnapshot(
            key: armedKey, armedAt: armedAt, scheduledCount: scheduledCount,
            plan: armedPlan, result: armedResult
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(ArmedSnapshot.self, from: data) else { return }
        guard Date().timeIntervalSince(snap.result.target) < Self.maxAge else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        armedPlan = snap.plan
        armedResult = snap.result
        armedKey = snap.key
        armedAt = snap.armedAt
        scheduledCount = snap.scheduledCount
        armed = true
        // The card outlived the process. The sync loop finds it again through
        // `Activity.activities`, so nothing needs re-requesting — it just picks
        // up where it left off.
        startSyncLoop()
    }
}
