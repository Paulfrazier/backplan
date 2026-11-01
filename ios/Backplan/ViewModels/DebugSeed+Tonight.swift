#if DEBUG
import Foundation

/// `-BPSelfCheck`, night widgets: the Tonight widget's solver against the
/// bridge card, the wake-up sheet's save, and the deep-link routes.
/// Launch args for screenshots:
///   -BPOpenURL <url>       follow a backplan:// link at launch (BackplanApp)
///   -BPGallery tonight     -BPWidgetGallery, Tonight faces only
///   -BPGallery standby     -BPWidgetGallery, StandBy faces only
extension DebugSeed {
    static func selfCheckTonight(at: (Int, Int, Int) -> Date, key: (Int) -> String,
                                 check: (String, Bool, String) -> Void) {
        let suite = "backplan.selfcheck.tonight"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PlanStore(defaults: defaults)

        /// The widget reads whatever the app last published, possibly days
        /// stale; the app normalizes first. Two paths, both must name the same
        /// night as the bridge card:
        ///  - cold: the app wasn't run since the snapshot, and opens at `now`
        ///    (reset to the saved pair, normalize once). Normalization is
        ///    path-dependent — a 9 AM roll lands tonight, a 9:30 PM one
        ///    tomorrow — so this is the only fair reading of a stale snapshot.
        ///  - warm: the app ran all along (normalized at every clock in turn)
        ///    and republished, so the widget reads the store's fresh inputs.
        func compare(_ label: String, _ times: [(Int, Int, Int)]) {
            let saved = store.pair
            let stale = store.sleepLeftInputs
            func agree(_ which: String, _ inputs: SleepLeft.Inputs, _ now: Date, _ tag: String) {
                guard let card = store.bridge(now: now), let w = Tonight.solve(inputs, now: now) else {
                    check("tonight \(label) \(which) \(tag) solves", false, "nil")
                    return
                }
                let same = w.lightsOut == card.lightsOut && w.morningTarget == card.morningTarget
                    && w.wake == card.wake && w.deadline == card.deadline
                    && w.latestStart == card.latestStart && w.slackMinutes == card.slackMinutes
                    && w.actualSleepMinutes == card.actualSleepMinutes
                    && w.startNowSlackMinutes == card.startNowSlackMinutes
                    && w.pillText == card.pillText && w.liveText == card.liveText(now: now)
                check("tonight == bridge, \(label) \(which) \(tag)", same,
                      "widget out \(w.lightsOut) dl \(w.deadline) \(w.pillText) \"\(w.liveText ?? "nil")\" vs "
                      + "card out \(card.lightsOut) dl \(card.deadline) \(card.pillText) \"\(card.liveText(now: now) ?? "nil")\"")
            }
            for (d, h, m) in times {
                let now = at(d, h, m)
                store.pair = saved
                store.normalizeDates(now: now)
                agree("cold", stale, now, "d\(d) \(h):\(String(format: "%02d", m))")
            }
            store.pair = saved
            for (d, h, m) in times {
                let now = at(d, h, m)
                store.normalizeDates(now: now)
                agree("warm", store.sleepLeftInputs, now, "d\(d) \(h):\(String(format: "%02d", m))")
            }
        }

        store.link.enabled = true
        store.link.sleepNeed = 660
        let bath = [Step(name: "Bath", duration: 25), Step(name: "Books", duration: 15)]
        let school = [Step(name: "Breakfast", duration: 40), Step(name: "Bike", duration: 30)]

        // A school night planned at lunch, read through the evening, past
        // midnight, before the school run (held) and after it (rolled).
        store.pair = PlanPair(
            evening: Plan(eventName: "Bed", target: "21:00", day: .today, steps: bath, baseDate: key(0)),
            morning: Plan(eventName: "School", target: "08:05", day: .tomorrow, steps: school, baseDate: key(0)))
        compare("school night", [(0, 12, 0), (0, 18, 30), (0, 19, 44), (0, 19, 55), (0, 20, 30), (0, 22, 0),
                                 (1, 0, 40), (1, 6, 55), (1, 9, 0)])

        // Saved yesterday, never reopened: held at dawn, rolled after school.
        store.pair = PlanPair(
            evening: Plan(eventName: "Bed", target: "21:00", day: .today, steps: bath, baseDate: key(-1)),
            morning: Plan(eventName: "School", target: "08:05", day: .tomorrow, steps: school, baseDate: key(-1)))
        compare("saved yesterday", [(0, 6, 55), (0, 9, 0), (0, 21, 30)])

        // Days stale, read after tonight's lights-out time: rolls to tomorrow.
        store.pair.evening.baseDate = key(-3)
        store.pair.morning.baseDate = key(-3)
        compare("three days stale", [(0, 22, 15)])

        // Planned for tomorrow evening on purpose: stays tomorrow.
        store.pair.evening = Plan(eventName: "Bed", target: "21:00", day: .tomorrow, steps: bath, baseDate: key(0))
        compare("tomorrow on purpose", [(0, 14, 0)])

        // Lights out after midnight: that same morning, not one 31 hr away.
        store.pair.evening = Plan(eventName: "Bed", target: "00:30", day: .tomorrow, steps: bath, baseDate: key(0))
        compare("12:30 AM lights-out", [(0, 20, 0), (1, 0, 10), (1, 7, 0)])

        // Late, tight and AM/PM-swapped verdicts.
        store.pair.evening = Plan(eventName: "Bed", target: "21:30", day: .today, steps: bath, baseDate: key(0))
        compare("late", [(0, 19, 0)])
        store.pair.evening.target = "19:45"
        compare("tight", [(0, 19, 0)])
        store.pair.evening.target = "22:00"
        store.pair.morning.target = "21:00"
        compare("check times", [(0, 12, 0)])

        // No evening steps: no live line on either side.
        store.pair = PlanPair(
            evening: Plan(eventName: "Bed", target: "21:00", day: .today, steps: [], baseDate: key(0)),
            morning: Plan(eventName: "School", target: "08:05", day: .tomorrow, steps: school, baseDate: key(0)))
        compare("no evening steps", [(0, 19, 0)])

        // A payload from before Tonight existed still decodes, and Tonight
        // reads it as "not set up" rather than guessing an evening.
        let old = #"{"enabled":true,"morningTarget":"08:05","morningName":"School","morningMinutes":70,"windDownMinutes":40,"rideMinutes":0,"sleepNeed":660,"sleeper":"Ezra"}"#
        let decoded = try? JSONDecoder().decode(SleepLeft.Inputs.self, from: Data(old.utf8))
        check("pre-Tonight payload decodes", decoded != nil && decoded?.eveningTarget == nil, "")
        check("pre-Tonight payload shows set-up, not a guess",
              decoded.map { Tonight.solve($0, now: at(0, 19, 0)) == nil } ?? false, "")
        check("Sleep Left still reads a pre-Tonight payload",
              decoded.map { SleepLeft.solve($0, now: at(0, 19, 0)).sleepNeed == 660 } ?? false, "")

        // Smart Stack: high in the run-up and through lights out, low by day.
        if let n = Tonight.solve(SleepLeft.Inputs.preview, now: at(0, 12, 0)) {
            let end = max(n.lightsOut, n.deadline)
            let r = { (t: Date) in Tonight.relevance(now: t, start: n.latestStart, end: end) }
            check("relevance low at noon", r(at(0, 12, 0)) < 0.2, "\(r(at(0, 12, 0)))")
            check("relevance rises before start-by",
                  r(n.latestStart.addingTimeInterval(-90 * 60)) < r(n.latestStart.addingTimeInterval(-10 * 60))
                  && r(n.latestStart.addingTimeInterval(-90 * 60)) >= 0.6, "")
            check("relevance full through lights out", r(end.addingTimeInterval(-60)) == 1, "")
            check("relevance low after lights out", r(end.addingTimeInterval(30 * 60)) < 0.2, "")
        }

        // The wake-up sheet: its own night (wake + need + wind-down). It must not
        // switch the chain on — that re-read an 88-min errand plan as bedtime and
        // put "21h" on the Lock Screen — nor seed a morning routine.
        store.link = NightLink()
        store.pair.morning = Plan(eventName: "", target: "08:15", day: .tomorrow, steps: [], baseDate: key(0))
        store.saveSleep(morningTarget: "06:45", sleepNeed: 600, sleeper: " Ezra ", windDown: 30)
        let own = store.sleepLeftInputs
        check("sleep sheet leaves the chain alone", !store.link.enabled && store.link.windDown == 30, "")
        check("sleep sheet's night reaches the widgets",
              own.enabled && own.ownNight == true && own.windDownMinutes == 30 && own.eveningTarget == nil, "\(own)")
        check("sleep sheet does not seed a morning", store.pair.morning.steps.isEmpty,
              "\(store.pair.morning.steps.count) steps")
        check("sleep sheet writes the store's fields",
              store.pair.morning.target == "06:45" && store.link.sleepNeed == 600 && store.link.sleeper == "Ezra",
              "\(store.pair.morning.target) \(store.link.sleepNeed) \(store.link.sleeper)")
        check("bare wake: wake is the target", !store.wakeIsDerived
              && SleepLeft.solve(own, now: at(0, 12, 0)).wake == at(1, 6, 45), "")
        let tn = Tonight.solve(own, now: at(0, 12, 0))
        check("own night: Tonight's lights out is the deadline",
              tn?.deadline == at(0, 20, 45) && tn?.lightsOut == tn?.deadline && tn?.ownBedtime == false
                && tn?.latestStart == at(0, 20, 15), "\(String(describing: tn?.deadline))")
        // Daytime: the full need, not "21h".
        let morn = SleepLeft.solve(own, now: at(0, 7, 37))
        check("daytime shows the full night", morn.hasRoom && morn.shownMinutes == 600 && morn.verdict == .onTrack,
              "\(morn.sleepMinutes) shown \(morn.shownMinutes)")
        // With a routine, the edited time is the obligation; wake follows.
        store.pair.morning.steps = school
        store.saveSleep(morningTarget: "08:10", sleepNeed: 600, sleeper: "Ezra", windDown: 30)
        check("routine: target moves, wake derived", store.wakeIsDerived
              && SleepLeft.solve(store.sleepLeftInputs, now: at(0, 12, 0)).wake == at(1, 7, 0), "")
        // Chaining is the explicit "my evening plan is bedtime": it clears the sheet's night.
        store.setLinkEnabled(true)
        check("chaining clears the sheet's wind-down",
              store.link.windDown == nil && store.sleepLeftInputs.eveningTarget != nil, "")
        // Up before the alarm: 7:41 AM, wake 8:15, 11 h. Tonight is tonight's,
        // not last night's.
        do {
            let i = SleepLeft.Inputs(enabled: true, morningTarget: "08:15", morningName: "", morningMinutes: 0,
                                     windDownMinutes: 0, rideMinutes: 0, sleepNeed: 660, sleeper: "")
            let w = SleepLeft.tonightWake(i, now: at(0, 7, 41))
            check("up before the alarm: tonight's wake is tomorrow's", w == at(1, 8, 15), "\(w)")
            check("1 AM: tonight's wake is still this morning's",
                  SleepLeft.tonightWake(i, now: at(0, 1, 0)) == at(0, 8, 15), "")
        }
        // Nov 1 2026, 7:37 AM (US clocks fell back at 2 AM): wake 6:20, 8 h. The
        // first sheet anchored 6:20 to *today* and walked back across the extra
        // hour to "11:20 PM". Tonight's answer is 10:20 PM.
        if let nov1 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 7, minute: 37)) {
            let i = SleepLeft.Inputs(enabled: true, morningTarget: "06:20", morningName: "", morningMinutes: 0,
                                     windDownMinutes: 0, rideMinutes: 0, sleepNeed: 480, sleeper: "")
            let n = SleepLeft.solve(i, now: nov1)
            let c = Calendar.current.dateComponents([.day, .hour, .minute], from: n.lightsOutBy)
            check("Nov 1: 6:20 wake, 8 h -> lights out 10:20 PM tonight",
                  c.day == 1 && c.hour == 22 && c.minute == 20, "\(c)")
        }

        // Deep links.
        let routes: [(String, DeepLink?)] = [
            ("backplan://sleep", .sleep), ("backplan://now", .now), ("backplan://day", .day),
            ("backplan://kid", .kid), ("BACKPLAN://Sleep", .sleep), ("backplan:sleep", .sleep),
            ("backplan://nope", nil), ("https://sleep", nil),
        ]
        for (s, want) in routes {
            check("deep link \(s)", URL(string: s).flatMap(DeepLink.init) == want, "")
        }
        check("deep link round-trips", DeepLink.allCases.allSatisfy { DeepLink($0.url) == $0 }, "")

        defaults.removePersistentDomain(forName: suite)
    }
}
#endif
