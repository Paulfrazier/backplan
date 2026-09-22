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
        compute(plan, endingAt: plan.targetDate(now: now, calendar: calendar), now: now, calendar: calendar)
    }

    /// Explicit-end form. Track mode's wind-down doesn't end at a bedtime anyone
    /// typed — it ends wherever "leave now" lands you — so its rows have to be
    /// walked back from that instead, which also places the first of them
    /// exactly at now + the ride, when you actually walk in the door.
    static func compute(
        _ plan: Plan, endingAt target: Date,
        now: Date = Date(), calendar: Calendar = .current
    ) -> PlanResult {
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

    /// Compact form for the one number big enough that "7 hr 12 min" would wrap.
    static func sleep(_ mins: Int) -> String {
        let m = max(0, mins)
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// H:MM:SS / M:SS countdown clock. The arm bar's running plan and the
    /// tracker's departure deadline are the two things genuinely counting down,
    /// so they get a seconds hand; everything else stays minute-grain.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
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
}

// MARK: - The night edge

/// The half of the night chain both lenses share: the morning obligation minus
/// the morning routine is wake, and wake minus the sleep need is the real
/// lights-out deadline. The pair and the tracker both read it, and they must
/// never drift into two different answers for "when is lights out really", so
/// the solve lives here once. They differ in exactly one input — which day the
/// morning obligation lands on.
///
/// Direct port of the web `solveNight()` — keep the two in sync.
struct NightSolve {
    let morningTarget: Date
    let morningMinutes: Int
    let wake: Date
    /// The real bedtime deadline — routinely earlier than the one the user set.
    let deadline: Date

    static func solve(
        morning: Plan, morningOffset: Int, sleepNeed: Int,
        now: Date = Date(), calendar: Calendar = .current
    ) -> NightSolve {
        let morningTarget = morning.targetDate(now: now, calendar: calendar, dayOffset: morningOffset)
        let wake = morningTarget.addingTimeInterval(TimeInterval(-morning.totalMinutes * 60))
        return NightSolve(
            morningTarget: morningTarget,
            morningMinutes: morning.totalMinutes,
            wake: wake,
            deadline: wake.addingTimeInterval(TimeInterval(-sleepNeed * 60))
        )
    }

    /// Track mode has no day toggle, so the morning obligation is simply the
    /// next one that hasn't happened yet. That is not a restatement of the
    /// pair's rule: the pair derives the morning from the *evening plan's*
    /// Today / Tomorrow choice, which cannot express "it is 12:40am and I want
    /// the 6am that's five hours away, not the one 29 hours out" — the exact
    /// case a mode for people still out at night has to get right.
    static func trackMorningOffset(
        morning: Plan, sleepNeed: Int, now: Date = Date(), calendar: Calendar = .current
    ) -> Int {
        solve(morning: morning, morningOffset: 0, sleepNeed: sleepNeed,
              now: now, calendar: calendar).wake > now ? 0 : 1
    }
}

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
        let solved = NightSolve.solve(morning: morning, morningOffset: morningOffset,
                                      sleepNeed: sleepNeed, now: now, calendar: calendar)
        let morningTarget = solved.morningTarget
        let wake = solved.wake
        let deadline = solved.deadline
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

// MARK: - Track to sleep

/// The same night edge as `NightBridge`, anchored at now instead of at a bedtime
/// you typed: leave now → travel home → the wind-down → asleep → the wake you
/// can't move. Everything downstream of wake is shared (same `NightSolve`, same
/// sleep need, same deadline); what this adds is the ride home and a near end
/// that drifts on its own, one minute of sleep per minute spent deciding.
///
/// Direct port of the web `computeTrack()` — keep the two in sync, wording
/// included, so the platforms say the same thing about the same night.
struct SleepTrack {
    enum Verdict { case onTrack, tight, short }

    let morningTarget: Date
    let morningMinutes: Int
    let wake: Date
    let deadline: Date
    /// 0 when the leg is unresolved — an unrouted ride contributes nothing
    /// rather than a guess, because a made-up number would be
    /// indistinguishable from a routed one in the headline figure.
    let rideMinutes: Int
    /// The evening plan *is* the wind-down: the steps between walking in the
    /// door and lights out. Track mode does not own a second step list.
    let windDownMinutes: Int
    let chainMinutes: Int
    let asleepAt: Date
    let sleepMinutes: Int
    let deficitMinutes: Int
    /// The latest departure that still buys the full sleep need.
    let leaveBy: Date
    let secondsToLeaveBy: Int

    /// The same three states and the same 15-minute band as the bridge, so one
    /// night can't read "tight" in one lens and "fine" in the other.
    var verdict: Verdict {
        if deficitMinutes <= 0 { return .onTrack }
        if deficitMinutes <= 15 { return .tight }
        return .short
    }

    var pillText: String {
        switch verdict {
        case .onTrack: return "On track"
        case .tight: return "Tight"
        case .short: return "Short"
        }
    }

    static func make(
        evening: Plan, morning: Plan,
        sleepNeed: Int, rideMinutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepTrack {
        let offset = NightSolve.trackMorningOffset(morning: morning, sleepNeed: sleepNeed,
                                                   now: now, calendar: calendar)
        let solved = NightSolve.solve(morning: morning, morningOffset: offset,
                                      sleepNeed: sleepNeed, now: now, calendar: calendar)
        let windDown = evening.totalMinutes
        let chain = rideMinutes + windDown
        let asleepAt = now.addingTimeInterval(TimeInterval(chain * 60))
        // Floor, not round. Claiming a minute of sleep you don't have is the one
        // error this number is not allowed to make.
        let sleepMinutes = Int(floor(solved.wake.timeIntervalSince(asleepAt) / 60))
        // The inverse question, off the same deadline the bridge uses: walk the
        // chain back from it instead of comparing a chosen bedtime against it.
        let leaveBy = solved.deadline.addingTimeInterval(TimeInterval(-chain * 60))

        return SleepTrack(
            morningTarget: solved.morningTarget,
            morningMinutes: solved.morningMinutes,
            wake: solved.wake,
            deadline: solved.deadline,
            rideMinutes: rideMinutes,
            windDownMinutes: windDown,
            chainMinutes: chain,
            asleepAt: asleepAt,
            sleepMinutes: sleepMinutes,
            deficitMinutes: sleepNeed - sleepMinutes,
            leaveBy: leaveBy,
            secondsToLeaveBy: Int(leaveBy.timeIntervalSince(now).rounded())
        )
    }

    /// The sub-line under the figure: where the chain lands and what it's measured against.
    func chainText(sleepNeed: Int) -> String {
        "asleep by \(Fmt.time(asleepAt)) · wake \(Fmt.time(wake)) · need \(Fmt.duration(sleepNeed))"
    }

    func verdictText(sleepNeed: Int) -> String {
        let need = Fmt.duration(sleepNeed)
        if chainMinutes <= 0 {
            // Nothing between standing up and being asleep: the figure is still
            // true, but it isn't a plan and shouldn't be dressed as one.
            return "Nothing counted between here and asleep yet — add the trip home above, or a wind-down below."
        }
        if secondsToLeaveBy > 0 {
            return "Leave by \(Fmt.time(leaveBy)) and the full \(need) still fits — \(Fmt.clock(secondsToLeaveBy)) from now."
        }
        return "The full \(need) needed leaving by \(Fmt.time(leaveBy)) — \(Fmt.clock(-secondsToLeaveBy)) ago. "
             + "Every minute here is a minute of sleep: trim the wind-down below, or take the loss."
    }
}
