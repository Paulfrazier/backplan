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
}

extension Plan {
    /// Resolve the target "HH:mm" + day into an absolute Date relative to `now`,
    /// matching the web `targetDate()` (seconds/millis zeroed).
    func targetDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        targetDate(now: now, calendar: calendar, dayOffset: day == .tomorrow ? 1 : 0)
    }

    /// Explicit-offset form, matching the web `targetDateFor(plan)`. The night
    /// pair spans midnight, which two-valued `TargetDay` cannot express on its
    /// own: chained, the morning plan is always the day *after* the evening one,
    /// so its offset is derived rather than chosen.
    func targetDate(now: Date = Date(), calendar: Calendar = .current, dayOffset: Int) -> Date {
        let parts = target.split(separator: ":")
        let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        var base = now
        if dayOffset != 0 {
            base = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        }
        return calendar.date(
            bySettingHour: min(max(h, 0), 23),
            minute: min(max(m, 0), 59),
            second: 0,
            of: base
        ) ?? base
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
