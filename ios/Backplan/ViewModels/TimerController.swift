import Foundation
import Observation
import WidgetKit

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
    /// Done / Running late edits made to the frozen result since arming (Now
    /// skin). `nil` = untouched, which is every snapshot Classic ever writes.
    private(set) var adjustments: ArmAdjustments?

    /// Wakes exactly at each boundary rather than polling — see `startSyncLoop`.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// Stop's teardown (pending alerts + the Live Activity). Every arm awaits
    /// it before scheduling: left fire-and-forget, a Stop → Start tapped in
    /// quick succession let the old removal land *after* the new requests and
    /// delete them — alert ids are positional, so old and new share names —
    /// or end the card the new countdown had just started.
    @ObservationIgnored private var teardown: Task<Void, Never>?

    private let storageKey = "backplan.armed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
        // Whatever launch found — a live snapshot, a dead one just discarded,
        // nothing — the widget hears it. Covers an install that armed before
        // the widget existed. A string compare when nothing changed.
        publishChain()
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

    /// `plan` is the half as it will run — `PlanStore.resolved(key)` — so its
    /// date is already absolute and a re-arm lands on the plan's own day.
    func arm(key: PlanKey, plan: Plan) async {
        // Ask for notification permission the first time the user arms a plan.
        await NotificationService.shared.requestAuthorization()
        await settleTeardown()
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
        adjustments = nil
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
        await settleTeardown()
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
        adjustments = nil
        scheduledCount = count
        armed = true
        persist()
        await LiveActivityService.start(name: Self.dayName, result: result, armedAt: armedAt)
        startSyncLoop()
    }

    static let dayName = "Your day"

    func disarm() {
        let previous = teardown
        teardown = Task {
            await previous?.value
            await NotificationService.shared.cancelAll()
            await LiveActivityService.end()
        }
        syncTask?.cancel()
        syncTask = nil
        armed = false
        armedPlan = nil
        armedDay = nil
        armedResult = nil
        adjustments = nil
        scheduledCount = 0
        defaults.removeObject(forKey: storageKey)
        publishChain()
    }

    /// What `PlanStore.normalizeDates` must not roll out from under the countdown.
    var dateHold: PlanStore.DateHold {
        guard armed else { return PlanStore.DateHold() }
        return armedIsDay ? PlanStore.DateHold(day: true) : PlanStore.DateHold(plan: armedKey)
    }

    /// Wait out any Stop still tearing down. See `teardown`.
    private func settleTeardown() async {
        guard let pending = teardown else { return }
        await pending.value
        if teardown == pending { teardown = nil }
    }

    // MARK: - Stale

    /// True when the live plan (or Day) no longer matches the armed snapshot —
    /// the scheduled alerts, the countdown and the Live Activity are all out of
    /// date until a re-arm. Compared as *absolute* schedules: overnight, a
    /// plan's Tomorrow becomes Today with no moment moving, and that is not a
    /// change. Asked of the armed half, not the one being edited — switching
    /// tabs is not a change to the armed plan. Done / Running late edit the
    /// result, not the snapshot, so they never read as changed either.
    func isStale(against store: PlanStore, now: Date = Date()) -> Bool {
        guard armed else { return false }
        if let armedDay { return store.day.anchored(now: now) != armedDay.anchored(now: now) }
        guard let armedPlan else { return false }
        return store.resolved(armedKey, now: now).anchored(now: now) != armedPlan.anchored(now: now)
    }

    // MARK: - Done / Running late (Now skin)

    /// Minutes of room between the current run's end and the next fixed thing
    /// (positive = to spare, negative = behind). See `PlanResult.slack(at:)`.
    func slackMinutes(now: Date = Date()) -> Int? {
        armedResult?.slack(at: now)?.minutes
    }

    /// Finish the running step now; the rest of its run closes up behind it.
    /// No-op outside a step.
    func finishCurrentStep(now: Date = Date()) async {
        guard armed, let armedResult,
              let (result, banked) = armedResult.finishingCurrent(at: now) else { return }
        var adj = adjustments ?? ArmAdjustments(origEnd: armedResult.chainEnd ?? armedResult.target)
        adj.bankedMin += banked
        await apply(result, adj, now: now)
    }

    /// Running late: stretch the running step (or move the next run) by
    /// `minutes`. The target and every other run stay put.
    func slip(minutes: Int, now: Date = Date()) async {
        guard armed, let armedResult,
              let result = armedResult.slipping(minutes: minutes, at: now) else { return }
        var adj = adjustments ?? ArmAdjustments(origEnd: armedResult.chainEnd ?? armedResult.target)
        adj.slipMin += minutes
        await apply(result, adj, now: now)
    }

    /// Swap in the adjusted chain and bring every surface back into agreement
    /// with it: notifications are rescheduled from scratch (anything already
    /// past is skipped by `NotificationService.arm`, so a boundary that fired is
    /// never refired, and one pushed later is rescheduled, not dropped), the
    /// Live Activity is pushed, and the boundary loop re-aims. The plan/day
    /// snapshot is untouched, so the stale banner stays quiet.
    private func apply(_ result: PlanResult, _ adj: ArmAdjustments, now: Date) async {
        armedResult = result
        adjustments = adj
        persist()
        let name = armedIsDay ? Self.dayName
            : (armedPlan?.eventName.trimmingCharacters(in: .whitespaces) ?? "")
        scheduledCount = await NotificationService.shared.arm(
            name: name, result: result,
            finalAlert: armedIsDay ? ("That's the day.", "Your last block is done.") : nil,
            now: now
        )
        // A disarm may have landed while we were awaiting the scheduler — don't
        // leave its alerts behind it.
        guard armed else { await NotificationService.shared.cancelAll(); return }
        guard armedResult == result else { return }
        persist()
        let at = armedAt
        await LiveActivityService.sync(result: result, armedAt: at)
        startSyncLoop()
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
        /// Now skin's Done / Running late record. Optional, so every snapshot
        /// written before it existed (or by Classic, which never sets it) decodes.
        var adj: ArmAdjustments?
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
            plan: armedPlan, day: armedDay, result: armedResult, adj: adjustments
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: storageKey)
        }
        publishChain()
    }

    /// The chain as the Countdown widget sees it: flat names and clock times,
    /// since the extension can't see `PlanResult`. Every persist goes through
    /// here, so arm, Done and Running late all reach the widget; disarm (and a
    /// dead snapshot found at launch) clears it.
    var widgetChain: ArmedChain? {
        guard armed, let armedResult else { return nil }
        return ArmedChain(
            kind: armedIsDay ? .day : .plan,
            eventName: armedIsDay ? Self.dayName
                : (armedPlan?.eventName.trimmingCharacters(in: .whitespaces) ?? ""),
            target: armedResult.target,
            armedAt: armedAt,
            segments: armedResult.segments.map { .init(name: $0.name, start: $0.start, end: $0.end) }
        )
    }

    /// Write `widgetChain` to the App Group; reload the widget only when it
    /// actually changed, since reloads are budgeted and persists are not.
    private func publishChain() {
        // Only the real controller — a test one on its own suite must not land
        // on the user's Home Screen. Same rule as `PlanStore.publishSleepLeft`.
        guard defaults === UserDefaults.standard else { return }
        if CountdownStore.save(chain: widgetChain) {
            WidgetCenter.shared.reloadTimelines(ofKind: CountdownStore.widgetKind)
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
        adjustments = snap.adj
        scheduledCount = snap.scheduledCount
        armed = true
        // The card outlived the process. The sync loop finds it again through
        // `Activity.activities`, so nothing needs re-requesting — it just picks
        // up where it left off.
        startSyncLoop()
    }
}

/// What Done / Running late have done to an armed chain. Web parity:
/// `adj: { origEnd, slipMin, bankedMin }` on the armed snapshot.
struct ArmAdjustments: Codable, Equatable, Sendable {
    /// The chain's end at arm time (a plan's target, a day's last block end).
    /// Kept for the record; slack is measured run-by-run, not against this.
    var origEnd: Date
    var slipMin: Int = 0
    var bankedMin: Int = 0

    init(origEnd: Date, slipMin: Int = 0, bankedMin: Int = 0) {
        self.origEnd = origEnd
        self.slipMin = slipMin
        self.bankedMin = bankedMin
    }

    // A default value does NOT make a key optional to the synthesized decoder;
    // only `origEnd` is load-bearing, so only it is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origEnd = try c.decode(Date.self, forKey: .origEnd)
        slipMin = try c.decodeIfPresent(Int.self, forKey: .slipMin) ?? 0
        bankedMin = try c.decodeIfPresent(Int.self, forKey: .bankedMin) ?? 0
    }
}
