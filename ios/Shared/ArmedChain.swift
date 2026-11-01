import Foundation

/// What the Countdown widget knows about the armed countdown — and, when
/// nothing is armed, about tomorrow's school morning.
///
/// The widget runs in its own process and cannot see `TimerController`,
/// `PlanResult` or the planner, so the app flattens the frozen chain into clock
/// times and names and writes it to the App Group every time the timer
/// persists (arm, Done, Running late) and clears it on disarm. Everything the
/// widget says is derived from these dates plus the wall clock, which is what
/// lets its timeline advance the step *name* at each boundary with the app
/// suspended — the thing the Live Activity cannot do without a push server.
///
/// Shared source (`ios/Shared`) so the payload and the countdown copy can't
/// drift between the two processes. KEEP IN SYNC with `PlanCountdown.make` /
/// `nextChange` in `BackwardsPlanner.swift`; `DebugSeed.selfCheck` asserts the
/// two agree moment by moment.
struct ArmedChain: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case plan, day }

    struct Segment: Codable, Equatable, Sendable {
        var name: String
        var start: Date
        var end: Date
    }

    var kind: Kind
    /// "School", or `TimerController.dayName` for a Day.
    var eventName: String
    var target: Date
    /// Only sets the start of the pre-plan interval, as in `PlanCountdown`.
    var armedAt: Date
    var segments: [Segment]

    /// The chain's span as it now stands — Done / Running late move it.
    var spanStart: Date { segments.map(\.start).min() ?? target }
    var spanEnd: Date { max(segments.map(\.end).max() ?? target, target) }

    /// How long a finished chain stays on the widget counting "Over by" before
    /// the face falls back. Matches the Live Activity's dismissal grace in
    /// `TimerController.startSyncLoop`: a Day is over when its last block ends,
    /// a plan may well still be in the middle of being late.
    var overGrace: TimeInterval { kind == .day ? 5 * 60 : 60 * 60 }
    /// After this the snapshot is debris (the app clears it on its next launch;
    /// the widget just stops believing it). Matches `TimerController.maxAge`.
    static let maxAge: TimeInterval = 6 * 60 * 60

    func isLive(at now: Date) -> Bool {
        now < target.addingTimeInterval(min(overGrace, Self.maxAge))
    }
}

// MARK: - Countdown (mirror of PlanCountdown)

/// One moment's reading of a flat chain. Same fields and the same copy as the
/// app's `PlanCountdown`, minus the parts only the app's views read.
struct ChainReading: Equatable, Sendable {
    enum Phase: String, Sendable { case future, active, past }

    let phase: Phase
    /// "Starts in" / "Next step in" / "Ends in" / "Next up in" / "Target in" / "Over by".
    let label: String
    let boundary: Date
    let windowStart: Date
    /// "Not started" / "Start now" / "Step 2 of 5" / "Free time" / "Running over".
    let phaseWord: String
    /// The step the user is (or is about to be) on.
    let detail: String
    /// The running step's name, nil outside one — what Done would finish.
    let current: String?
    /// What follows; nil when nothing does.
    let next: String?
    /// 1-based, 0 outside a step (an upcoming index in a Day's gap, as in the app).
    let stepNumber: Int
    let stepCount: Int

    /// Done needs a running step; Running late needs anything still to come.
    var canFinish: Bool { current != nil }
    var canSlip: Bool { phase != .past }
}

extension ArmedChain {
    /// KEEP IN SYNC with `PlanCountdown.make`.
    func reading(at now: Date) -> ChainReading? {
        guard let first = segments.first else { return nil }
        let count = segments.count
        let t = SleepLeft.time

        if now < first.start {
            return ChainReading(
                phase: .future, label: "Starts in", boundary: first.start,
                windowStart: min(armedAt, now),
                phaseWord: first.start.timeIntervalSince(now) <= 60 ? "Start now" : "Not started",
                detail: "\(first.name) at \(t(first.start))",
                current: nil, next: first.name, stepNumber: 0, stepCount: count)
        }
        if now > target {
            return ChainReading(
                phase: .past, label: "Over by", boundary: target, windowStart: target,
                phaseWord: "Running over", detail: "Target was \(t(target))",
                current: nil, next: nil, stepNumber: 0, stepCount: count)
        }
        if let i = segments.firstIndex(where: { now >= $0.start && now < $0.end }) {
            let cur = segments[i]
            let isLast = i == count - 1
            let following = isLast ? nil : segments[i + 1]
            return ChainReading(
                phase: .active,
                label: isLast ? "Target in" : (following!.start > cur.end ? "Ends in" : "Next step in"),
                boundary: cur.end, windowStart: cur.start,
                phaseWord: "Step \(i + 1) of \(count)",
                detail: cur.name, current: cur.name,
                next: following?.name, stepNumber: i + 1, stepCount: count)
        }
        if let upIdx = segments.firstIndex(where: { $0.start > now }) {
            let up = segments[upIdx]
            let prevEnd = segments[..<upIdx].map(\.end).max() ?? first.start
            return ChainReading(
                phase: .active, label: "Next up in", boundary: up.start,
                windowStart: min(prevEnd, now),
                phaseWord: up.start.timeIntervalSince(now) <= 60 ? "Start now" : "Free time",
                detail: "\(up.name) at \(t(up.start))",
                current: nil, next: up.name, stepNumber: upIdx, stepCount: count)
        }
        return ChainReading(
            phase: .active, label: "Target in", boundary: target, windowStart: first.start,
            phaseWord: "In progress", detail: "Between steps",
            current: nil, next: nil, stepNumber: 0, stepCount: count)
    }

    /// Every moment the copy changes, in order. KEEP IN SYNC with
    /// `PlanCountdown.nextChange` — the widget lays out one entry per mark
    /// rather than asking for the next one, since nothing re-asks while the
    /// app is suspended.
    var changeMarks: [Date] {
        var marks = segments.map(\.start) + segments.map(\.end)
        marks.append(target)
        if let first = segments.first { marks.append(first.start.addingTimeInterval(-60)) }
        for (prev, seg) in zip(segments, segments.dropFirst()) where seg.start > prev.end {
            marks.append(seg.start.addingTimeInterval(-60))
        }
        // Ends land on the next start in a plan; listing both is harmless and
        // catches a Done that left a sliver before the next run.
        return Array(Set(marks)).sorted()
    }
}

// MARK: - The morning fallback

/// The school morning as the user has written it, published by the store so
/// the widget can show "School in 1:12 · now: Breakfast" in the morning window
/// even when nobody tapped Start, and "Tomorrow: School 8:05 · wake 6:55" the
/// rest of the time. Plan-level inputs, not a solved morning — the same reason
/// as `SleepLeft.Inputs`: they stay true every day until the user edits.
struct MorningInputs: Codable, Equatable, Sendable {
    struct Step: Codable, Equatable, Sendable {
        var name: String
        var minutes: Int
    }

    /// The night pair is on — without it there is no morning plan in the app.
    var enabled: Bool
    var eventName: String
    /// "HH:mm", the morning plan's own `target`.
    var target: String
    /// Zero-length steps dropped, as `BackwardsPlanner` drops them from segments.
    var steps: [Step]

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    var displayName: String {
        let n = eventName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Morning" : n
    }

    /// How long before wake the morning face takes over from the idle one.
    static let leadMinutes = 60

    static let preview = MorningInputs(enabled: true, eventName: "School", target: "08:05", steps: [
        Step(name: "Wake up", minutes: 10), Step(name: "Breakfast", minutes: 30),
        Step(name: "Get dressed", minutes: 15), Step(name: "Shoes", minutes: 5),
        Step(name: "Bike to School", minutes: 10),
    ])

    /// The next morning target that hasn't gone by — at 7:30 that's today's
    /// 8:05, at 8:06 it's tomorrow's. Same rule as `SleepLeft.solve`, except
    /// keyed on the target rather than wake: the morning window runs to the bell.
    func nextTarget(after now: Date, calendar: Calendar = .current) -> Date {
        let parts = target.split(separator: ":").map { Int($0) ?? 0 }
        func on(_ offset: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: parts.first ?? 0, minute: parts.count > 1 ? parts[1] : 0,
                                 second: 0, of: day) ?? day
        }
        let today = on(0)
        return today > now ? today : on(1)
    }

    /// The chain backwards from `target` — exactly `BackwardsPlanner`'s
    /// segments for a plan whose target is that moment.
    func chain(endingAt target: Date) -> ArmedChain {
        var cursor = target
        var segs: [ArmedChain.Segment] = []
        for s in steps.reversed() {
            let start = cursor.addingTimeInterval(TimeInterval(-s.minutes * 60))
            segs.insert(.init(name: s.name, start: start, end: cursor), at: 0)
            cursor = start
        }
        return ArmedChain(kind: .plan, eventName: displayName, target: target,
                          armedAt: cursor.addingTimeInterval(TimeInterval(-Self.leadMinutes * 60)),
                          segments: segs)
    }

    /// The morning window around `now`: wake − lead … target. Nil outside it,
    /// or when there's no morning to speak of.
    func window(at now: Date, calendar: Calendar = .current) -> ArmedChain? {
        guard enabled, totalMinutes > 0 else { return nil }
        let chain = chain(endingAt: nextTarget(after: now, calendar: calendar))
        return now >= chain.armedAt ? chain : nil
    }
}

// MARK: - What the widget shows

enum CountdownFace: Equatable, Sendable {
    /// The armed chain.
    case armed(ArmedChain)
    /// Nothing armed, but it's the morning: the morning plan as written.
    case morning(ArmedChain)
    /// Nothing to count: tomorrow's morning (if the pair is on) and a Start button.
    case idle(MorningInputs?)

    static func resolve(chain: ArmedChain?, morning: MorningInputs?, now: Date) -> CountdownFace {
        if let chain, chain.isLive(at: now) { return .armed(chain) }
        if let m = morning?.window(at: now) { return .morning(m) }
        return .idle(morning)
    }

    /// Smart Stack: rotate it up while there's something to count, and keep it
    /// out of the way the rest of the day.
    var relevanceScore: Float {
        switch self {
        case .armed: return 100
        case .morning: return 80
        case .idle: return 1
        }
    }
}

enum CountdownStore {
    static let widgetKind = "CountdownWidget"
    static let chainKey = "backplan.armedChain"
    static let morningKey = "backplan.morningInputs"

    static func loadChain() -> ArmedChain? { load(chainKey) }
    static func loadMorning() -> MorningInputs? { load(morningKey) }

    /// Each returns true when the stored value actually changed, so the caller
    /// reloads the widget only then. `nil` clears.
    @discardableResult
    static func save(chain: ArmedChain?) -> Bool { save(chain, chainKey) }
    @discardableResult
    static func save(morning: MorningInputs) -> Bool { save(morning, morningKey) }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = SleepLeft.sharedDefaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, _ key: String) -> Bool {
        guard let defaults = SleepLeft.sharedDefaults else { return false }
        guard let value else {
            guard defaults.object(forKey: key) != nil else { return false }
            defaults.removeObject(forKey: key)
            return true
        }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        if defaults.data(forKey: key) == data { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
