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
    /// The Day as it was when it was armed; non-nil exactly when the countdown
    /// is running the Day rather than a plan. Kept so "has the day changed" can
    /// be asked of the blocks, not of a result that drifts with the clock.
    private(set) var armedDay: DayPlan?
    var armedIsDay: Bool { armedDay != nil }
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
        let name = plan.eventName.trimmingCharacters(in: .whitespaces)
        let count = await NotificationService.shared.arm(name: name, result: result)
        armedPlan = plan
        armedDay = nil
        armedResult = result
        armedKey = key
        armedAt = Date()
        scheduledCount = count
        armed = true
        persist()
        await LiveActivityService.start(name: name, result: result, armedAt: armedAt)
        startSyncLoop()
    }

    /// Arm the whole Day: `result` is `DayPlanner.armable(store.dayResult())`,
    /// frozen here exactly like a plan's. Replaces whatever was armed — there is
    /// one countdown and one Live Activity, never two.
    func armDay(_ day: DayPlan, result: PlanResult) async {
        await NotificationService.shared.requestAuthorization()
        // Same guard as `arm`; KEEP IN SYNC with the web `canArmDay`.
        guard !result.isPast, !result.segments.isEmpty else { return }
        let count = await NotificationService.shared.arm(
            name: Self.dayName, result: result,
            finalAlert: ("That's the day.", "Your last block is done.")
        )
        armedPlan = nil
        armedDay = day
        armedResult = result
        armedAt = Date()
        scheduledCount = count
        armed = true
        persist()
        await LiveActivityService.start(name: Self.dayName, result: result, armedAt: armedAt)
        startSyncLoop()
    }

    static let dayName = "Your day"

    func disarm() {
        NotificationService.shared.cancelAll()
        syncTask?.cancel()
        syncTask = nil
        armed = false
        armedPlan = nil
        armedDay = nil
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
                    // A Day isn't "late" once its last block ends — it's over —
                    // so its card goes almost at once.
                    let grace: TimeInterval = self.armedIsDay ? 5 * 60 : 60 * 60
                    await LiveActivityService.finish(
                        dismissAfter: result.target.addingTimeInterval(grace)
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
        /// Exactly one of `plan` / `day` is set. Both optional so a v1 record
        /// (plan only, written before Day arming) still decodes.
        var plan: Plan?
        var day: DayPlan?
        var result: PlanResult
    }

    /// A snapshot whose target is this far behind us is debris from a session
    /// nobody disarmed — restoring it would open the app onto a dead countdown
    /// claiming you're nine hours late for yesterday. Matches the web's
    /// `ARMED_MAX_AGE_MS`.
    private static let maxAge: TimeInterval = 6 * 60 * 60

    private func persist() {
        guard armedPlan != nil || armedDay != nil, let armedResult else { return }
        let snap = ArmedSnapshot(
            key: armedKey, armedAt: armedAt, scheduledCount: scheduledCount,
            plan: armedPlan, day: armedDay, result: armedResult
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(ArmedSnapshot.self, from: data),
              snap.plan != nil || snap.day != nil else { return }
        guard Date().timeIntervalSince(snap.result.target) < Self.maxAge else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        armedPlan = snap.plan
        armedDay = snap.day
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
