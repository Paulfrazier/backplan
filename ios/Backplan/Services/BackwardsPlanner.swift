import Foundation

/// One step's resolved placement on the timeline.
struct PlanSegment: Identifiable {
    let id: UUID
    let name: String
    let minutes: Int
    let start: Date
    let end: Date
}

/// Result of walking a plan backwards from its target time.
/// Pure data — produced by `BackwardsPlanner.compute` and consumed by the UI
/// and the notification scheduler alike.
struct PlanResult {
    let target: Date
    /// Per-step start time, index-aligned to `plan.steps` (includes zero-duration steps).
    let startTimes: [Date]
    /// Start of the whole chain (first step's start), nil when there are no steps.
    let overallStart: Date?
    /// True when the chain starts before midnight of the target's day.
    let overflowsPrevDay: Bool
    let totalMinutes: Int
    /// Non-zero-duration steps, with absolute start/end — drives the timeline.
    let segments: [PlanSegment]
    /// True when the target time itself has already passed — the plan is moot
    /// (nothing left to schedule). Distinct from `overflowsPrevDay`.
    let isPast: Bool

    var hasSteps: Bool { overallStart != nil }
}

enum BackwardsPlanner {
    /// Direct port of the web `compute()`: walk steps last→first, subtracting each
    /// step's minutes from a cursor that starts at the target time.
    static func compute(_ plan: Plan, now: Date = Date(), calendar: Calendar = .current) -> PlanResult {
        let target = plan.targetDate(now: now, calendar: calendar)

        var startTimes = [Date](repeating: target, count: plan.steps.count)
        var totalMin = 0
        var cursor = target
        for i in stride(from: plan.steps.count - 1, through: 0, by: -1) {
            let mins = plan.steps[i].minutes
            let start = cursor.addingTimeInterval(TimeInterval(-mins * 60))
            startTimes[i] = start
            totalMin += mins
            cursor = start
        }

        let overallStart = plan.steps.isEmpty ? nil : startTimes.first
        let targetDayStart = calendar.startOfDay(for: target)
        let overflows = (overallStart.map { $0 < targetDayStart }) ?? false

        var segments: [PlanSegment] = []
        for (i, step) in plan.steps.enumerated() {
            let mins = step.minutes
            guard mins > 0 else { continue }
            let start = startTimes[i]
            let name = step.name.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Step \(i + 1)"
                : step.name.trimmingCharacters(in: .whitespaces)
            segments.append(PlanSegment(
                id: step.id,
                name: name,
                minutes: mins,
                start: start,
                end: start.addingTimeInterval(TimeInterval(mins * 60))
            ))
        }

        return PlanResult(
            target: target,
            startTimes: startTimes,
            overallStart: overallStart,
            overflowsPrevDay: overflows,
            totalMinutes: totalMin,
            segments: segments,
            isPast: target < now
        )
    }
}

// MARK: - Formatting helpers (ports of the web fmtTime / fmtDuration)

enum Fmt {
    static func time(_ d: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: d)
        var h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let ampm = h >= 12 ? "PM" : "AM"
        h = h % 12
        if h == 0 { h = 12 }
        return String(format: "%d:%02d %@", h, m, ampm)
    }

    static func duration(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins - h * 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
