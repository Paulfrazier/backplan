#if DEBUG
import SwiftUI
import WidgetKit

/// The Day widget's families at a few moments of one seeded Day, for the
/// `-BPWidgetGallery` screen. `-BPDayGalleryPage N` picks a page (the screen
/// only fits so many), since the simulator can't scroll headlessly.
struct DayWidgetGallerySection: View {
    private static func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    /// Climb (flex) → Pick-up 3:00 pinned at school → Dinner pinned, routed
    /// legs 15 min each. `homework` squeezes a block in until it doesn't fit.
    static func snapshot(dinner: String, homework: Bool = false) -> DayWidget.Snapshot {
        var blocks = [
            DayBlock(name: "Climb", duration: 1, unit: .hr, placeID: DebugSeed.gym.id),
            DayBlock(name: "Pick-up", duration: 30, unit: .min, at: "15:00", placeID: DebugSeed.school.id),
        ]
        if homework { blocks.append(DayBlock(name: "Homework", duration: 45, unit: .min)) }
        blocks.append(DayBlock(name: "Dinner", duration: 30, unit: .min, at: dinner))
        let places = [DebugSeed.home, DebugSeed.gym, DebugSeed.school]
        let r = DayPlanner.compute(DayPlan(date: .today, blocks: blocks), places: places, now: at(9, 0)) { _, _, _ in .ok(15) }
        return DayWidget.snapshot(from: r, places: places, dayKey: DayWidget.key(Date()))
    }

    private var page: Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-BPDayGalleryPage"), a.indices.contains(i + 1) else { return 0 }
        return Int(a[i + 1]) ?? 0
    }

    var body: some View {
        // Only on request, so the Sleep Left gallery below stays what it was.
        if ProcessInfo.processInfo.arguments.contains("-BPDayGalleryPage") { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch page {
            case 0:
                let roomy = Self.snapshot(dinner: "18:00")
                scene("Free time: 12:10, Pick-up 3:00 pinned", roomy, Self.at(12, 10), medium: true)
                scene("Climb running: 14:00", roomy, Self.at(14, 0), medium: false)
            case 1:
                let tight = Self.snapshot(dinner: "15:20", homework: true)
                scene("Over by: 14:40, Dinner 3:20 squeezes Homework", tight, Self.at(14, 40), medium: true)
                scene("Leaving: 14:30 in the lead-in", Self.snapshot(dinner: "18:00"), Self.at(14, 30), medium: false)
            default:
                let roomy = Self.snapshot(dinner: "18:00")
                scene("After the last block: 7 PM", roomy, Self.at(19, 0), medium: false)
                scene("No Day published", nil, Self.at(12, 0), medium: false)
            }
        }
    }

    private func scene(_ title: String, _ s: DayWidget.Snapshot?, _ now: Date, medium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold())
            home(s, now, .systemSmall, width: 158)
            if medium { home(s, now, .systemMedium, width: 338) }
            VStack(alignment: .leading, spacing: 8) {
                DayWidgetView(now: now, snapshot: s, family: .accessoryInline).font(.caption)
                DayWidgetView(now: now, snapshot: s, family: .accessoryRectangular)
                    .frame(width: 170, height: 72, alignment: .topLeading)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(width: 338, alignment: .topLeading)
            .background(Color(hex: 0x2B2440))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
    }

    private func home(_ s: DayWidget.Snapshot?, _ now: Date, _ f: WidgetFamily, width: CGFloat) -> some View {
        DayWidgetView(now: now, snapshot: s, family: f)
            .padding(16)
            .frame(width: width, height: 158)
            .background(Color.bpPaper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
