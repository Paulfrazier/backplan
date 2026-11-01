#if DEBUG
import SwiftUI
import WidgetKit

/// `-BPWidgetGallery`: every Sleep Left family at three points in one evening,
/// rendered in the app so they can be screenshot from the simulator (which
/// can't add a widget to the Home Screen headlessly). Sizes are the iPhone
/// 15/16 Pro widget sizes; the Lock Screen ones sit on a dark ground in white,
/// roughly how the system renders them.
struct SleepWidgetGallery: View {
    private let inputs = SleepLeft.Inputs.preview

    private func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DayWidgetGallerySection()
                Text("School 8:05 · 70 min morning · 40 min wind-down · need 11h")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach([(18, 30), (19, 25), (21, 30)], id: \.0) { h, m in
                    let now = at(h, m)
                    Text(SleepLeft.time(now)).font(.caption.bold())
                    home(now, inputs, .systemSmall, width: 158)
                    if h == 18 { home(now, inputs, .systemMedium, width: 338) }
                    lock(now, inputs)
                }
                Text("Night pair off").font(.caption.bold())
                home(at(20, 0), nil, .systemSmall, width: 158)
                lock(at(20, 0), nil)
                CountdownGallerySection()
            }
            .padding(16)
        }
        .background(Color(white: 0.85))
    }

    private func home(_ now: Date, _ i: SleepLeft.Inputs?, _ f: WidgetFamily, width: CGFloat) -> some View {
        SleepLeftView(now: now, inputs: i, family: f)
            .padding(16)
            .frame(width: width, height: 158)
            .background(Color.bpPaper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func lock(_ now: Date, _ i: SleepLeft.Inputs?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SleepLeftView(now: now, inputs: i, family: .accessoryInline)
                .font(.caption)
            HStack(spacing: 8) {
                SleepLeftView(now: now, inputs: i, family: .accessoryCircular)
                    .frame(width: 72, height: 72)
                SleepLeftView(now: now, inputs: i, family: .accessoryRectangular)
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
#endif
