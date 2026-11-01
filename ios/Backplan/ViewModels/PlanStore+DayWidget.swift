import Foundation
import WidgetKit

/// Publishing the solved Day to the Day widget (see `DayWidget`).
extension DayWidget {
    /// Flatten a `DayResult`. Pure, so the self-check can run it on a scenario
    /// without a store.
    static func snapshot(from r: DayResult, places: [SavedPlace], dayKey: String) -> Snapshot {
        var blocks: [Block] = []
        var legs: [Leg] = []
        func add(_ d: Date, _ m: Int) -> Date { d.addingTimeInterval(TimeInterval(m * 60)) }

        for it in r.items {
            let b = it.block
            let place = places.first { $0.id == b.placeID }?.name ?? it.comp?.endPlace?.label
            blocks.append(Block(index: it.index, name: b.name.trimmingCharacters(in: .whitespaces),
                                start: it.start, end: it.end, pinned: b.isAnchor,
                                doneBy: b.isAnchor && b.edge == .end, place: place))
            // A plain block's travel runs up to its start; a plan-block's runs
            // inside it. Legs still being routed have no minutes yet — skipped.
            if let l = it.leg, l.minutes > 0 {
                legs.append(Leg(blockIndex: it.index, start: l.start, end: it.start, mode: l.mode.rawValue,
                                minutes: l.minutes, leaveBy: true))
            }
            for row in it.comp?.rows ?? [] {
                guard let l = row.leg, l.status != .there, row.minutes > 0 else { continue }
                let s = add(it.start, row.offset)
                legs.append(Leg(blockIndex: it.index, start: s, end: add(s, row.minutes), mode: l.mode.rawValue,
                                minutes: row.minutes, leaveBy: s <= it.start))
            }
        }
        // Only the first leg that starts with the block is its departure.
        var seen = Set<Int>()
        for i in legs.indices where legs[i].leaveBy {
            if !seen.insert(legs[i].blockIndex).inserted { legs[i].leaveBy = false }
        }

        let gaps = r.gaps.map { g -> Gap in
            if g.slack < 0 {
                return Gap(start: g.depart, end: r.items[g.q].start, overMinutes: -g.slack)
            }
            return Gap(start: g.freeFrom, end: g.depart, overMinutes: nil)
        }
        return Snapshot(dayKey: dayKey, blocks: blocks, legs: legs, gaps: gaps)
    }
}

extension PlanStore {
    /// Hand the widget today's Day; reload only when it changed. Called wherever
    /// the Day persists and when a routed leg lands (its minutes move times).
    func publishDayWidget() {
        // Only the real store — self-check stores must not land on the Home Screen.
        guard defaults === UserDefaults.standard else { return }
        let snap = DayWidget.snapshot(from: dayResult(), places: places,
                                      dayKey: LocalDay.key(day.effectiveDay()))
        if DayWidget.save(snap) {
            WidgetCenter.shared.reloadTimelines(ofKind: DayWidget.widgetKind)
        }
    }
}
