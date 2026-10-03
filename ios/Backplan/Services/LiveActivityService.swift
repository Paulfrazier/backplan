import ActivityKit
import Foundation

/// Owns the one Live Activity Backplan ever runs. Started when the user arms a
/// plan, updated at each step boundary, ended on disarm.
///
/// Three things shape the design:
///
/// 1. **The system ticks the clock, not us.** The content state carries a
///    *boundary date*, and the widget renders it with `Text(timerInterval:)`.
///    A countdown therefore stays correct with zero updates — pushing a new
///    state every second would be rate-limited into uselessness and would burn
///    battery drawing a number the system draws for free.
/// 2. **Updates only land while the app is alive.** Local `Activity.update` has
///    no background entitlement behind it, so a suspended app cannot advance the
///    step name. Every state therefore carries a `staleDate` set to the next
///    boundary: if we miss it, the system dims the card rather than showing a
///    confidently wrong step. Fixing that properly needs push tokens and a
///    server, which Backplan does not have (see BACKLOG).
/// 3. **No stored handle.** `Activity` is not `Sendable`, so holding one in an
///    isolated property and then `await`ing a method on it is a Swift 6 error
///    ("sending 'activity' risks causing data races"). Looking the live one up
///    from `Activity.activities` inside each `nonisolated` call sidesteps the
///    crossing entirely — and as a bonus it survives a relaunch, where a stored
///    handle would have been lost while the card kept running.
enum LiveActivityService {
    private static var current: Activity<PlanActivityAttributes>? {
        Activity<PlanActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    static func start(name: String, result: PlanResult, armedAt: Date, now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        #if DEBUG
        // Requesting an activity raises the notification-permission alert on a
        // fresh simulator, which nothing headless can dismiss.
        if ProcessInfo.processInfo.arguments.contains("-BPNoAuth") { return }
        #endif
        guard let first = result.segments.first,
              let content = makeContent(result: result, armedAt: armedAt, now: now) else { return }

        // Re-arming replaces the card rather than stacking a second one.
        await end()

        let attributes = PlanActivityAttributes(
            eventName: name,
            chainStart: first.start,
            target: result.target
        )
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func sync(result: PlanResult, armedAt: Date, now: Date = Date()) async {
        guard let activity = current,
              let content = makeContent(result: result, armedAt: armedAt, now: now) else { return }
        await activity.update(content)
    }

    /// The plan is over and there is nothing left to update. Leave the overrun
    /// card up for a while — the user may well be in the middle of being late —
    /// but give it an expiry, or a card nobody disarmed sits on the Lock Screen
    /// until the system's own 8-hour limit.
    static func finish(dismissAfter date: Date) async {
        for activity in Activity<PlanActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .after(date))
        }
    }

    /// Ends immediately. Disarm should feel like disarm — leaving the card up
    /// for the system's default four hours reads as the button not having worked.
    static func end() async {
        for activity in Activity<PlanActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func makeContent(
        result: PlanResult, armedAt: Date, now: Date
    ) -> ActivityContent<PlanActivityAttributes.ContentState>? {
        guard let countdown = PlanCountdown.make(result: result, now: now, armedAt: armedAt) else { return nil }
        let state = PlanActivityAttributes.ContentState(
            label: countdown.label,
            boundary: countdown.boundary,
            windowStart: countdown.windowStart,
            phaseWord: countdown.phaseWord,
            detail: countdown.detail,
            // Before the plan starts, `next` *is* the first step — printing it
            // under a detail line that already says so reads as a bug. Same call
            // the web arm strip makes.
            next: countdown.phase == .future ? "" : countdown.status.next,
            phase: phase(countdown.phase)
        )
        return ActivityContent(state: state, staleDate: PlanCountdown.nextChange(result: result, now: now))
    }

    private static func phase(_ p: PlanPhase) -> PlanActivityAttributes.Phase {
        switch p {
        case .future: return .future
        case .active: return .active
        case .past: return .past
        }
    }
}
