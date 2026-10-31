import Foundation

/// "How much sleep is left?" — the figure the Sleep Left widget shows.
///
/// It is the track-to-sleep figure (`SleepTrack`) with the wall clock as its
/// near end: start the wind-down now (after the ride home, in track mode),
/// fall asleep at the end of it, and wake at the next morning target that
/// hasn't gone by, minus the morning routine. So it falls one minute per
/// minute — which is what lets the widget lay out its own timeline from a
/// handful of numbers, with the app not running.
///
/// The widget runs in its own process and cannot see `PlanStore`, so the app
/// publishes a `SleepLeft.Inputs` snapshot to the App Group on every save and
/// the widget solves from that. Shared source (`ios/Shared`) so the payload and
/// the arithmetic can't drift between the two processes.
///
/// KEEP IN SYNC with `NightSolve.trackMorningOffset` / `SleepTrack.make` in
/// `BackwardsPlanner.swift`. `DebugSeed.selfCheck` asserts the two agree.
enum SleepLeft {
    static let appGroup = "group.website.fairpoint.backplan"
    static let inputsKey = "backplan.sleepLeft"
    /// `WidgetConfiguration` kind — the app reloads by this.
    static let widgetKind = "SleepLeftWidget"

    /// What the app hands the widget. Plan-level inputs, not a solved night:
    /// a solved wake goes stale at that wake, while the inputs stay true every
    /// night until the user edits something.
    struct Inputs: Codable, Equatable, Sendable {
        /// The night pair is on. Off, there is no morning to count toward.
        var enabled: Bool
        /// Morning target, "HH:mm" 24h — the plan's own `target`.
        var morningTarget: String
        var morningName: String
        /// The morning routine; wake = morning target − this.
        var morningMinutes: Int
        /// The evening plan: the steps between starting the wind-down and lights out.
        var windDownMinutes: Int
        /// The routed ride home — only while track mode is on, mirroring the tracker.
        var rideMinutes: Int
        var sleepNeed: Int
        var sleeper: String

        static let preview = Inputs(enabled: true, morningTarget: "08:05", morningName: "School",
                                    morningMinutes: 70, windDownMinutes: 40, rideMinutes: 0,
                                    sleepNeed: 660, sleeper: "Ezra")
    }

    enum Verdict: String, Sendable { case onTrack, tight, short }

    /// One moment's reading.
    struct Night: Equatable, Sendable {
        let now: Date
        let morningTarget: Date
        let wake: Date
        /// Last moment to start (leaving, in track mode) that still buys the full need.
        let startBy: Date
        /// Floored: claiming a minute of sleep you don't have is the one error
        /// this number is not allowed to make (same rule as `SleepTrack`).
        let sleepMinutes: Int
        let sleepNeed: Int
        let chainMinutes: Int

        var deficitMinutes: Int { sleepNeed - sleepMinutes }
        /// Same thresholds as `SleepTrack.verdict`, so one night can't read
        /// "tight" on the widget and "on track" in the app.
        var verdict: Verdict {
            if deficitMinutes <= 0 { return .onTrack }
            if deficitMinutes <= 15 { return .tight }
            return .short
        }
        /// 0…1 of the need, for gauges.
        var fraction: Double {
            guard sleepNeed > 0 else { return 1 }
            return min(1, max(0, Double(sleepMinutes) / Double(sleepNeed)))
        }
        /// The moment the floor drops a minute — and after which "start by" has passed.
        var asleepIfNow: Date { now.addingTimeInterval(TimeInterval(chainMinutes * 60)) }
    }

    static func solve(_ inputs: Inputs, now: Date, calendar: Calendar = .current) -> Night {
        func target(dayOffset: Int) -> Date {
            let parts = inputs.morningTarget.split(separator: ":").map { Int($0) ?? 0 }
            let today = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: parts.first ?? 0,
                                 minute: parts.count > 1 ? parts[1] : 0,
                                 second: 0, of: day) ?? day
        }
        func wake(_ t: Date) -> Date { t.addingTimeInterval(TimeInterval(-inputs.morningMinutes * 60)) }

        // The next morning that hasn't happened yet: at 12:40 AM that is the
        // 6 AM five hours away, not the one 29 hours out.
        var morning = target(dayOffset: 0)
        if wake(morning) <= now { morning = target(dayOffset: 1) }
        let wakeAt = wake(morning)
        let chain = inputs.windDownMinutes + inputs.rideMinutes
        let asleep = now.addingTimeInterval(TimeInterval(chain * 60))
        return Night(
            now: now,
            morningTarget: morning,
            wake: wakeAt,
            startBy: wakeAt.addingTimeInterval(TimeInterval(-(inputs.sleepNeed + chain) * 60)),
            sleepMinutes: Int(floor(wakeAt.timeIntervalSince(asleep) / 60)),
            sleepNeed: inputs.sleepNeed,
            chainMinutes: chain
        )
    }

    // MARK: - Storage

    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> Inputs? {
        guard let data = sharedDefaults?.data(forKey: inputsKey) else { return nil }
        return try? JSONDecoder().decode(Inputs.self, from: data)
    }

    /// Returns true when the stored inputs actually changed — the caller only
    /// reloads the widget then, so typing in a step name costs nothing.
    @discardableResult
    static func save(_ inputs: Inputs) -> Bool {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(inputs) else { return false }
        if defaults.data(forKey: inputsKey) == data { return false }
        defaults.set(data, forKey: inputsKey)
        return true
    }

    // MARK: - Formatting (the widget can't see the app's `Fmt`)

    /// Mirrors `Fmt.sleep` — "9h 05m".
    static func hm(_ mins: Int) -> String {
        let m = max(0, mins)
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// Mirrors `Fmt.duration` — "45 min", "1 hr 20 min".
    static func duration(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// Mirrors `Fmt.time` — the user's own 12/24h format.
    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}
