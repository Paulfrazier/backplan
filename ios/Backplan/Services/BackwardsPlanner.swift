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

/// Where the wall clock sits relative to a plan.
enum PlanPhase {
    case future  // hasn't started
    case active  // running
    case past    // target has come and gone
}

/// The one place that turns a `PlanResult` plus "now" into words. Both the
/// timeline's Now/Next block and the arm bar's countdown read from this — they
/// used to compute nearly-identical strings separately and drifted apart.
struct PlanStatus {
    let phase: PlanPhase
    /// Short column label: "Start" / "Now" / "Past".
    let key: String
    /// Value for the label column — reads as a fragment after `key`.
    let now: String
    /// Standalone form, for contexts with no label column (the arm bar).
    let headline: String
    /// What follows the current step. Empty when there is nothing after it.
    let next: String

    /// `precise` swaps minute-granular durations for an H:MM:SS clock, which is
    /// what the arm bar wants once a plan is actually running.
    static func make(result: PlanResult, now date: Date, precise: Bool = false) -> PlanStatus {
        guard let start = result.overallStart else {
            return PlanStatus(phase: .future, key: "Now", now: "no steps", headline: "No steps", next: "")
        }
        let end = result.target

        func span(_ interval: TimeInterval) -> String {
            precise ? clock(Int(interval)) : Fmt.duration(max(1, Int((interval / 60).rounded())))
        }
        func label(_ seg: PlanSegment) -> String { "\(seg.name) at \(Fmt.time(seg.start))" }

        if date < start {
            let ahead = span(start.timeIntervalSince(date))
            return PlanStatus(
                phase: .future,
                key: "Start",
                // No clock time here — the Next line already carries it, and the
                // first step always starts exactly at the chain start.
                now: "in \(ahead)",
                headline: "Starts in \(ahead)",
                next: result.segments.first.map(label) ?? ""
            )
        }

        if date > end {
            let over = Fmt.duration(max(1, Int((date.timeIntervalSince(end) / 60).rounded())))
            return PlanStatus(
                phase: .past,
                key: "Past",
                now: "target was \(over) ago",
                headline: "Target was \(over) ago",
                next: ""
            )
        }

        if let idx = result.segments.firstIndex(where: { date >= $0.start && date < $0.end }) {
            let cur = result.segments[idx]
            let body = "\(cur.name) · \(span(cur.end.timeIntervalSince(date))) left"
            let following = result.segments.indices.contains(idx + 1) ? result.segments[idx + 1] : nil
            return PlanStatus(
                phase: .active,
                key: "Now",
                now: body,
                headline: "Now: \(body)",
                next: following.map(label) ?? "Done at \(Fmt.time(end))"
            )
        }

        // Inside the window but between segments (only reachable with zero-length gaps).
        return PlanStatus(
            phase: .active,
            key: "Now",
            now: "in progress · target \(Fmt.time(end))",
            headline: "In progress · target \(Fmt.time(end))",
            next: ""
        )
    }

    /// H:MM:SS or M:SS countdown clock.
    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}
