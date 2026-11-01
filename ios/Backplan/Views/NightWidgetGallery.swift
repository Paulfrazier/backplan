#if DEBUG
import SwiftUI
import WidgetKit

/// `-BPWidgetGallery -BPGallery tonight|standby`: the Tonight widget's faces,
/// and both night widgets as StandBy draws them, for simulator screenshots.
/// A section of its own (one screen each) so the gallery's original page and
/// these don't fight for the one screenshot the simulator gives.
struct NightWidgetGallery: View {
    let section: String
    private let inputs = SleepLeft.Inputs.preview

    private func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if section == "standby" { standBySection } else { tonightSection }
            }
            .padding(16)
        }
        .background(Color(white: 0.85))
    }

    // MARK: Tonight

    private var late: SleepLeft.Inputs {
        var i = inputs
        i.eveningTarget = "21:30"
        return i
    }

    @ViewBuilder
    private var tonightSection: some View {
        Text("School 8:05 · 70 min morning · 40 min evening · need 11h · bed 9:00")
            .font(.caption).foregroundStyle(.secondary)
        Text("\(SleepLeft.time(at(18, 50))) · bed 9:00").font(.caption.bold())
        HStack(spacing: 12) {
            home(at(18, 50), inputs, .systemSmall, width: 158)
            home(at(19, 30), late, .systemSmall, width: 158)
        }
        home(at(18, 50), inputs, .systemMedium, width: 338)
        lock(at(18, 50), inputs)
        Text("\(SleepLeft.time(at(19, 30))) · bed 9:30 — past the start").font(.caption.bold())
        lock(at(19, 30), late)
        Text("Night pair off").font(.caption.bold())
        HStack(alignment: .top, spacing: 12) {
            home(at(20, 0), nil, .systemSmall, width: 158)
            lock(at(20, 0), nil, width: 172)
        }
    }

    // MARK: StandBy

    @ViewBuilder
    private var standBySection: some View {
        Text("StandBy (nightstand) — the system tints red at night")
            .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 12) {
            standBy(SleepLeftView(now: at(19, 25), inputs: inputs, family: .systemSmall, standBy: true))
            standBy(TonightView(now: at(18, 50), inputs: inputs, family: .systemSmall, standBy: true))
        }
        HStack(spacing: 12) {
            standBy(SleepLeftView(now: at(21, 30), inputs: inputs, family: .systemSmall, standBy: true))
            standBy(TonightView(now: at(20, 0), inputs: nil, family: .systemSmall, standBy: true))
        }
        Text("Night mode, approximated").font(.caption.bold())
        HStack(spacing: 12) {
            standBy(SleepLeftView(now: at(22, 10), inputs: inputs, family: .systemSmall, standBy: true))
                .colorMultiply(Color(red: 1, green: 0.25, blue: 0.2))
            standBy(TonightView(now: at(19, 20), inputs: inputs, family: .systemSmall, standBy: true))
                .colorMultiply(Color(red: 1, green: 0.25, blue: 0.2))
        }
    }

    // MARK: Frames

    private func home(_ now: Date, _ i: SleepLeft.Inputs?, _ f: WidgetFamily, width: CGFloat) -> some View {
        TonightView(now: now, inputs: i, family: f, standBy: false)
            .padding(16)
            .frame(width: width, height: 158)
            .background(Color.bpPaper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func lock(_ now: Date, _ i: SleepLeft.Inputs?, width: CGFloat = 338) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TonightView(now: now, inputs: i, family: .accessoryInline, standBy: false)
                .font(.caption)
                .lineLimit(1)
            TonightView(now: now, inputs: i, family: .accessoryRectangular, standBy: false)
                .frame(width: 160, height: 72)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: width, alignment: .topLeading)
        .background(Color(hex: 0x2B2440))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// StandBy shows a small widget scaled up on black, with no container.
    private func standBy(_ face: some View) -> some View {
        face
            .padding(14)
            .frame(width: 163, height: 163)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
#endif
