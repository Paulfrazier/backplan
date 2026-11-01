import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen: the next pinned block and when to leave for it,
/// plus how much free time is left before the next thing starts.
///
/// The Day is solved in the app and published whole (`DayWidget.Snapshot`), so
/// the provider only walks its boundaries; the app reloads this when the Day
/// changes (`PlanStore.publishDayWidget`).
struct DayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayWidget.widgetKind, provider: DayWidgetProvider()) { entry in
            DayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Day")
        .description("The next pinned block, when to leave for it, and how much free time is left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct DayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DayWidget.Snapshot?
    let relevance: TimelineEntryRelevance?
}

struct DayWidgetProvider: TimelineProvider {
    /// Minute entries this far out keep "N min free" honest; past it, every
    /// ten minutes is close enough and keeps the timeline short.
    static let minuteHorizon: TimeInterval = 90 * 60
    static let maxEntries = 320

    func placeholder(in context: Context) -> DayWidgetEntry {
        DayWidgetEntry(date: Date(), snapshot: nil, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayWidgetEntry) -> Void) {
        completion(DayWidgetEntry(date: Date(), snapshot: DayWidget.load(), relevance: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayWidgetEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let snap = DayWidget.load()
        guard let snap, let dayStart = DayWidget.dayStart(snap.dayKey, calendar: cal),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            completion(Timeline(entries: [DayWidgetEntry(date: now, snapshot: snap, relevance: nil)], policy: .never))
            return
        }

        // Moments the picture changes, then the ticks that keep the free-time
        // figure falling, then the midnight after which the Day is yesterday's
        // (or, for a Day dated ahead, the midnight it becomes today's).
        var moments = Set(snap.boundaries)
        moments.insert(dayStart)
        moments.insert(dayEnd)
        var t = cal.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(60)
        while t < dayEnd {
            moments.insert(t)
            t = t.addingTimeInterval(t.timeIntervalSince(now) < Self.minuteHorizon ? 60 : 600)
        }
        let dates = ([now] + moments.filter { $0 > now && $0 <= dayEnd }.sorted()).prefix(Self.maxEntries)

        let entries = dates.enumerated().map { i, d in
            let next = i + 1 < dates.count ? dates[dates.startIndex + i + 1] : nil
            return DayWidgetEntry(date: d, snapshot: snap, relevance: Self.relevance(snap, at: d, until: next))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Smart Stack: lift the widget in the half hour before a departure or a
    /// pinned start — the moment this widget is the answer to "what now?".
    static func relevance(_ s: DayWidget.Snapshot, at d: Date, until next: Date?) -> TimelineEntryRelevance {
        let r = DayWidget.read(s, now: d)
        guard r.kind == .live else { return TimelineEntryRelevance(score: 0) }
        let span = next.map { $0.timeIntervalSince(d) } ?? 60
        if let secs = r.secondsToTarget, secs <= DayWidget.relevanceWindow {
            // Sooner is higher; a late departure (already past) keeps top score via `.live`.
            return TimelineEntryRelevance(score: 100 - Float(secs / DayWidget.relevanceWindow) * 30, duration: span)
        }
        return TimelineEntryRelevance(score: r.overMinutes != nil ? 40 : 10, duration: span)
    }
}

struct DayWidgetEntryView: View {
    let entry: DayWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        DayWidgetView(now: entry.date, snapshot: entry.snapshot, family: family)
            .widgetURL(URL(string: "backplan://day"))
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { Color.bpPaper }
            }
    }
}
