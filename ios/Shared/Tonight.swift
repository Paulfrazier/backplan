import Foundation

/// "When is lights out, really?" — the night pair's bridge, for the Tonight
/// widget. The Sleep Left widget asks the tracker's question (if I start now,
/// what do I get?); this one asks the pair's: given tomorrow's wake and the
/// sleep need, what is tonight's real deadline, when does the evening have to
/// start to make it, and does the bedtime the user set clear it?
///
/// Solved in the widget process from the same `SleepLeft.Inputs` snapshot, so
/// it also has to do the one thing the app does before it ever solves: decide
/// *which* night the evening plan means right now. The app does that by
/// normalizing dates (`PlanStore.normalizeDates`) on launch, on foreground and
/// every minute; the widget may be read days after the last save, so it
/// replays that rule on the snapshot instead.
///
/// KEEP IN SYNC with `NightBridge.make` / `liveText`, `PlanStore.chainedMorning`
/// and the linked branch of `PlanStore.normalizeDates`. `DebugSeed` asserts
/// this == `store.bridge()` at several clocks, stale snapshots included.
enum Tonight {
    /// `WidgetConfiguration` kind — the app reloads by this.
    static let widgetKind = "TonightWidget"

    /// Same four states as `NightBridge.Verdict`.
    enum Verdict: String, Sendable { case onTrack, tight, late, checkTimes }

    struct Night: Equatable, Sendable {
        let now: Date
        /// The bedtime the user set — the evening plan's target.
        let lightsOut: Date
        let morningTarget: Date
        let wake: Date
        /// The real bedtime deadline: wake − sleep need.
        let deadline: Date
        /// Last moment the evening can start and still make the deadline.
        let latestStart: Date
        let eveningMinutes: Int
        let slackMinutes: Int
        let actualSleepMinutes: Int
        let startNowLightsOut: Date
        let startNowSlackMinutes: Int
        let sleepNeed: Int
        /// False for the wake-up sheet's night: there is no bedtime the user set,
        /// so lights out is the deadline and the faces drop the "You set" verdict.
        var ownBedtime = true
        /// "the evening" for the pair (its evening plan); "wind-down" for the sheet's.
        private var startWhat: String { ownBedtime ? "the evening" : "wind-down" }

        var verdict: Verdict {
            if actualSleepMinutes > Self.nightMaxMinutes { return .checkTimes }
            if slackMinutes < 0 { return .late }
            if slackMinutes < 15 { return .tight }
            return .onTrack
        }

        /// KEEP IN SYNC with `NightBridge.nightMaxMinutes`.
        static let nightMaxMinutes = 16 * 60

        var pillText: String {
            switch verdict {
            case .onTrack: return "On track"
            case .tight: return "Tight"
            case .late: return "Too late"
            case .checkTimes: return "Check times"
            }
        }

        var minutesToLatestStart: Int { Int((latestStart.timeIntervalSince(now) / 60).rounded()) }

        /// `NightBridge.liveText`, word for word — the self-check compares the
        /// two strings, so a drift in either shows up as a FAIL.
        var liveText: String? {
            guard eveningMinutes > 0 else { return nil }
            if now >= deadline {
                return "Tonight\u{2019}s deadline has already passed."
            }
            if startNowSlackMinutes < 0 {
                return "Starting the evening now puts lights out at \(SleepLeft.time(startNowLightsOut)) \u{2014} "
                     + "\(SleepLeft.duration(-startNowSlackMinutes)) short. Trim a step, or take the loss."
            }
            if minutesToLatestStart <= 0 {
                return "Start now \u{2014} there is no slack left in tonight."
            }
            return "Start \(startWhat) by \(SleepLeft.time(latestStart)) \u{2014} \(SleepLeft.duration(minutesToLatestStart)) from now."
        }

        /// The same four cases cut to widget length.
        var liveShort: String? {
            guard eveningMinutes > 0 else { return nil }
            if now >= deadline { return "Deadline passed" }
            if startNowSlackMinutes < 0 {
                return "Starting now: \(SleepLeft.duration(-startNowSlackMinutes)) short"
            }
            if minutesToLatestStart <= 0 { return "Start now \u{2014} no slack left" }
            return "Start \(startWhat) by \(SleepLeft.time(latestStart)) \u{00B7} \(SleepLeft.duration(minutesToLatestStart)) from now"
        }

        /// The verdict on the bedtime the user typed, in one short line.
        var setLine: String {
            guard ownBedtime else { return "Lights out by \(SleepLeft.time(deadline))" }
            let set = SleepLeft.time(lightsOut)
            switch verdict {
            case .onTrack: return "Your \(set) leaves \(SleepLeft.duration(slackMinutes)) spare"
            case .tight:
                return slackMinutes == 0 ? "Your \(set) lands right on it" : "Your \(set) is tight"
            case .late: return "Your \(set) is \(SleepLeft.duration(-slackMinutes)) late"
            case .checkTimes: return "Check AM / PM on both times"
            }
        }
    }

    /// `nil` when the pair is off, or the snapshot predates the evening fields.
    static func solve(_ i: SleepLeft.Inputs, now: Date, calendar: Calendar = .current) -> Night? {
        if i.enabled, i.ownNight == true { return solveOwn(i, now: now, calendar: calendar) }
        guard i.enabled, let eveningTarget = i.eveningTarget else { return nil }
        let today = calendar.startOfDay(for: now)
        func addDays(_ n: Int, _ d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d) ?? d }

        // Which night. `Plan.effectiveDay`: the base date (today when missing or
        // malformed) plus one for Tomorrow.
        let base = i.eveningBaseDate.flatMap { dayStart($0, calendar) } ?? today
        var effective = addDays(i.eveningDay == "tomorrow" ? 1 : 0, base)
        // `normalizeDates`, linked: an evening whose date has gone by is last
        // night's, and stays put until the morning chained to it has gone by
        // too — then it rolls to the next occurrence of its clock time. (The
        // app also holds it while a plan is armed; the widget can't see that,
        // and an armed plan republishes on disarm anyway.)
        if effective < today && morning(after: effective, i, eveningTarget, calendar) <= now {
            effective = at(eveningTarget, on: today, calendar) > now ? today : addDays(1, today)
        }

        let lightsOut = at(eveningTarget, on: effective, calendar)
        let morningTarget = morning(after: effective, i, eveningTarget, calendar)
        let wake = morningTarget.addingTimeInterval(TimeInterval(-i.morningMinutes * 60))
        let deadline = wake.addingTimeInterval(TimeInterval(-i.sleepNeed * 60))
        let evening = i.windDownMinutes
        let startNowLightsOut = now.addingTimeInterval(TimeInterval(evening * 60))
        func mins(_ t: TimeInterval) -> Int { Int((t / 60).rounded()) }
        return Night(
            now: now,
            lightsOut: lightsOut,
            morningTarget: morningTarget,
            wake: wake,
            deadline: deadline,
            latestStart: deadline.addingTimeInterval(TimeInterval(-evening * 60)),
            eveningMinutes: evening,
            slackMinutes: mins(deadline.timeIntervalSince(lightsOut)),
            actualSleepMinutes: mins(wake.timeIntervalSince(lightsOut)),
            startNowLightsOut: startNowLightsOut,
            startNowSlackMinutes: mins(deadline.timeIntervalSince(startNowLightsOut)),
            sleepNeed: i.sleepNeed
        )
    }

    /// The wake-up sheet's night: wake is the next one that hasn't gone by (the
    /// Sleep Left rule — no evening plan to say which night), lights out is the
    /// deadline itself, and the wind-down is the sheet's own.
    private static func solveOwn(_ i: SleepLeft.Inputs, now: Date, calendar: Calendar) -> Night {
        let wake = SleepLeft.tonightWake(i, now: now, calendar: calendar)
        let morningTarget = wake.addingTimeInterval(TimeInterval(i.morningMinutes * 60))
        let deadline = wake.addingTimeInterval(TimeInterval(-i.sleepNeed * 60))
        let startNowLightsOut = now.addingTimeInterval(TimeInterval(i.windDownMinutes * 60))
        return Night(
            now: now, lightsOut: deadline, morningTarget: morningTarget, wake: wake,
            deadline: deadline,
            latestStart: deadline.addingTimeInterval(TimeInterval(-i.windDownMinutes * 60)),
            eveningMinutes: i.windDownMinutes,
            slackMinutes: 0,
            actualSleepMinutes: i.sleepNeed,
            startNowLightsOut: startNowLightsOut,
            startNowSlackMinutes: Int((deadline.timeIntervalSince(startNowLightsOut) / 60).rounded()),
            sleepNeed: i.sleepNeed,
            ownBedtime: false
        )
    }

    /// `PlanStore.chainedMorning`: the first morning target after lights out —
    /// the same day for a lights-out after midnight, else the next.
    private static func morning(after eveningDay: Date, _ i: SleepLeft.Inputs, _ eveningTarget: String,
                                _ calendar: Calendar) -> Date {
        let sameDay = minutes(i.morningTarget) > minutes(eveningTarget)
        let day = sameDay ? eveningDay : (calendar.date(byAdding: .day, value: 1, to: eveningDay) ?? eveningDay)
        return at(i.morningTarget, on: day, calendar)
    }

    // MARK: - Smart Stack

    /// High from two hours before the evening has to start until lights out
    /// (whichever of the set bedtime and the deadline is later), low otherwise —
    /// a bedtime widget has nothing to say at 10 AM. Shared by both night
    /// widgets so the stack doesn't flip between them.
    static func relevance(now: Date, start: Date, end: Date) -> Float {
        let lead = start.addingTimeInterval(-2 * 3600)
        guard now >= lead, now <= max(start, end) else { return 0.1 }
        // Ramp over the lead-in, so "start in 10 min" outranks "start in 2 hr".
        if now < start { return Float(0.6 + 0.4 * (now.timeIntervalSince(lead) / start.timeIntervalSince(lead))) }
        return 1
    }

    // MARK: - Date helpers (the widget can't see `Plan` / `LocalDay`)

    /// Mirrors `LocalDay.start`.
    static func dayStart(_ key: String, _ calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Mirrors `Plan.at` — clamped, seconds zeroed.
    static func at(_ hhmm: String, on day: Date, _ calendar: Calendar) -> Date {
        let parts = hhmm.split(separator: ":")
        let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return calendar.date(bySettingHour: min(max(h, 0), 23), minute: min(max(m, 0), 59),
                             second: 0, of: day) ?? day
    }

    static func minutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":").map { Int($0) ?? 0 }
        return (parts.first ?? 0) * 60 + (parts.count > 1 ? parts[1] : 0)
    }
}
