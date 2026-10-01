import Foundation

/// A routed leg's state as the planner sees it. Misses are `.loading` and get
/// listed in `DayResult.needed` so the store can fetch them.
enum LegLookup: Equatable, Sendable {
    case ok(Int)
    case loading
    case error(TravelError)
}

struct LegRequest: Hashable, Sendable {
    let key: String
    let mode: TravelMode
    let from: PlaceRef
    let to: PlaceRef
}

/// A travel leg in front of a plain block (previous place → this block's place).
struct DayLeg {
    let from: PlaceRef
    let to: PlaceRef
    let mode: TravelMode
    let key: String
    let lookup: LegLookup
    let minutes: Int
    var start: Date = .distantPast
}

/// One step of a plan-block, laid out against the day.
struct DayStepRow {
    enum LegStatus: Equatable { case ok, loading, error, there }
    struct Leg {
        let from: PlaceRef
        let to: PlaceRef
        let mode: TravelMode
        let key: String?
        let status: LegStatus
    }
    let name: String
    let minutes: Int
    let leg: Leg?
    /// Minutes from the block's start.
    let offset: Int
}

struct DayComposite {
    struct Bridge {
        let here: PlaceRef
        let natural: PlaceRef?
        let on: Bool
    }
    let minutes: Int
    let rows: [DayStepRow]
    let endPlace: PlaceRef?
    /// Present when bridging is possible: the day has you somewhere other than
    /// where the plan would otherwise leave from.
    let bridge: Bridge?
}

struct DayItem: Identifiable {
    var id: UUID { block.id }
    let block: DayBlock
    let index: Int
    let start: Date
    let end: Date
    let minutes: Int
    /// Inside a gap that runs over its next anchor.
    let over: Bool
    let leg: DayLeg?
    let comp: DayComposite?
}

/// The free time between two anchors. `slack` < 0 means it doesn't fit.
struct DayGap {
    let p: Int
    let q: Int
    let slack: Int
    let freeFrom: Date
    let depart: Date
}

struct DayResult {
    let items: [DayItem]
    let gaps: [DayGap]
    let anchored: Bool
    let needed: [LegRequest]

    /// The gap (if any) whose slack row sits on top of block `index`.
    func gap(before index: Int) -> DayGap? { gaps.first { $0.p + 1 == index } }
}

/// Port of the web `computeDay`. KEEP IN SYNC with index.html.
///
/// Pinned blocks sit at their clock time. Flex blocks between two anchors stack
/// backwards from the later one, so a gap's slack collects at its front and the
/// first departure is as late as it can be. Before the first anchor: backwards
/// too ("when do I leave"). After the last: forwards. No anchors: forwards from
/// now (or 9:00 tomorrow).
enum DayPlanner {
    /// Same key format as `RouteService.cacheKey`, so the two caches agree.
    static func legKey(_ mode: TravelMode, _ from: PlaceRef, _ to: PlaceRef) -> String {
        String(format: "%@|%.5f,%.5f|%.5f,%.5f", mode.rawValue, from.lat, from.lng, to.lat, to.lng)
    }

    /// Equirectangular metres — same as the web `distanceM`.
    static func distanceM(_ a: PlaceRef, _ b: PlaceRef) -> Double {
        let mLat = 111_320.0
        let mLng = 111_320.0 * cos(a.lat * .pi / 180)
        let dy = (a.lat - b.lat) * mLat
        let dx = (a.lng - b.lng) * mLng
        return (dx * dx + dy * dy).squareRoot()
    }

    static let samePlaceMeters = 75.0

    static func clock(_ hhmm: String, on day: TargetDay, now: Date) -> Date {
        Plan(target: hhmm, day: day).targetDate(now: now)
    }

    static func round5(_ d: Date, up: Bool = false, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let minute = Double(comps.minute ?? 0) / 5
        let rounded = Int(up ? minute.rounded(.up) : minute.rounded()) * 5
        var c = comps
        c.minute = 0
        let base = calendar.date(from: c) ?? d
        return base.addingTimeInterval(TimeInterval(rounded * 60))
    }

    static func hhmm(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func compute(
        _ day: DayPlan,
        places: [SavedPlace],
        now: Date = Date(),
        lookup: (TravelMode, PlaceRef, PlaceRef) -> LegLookup
    ) -> DayResult {
        let blocks = day.blocks
        let n = blocks.count
        let homeRef = places.first(where: { $0.isHome })?.ref
        var needed: [String: LegRequest] = [:]

        func look(_ mode: TravelMode, _ from: PlaceRef, _ to: PlaceRef) -> (String, LegLookup) {
            let key = legKey(mode, from, to)
            let r = lookup(mode, from, to)
            if r == .loading { needed[key] = LegRequest(key: key, mode: mode, from: from, to: to) }
            return (key, r)
        }

        // Where you are before each block: the last place set, else home.
        var legs = [DayLeg?](repeating: nil, count: n)
        var comps = [DayComposite?](repeating: nil, count: n)
        var D = [Int](repeating: 0, count: n)
        var here = homeRef
        for i in 0..<n {
            let b = blocks[i]
            if b.steps != nil {
                let c = layoutComposite(b, here: here, home: homeRef, look: look)
                comps[i] = c
                D[i] = c.minutes
                if let end = c.endPlace { here = end }
                continue
            }
            D[i] = b.minutes
            guard let pl = places.first(where: { $0.id == b.placeID }) else { continue }
            let there = pl.ref
            if let from = here, distanceM(from, there) > samePlaceMeters {
                let (key, r) = look(b.via, from, there)
                let mins: Int
                if case .ok(let m) = r { mins = m } else { mins = 0 }
                legs[i] = DayLeg(from: from, to: there, mode: b.via, key: key, lookup: r, minutes: mins)
            }
            here = there
        }

        let L = legs.map { $0?.minutes ?? 0 }
        var S = [Date](repeating: now, count: n)
        var over = [Bool](repeating: false, count: n)
        let anchors = blocks.indices.filter { blocks[$0].isAnchor }
        var gaps: [DayGap] = []

        func add(_ d: Date, _ m: Int) -> Date { d.addingTimeInterval(TimeInterval(m * 60)) }

        // Stack blocks (stop, q) backwards from anchor q; returns the departure.
        func back(_ q: Int, stop: Int) -> Date {
            var cursor = add(S[q], -L[q])
            var i = q - 1
            while i > stop {
                S[i] = add(cursor, -D[i])
                cursor = add(S[i], -L[i])
                i -= 1
            }
            return cursor
        }
        func fwd(from: Date, startIdx: Int) {
            var cursor = from
            guard startIdx < n else { return }
            for i in startIdx..<n {
                S[i] = add(cursor, L[i])
                cursor = add(S[i], D[i])
            }
        }

        if anchors.isEmpty {
            fwd(from: day.date == .today ? round5(now, up: true) : clock("09:00", on: day.date, now: now), startIdx: 0)
        } else {
            for a in anchors {
                let t = clock(blocks[a].at ?? "00:00", on: day.date, now: now)
                S[a] = blocks[a].edge == .end ? add(t, -D[a]) : t
            }
            _ = back(anchors[0], stop: -1)
            for k in 0..<(anchors.count - 1) {
                let p = anchors[k], q = anchors[k + 1]
                let depart = back(q, stop: p)
                let freeFrom = add(S[p], D[p])
                let slack = Int((depart.timeIntervalSince(freeFrom) / 60).rounded())
                gaps.append(DayGap(p: p, q: q, slack: slack, freeFrom: freeFrom, depart: depart))
                if slack < 0 { for i in (p + 1)...q { over[i] = true } }
            }
            let last = anchors[anchors.count - 1]
            fwd(from: add(S[last], D[last]), startIdx: last + 1)
        }

        let items = (0..<n).map { i -> DayItem in
            var leg = legs[i]
            leg?.start = add(S[i], -L[i])
            return DayItem(block: blocks[i], index: i, start: S[i], end: add(S[i], D[i]),
                           minutes: D[i], over: over[i], leg: leg, comp: comps[i])
        }
        return DayResult(items: items, gaps: gaps, anchored: !anchors.isEmpty,
                         needed: needed.values.sorted { $0.key < $1.key })
    }

    /// Lay a plan-block's steps out against the day. Mirrors the plan's own
    /// chain rule (explicit from → previous leg's to → home), except the first
    /// leg may be bridged from wherever the day has you.
    static func layoutComposite(
        _ b: DayBlock,
        here: PlaceRef?,
        home: PlaceRef?,
        look: (TravelMode, PlaceRef, PlaceRef) -> (String, LegLookup)
    ) -> DayComposite {
        var at: PlaceRef?
        var first = true
        var bridge: DayComposite.Bridge?
        var total = 0
        var rows: [DayStepRow] = []
        for st in b.steps ?? [] {
            var m = st.minutes
            var leg: DayStepRow.Leg?
            if let t = st.travel, let to = t.to {
                let natural = t.from ?? at ?? home
                var origin = natural
                if first {
                    first = false
                    if let here, natural.map({ distanceM(here, $0) > samePlaceMeters }) ?? true {
                        bridge = .init(here: here, natural: natural, on: b.bridge)
                        if b.bridge { origin = here }
                    }
                }
                if let origin {
                    if distanceM(origin, to) <= samePlaceMeters {
                        m = 0   // already there
                        leg = .init(from: origin, to: to, mode: t.mode, key: nil, status: .there)
                    } else if t.manual {
                        // A hand-typed duration stays the user's call.
                        leg = .init(from: origin, to: to, mode: t.mode, key: nil, status: .ok)
                    } else {
                        // Until a route lands, the plan's own number stands in.
                        let (key, r) = look(t.mode, origin, to)
                        let status: DayStepRow.LegStatus
                        switch r {
                        case .ok(let mins): m = mins; status = .ok
                        case .loading: status = .loading
                        case .error: status = .error
                        }
                        leg = .init(from: origin, to: to, mode: t.mode, key: key, status: status)
                    }
                }
                at = to
            }
            let trimmed = st.name.trimmingCharacters(in: .whitespaces)
            rows.append(DayStepRow(name: trimmed.isEmpty ? (leg != nil ? "Travel" : "Step") : trimmed,
                                   minutes: m, leg: leg, offset: total))
            total += m
        }
        return DayComposite(minutes: total, rows: rows, endPlace: at, bridge: bridge)
    }
}

/// The Day hero, as words. Port of the web `renderDayHero`.
struct DayStatus {
    var label = "Leave by"
    var time = "—"
    var meta = ""
    var late = false
    var nextFixedTime = "—"
    var nextFixedName = "Nothing pinned"
    var warning: String?

    static func make(_ r: DayResult, now: Date) -> DayStatus {
        var s = DayStatus()
        func named(_ it: DayItem) -> String {
            let t = it.block.name.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? (it.block.isAnchor ? "fixed block" : "next block") : t
        }
        func span(_ a: Date, _ b: Date) -> String {
            Fmt.duration(max(1, Int((abs(b.timeIntervalSince(a)) / 60).rounded())))
        }
        let up = r.items.first { $0.start > now }
        let cur = r.items.first { $0.start <= now && now < $0.end }

        if r.items.isEmpty {
            s.meta = "Pin a fixed time, then drop blocks in before it."
        } else if up == nil {
            s.label = cur != nil ? "Now" : "Day"
            s.time = cur.map { Fmt.time($0.end) } ?? "Done"
            s.meta = cur.map { "\(named($0)) until then" } ?? "Nothing left on today’s plan."
        } else if let up, let c = up.comp,
                  let row = c.rows.first(where: { $0.minutes > 0 && $0.leg != nil && $0.leg?.status != .there }),
                  let leg = row.leg {
            // A plan-block's departure is inside it: the first real travel step.
            let leave = up.start.addingTimeInterval(TimeInterval(row.offset * 60))
            if row.offset == 0 {
                s.label = "Leave by"
                s.time = Fmt.time(leave)
                s.meta = "\(leg.from.label) → \(leg.to.label) for \(named(up)) · in \(span(now, leave))"
            } else {
                s.label = "Start by"
                s.time = Fmt.time(up.start)
                s.meta = "\(named(up)), then leave \(leg.from.label) at \(Fmt.time(leave))"
            }
        } else if let up, let leg = up.leg {
            s.late = leg.start < now
            s.label = s.late ? "Should have left" : "Leave by"
            s.time = Fmt.time(leg.start)
            s.meta = "\(leg.mode.label) to \(leg.to.label) for \(named(up)) · " +
                (s.late ? "\(span(now, leg.start)) ago" : "in \(span(now, leg.start))")
        } else if let up {
            s.label = "Start by"
            s.time = Fmt.time(up.start)
            s.meta = "\(named(up)) · in \(span(now, up.start))"
        }
        if !r.items.isEmpty && !r.anchored {
            s.meta += " · nothing pinned, so this runs forward from now"
        }

        if let next = r.items.first(where: { $0.block.isAnchor && $0.start > now }) {
            let byEnd = next.block.edge == .end
            s.nextFixedTime = Fmt.time(byEnd ? next.end : next.start)
            s.nextFixedName = named(next) + (byEnd ? " · done by" : "")
        }
        if let bad = r.gaps.first(where: { $0.slack < 0 }) {
            let q = r.items[bad.q]
            s.warning = "\(Fmt.duration(-bad.slack)) too much before \(named(q)) at \(Fmt.time(q.start)). Shorten a block or move one out."
        }
        return s
    }
}

// MARK: - Arming a day

extension DayPlanner {
    /// The day as one armable chain: every leg, step and plain block that takes
    /// time becomes a segment, and the idle stretches between them stay gaps.
    ///
    /// Arming a day is the same act as arming a plan — alerts at each boundary,
    /// a frozen snapshot, one Live Activity — so rather than teach the timer a
    /// second shape this flattens the day into the one it already speaks.
    /// `PlanCountdown` knows what to say inside a gap ("Next up in").
    static func armable(_ r: DayResult, now: Date = Date()) -> PlanResult {
        func add(_ d: Date, _ m: Int) -> Date { d.addingTimeInterval(TimeInterval(m * 60)) }
        func named(_ it: DayItem) -> String {
            let t = it.block.name.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? (it.block.isAnchor ? "Fixed block" : "Block") : t
        }
        var segs: [PlanSegment] = []
        func push(_ name: String, _ start: Date, _ minutes: Int) {
            guard minutes > 0 else { return }
            segs.append(PlanSegment(id: UUID(), name: name, minutes: minutes,
                                    start: start, end: add(start, minutes)))
        }
        for it in r.items {
            if let leg = it.leg, leg.minutes > 0 {
                push("\(leg.mode.label) to \(leg.to.label)", leg.start, leg.minutes)
            }
            if let c = it.comp {
                for row in c.rows {
                    let name = row.leg.map { "\($0.mode.label) to \($0.to.label)" } ?? row.name
                    push(name, add(it.start, row.offset), row.minutes)
                }
            } else {
                push(named(it), it.start, it.minutes)
            }
        }
        // An over-full stretch can overlap its neighbours; the countdown walks
        // segments in time order, so that is the order they have to be in.
        segs.sort { $0.start < $1.start }
        let target = segs.map(\.end).max() ?? now
        return PlanResult(
            target: target,
            startTimes: segs.map(\.start),
            overallStart: segs.first?.start,
            overflowsPrevDay: false,
            totalMinutes: segs.reduce(0) { $0 + $1.minutes },
            segments: segs,
            isPast: target <= now
        )
    }
}
