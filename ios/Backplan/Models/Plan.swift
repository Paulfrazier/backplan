import Foundation

enum TargetDay: String, Codable, CaseIterable, Identifiable {
    case today, tomorrow
    var id: String { rawValue }
    var label: String { self == .today ? "Today" : "Tomorrow" }
}

enum DurationUnit: String, Codable, CaseIterable, Identifiable {
    case min, hr
    var id: String { rawValue }
    var label: String { self == .min ? "min" : "hr" }
}

/// KEEP IN SYNC with the web `TRAVEL_MODES` table in index.html. These are stock
/// BRouter profiles served by brouter.de; measured on a 3.5 mi Portland trip:
/// car-eco 15 min, trekking ~14 mph, hiking-beta ~3.2 mph.
enum TravelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case drive, bike, walk

    var id: String { rawValue }
    var label: String {
        switch self {
        case .drive: return "Drive"
        case .bike: return "Bike"
        case .walk: return "Walk"
        }
    }
    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .bike: return "bicycle"
        case .walk: return "figure.walk"
        }
    }
    var profile: String {
        switch self {
        case .drive: return "car-eco"
        case .bike: return "trekking"
        case .walk: return "hiking-beta"
        }
    }
    /// Verb used to auto-name a travel step ("Drive to Powell's").
    var verb: String { label }
}

/// A resolved point. `label` is the display name, `sub` the qualifying context
/// line ("838 NW 23rd Ave, Portland").
struct PlaceRef: Codable, Hashable, Sendable {
    var label: String
    var sub: String = ""
    var lat: Double
    var lng: Double

    init(label: String, sub: String = "", lat: Double, lng: Double) {
        self.label = label
        self.sub = sub
        self.lat = lat
        self.lng = lng
    }

    // A default value does NOT make a key optional to the synthesized decoder —
    // a payload without "sub" would throw and take the whole plan down with it.
    // `encode(to:)` stays synthesized because CodingKeys matches the properties.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
    }
}

struct TravelResult: Codable, Hashable, Sendable {
    var minutes: Int
    var distanceM: Int
    var fetchedAt: Date
}

/// The travel leg attached to a step. Every property is defaulted so plans
/// encoded before travel existed still decode — note there is deliberately no
/// custom `init(from:)`, which would break the synthesized `Encodable`.
struct Travel: Codable, Hashable, Sendable {
    var mode: TravelMode = .drive
    /// `nil` means "inherit the previous leg's destination" (see PlanStore.resolveOrigin).
    var from: PlaceRef?
    var to: PlaceRef?
    var result: TravelResult?
    /// Set once the user hand-edits the duration; refreshes stop overwriting it.
    var manual: Bool = false

    init(mode: TravelMode = .drive, from: PlaceRef? = nil, to: PlaceRef? = nil,
         result: TravelResult? = nil, manual: Bool = false) {
        self.mode = mode
        self.from = from
        self.to = to
        self.result = result
        self.manual = manual
    }

    // Lenient by design: a Travel block written with only some of its keys (a
    // template snapshot, a payload from an older or newer build) must still
    // decode. Without this, one missing key throws and the user loses the whole
    // saved plan, not just the travel leg.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(TravelMode.self, forKey: .mode) ?? .drive
        from = try c.decodeIfPresent(PlaceRef.self, forKey: .from)
        to = try c.decodeIfPresent(PlaceRef.self, forKey: .to)
        result = try c.decodeIfPresent(TravelResult.self, forKey: .result)
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
    }
}

struct Step: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var duration: Double = 5
    var unit: DurationUnit = .min
    /// Present only on travel steps. Optional so pre-travel payloads decode.
    var travel: Travel?

    /// Normalized duration in whole minutes, matching the web `stepMinutes`:
    /// clamps negatives/NaN to 0, rounds, converts hours → minutes.
    var minutes: Int {
        guard duration.isFinite, duration >= 0 else { return 0 }
        return unit == .hr ? Int((duration * 60).rounded()) : Int(duration.rounded())
    }
}

struct Plan: Codable, Equatable {
    var eventName: String = ""
    /// Target time of day in "HH:mm" (24h), mirroring the web `state.target`.
    var target: String = "18:20"
    var day: TargetDay = .today
    var steps: [Step] = []
    /// The local calendar date `day` is relative to, as "YYYY-MM-DD". Without
    /// it "tomorrow" was resolved against *now*, so a 9 PM plan for "8:05
    /// tomorrow" quietly meant the day after once midnight passed. Optional so
    /// records written before it decode (the synthesized decoder treats an
    /// Optional key as optional); nil reads as today. Templates never carry
    /// one — they stay relative. KEEP IN SYNC with the web `baseDate`.
    var baseDate: String? = nil
}

extension Plan {
    // Written out only to make `baseDate` lenient: a value of the wrong type
    // must cost the date (it reads as today), never the whole saved plan. The
    // other keys keep exactly the strictness the synthesized decoder had. In
    // an extension, so the memberwise init survives.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventName = try c.decode(String.self, forKey: .eventName)
        target = try c.decode(String.self, forKey: .target)
        day = try c.decode(TargetDay.self, forKey: .day)
        steps = try c.decode([Step].self, forKey: .steps)
        baseDate = try? c.decodeIfPresent(String.self, forKey: .baseDate)
    }
}

/// "YYYY-MM-DD" local calendar dates — the storage format of `baseDate`.
/// Built from calendar components rather than a DateFormatter, so it is
/// locale-proof and Sendable.
enum LocalDay {
    static func key(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of that day, or nil for anything that isn't a well-formed date.
    static func start(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole calendar days from `a`'s day to `b`'s day.
    static func days(from a: Date, to b: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// "today" / "tomorrow" / "Mon, Oct 20" — for sentences about a plan's date.
    static func word(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch days(from: now, to: d, calendar: calendar) {
        case 0: return "today"
        case 1: return "tomorrow"
        default: return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

extension Plan {
    /// Start of the calendar day the target lands on: `baseDate` plus one for
    /// Tomorrow. A missing or malformed `baseDate` reads as today.
    func effectiveDay(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let base = baseDate.flatMap { LocalDay.start($0, calendar: calendar) } ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: day == .tomorrow ? 1 : 0, to: base) ?? base
    }

    /// The target as an absolute Date, anchored to `baseDate` rather than to
    /// `now`, so the same saved plan means the same moment whenever it is read.
    /// Matches the web `targetDate()` (seconds/millis zeroed).
    func targetDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        Plan.at(target, on: effectiveDay(now: now, calendar: calendar), calendar: calendar)
    }

    /// Explicit-offset form, relative to *today* and ignoring `baseDate`. Only
    /// track mode wants this: its morning is "the next one that hasn't
    /// happened yet", which is a question about now, not about a saved date.
    func targetDate(now: Date = Date(), calendar: Calendar = .current, dayOffset: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return Plan.at(target, on: day, calendar: calendar)
    }

    /// "HH:mm" on a given day.
    static func at(_ hhmm: String, on day: Date, calendar: Calendar = .current) -> Date {
        let parts = hhmm.split(separator: ":")
        let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return calendar.date(
            bySettingHour: min(max(h, 0), 23),
            minute: min(max(m, 0), 59),
            second: 0,
            of: day
        ) ?? day
    }

    /// Bring a plan saved on an earlier day up to today. KEEP IN SYNC with the
    /// web `normalizePlanDate`.
    ///
    /// - No `baseDate` (a legacy record): adopt today. If its time has gone by,
    ///   the past-target offer is what the user sees — nothing is guessed.
    /// - Its date is still today or later: rewrite as Today / Tomorrow from
    ///   today, keeping the *same absolute moment* (a 9 PM "tomorrow 8:05"
    ///   reads "today 8:05" at 6:55 AM).
    /// - Its date has gone by (a plan from days ago): roll to the next
    ///   occurrence of the target clock time — today if still ahead, else
    ///   tomorrow. That one *moves* the moment, so it waits while `hold` (the
    ///   plan is the armed one, or a linked evening is still last night's).
    ///
    /// Returns true when anything changed.
    @discardableResult
    mutating func normalizeDate(now: Date = Date(), calendar: Calendar = .current, hold: Bool = false) -> Bool {
        let today = calendar.startOfDay(for: now)
        let todayKey = LocalDay.key(today, calendar: calendar)
        guard let base = baseDate.flatMap({ LocalDay.start($0, calendar: calendar) }) else {
            baseDate = todayKey
            return true
        }
        guard base < today else { return false }
        let effective = effectiveDay(now: now, calendar: calendar)
        if effective >= today {
            day = LocalDay.days(from: today, to: effective, calendar: calendar) >= 1 ? .tomorrow : .today
        } else {
            if hold { return false }
            day = Plan.at(target, on: today, calendar: calendar) > now ? .today : .tomorrow
        }
        baseDate = todayKey
        return true
    }

    /// The same plan with its date written out absolutely, for "is this the
    /// same schedule?" checks. A date normalization changes `day` and
    /// `baseDate` together without moving anything, so comparing raw plans
    /// would call that an edit.
    func anchored(now: Date = Date(), calendar: Calendar = .current) -> Plan {
        var p = self
        p.baseDate = LocalDay.key(effectiveDay(now: now, calendar: calendar), calendar: calendar)
        p.day = .today
        return p
    }

    /// What a template stores: everything but the date, which stays relative.
    var asTemplate: Plan {
        var p = self
        p.baseDate = nil
        return p
    }

    /// Total scheduled minutes, matching the web `planMinutes(plan)`.
    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
}

// MARK: - The night pair

/// Which half of the pair a plan is. Mirrors the web `plans` object's keys.
enum PlanKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case evening, morning
    var id: String { rawValue }
    /// Tab copy. "Tonight" rather than "Evening" because the pair is always
    /// tonight-into-tomorrow, never an arbitrary pair of days.
    var label: String { self == .evening ? "Tonight" : "Tomorrow AM" }
}

/// Both halves. `subscript` is what lets `PlanStore.plan` stay a plain
/// read/write pointer, so every existing `store.plan.steps` call site keeps
/// working unchanged — the same trick the web port uses with `let state`.
struct PlanPair: Codable, Equatable {
    var evening: Plan
    var morning: Plan

    subscript(key: PlanKey) -> Plan {
        get { key == .evening ? evening : morning }
        set { if key == .evening { evening = newValue } else { morning = newValue } }
    }
}

/// The edge between the two plans. `sleepNeed` is a *minimum* in minutes, not a
/// duration — the plan is wrong when sleep falls under it, not when it differs.
struct NightLink: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var sleepNeed: Int = 660
    var sleeper: String = ""
    /// Set by the wake-up sheet: minutes of wind-down before lights out. Non-nil
    /// means the sleep widgets have a night of their own — wake, need and this —
    /// and the evening plan is *not* bedtime (it may be an errand run at 5:43).
    /// Optional, so records from before it existed still decode.
    var windDown: Int? = nil
}

// MARK: - Track to sleep

/// The third lens on that same edge, and deliberately NOT a second model of it:
/// wake, sleep need and the lights-out deadline all still come from `NightLink`
/// + the morning plan. What the tracker adds is one leg the pair has nowhere to
/// put — the ride home — and a different anchor. The pair asks "given the
/// bedtime I set, does tomorrow survive?"; the tracker asks "if I stand up right
/// now, what do I get?", so its near end is the wall clock and moves on its own.
///
/// `ride` reuses `Travel` wholesale: same routing, same cache, same free-flow
/// caveat. Its `to` is written from the home place at refresh time rather than
/// picked — "back-plan to home" is the mode's premise, and only the origin is
/// the user's to choose, because that is what changes from one evening out to
/// the next. KEEP IN SYNC with the web `track` object in index.html.
struct TrackState: Codable, Equatable {
    var on: Bool = false
    var ride: Travel = Travel()

    init(on: Bool = false, ride: Travel = Travel()) {
        self.on = on
        self.ride = ride
    }

    // Lenient by design, and doubly so here: a default value does NOT make a key
    // optional to the synthesized decoder (see `PlaceRef`), and this whole block
    // postdates the records already in the field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        ride = try c.decodeIfPresent(Travel.self, forKey: .ride) ?? Travel()
    }
}

/// What the morning plan is seeded with the first time the pair is switched on.
/// An empty morning would make wake == target, a technically valid chain that
/// tells the user nothing.
enum MorningSeed {
    static let eventName = "Out the door"
    static let steps: [Step] = [
        Step(name: "Wake & dressed", duration: 15, unit: .min),
        Step(name: "Breakfast", duration: 20, unit: .min),
        Step(name: "Shoes, bag, out", duration: 10, unit: .min),
    ]
}
