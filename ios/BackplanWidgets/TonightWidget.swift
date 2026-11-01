import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen / StandBy: tonight's real lights-out deadline
/// (tomorrow's wake − the sleep need), when the evening has to start to make
/// it, and whether the bedtime the user set clears it. The night pair's bridge
/// card, off the app.
///
/// Solved from the same App Group snapshot as Sleep Left (`Tonight.solve`), so
/// the app's one publish reloads both.
struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Tonight.widgetKind, provider: TonightProvider()) { entry in
            TonightEntryView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's lights-out deadline, worked back from tomorrow's wake-up, and when to start the evening.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TonightEntry: TimelineEntry {
    let date: Date
    let inputs: SleepLeft.Inputs?
    var relevance: TimelineEntryRelevance? = nil

    /// Smart Stack: rises from two hours before the evening has to start
    /// through lights out (the later of the set bedtime and the deadline).
    static func at(_ date: Date, _ inputs: SleepLeft.Inputs?) -> TonightEntry {
        guard let inputs, let n = Tonight.solve(inputs, now: date) else {
            return TonightEntry(date: date, inputs: inputs, relevance: TimelineEntryRelevance(score: 0))
        }
        return TonightEntry(date: date, inputs: inputs, relevance: TimelineEntryRelevance(
            score: Tonight.relevance(now: date, start: n.latestStart, end: max(n.lightsOut, n.deadline))))
    }
}

struct TonightProvider: TimelineProvider {
    /// Same shape as Sleep Left: the deadline itself only moves when the inputs
    /// do, but "25 min from now" moves every minute.
    static let horizonMinutes = 180

    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: Date(), inputs: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        let stored = SleepLeft.load()
        let usable = stored.flatMap { Tonight.solve($0, now: Date()) } != nil
        completion(TonightEntry(date: Date(), inputs: context.isPreview && !usable ? .preview : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let now = Date()
        let inputs = SleepLeft.load()
        guard let inputs, Tonight.solve(inputs, now: now) != nil else {
            // Nothing ticks; the app reloads when the pair is switched on.
            completion(Timeline(entries: [.at(now, inputs)], policy: .never))
            return
        }
        let firstBoundary = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                                      matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        var entries = [TonightEntry.at(now, inputs)]
        for m in 0..<Self.horizonMinutes {
            entries.append(.at(firstBoundary.addingTimeInterval(TimeInterval(m * 60)), inputs))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TonightEntryView: View {
    let entry: TonightEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TonightView(now: entry.date, inputs: entry.inputs, family: family)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { Color.bpPaper }
            }
            .widgetURL(URL(string: "backplan://sleep"))
    }
}
