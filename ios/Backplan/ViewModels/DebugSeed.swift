#if DEBUG
import Foundation

/// Launch-argument state for simulator screenshots — the simulator can't take
/// injected touches, so every screen state has to be reachable from launch.
///   -BPDemo      reset to the climbing → pick-up scenario
///   -BPAddToDay  then run "Add to Day" and edit the plan (exercises the link)
///   -BPExpand    show every plan-block's steps
///   -BPTab day   open on a tab
///   -BPArmDay    start the Day countdown (BackplanApp)
///   -BPRollover  a plan saved *yesterday* as "tomorrow, 90 min from now" —
///                launch normalization must read it as today, same moment
///   -BPRolloverPair  the night pair saved yesterday (bedtime + school run)
///   -BPSelfCheck run the date-model checks below and print BPCHECK lines
///   -BPKid       open Kid view at launch (sets backplan.kidView)
///   -BPWidgetGallery  show every Sleep Left widget family (BackplanApp)
///   -BPCountdownGallery [armed|morning|idle|live]  Countdown widget faces
///   -BPMorningDemo N  night pair on, School bell N min from now (negative:
///                gone by), evening = last night; nothing armed
///   -BPIntent done|late|start  run that intent through the installed handler
///   -BPWidgetCheck  arm the open plan, then Done, +5, disarm — checking the
///                App Group chain against the timer after each (BPCHECK lines)
@MainActor
enum DebugSeed {
    static let home = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
                                 name: "Home", label: "3703 NE 22nd Ave", lat: 45.5497, lng: -122.6434, isHome: true)
    static let gym = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
                                name: "Climbing gym", label: "The Circuit NE", lat: 45.5352, lng: -122.6402)
    static let school = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!,
                                   name: "School", label: "Sabin", lat: 45.5536, lng: -122.6494)

    static func applyIfRequested(_ defaults: UserDefaults = .standard) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-BPSelfCheck") { selfCheck() }
        if args.contains("-BPRollover") || args.contains("-BPRolloverPair") {
            seedRollover(defaults, pair: args.contains("-BPRolloverPair"))
            return
        }
        if args.contains("-BPKid") { defaults.set(true, forKey: "backplan.kidView") }
        if let i = args.firstIndex(of: "-BPTab"), args.indices.contains(i + 1) {
            defaults.set(args[i + 1], forKey: "backplan.mode")
        }
        //   -BPSkin now|classic   pick the skin
        if let i = args.firstIndex(of: "-BPSkin"), args.indices.contains(i + 1) {
            defaults.set(args[i + 1], forKey: Skin.storageKey)
        }
        //   -BPNowDemo   a plan already under way (target now+40, 45 min of steps)
        //                and an empty Day, so the Now preview picks the plan.
        //   Pair with -BPArmPlan / -BPDone / -BPLate N (BackplanApp).
        if args.contains("-BPNowDemo") {
            let enc = JSONEncoder()
            let target = Date().addingTimeInterval(40 * 60)
            let c = Calendar.current.dateComponents([.hour, .minute], from: target)
            // Near midnight "now + 40" is tomorrow's clock time.
            let day: TargetDay = Calendar.current.isDateInToday(target) ? .today : .tomorrow
            let plan = Plan(eventName: "School", target: String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0),
                            day: day, steps: [
                Step(name: "Pack bag", duration: 15, unit: .min),
                Step(name: "Shoes on", duration: 5, unit: .min),
                Step(name: "Bike to School", duration: 25, unit: .min),
            ])
            defaults.removeObject(forKey: "backplan.armed")
            defaults.set(try? enc.encode(plan), forKey: "backplan.last")
            defaults.set(try? enc.encode(DayPlan(date: .today, blocks: [])), forKey: "backplan.day")
            return
        }
        //   -BPNowDayDemo   a Day with "Errands" running (pinned 10 min ago, 30 min)
        //                   then a 35-min gap before "Climb". Pair with -BPArmDay.
        if args.contains("-BPNowDayDemo") {
            let cal = Calendar.current
            func hhmm(_ d: Date) -> String {
                let c = cal.dateComponents([.hour, .minute], from: d)
                return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
            let start = Date().addingTimeInterval(-10 * 60)
            defaults.removeObject(forKey: "backplan.armed")
            defaults.set(try? JSONEncoder().encode(DayPlan(date: .today, blocks: [
                DayBlock(name: "Errands", duration: 30, unit: .min, at: hhmm(start)),
                DayBlock(name: "Climb", duration: 60, unit: .min, at: hhmm(start.addingTimeInterval(65 * 60))),
            ])), forKey: "backplan.day")
            return
        }
        if let i = args.firstIndex(of: "-BPMorningDemo"), args.indices.contains(i + 1),
           let mins = Int(args[i + 1]) {
            seedMorning(defaults, bellIn: mins)
            return
        }
        guard args.contains("-BPDemo") else { return }
        let enc = JSONEncoder()
        for key in ["backplan.templates", "backplan.linked", "backplan.day", "backplan.last"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(try? enc.encode([home, gym, school]), forKey: "backplan.places")
        let plan = Plan(eventName: "Pick-up", target: "15:00", day: .today, steps: [
            Step(name: "Snack", duration: 10, unit: .min),
            Step(name: "Bike to School", duration: 3, unit: .min, travel: Travel(mode: .bike, to: school.ref)),
        ])
        defaults.set(try? enc.encode(plan), forKey: "backplan.last")
        let day = DayPlan(date: .today, blocks: [DayBlock(name: "Climb", duration: 1, unit: .hr, placeID: gym.id)])
        defaults.set(try? enc.encode(day), forKey: "backplan.day")
    }

    /// Runs after the store exists.
    static func afterLaunch(_ store: PlanStore) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-BPRollover") || args.contains("-BPRolloverPair") {
            for key in PlanKey.allCases {
                let p = store.resolved(key)
                print("BPDEBUG after  \(key.rawValue): day=\(p.day.rawValue) base=\(p.baseDate ?? "nil") target=\(p.targetDate())")
            }
            if let b = store.bridge() {
                print("BPDEBUG bridge lightsOut=\(b.lightsOut) wake=\(b.wake) deadline=\(b.deadline) sleep=\(b.actualSleepMinutes)min")
            }
            fflush(stdout)
        }
        guard args.contains("-BPAddToDay") else { return }
        store.addPlanToDay(name: "Pick-up")
        // Edit the linked plan: the Day block must pick this up.
        store.plan.steps[0].duration = 15
        print("BPDEBUG linked=\(store.linkedTemplate?.name ?? "nil") blockSteps=\(store.day.blocks.compactMap { $0.steps?.map(\.minutes) })")
    }
}

// MARK: - Countdown widget

extension DebugSeed {
    /// The night pair with the school bell `bellIn` minutes away and last
    /// night's bedtime — the state a real school morning opens in.
    static func seedMorning(_ defaults: UserDefaults, bellIn: Int) {
        let cal = Calendar.current
        let yesterday = LocalDay.key(cal.date(byAdding: .day, value: -1, to: Date())!)
        let enc = JSONEncoder()
        defaults.removeObject(forKey: "backplan.armed")
        defaults.removeObject(forKey: "backplan.linked")
        defaults.set(try? enc.encode(DayPlan(date: .today, blocks: [])), forKey: "backplan.day")
        let morning = Plan(eventName: "School", target: hhmm(Date().addingTimeInterval(TimeInterval(bellIn * 60))),
                           day: .tomorrow, steps: MorningInputs.preview.steps.map {
            Step(name: $0.name, duration: Double($0.minutes), unit: .min)
        }, baseDate: yesterday)
        let evening = Plan(eventName: "Bedtime", target: "21:00", day: .today, steps: [
            Step(name: "Bath", duration: 20, unit: .min),
            Step(name: "Stories", duration: 20, unit: .min),
        ], baseDate: yesterday)
        let plans = try? JSONSerialization.jsonObject(with: enc.encode(PlanPair(evening: evening, morning: morning)))
        let link = try? JSONSerialization.jsonObject(with: enc.encode(NightLink(enabled: true, sleepNeed: 660, sleeper: "Ezra")))
        let snap: [String: Any] = ["v": 2, "active": "morning", "link": link ?? [:], "plans": plans ?? [:]]
        defaults.set(try? JSONSerialization.data(withJSONObject: snap), forKey: "backplan.last")
    }

    /// The simulator can't tap a widget, so drive the same handler a tap
    /// reaches, and check what the widget would read after each step.
    static func widgetLaunchArgs(store: PlanStore, timer: TimerController) async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-BPIntent"), args.indices.contains(i + 1) {
            let action: IntentAction? = switch args[i + 1] {
            case "done": .done
            case "late": .late(5)
            case "start": .startMorning
            default: nil
            }
            if let action {
                // Through `IntentRouter`, not `IntentHandler` directly — this
                // is also the check that `BackplanApp.init` installed it.
                let said = await IntentRouter.run(action)
                print("BPDEBUG intent \(args[i + 1]) -> \(said)")
                let chain = CountdownStore.loadChain()
                print("BPDEBUG appgroup chain=\(chain.map { "\($0.eventName) \($0.segments.map { "\($0.name)@\(Fmt.time($0.start))-\(Fmt.time($0.end))" })" } ?? "nil")")
                fflush(stdout)
            }
        }
        guard args.contains("-BPWidgetCheck") else { return }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if !ok { failures += 1 }
            print("BPCHECK \(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " \u{2014} " + detail())")
        }
        /// The App Group copy is exactly the timer's frozen result, flattened.
        func matches(_ stage: String) {
            let stored = CountdownStore.loadChain()
            let segs = timer.armedResult?.segments ?? []
            check("widget chain == armedResult after \(stage)",
                  stored != nil && stored == timer.widgetChain
                    && stored!.segments.count == segs.count
                    && zip(stored!.segments, segs).allSatisfy { $0.name == $1.name && $0.start == $1.start && $0.end == $1.end }
                    && stored!.target == timer.armedResult?.target,
                  "stored \(String(describing: stored?.segments)) vs \(segs.map { "\($0.name) \($0.start)-\($0.end)" })")
        }
        await timer.arm(key: store.activeKey, plan: store.resolved(store.activeKey))
        check("armed", timer.armed)
        matches("arm")
        let before = timer.armedResult
        _ = await IntentRouter.run(.done)
        check("Done moved the chain", timer.armedResult != before)
        matches("Done")
        let beforeLate = timer.armedResult
        _ = await IntentRouter.run(.late(5))
        check("+5 moved the chain", timer.armedResult != beforeLate)
        matches("Late +5")
        timer.disarm()
        check("disarm clears the widget chain", CountdownStore.loadChain() == nil)
        print("BPCHECK widget-live \(failures == 0 ? "ALL PASS" : "\(failures) FAILED")")
        fflush(stdout)
    }
}

// MARK: - Date model

extension DebugSeed {
    static func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func seedRollover(_ defaults: UserDefaults, pair: Bool) {
        let cal = Calendar.current
        let yesterday = LocalDay.key(cal.date(byAdding: .day, value: -1, to: Date())!)
        let enc = JSONEncoder()
        defaults.removeObject(forKey: "backplan.armed")
        defaults.removeObject(forKey: "backplan.linked")
        defaults.set(try? enc.encode(DayPlan(date: .today, blocks: [], baseDate: yesterday)), forKey: "backplan.day")
        let target = Date().addingTimeInterval(90 * 60)
        let school = Plan(eventName: "School", target: hhmm(target), day: .tomorrow, steps: [
            Step(name: "Breakfast", duration: 20, unit: .min),
            Step(name: "Shoes, bag, out", duration: 10, unit: .min),
            Step(name: "Bike to School", duration: 15, unit: .min),
        ], baseDate: yesterday)
        print("BPDEBUG before: saved \(yesterday) as tomorrow \(school.target) → expect today \(school.target)")
        fflush(stdout)
        guard pair else {
            defaults.set(try? enc.encode(school), forKey: "backplan.last")
            return
        }
        // v2 pair record, hand-assembled: `PairSnapshot` is private to the store.
        var morning = school
        morning.target = "08:05"
        let evening = Plan(eventName: "Bedtime", target: "21:00", day: .today, steps: [
            Step(name: "Bath", duration: 20, unit: .min),
            Step(name: "Stories", duration: 20, unit: .min),
        ], baseDate: yesterday)
        let plans = try? JSONSerialization.jsonObject(with: enc.encode(PlanPair(evening: evening, morning: morning)))
        let link = try? JSONSerialization.jsonObject(with: enc.encode(NightLink(enabled: true, sleepNeed: 660, sleeper: "Ezra")))
        let snap: [String: Any] = ["v": 2, "active": "evening", "link": link ?? [:], "plans": plans ?? [:]]
        defaults.set(try? JSONSerialization.data(withJSONObject: snap), forKey: "backplan.last")
    }

    /// Pure checks of the date model, at fixed synthetic clocks — the one way
    /// to exercise midnight without waiting for it. Prints BPCHECK PASS/FAIL.
    static func selfCheck() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: today)!)!
        }
        func key(_ dayOffset: Int) -> String { LocalDay.key(cal.date(byAdding: .day, value: dayOffset, to: today)!) }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if !ok { failures += 1 }
            print("BPCHECK \(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — " + detail())")
        }

        // 1. Made at 9 PM for "8:05 tomorrow"; read at 6:55 AM.
        let made = Plan(eventName: "School", target: "08:05", day: .tomorrow, steps: [], baseDate: key(-1))
        let dawn = at(0, 6, 55)
        check("9pm tomorrow-plan still means today 8:05 before normalizing",
              made.targetDate(now: dawn) == at(0, 8, 5), "\(made.targetDate(now: dawn))")
        var n = made
        check("normalize reports a change", n.normalizeDate(now: dawn))
        check("normalized reads today", n.day == .today && n.baseDate == key(0), "\(n.day) \(n.baseDate ?? "nil")")
        check("normalized keeps the same moment", n.targetDate(now: dawn) == at(0, 8, 5))
        check("normalization is not an edit (anchored equal)", n.anchored(now: dawn) == made.anchored(now: dawn))
        check("second normalize is a no-op", !n.normalizeDate(now: dawn))
        check("a real edit is still an edit",
              { var e = n; e.target = "08:10"; return e.anchored(now: dawn) != made.anchored(now: dawn) }())

        // 2. A plan from days ago rolls to the next occurrence.
        let old = Plan(eventName: "", target: "08:05", day: .today, steps: [], baseDate: key(-3))
        var early = old; early.normalizeDate(now: dawn)
        check("stale plan, time still ahead → today", early.targetDate(now: dawn) == at(0, 8, 5),
              "\(early.targetDate(now: dawn))")
        var late = old; late.normalizeDate(now: at(0, 9, 0))
        check("stale plan, time gone → tomorrow", late.day == .tomorrow && late.targetDate(now: at(0, 9, 0)) == at(1, 8, 5),
              "\(late.day) \(late.targetDate(now: at(0, 9, 0)))")

        // 3. Legacy record: no baseDate → today, and a passed time is shown as passed.
        let legacyJSON = #"{"eventName":"x","target":"08:05","day":"today","steps":[]}"#
        if var legacy = try? JSONDecoder().decode(Plan.self, from: Data(legacyJSON.utf8)) {
            check("legacy decodes with no baseDate", legacy.baseDate == nil)
            legacy.normalizeDate(now: at(0, 9, 0))
            check("legacy adopts today", legacy.baseDate == key(0) && legacy.day == .today)
            check("legacy past target is past",
                  BackwardsPlanner.compute(legacy, now: at(0, 9, 0)).isPast)
        } else {
            check("legacy decodes", false)
        }
        let badJSON = #"{"eventName":"x","target":"08:05","day":"tomorrow","steps":[],"baseDate":42}"#
        check("wrong-typed baseDate costs only the date",
              (try? JSONDecoder().decode(Plan.self, from: Data(badJSON.utf8)))?.baseDate == nil
              && (try? JSONDecoder().decode(Plan.self, from: Data(badJSON.utf8))) != nil)
        var garbage = Plan(eventName: "", target: "08:05", day: .today, steps: [], baseDate: "not-a-date")
        check("malformed baseDate reads as today", garbage.targetDate(now: dawn) == at(0, 8, 5))
        garbage.normalizeDate(now: dawn)
        check("malformed baseDate is repaired", garbage.baseDate == key(0))
        let dayJSON = #"{"date":"tomorrow","blocks":[]}"#
        check("legacy Day decodes", (try? JSONDecoder().decode(DayPlan.self, from: Data(dayJSON.utf8)))?.baseDate == nil)

        // 4. Day: yesterday's "tomorrow" is today; a stale Day is today.
        var d = DayPlan(date: .tomorrow, blocks: [], baseDate: key(-1))
        d.normalizeDate(now: dawn)
        check("Day tomorrow→today overnight", d.date == .today && d.baseDate == key(0) && d.isToday(now: dawn))
        var stale = DayPlan(date: .today, blocks: [], baseDate: key(-4))
        stale.normalizeDate(now: dawn)
        check("stale Day becomes today", stale.date == .today && stale.isToday(now: dawn))

        // 5. Store-level: chain dates, linked write-through, Add to Day dates.
        let suite = "backplan.selfcheck"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PlanStore(defaults: defaults)
        store.link.enabled = true
        store.pair = PlanPair(
            evening: Plan(eventName: "Bed", target: "21:00", day: .today, steps: [Step(name: "Bath", duration: 20)], baseDate: key(0)),
            morning: Plan(eventName: "School", target: "08:05", day: .today, steps: [Step(name: "Out", duration: 30)], baseDate: key(0)))
        let bridge = store.bridge(now: at(0, 12, 0))!
        check("chained morning is the day after the evening",
              bridge.lightsOut == at(0, 21, 0) && bridge.morningTarget == at(1, 8, 5),
              "\(bridge.lightsOut) \(bridge.morningTarget)")
        check("chained sleep is one night, not a day", bridge.actualSleepMinutes == 10 * 60 + 35,
              "\(bridge.actualSleepMinutes)")
        check("morning tab result uses the derived date",
              store.result(for: .morning, now: at(0, 12, 0)).target == at(1, 8, 5))

        // Lights out after midnight: the same day's morning, not one 31 hr away.
        store.pair.evening.target = "00:30"
        store.pair.evening.day = .tomorrow
        let afterMidnight = store.bridge(now: at(0, 12, 0))!
        check("12:30 AM lights-out → that morning's 8:05",
              afterMidnight.lightsOut == at(1, 0, 30) && afterMidnight.morningTarget == at(1, 8, 5),
              "\(afterMidnight.morningTarget)")
        // A school plan typed into the evening slot: no 23-hour night.
        store.pair.evening = Plan(eventName: "School", target: "08:05", day: .tomorrow,
                                  steps: [Step(name: "Out", duration: 30)], baseDate: key(0))
        store.pair.morning.target = "08:15"
        let school = store.bridge(now: at(0, 21, 0))!
        check("school-as-evening is not 23 hr of sleep", school.actualSleepMinutes < 60 && school.verdict == .late,
              "\(school.actualSleepMinutes) \(school.pillText)")
        // The morning typed as PM: lights out 10 PM, "wake" 8:30 PM next day.
        store.pair.morning.target = "21:00"
        store.pair.evening.target = "22:00"
        store.pair.evening.day = .today
        let swapped = store.bridge(now: at(0, 12, 0))!
        check("wake PM / lights-out AM reads Check times", swapped.pillText == "Check times",
              "\(swapped.pillText) \(swapped.actualSleepMinutes)")

        // Holds. Last night's evening at 6:55 AM, morning target still ahead.
        store.pair = PlanPair(
            evening: Plan(eventName: "Bed", target: "21:00", day: .today, steps: [Step(name: "Bath", duration: 20)], baseDate: key(-1)),
            morning: Plan(eventName: "School", target: "08:05", day: .tomorrow, steps: [Step(name: "Out", duration: 30)], baseDate: key(-1)))
        check("before normalizing, school is today 8:05", store.resolved(.morning, now: dawn).targetDate(now: dawn) == at(0, 8, 5))
        store.normalizeDates(now: dawn)
        check("linked evening held at 6:55 AM", store.pair.evening.baseDate == key(-1)
              && store.resolved(.morning, now: dawn).targetDate(now: dawn) == at(0, 8, 5),
              "\(store.pair.evening.baseDate ?? "nil") \(store.resolved(.morning, now: dawn).targetDate(now: dawn))")
        check("held evening reads 'last night'", store.isLastNight(.evening, now: dawn))
        store.normalizeDates(now: at(0, 9, 0))
        check("after the school run, evening rolls to tonight",
              store.pair.evening.baseDate == key(0) && store.resolved(.evening, now: at(0, 9, 0)).targetDate(now: at(0, 9, 0)) == at(0, 21, 0))
        store.pair.evening.baseDate = key(-3)
        store.normalizeDates(hold: PlanStore.DateHold(plan: .morning), now: at(0, 9, 0))
        check("any armed plan holds a linked evening", store.pair.evening.baseDate == key(-3))
        var armed = Plan(eventName: "", target: "08:05", day: .today, steps: [], baseDate: key(-2))
        check("armed plan is not rolled", !armed.normalizeDate(now: dawn, hold: true) && armed.baseDate == key(-2))
        var armedDay = DayPlan(date: .today, blocks: [], baseDate: key(-2))
        check("armed Day is not rolled", !armedDay.normalizeDate(now: dawn, hold: true))
        var reExpress = Plan(eventName: "", target: "08:05", day: .tomorrow, steps: [], baseDate: key(-1))
        check("re-expression happens even when held", reExpress.normalizeDate(now: dawn, hold: true) && reExpress.day == .today)

        // Plan for tomorrow, linked morning: moves the night.
        store.pair.evening = Plan(eventName: "Bed", target: "21:00", day: .today, steps: [], baseDate: key(0))
        store.planForTomorrow(.morning, now: at(0, 9, 0))
        check("plan-for-tomorrow on a linked morning lands it tomorrow",
              store.resolved(.morning, now: at(0, 9, 0)).targetDate(now: at(0, 9, 0)) == at(1, 8, 5))

        store.link.enabled = false
        store.activeKey = .evening
        store.pair.evening = Plan(eventName: "Pick-up", target: "15:00", day: .today,
                                  steps: [Step(name: "Snack", duration: 10)], baseDate: key(0))
        store.day = DayPlan(date: .today, blocks: [])
        store.addPlanToDay(name: "Pick-up")
        store.plan.target = "15:30"
        check("linked block follows a target edit", store.day.blocks.first?.at == "15:30",
              "\(String(describing: store.day.blocks.first?.at))")
        check("template stays dateless", store.linkedTemplate?.plan.baseDate == nil)
        store.plan.day = .tomorrow
        check("tomorrow plan vs today's Day asks to switch",
              store.addToDayDate() == .move(plan: "tomorrow", day: "today"),
              "\(store.addToDayDate())")
        let blocks = store.day.blocks.count
        check("clash adds nothing unasked", store.addPlanToDay(name: "Pick-up") == nil && store.day.blocks.count == blocks)
        store.addPlanToDay(name: "Pick-up", moveDay: true)
        check("moving the Day lands it on the plan's date",
              store.day.effectiveDay() == store.plan.effectiveDay() && store.day.blocks.count == blocks + 1)
        defaults.removePersistentDomain(forName: suite)

        // 5b. Sleep Left widget == the tracker card. Same inputs, same figure,
        // same wake, same verdict — in the evening, across midnight, and after
        // this morning's wake (which has to roll to tomorrow's).
        do {
            let evening = Plan(target: "21:00", steps: [Step(name: "Bath", duration: 25), Step(name: "Books", duration: 15)])
            let morning = Plan(eventName: "School", target: "08:05", steps: [Step(name: "Breakfast", duration: 70)])
            let inputs = SleepLeft.Inputs(enabled: true, morningTarget: "08:05", morningName: "School",
                                          morningMinutes: 70, windDownMinutes: 40, rideMinutes: 12,
                                          sleepNeed: 660, sleeper: "Ezra")
            for (d, h, m, s) in [(0, 19, 25, 0), (0, 21, 30, 41), (1, 0, 40, 0), (1, 6, 54, 59), (1, 7, 30, 0)] {
                let now = at(d, h, m).addingTimeInterval(TimeInterval(s))
                let card = SleepTrack.make(evening: evening, morning: morning, sleepNeed: 660, rideMinutes: 12, now: now)
                let widget = SleepLeft.solve(inputs, now: now)
                check("widget matches tracker at d\(d) \(h):\(m):\(s)",
                      widget.sleepMinutes == card.sleepMinutes && widget.wake == card.wake
                        && widget.startBy == card.leaveBy && widget.verdict.rawValue == "\(card.verdict)",
                      "widget \(widget.sleepMinutes) wake \(widget.wake) vs card \(card.sleepMinutes) wake \(card.wake)")
            }
            // The inputs the store publishes are the ones the card reads.
            let suiteW = "backplan.selfcheck.widget"
            let dw = UserDefaults(suiteName: suiteW)!
            dw.removePersistentDomain(forName: suiteW)
            let sw = PlanStore(defaults: dw)
            sw.setTrackMode(true)
            let now = at(0, 21, 30)
            check("store inputs reproduce the card",
                  SleepLeft.solve(sw.sleepLeftInputs, now: now).sleepMinutes == sw.sleepTrack(now: now)?.sleepMinutes)
            dw.removePersistentDomain(forName: suiteW)
        }

        // 5c. Day widget: the published snapshot reads the same as the solved Day.
        do {
            let places: [SavedPlace] = [DebugSeed.home, DebugSeed.gym, DebugSeed.school]
            func solve(_ blocks: [DayBlock], now: Date) -> DayResult {
                DayPlanner.compute(DayPlan(date: .today, blocks: blocks), places: places, now: now) { _, _, _ in .ok(15) }
            }
            func snap(_ r: DayResult) -> DayWidget.Snapshot {
                DayWidget.snapshot(from: r, places: places, dayKey: DayWidget.key(at(0, 12, 0)))
            }
            let climb = DayBlock(name: "Climb", duration: 1, unit: .hr, placeID: DebugSeed.gym.id)
            let pick = DayBlock(name: "Pick-up", duration: 30, unit: .min, at: "15:00", placeID: DebugSeed.school.id)
            let dinner = { (t: String) in DayBlock(name: "Dinner", duration: 30, unit: .min, at: t) }
            let roomy = solve([climb, pick, dinner("18:00")], now: at(0, 12, 0))
            let rs = snap(roomy)
            let nowA = at(0, 12, 10)
            let ra = DayWidget.read(rs, now: nowA)
            let wantNext = roomy.items.first { $0.block.isAnchor && $0.start > nowA }
            check("day widget: next pinned agrees with the solved Day",
                  ra.next?.name == wantNext?.block.name && ra.next?.start == wantNext?.start,
                  "\(ra.next?.name ?? "nil") vs \(wantNext?.block.name ?? "nil")")
            check("day widget: leave-by is the pinned block's leg start",
                  ra.leaveBy == wantNext?.leg?.start, "\(String(describing: ra.leaveBy)) vs \(String(describing: wantNext?.leg?.start))")
            // Before the first departure: free = time to the first leg start.
            let firstLeg = roomy.items.compactMap { $0.leg?.start }.min()!
            check("day widget: free minutes run to the next departure",
                  ra.freeMinutes == Int((firstLeg.timeIntervalSince(nowA) / 60).rounded()), "\(String(describing: ra.freeMinutes))")
            // Inside the gap between two pins: free = the gap's slack at its front.
            let gap = roomy.gaps[0]
            let rg = DayWidget.read(rs, now: gap.freeFrom)
            check("day widget: free minutes at the gap's front equal its slack",
                  rg.freeMinutes == gap.slack && rg.overMinutes == nil, "\(String(describing: rg.freeMinutes)) vs \(gap.slack)")
            // A gap that doesn't fit reads as over, by exactly the shortfall.
            let squeezed = solve([climb, pick, DayBlock(name: "Homework", duration: 45, unit: .min), dinner("15:20")],
                                 now: at(0, 12, 0))
            let sg = squeezed.gaps[0]
            let ro = DayWidget.read(snap(squeezed), now: sg.depart.addingTimeInterval(60))
            check("day widget: over-by equals the negative slack",
                  sg.slack < 0 && ro.overMinutes == -sg.slack, "\(String(describing: ro.overMinutes)) vs \(sg.slack)")
            // Dates: a stale Day says nothing about today; after the last block it's done.
            var stale = rs
            stale.dayKey = DayWidget.key(at(-1, 12, 0))
            check("day widget: yesterday's Day reads as no Day today",
                  DayWidget.read(stale, now: nowA).kind == .noDay && DayWidget.read(nil, now: nowA).kind == .noDay)
            check("day widget: after the last block the Day is done", DayWidget.read(rs, now: at(0, 19, 0)).kind == .done)
            // The snapshot survives the App Group round trip byte-for-byte.
            let rt = try? JSONDecoder().decode(DayWidget.Snapshot.self, from: JSONEncoder().encode(rs))
            check("day widget: snapshot round-trips", rt == rs)
        }

        // 5d. Countdown widget. The flattened chain reads exactly as the app's
        // own countdown does — label, clock, pill, step — before the start,
        // inside each step, at the boundaries and after the target, and again
        // after Done and Running late; and the morning fallback is the
        // planner's own chain.
        do {
            let target = at(0, 8, 5)
            let plan = Plan(eventName: "School", target: "08:05", day: .today, steps: [
                Step(name: "Breakfast", duration: 30), Step(name: "Shoes", duration: 5),
                Step(name: "Bike", duration: 15)], baseDate: key(0))
            let base = BackwardsPlanner.compute(plan, now: at(0, 6, 0))
            func flat(_ r: PlanResult, armedAt: Date) -> ArmedChain {
                ArmedChain(kind: .plan, eventName: "School", target: r.target, armedAt: armedAt,
                           segments: r.segments.map { .init(name: $0.name, start: $0.start, end: $0.end) })
            }
            func agree(_ r: PlanResult, _ label: String) {
                let armedAt = at(0, 6, 0)
                let chain = flat(r, armedAt: armedAt)
                var moments = r.segments.flatMap { [$0.start, $0.end, $0.start.addingTimeInterval(90)] }
                moments += [at(0, 6, 30), r.segments[0].start.addingTimeInterval(-30), target,
                            target.addingTimeInterval(1), target.addingTimeInterval(600)]
                var bad: [String] = []
                for m in moments {
                    guard let app = PlanCountdown.make(result: r, now: m, armedAt: armedAt),
                          let w = chain.reading(at: m) else { bad.append("nil @\(m)"); continue }
                    if app.label != w.label || app.boundary != w.boundary || app.windowStart != w.windowStart
                        || app.phaseWord != w.phaseWord || app.detail != w.detail
                        || app.stepNumber != w.stepNumber || "\(app.phase)" != w.phase.rawValue
                        || (app.status.index >= 0) != w.canFinish {
                        bad.append("\(Fmt.time(m)): app \(app.label)/\(app.detail)/\(app.phaseWord) widget \(w.label)/\(w.detail)/\(w.phaseWord)")
                    }
                    if let next = PlanCountdown.nextChange(result: r, now: m),
                       chain.changeMarks.first(where: { $0 > m }).map({ $0 > next }) ?? true {
                        bad.append("\(Fmt.time(m)): widget misses the change at \(Fmt.time(next))")
                    }
                }
                check("widget countdown == app countdown (\(label))", bad.isEmpty, bad.joined(separator: "; "))
            }
            agree(base, "as armed")
            let done = base.finishingCurrent(at: at(0, 7, 30))!.result
            agree(done, "after Done")
            agree(done.slipping(minutes: 5, at: at(0, 7, 31))!, "after Done, +5")
            agree(base.slipping(minutes: 10, at: at(0, 6, 0))!, "+10 before the start")

            let inputs = MorningInputs(enabled: true, eventName: "School", target: "08:05",
                                       steps: plan.steps.map { .init(name: $0.name, minutes: $0.minutes) })
            let morning = inputs.chain(endingAt: inputs.nextTarget(after: at(0, 7, 0)))
            check("morning fallback == planner's chain",
                  morning.target == base.target && morning.segments.map(\.start) == base.segments.map(\.start)
                    && morning.segments.map(\.end) == base.segments.map(\.end))
            check("morning window opens an hour before wake",
                  inputs.window(at: at(0, 6, 14)) == nil && inputs.window(at: at(0, 6, 15)) != nil
                    && inputs.window(at: at(0, 8, 4)) != nil && inputs.window(at: at(0, 8, 5)) == nil)
            check("after the bell the idle face is tomorrow's",
                  inputs.nextTarget(after: at(0, 8, 5)) == at(1, 8, 5))
            let armedChain = flat(base, armedAt: at(0, 6, 0))
            check("armed beats the morning window",
                  CountdownFace.resolve(chain: armedChain, morning: inputs, now: at(0, 7, 0)) == .armed(armedChain))
            check("a finished plan gives way after an hour",
                  CountdownFace.resolve(chain: armedChain, morning: inputs, now: at(0, 9, 4)) == .armed(armedChain)
                    && CountdownFace.resolve(chain: armedChain, morning: inputs, now: at(0, 9, 6)) == .idle(inputs))
            var off = inputs
            off.enabled = false
            check("pair off: no morning face",
                  CountdownFace.resolve(chain: nil, morning: off, now: at(0, 7, 0)) == .idle(off))
        }

        // 6. Copy.
        let track = SleepTrack.make(
            evening: Plan(target: "21:00", steps: [Step(name: "Wind down", duration: 30)]),
            morning: Plan(target: "07:00", steps: []), sleepNeed: 660, rideMinutes: 0, now: at(0, 23, 0))
        let text = track.verdictText(sleepNeed: 660)
        // A stopwatch reading (H:MM:SS) has no business in the sentence.
        check("track 'ago' is whole minutes",
              text.contains(" ago") && text.range(of: #"\d+:\d\d:\d\d"#, options: .regularExpression) == nil,
              text)
        print("BPCHECK time format sample: \(Fmt.time(at(0, 21, 5)))")
        print("BPCHECK \(failures == 0 ? "ALL PASS" : "\(failures) FAILED")")
        fflush(stdout)
    }
}

extension PlanStore {
    static func debugDayBlockIDs() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: "backplan.day"),
              let day = try? JSONDecoder().decode(DayPlan.self, from: data) else { return [] }
        return day.blocks.map(\.id)
    }
}
#endif
