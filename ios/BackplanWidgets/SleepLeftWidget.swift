import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen / StandBy: hours of sleep left before tomorrow's
/// wake, if the wind-down started now.
///
/// The figure falls exactly one minute per wall-clock minute, so the provider
/// lays out one entry per minute from a single snapshot of plan inputs and the
/// widget stays right with the app closed. The app reloads it only when those
/// inputs change (`PlanStore.publishSleepLeft`).
struct SleepLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SleepLeft.widgetKind, provider: SleepLeftProvider()) { entry in
            SleepLeftEntryView(entry: entry)
        }
        .configurationDisplayName("Sleep Left")
        .description("How much sleep is left before tomorrow's wake-up, if the wind-down starts now.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct SleepLeftEntry: TimelineEntry {
    let date: Date
    let inputs: SleepLeft.Inputs?
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
        completion(SleepLeftEntry(date: Date(), inputs: inputs))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepLeftEntry>) -> Void) {
        let now = Date()
        let inputs = SleepLeft.load()
        guard let inputs, inputs.enabled else {
            // Nothing ticks; the app reloads when the pair is switched on.
            completion(Timeline(entries: [SleepLeftEntry(date: now, inputs: inputs)], policy: .never))
            return
        }
        // Wake and every chain length are whole minutes, so the floored figure
        // only changes on the minute: one entry now, then one per boundary.
        let cal = Calendar.current
        let firstBoundary = cal.nextDate(after: now, matching: DateComponents(second: 0),
                                         matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        var entries = [SleepLeftEntry(date: now, inputs: inputs)]
        for m in 0..<Self.horizonMinutes {
            entries.append(SleepLeftEntry(date: firstBoundary.addingTimeInterval(TimeInterval(m * 60)),
                                          inputs: inputs))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SleepLeftEntryView: View {
    let entry: SleepLeftEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        SleepLeftView(now: entry.date, inputs: entry.inputs, family: family)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { Color.bpPaper }
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
