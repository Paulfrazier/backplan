import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen / StandBy. In the evening (from 8 PM, or the
/// wind-down's start-by if earlier) through wake: hours of sleep left. The rest
/// of the day: what's next — a running countdown, the morning countdown, or the
/// Day's next fixed thing (see `UpNext`). Kind unchanged, so a widget already
/// placed as "Sleep Left" picks this up.
///
/// The sleep figure falls one minute per minute and the other faces change on
/// minute boundaries too, so the provider lays out one entry per minute from
/// the App Group snapshots and stays right with the app closed. The app reloads
/// it when any of those snapshots change.
struct SleepLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SleepLeft.widgetKind, provider: SleepLeftProvider()) { entry in
            SleepLeftEntryView(entry: entry)
        }
        .configurationDisplayName("Up Next & Sleep")
        .description("What's next during the day; from 8 PM, hours of sleep left before tomorrow's wake-up.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct SleepLeftEntry: TimelineEntry {
    let date: Date
    let inputs: SleepLeft.Inputs?
    var chain: ArmedChain? = nil
    var morning: MorningInputs? = nil
    var day: DayWidget.Snapshot? = nil
    var relevance: TimelineEntryRelevance? = nil

    var mode: UpNext.Mode {
        UpNext.mode(inputs: inputs, chain: chain, morning: morning, day: day, now: date)
    }

    /// Smart Stack: up while counting or in the evening run-up; middling in the
    /// half hour before a Day departure; low otherwise.
    static func at(_ date: Date, _ inputs: SleepLeft.Inputs?, chain: ArmedChain? = nil,
                   morning: MorningInputs? = nil, day: DayWidget.Snapshot? = nil) -> SleepLeftEntry {
        var e = SleepLeftEntry(date: date, inputs: inputs, chain: chain, morning: morning, day: day)
        let score: Float
        switch e.mode {
        case .countdown(.armed): score = 1
        case .countdown: score = 0.8
        case .day:
            let s = DayWidget.read(day, now: date).secondsToTarget ?? .infinity
            score = s <= 30 * 60 ? 0.7 : 0.2
        case .sleep:
            if let inputs, inputs.enabled {
                let n = SleepLeft.solve(inputs, now: date)
                score = Tonight.relevance(now: date, start: n.startBy, end: n.lightsOutBy)
            } else {
                score = 0
            }
        }
        e.relevance = TimelineEntryRelevance(score: score)
        return e
    }
}

struct SleepLeftProvider: TimelineProvider {
    /// Three hours of minute entries, then the system asks again. Entries are
    /// cheap; it's reloads that are budgeted, and this costs ~8 a day.
    static let horizonMinutes = 180

    func placeholder(in context: Context) -> SleepLeftEntry {
        SleepLeftEntry(date: Date(), inputs: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepLeftEntry) -> Void) {
        // The gallery preview shouldn't show a "set it up" card.
        let stored = SleepLeft.load()
        let inputs = context.isPreview && stored?.enabled != true ? .preview : stored
        completion(.at(Date(), inputs, chain: CountdownStore.loadChain(),
                       morning: CountdownStore.loadMorning(), day: DayWidget.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepLeftEntry>) -> Void) {
        let now = Date()
        let inputs = SleepLeft.load()
        let chain = CountdownStore.loadChain()
        let morning = CountdownStore.loadMorning()
        let day = DayWidget.load()
        guard inputs?.enabled == true || chain != nil || day != nil || morning?.enabled == true else {
            // Nothing to show but the set-up card; the app reloads on change.
            completion(Timeline(entries: [.at(now, inputs)], policy: .never))
            return
        }
        // Everything here changes on whole minutes: one entry now, then one per boundary.
        let cal = Calendar.current
        let firstBoundary = cal.nextDate(after: now, matching: DateComponents(second: 0),
                                         matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        var entries = [SleepLeftEntry.at(now, inputs, chain: chain, morning: morning, day: day)]
        for m in 0..<Self.horizonMinutes {
            entries.append(.at(firstBoundary.addingTimeInterval(TimeInterval(m * 60)), inputs,
                               chain: chain, morning: morning, day: day))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SleepLeftEntryView: View {
    let entry: SleepLeftEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { Color.bpPaper }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.mode {
        case .countdown(let face):
            CountdownView(now: entry.date, face: face, family: family)
                .widgetURL(URL(string: "backplan://now"))
        // The Day has no circular face; the sleep gauge stands in.
        case .day where family != .accessoryCircular:
            DayWidgetView(now: entry.date, snapshot: entry.day, family: family)
                .widgetURL(URL(string: "backplan://day"))
        default:
            // Every sleep face opens the wake-up sheet — the empty one most of all.
            SleepLeftView(now: entry.date, inputs: entry.inputs, family: family)
                .widgetURL(URL(string: "backplan://sleep"))
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}
