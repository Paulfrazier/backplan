#if DEBUG
import SwiftUI
import WidgetKit

/// `-BPCountdownGallery [armed|morning|idle|live]`: every Countdown widget
/// family in one state, rendered in the app for simulator screenshots (the
/// simulator can't place a widget headlessly). One state per launch so a
/// screen holds all five families without scrolling; `live` renders whatever
/// the app just published to the App Group, which is the end-to-end check
/// that arm / Done / +5 actually reach the widget. `-BPWidgetGallery` shows
/// the armed state under the Sleep Left faces.
struct CountdownWidgetGallery: View {
    var body: some View {
        ScrollView {
            CountdownGallerySection(state: Self.requested)
                .padding(16)
        }
        .background(Color(white: 0.85))
    }

    static var requested: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-BPCountdownGallery"), args.indices.contains(i + 1),
              !args[i + 1].hasPrefix("-") else { return "armed" }
        return args[i + 1]
    }
}

struct CountdownGallerySection: View {
    var state = "armed"
    /// Sampled once, so every face in a screenshot reads the same moment.
    @State private var now = Date()

    private var face: CountdownFace {
        let minute = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
        switch state {
        case "live":
            return CountdownFace.resolve(chain: CountdownStore.loadChain(),
                                         morning: CountdownStore.loadMorning(), now: now)
        case "morning":
            // The bell in 47 min: Breakfast under way, Get dressed next.
            var m = MorningInputs.preview
            m.target = DebugSeed.hhmm(minute.addingTimeInterval(47 * 60))
            return CountdownFace.resolve(chain: nil, morning: m, now: now)
        case "idle":
            return .idle(.preview)
        default:
            // Armed 20 min ago, 12 min into Breakfast.
            let chain = MorningInputs.preview.chain(endingAt: minute.addingTimeInterval(48 * 60))
            return .armed(ArmedChain(kind: .plan, eventName: "School", target: chain.target,
                                     armedAt: minute.addingTimeInterval(-20 * 60), segments: chain.segments))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Countdown \u{00B7} \(state) \u{00B7} \(SleepLeft.time(now))")
                .font(.caption.bold())
            HStack(spacing: 12) {
                home(.systemSmall, width: 158)
                Spacer(minLength: 0)
            }
            home(.systemMedium, width: 338)
            VStack(alignment: .leading, spacing: 8) {
                CountdownView(now: now, face: face, family: .accessoryInline)
                    .font(.caption)
                HStack(spacing: 8) {
                    CountdownView(now: now, face: face, family: .accessoryCircular)
                        .frame(width: 72, height: 72)
                    CountdownView(now: now, face: face, family: .accessoryRectangular)
                        .frame(width: 170, height: 72)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(width: 338, alignment: .topLeading)
            .background(Color(hex: 0x2B2440))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
    }

    private func home(_ f: WidgetFamily, width: CGFloat) -> some View {
        CountdownView(now: now, face: face, family: f)
            .padding(16)
            .frame(width: width, height: 158)
            .background(Color.bpPaper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
