import Foundation

/// One step's resolved placement on the timeline.
/// `Codable` so an armed plan can be frozen to disk — see `TimerController`.
struct PlanSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let minutes: Int
    let start: Date
    let end: Date
}

/// Result of walking a plan backwards from its target time.
/// Pure data — produced by `BackwardsPlanner.compute` and consumed by the UI
/// and the notification scheduler alike. `Codable` because arming freezes one
/// and reloads it next launch rather than re-deriving (see `TimerController`).
struct PlanResult: Codable, Hashable {
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

    /// H:MM:SS (or M:SS under an hour). Only the live countdown wants this —
    /// everywhere else a minute is the smallest unit anyone acts on. Mirrors
    /// the web `fmtClock`.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    static func clock(_ interval: TimeInterval) -> String {
        clock(Int(interval.rounded()))
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
    /// Index into `result.segments` of the running step; -1 outside one.
    var index: Int = -1

    /// `precise` swaps minute-granular durations for an H:MM:SS clock, which is
    /// what the arm bar wants once a plan is actually running.
    static func make(result: PlanResult, now date: Date, precise: Bool = false) -> PlanStatus {
        guard let start = result.overallStart else {
            return PlanStatus(phase: .future, key: "Now", now: "no steps", headline: "No steps", next: "")
        }
        let end = result.target

        func span(_ interval: TimeInterval) -> String {
            precise ? Fmt.clock(Int(interval)) : Fmt.duration(max(1, Int((interval / 60).rounded())))
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
                next: following.map(label) ?? "Done at \(Fmt.time(end))",
                index: idx
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

}

/// What the live countdown *counts to*, as opposed to what `PlanStatus` says is
/// happening. The two are deliberately separate: the status line names the step,
/// this names the next moment the plan changes state — the chain start before it
/// begins, the end of the running step while it does, the target once the last
/// step is running. A clock aimed at anything else runs past zero and stops
/// meaning anything.
///
/// KEEP IN SYNC with the web `tickArm()` in index.html.
struct PlanCountdown {
    let phase: PlanPhase
    /// Label above the clock: "Starts in" / "Next step in" / "Target in" / "Over by".
    let label: String
    /// The moment the clock is counting to (or, when past, counting up from).
    let boundary: Date
    /// Where that interval began. Only `Text(timerInterval:)` and progress bars
    /// need it; the in-app clock just wants `boundary`.
    let windowStart: Date
    /// Pill copy: "Not started" / "Start now" / "Step 2 of 5" / "Running over".
    let phaseWord: String
    /// The step the user is (or is about to be) on.
    let detail: String
    /// 1-based position of that step; 0 when the plan is not inside one.
    let stepNumber: Int
    let stepCount: Int

    var status: PlanStatus

    /// `armedAt` only sets the *start* of the pre-plan interval, so a progress
    /// bar before the first step has something to fill from.
    static func make(result: PlanResult, now: Date, armedAt: Date) -> PlanCountdown? {
        let segments = result.segments
        guard let first = segments.first else { return nil }
        let status = PlanStatus.make(result: result, now: now, precise: true)
        let end = result.target

        if now < first.start {
            let toStart = first.start.timeIntervalSince(now)
            return PlanCountdown(
                phase: .future,
                label: "Starts in",
                boundary: first.start,
                windowStart: min(armedAt, now),
                // Inside the last minute, "not started" is the wrong word — this
                // is the moment the whole plan exists to produce.
                phaseWord: toStart <= 60 ? "Start now" : "Not started",
                detail: "\(first.name) at \(Fmt.time(first.start))",
                stepNumber: 0,
                stepCount: segments.count,
                status: status
            )
        }

        if now > end {
            return PlanCountdown(
                phase: .past,
                label: "Over by",
                boundary: end,
                windowStart: end,
                phaseWord: "Running over",
                detail: "Target was \(Fmt.time(end))",
                stepNumber: 0,
                stepCount: segments.count,
                status: status
            )
        }

        if status.index >= 0 {
            let cur = segments[status.index]
            let isLast = status.index == segments.count - 1
            return PlanCountdown(
                phase: .active,
                label: isLast ? "Target in" : "Next step in",
                boundary: cur.end,
                windowStart: cur.start,
                phaseWord: "Step \(status.index + 1) of \(segments.count)",
                detail: cur.name,
                stepNumber: status.index + 1,
                stepCount: segments.count,
                status: status
            )
        }

        // Inside the window but between segments — only reachable with zero-length gaps.
        return PlanCountdown(
            phase: .active,
            label: "Target in",
            boundary: end,
            windowStart: first.start,
            phaseWord: "In progress",
            detail: "Between steps",
            stepNumber: 0,
            stepCount: segments.count,
            status: status
        )
    }

    /// The next moment the countdown's own copy goes out of date. Drives both
    /// the in-app refresh loop and the Live Activity's `staleDate`.
    static func nextChange(result: PlanResult, now: Date) -> Date? {
        var marks = result.segments.map(\.start)
        marks.append(result.target)
        // The "Start now" flip a minute before the chain start is a copy change
        // with no boundary behind it, so it has to be listed explicitly.
        if let first = result.segments.first {
            marks.append(first.start.addingTimeInterval(-60))
        }
        return marks.filter { $0 > now }.min()
    }
}

// MARK: - The night edge

/// Tonight's lights-out and tomorrow's wake as one chain, with sleep as the
/// elastic middle. Solvable in one direction only, which is what makes it
/// useful: the morning target is fixed (a school bell does not move), so
/// `wake = morning target − morning steps` and `deadline = wake − sleep need`.
/// Everything else is a comparison against that deadline.
///
/// Direct port of the web `computeLink()` — keep the two in sync.
struct NightBridge {
    enum Verdict { case onTrack, tight, late }

    let morningTarget: Date
    let wake: Date
    /// The real bedtime deadline — routinely earlier than the one the user set.
    let deadline: Date
    /// The evening plan's target, which under this model *is* lights-out.
    let lightsOut: Date
    let eveningMinutes: Int
    /// Positive = room to spare before the deadline.
    let slackMinutes: Int
    let actualSleepMinutes: Int
    let startNowLightsOut: Date
    let startNowSlackMinutes: Int
    let latestStart: Date

    var verdict: Verdict {
        if slackMinutes < 0 { return .late }
        if slackMinutes < 15 { return .tight }
        return .onTrack
    }

    var pillText: String {
        switch verdict {
        case .onTrack: return "On track"
        case .tight: return "Tight"
        case .late: return "Too late"
        }
    }

    static func make(
        evening: Plan, eveningOffset: Int,
        morning: Plan, morningOffset: Int,
        sleepNeed: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NightBridge {
        let morningTarget = morning.targetDate(now: now, calendar: calendar, dayOffset: morningOffset)
        let wake = morningTarget.addingTimeInterval(TimeInterval(-morning.totalMinutes * 60))
        let deadline = wake.addingTimeInterval(TimeInterval(-sleepNeed * 60))
        let lightsOut = evening.targetDate(now: now, calendar: calendar, dayOffset: eveningOffset)
        let eveningMinutes = evening.totalMinutes

        // "If the whole evening started right now" — a projection that needs no
        // progress tracking, which is the timer feature's job, not this one's.
        let startNowLightsOut = now.addingTimeInterval(TimeInterval(eveningMinutes * 60))
        let latestStart = deadline.addingTimeInterval(TimeInterval(-eveningMinutes * 60))

        func mins(_ interval: TimeInterval) -> Int { Int((interval / 60).rounded()) }

        return NightBridge(
            morningTarget: morningTarget,
            wake: wake,
            deadline: deadline,
            lightsOut: lightsOut,
            eveningMinutes: eveningMinutes,
            slackMinutes: mins(deadline.timeIntervalSince(lightsOut)),
            actualSleepMinutes: mins(wake.timeIntervalSince(lightsOut)),
            startNowLightsOut: startNowLightsOut,
            startNowSlackMinutes: mins(deadline.timeIntervalSince(startNowLightsOut)),
            latestStart: latestStart
        )
    }

    /// Wording mirrors the web `renderLink()` verbatim so the two platforms say
    /// the same thing about the same plan.
    func verdictText(sleeper: String, sleepNeed: Int) -> String {
        let who = sleeper.trimmingCharacters(in: .whitespaces)
        let need = Fmt.duration(sleepNeed)
        let sleepPhrase = who.isEmpty ? "\(need) needed" : "\(who) needs \(need)"
        let slept = Fmt.duration(max(0, actualSleepMinutes))

        switch verdict {
        case .late:
            return "Lights out at \(Fmt.time(lightsOut)) is \(Fmt.duration(-slackMinutes)) past the deadline. "
                 + "Wake at \(Fmt.time(wake)) gives \(slept) — \(sleepPhrase)."
        case .tight:
            // Fmt.duration(0) is "0 min", which reads as a rounding artefact
            // rather than the exact landing it actually is.
            let lands = slackMinutes == 0
                ? "Lights out at \(Fmt.time(lightsOut)) lands exactly on the deadline."
                : "Lights out at \(Fmt.time(lightsOut)) clears the deadline by \(Fmt.duration(slackMinutes))."
            return "\(lands) Any slip tonight comes out of tomorrow — \(sleepPhrase)."
        case .onTrack:
            return "Lights out at \(Fmt.time(lightsOut)) leaves \(Fmt.duration(slackMinutes)) of room — "
                 + "\(slept) of sleep, \(sleepPhrase)."
        }
    }

    /// The line that moves on the clock. `nil` when the evening plan has no
    /// steps, since there is then no start time to advise.
    func liveText(now: Date = Date()) -> String? {
        guard eveningMinutes > 0 else { return nil }
        let toLatest = Int((latestStart.timeIntervalSince(now) / 60).rounded())
        if now >= deadline {
            return "Tonight\u{2019}s deadline has already passed."
        }
        if startNowSlackMinutes < 0 {
            return "Starting the evening now puts lights out at \(Fmt.time(startNowLightsOut)) — "
                 + "\(Fmt.duration(-startNowSlackMinutes)) short. Trim a step, or take the loss."
        }
        if toLatest <= 0 {
            return "Start now — there is no slack left in tonight."
        }
        return "Start the evening by \(Fmt.time(latestStart)) — \(Fmt.duration(toLatest)) from now."
    }
}
