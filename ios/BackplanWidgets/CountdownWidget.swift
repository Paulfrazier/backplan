import AppIntents
import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen / StandBy: the armed countdown — current step,
/// what's next, a clock to the boundary, Done / +5 — and in the school-morning
/// window with nothing armed, the morning plan as written.
///
/// The timeline is the point. The Live Activity can only change its step name
/// while the app is running; this lays out one entry per boundary from the
/// published chain, so the name advances with the app suspended or killed.
/// The app reloads it only when the chain or the morning inputs change.
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CountdownStore.widgetKind, provider: CountdownProvider()) { entry in
            CountdownEntryView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        .description("The step you're on, what's next, and Done / +5 — or tomorrow morning when nothing's armed.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let face: CountdownFace
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: face.relevanceScore) }
}

struct CountdownProvider: TimelineProvider {
    /// How far ahead to lay out boundaries. A morning plan or a Day fits well
    /// inside it; past the end the system asks again.
    static let horizon: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: Date(), face: .morning(Self.previewChain(now: Date())))
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        let now = Date()
        let face = CountdownFace.resolve(chain: CountdownStore.loadChain(),
                                         morning: CountdownStore.loadMorning(), now: now)
        // The gallery preview shouldn't show "nothing armed".
        if context.isPreview, case .idle = face {
            completion(CountdownEntry(date: now, face: .morning(Self.previewChain(now: now))))
        } else {
            completion(CountdownEntry(date: now, face: face))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let now = Date()
        let chain = CountdownStore.loadChain()
        let morning = CountdownStore.loadMorning()
        let dates = [now] + Self.changeDates(chain: chain, morning: morning, now: now)
        var entries: [CountdownEntry] = []
        for d in dates {
            let face = CountdownFace.resolve(chain: chain, morning: morning, now: d)
            // Consecutive identical idle faces add nothing; running ones differ
            // by the reading, which is derived from the entry date, so keep them.
            if case .idle = face, let last = entries.last, last.face == face { continue }
            entries.append(CountdownEntry(date: d, face: face))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Every moment within the horizon at which the face or its words change:
    /// the armed chain's boundaries and its expiry, and the next morning
    /// window's opening, boundaries and bell.
    static func changeDates(chain: ArmedChain?, morning: MorningInputs?, now: Date) -> [Date] {
        var marks: [Date] = []
        if let chain, chain.isLive(at: now) {
            marks += chain.changeMarks
            marks.append(chain.target.addingTimeInterval(min(chain.overGrace, ArmedChain.maxAge)))
        }
        if let morning, morning.enabled, morning.totalMinutes > 0 {
            // Today's and tomorrow's mornings, so an evening reload already
            // knows when the window opens.
            var t = now
            for _ in 0..<2 {
                let target = morning.nextTarget(after: t)
                let c = morning.chain(endingAt: target)
                marks.append(c.armedAt)
                marks += c.changeMarks
                t = target.addingTimeInterval(1)
            }
            // The idle face says "Today" or "Tomorrow", which flips at midnight.
            if let midnight = Calendar.current.date(byAdding: .day, value: 1,
                                                    to: Calendar.current.startOfDay(for: now)) {
                marks.append(midnight)
            }
        }
        let end = now.addingTimeInterval(horizon)
        // A second past each boundary, so the entry renders the state we're
        // entering rather than the edge of the one we're leaving.
        return Array(Set(marks.filter { $0 > now && $0 < end }))
            .sorted()
            .prefix(150)
            .map { $0.addingTimeInterval(0.5) }
    }

    static func previewChain(now: Date) -> ArmedChain {
        let target = now.addingTimeInterval(52 * 60)
        return MorningInputs.preview.chain(endingAt: Calendar.current.date(
            bySetting: .second, value: 0, of: target) ?? target)
    }
}

struct CountdownEntryView: View {
    let entry: CountdownEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        CountdownView(now: entry.date, face: entry.face, family: family)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { Color.bpPaper }
            }
            // The router (another branch) sends this to the Now screen.
            .widgetURL(URL(string: "backplan://now"))
    }
}

/// Control Center / Lock Screen / Action button: one tap arms tomorrow
/// morning. iOS 18 only; the widget's own Start button covers iOS 17.
@available(iOS 18, *)
struct StartMorningControl: ControlWidget {
    static let kind = "StartMorningControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartMorningIntent()) {
                Label("Start school morning", systemImage: "sunrise.fill")
            }
        }
        .displayName("Start school morning")
        .description("Arm the morning plan in Backplan.")
    }
}
