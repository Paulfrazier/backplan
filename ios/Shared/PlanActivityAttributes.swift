import ActivityKit
import Foundation

/// What the Lock Screen / Dynamic Island knows about an armed plan.
///
/// Deliberately a flat snapshot of clock times rather than a handle on the plan:
/// the widget runs in its own process and cannot see `PlanStore`, and — more to
/// the point — a Live Activity is supposed to be a frozen record of what was
/// armed. When the plan moves underneath it the app re-arms and pushes a new
/// state; the activity never re-derives anything for itself.
///
/// Shared source between the app and the widget extension (`ios/Shared`), so the
/// two can't disagree about the payload's shape.
struct PlanActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the activity.
    let eventName: String
    /// The whole plan's window, used for the progress bar behind the countdown.
    let chainStart: Date
    let target: Date

    struct ContentState: Codable, Hashable {
        /// "Starts in" / "Next step in" / "Target in" / "Over by".
        var label: String
        /// The moment the clock counts to. `Text(timerInterval:)` ticks this for
        /// us — the system owns the seconds, so the app never has to push an
        /// update just to advance a number.
        var boundary: Date
        /// Where the current interval began, so the ring/bar has a span to fill.
        var windowStart: Date
        /// "Not started" / "Start now" / "Step 2 of 5" / "Running over".
        var phaseWord: String
        /// The step the user is (or is about to be) on.
        var detail: String
        /// What follows it; empty when nothing does.
        var next: String
        var phase: Phase
    }

    /// Mirrors `PlanPhase`, redeclared here because the planner is app-only.
    enum Phase: String, Codable, Hashable {
        case future, active, past
    }
}
