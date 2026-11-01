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

        // The wake-up sheet: a bare wake turns the night on WITHOUT seeding a
        // morning routine (which would move wake an hour), and writes the
        // store's own fields.
        store.link = NightLink()
        store.pair.morning = Plan(eventName: "", target: "08:15", day: .tomorrow, steps: [], baseDate: key(0))
        store.saveSleep(morningTarget: "06:45", sleepNeed: 600, sleeper: " Ezra ")
        check("sleep sheet turns the night on", store.link.enabled, "")
        check("sleep sheet does not seed a morning", store.pair.morning.steps.isEmpty,
              "\(store.pair.morning.steps.count) steps")
        check("sleep sheet writes the store's fields",
              store.pair.morning.target == "06:45" && store.link.sleepNeed == 600 && store.link.sleeper == "Ezra",
              "\(store.pair.morning.target) \(store.link.sleepNeed) \(store.link.sleeper)")
        check("bare wake: wake is the target", !store.wakeIsDerived
              && store.bridge(now: at(0, 12, 0))?.wake == at(1, 6, 45), "")
        // With a routine, the edited time is the obligation; wake follows.
        store.pair.morning.steps = school
        store.saveSleep(morningTarget: "08:10", sleepNeed: 600, sleeper: "Ezra")
        check("routine: target moves, wake derived", store.wakeIsDerived
              && store.bridge(now: at(0, 12, 0))?.wake == at(1, 7, 0), "")

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
