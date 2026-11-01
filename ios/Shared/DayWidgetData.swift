import Foundation

/// What the Day widget shows: a flat snapshot of today's Day, and the arithmetic
/// that reads it at any moment.
///
/// The widget runs in its own process and can't see `PlanStore` or `DayPlanner`,
/// so the app publishes the *solved* Day (`PlanStore.publishDayWidget`) to the
/// App Group and the widget reads it. Unlike Sleep Left's inputs, a solved Day
/// holds absolute times, so it stays right with the app closed for as long as
/// the Day itself does; the timeline just walks its boundaries.
///
/// Shared source (`ios/Shared`) so the payload and `read` can't drift between
/// the two processes. `DebugSeed.selfCheck` asserts `read` agrees with `DayResult`.
enum DayWidget {
    static let appGroup = "group.website.fairpoint.backplan"
    static let snapshotKey = "backplan.dayWidget"
    /// `WidgetConfiguration` kind — the app reloads by this.
    static let widgetKind = "DayWidget"
    /// How long before a "leave by" / pinned start the Smart Stack should lift it.
    static let relevanceWindow: TimeInterval = 30 * 60

    struct Block: Codable, Equatable, Sendable {
        /// Position in the Day; legs point back at it.
        var index: Int
        var name: String
        var start: Date
        var end: Date
        var pinned: Bool
        /// Pinned by its end ("done by"), not its start.
        var doneBy: Bool
        /// Where it happens, when the block has a place.
        var place: String?
    }

    struct Leg: Codable, Equatable, Sendable {
        var blockIndex: Int
        var start: Date
        var end: Date
        /// `TravelMode.rawValue` — the extension has no `TravelMode`.
        var mode: String
        var minutes: Int
        /// This leg's start is the "leave by" for its block (it starts no later
        /// than the block does). A leg inside a plan-block, after the block has
        /// begun, is travel but not the departure — same rule as `DayStatus`.
        var leaveBy: Bool
    }

    struct Gap: Codable, Equatable, Sendable {
        var start: Date
        var end: Date
        /// Set when the blocks between two pins don't fit; the gap is then the
        /// squeezed stretch, not free time.
        var overMinutes: Int?
    }

    struct Snapshot: Codable, Equatable, Sendable {
        /// "yyyy-MM-dd" — the calendar day the blocks are on.
        var dayKey: String
        var blocks: [Block]
        var legs: [Leg]
        var gaps: [Gap]

        /// Every moment the picture changes, plus the lead-in to each departure
        /// (relevance steps up there), sorted.
        var boundaries: [Date] {
            var out = Set<Date>()
            for b in blocks { out.insert(b.start); out.insert(b.end) }
            for l in legs { out.insert(l.start); out.insert(l.end) }
            for g in gaps { out.insert(g.start); out.insert(g.end) }
            for t in targets { out.insert(t.addingTimeInterval(-DayWidget.relevanceWindow)) }
            return out.sorted()
        }

        /// What the headline counts toward: each leave-by and pinned start.
        var targets: [Date] {
            var out: [Date] = []
            for l in legs where l.leaveBy { out.append(l.start) }
            for b in blocks where b.pinned { out.append(b.start) }
            return out
        }
    }

    // MARK: - Reading

    struct Reading: Equatable, Sendable {
        enum Kind: Sendable { case noDay, empty, done, live }
        var kind: Kind
        /// The headline block: the next pinned one, else the next one to start.
        var next: Block?
        var leaveBy: Date?
        /// Running right now.
        var current: Block?
        /// On the road right now.
        var travelling: Leg?
        /// Nothing running and nothing to leave for yet: minutes until the next
        /// thing (a departure or a block) begins.
        var freeMinutes: Int?
        var overMinutes: Int?
        /// The current block (if any) and the ones after it, up to three.
        var upcoming: [Block]
        /// Seconds from now to the departure / pinned start the Smart Stack is counting to.
        var secondsToTarget: TimeInterval?
    }

    static func read(_ s: Snapshot?, now: Date, calendar: Calendar = .current) -> Reading {
        func bare(_ k: Reading.Kind) -> Reading {
            Reading(kind: k, upcoming: [])
        }
        // A Day whose date isn't today — passed, or not yet here — says nothing
        // about today.
        guard let s, s.dayKey == key(now, calendar: calendar) else { return bare(.noDay) }
        guard !s.blocks.isEmpty else { return bare(.empty) }
        guard let lastEnd = s.blocks.map(\.end).max(), now < lastEnd else { return bare(.done) }

        let current = s.blocks.first { $0.start <= now && now < $0.end }
        let travelling = s.legs.first { $0.start <= now && now < $0.end }
        let ahead = s.blocks.filter { $0.start > now }.sorted { $0.start < $1.start }
        let next = ahead.first { $0.pinned } ?? ahead.first
        let leave = next.flatMap { n in
            s.legs.first { $0.leaveBy && $0.blockIndex == n.index }?.start
        }

        // Over beats everything else: it's the one line that needs action.
        let over = s.gaps.first { $0.overMinutes != nil && $0.start <= now && now <= $0.end }?.overMinutes

        var free: Int?
        if over == nil, current == nil, travelling == nil {
            let nextStart = ([ahead.first?.start] + s.legs.filter { $0.start > now }.map { Optional($0.start) })
                .compactMap { $0 }.min()
            // Inside a gap the end of it is the departure; otherwise the next
            // start of anything. Same number either way.
            let end = s.gaps.first { $0.overMinutes == nil && $0.start <= now && now < $0.end }?.end ?? nextStart
            if let end { free = Int((end.timeIntervalSince(now) / 60).rounded()) }
        }

        let upcoming = Array(((current.map { [$0] } ?? []) + ahead).prefix(3))
        let target = [leave, next?.start].compactMap { $0 }.filter { $0 > now }.min()
        return Reading(kind: .live, next: next, leaveBy: leave, current: current, travelling: travelling,
                       freeMinutes: free, overMinutes: over, upcoming: upcoming,
                       secondsToTarget: target.map { $0.timeIntervalSince(now) })
    }

    static func key(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of the day a snapshot is for, or nil if the key is malformed.
    static func dayStart(_ key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    // MARK: - Storage

    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> Snapshot? {
        guard let data = sharedDefaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// True when the stored snapshot actually changed — the caller only reloads
    /// the widget then, so editing a block's note costs nothing.
    @discardableResult
    static func save(_ s: Snapshot) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let enc = JSONEncoder()
        // Stable bytes, or the equality check below could miss.
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(s) else { return false }
        if defaults.data(forKey: snapshotKey) == data { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    // MARK: - Formatting

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// "1 hr 20 min" — mirrors `Fmt.duration`.
    static func duration(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static func symbol(forMode m: String) -> String {
        switch m {
        case "bike": return "bicycle"
        case "walk": return "figure.walk"
        default: return "car.fill"
        }
    }
}
