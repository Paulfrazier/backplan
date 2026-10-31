import SwiftUI
import WidgetKit

/// The Sleep Left widget's faces, one per family.
///
/// Lives in `ios/Shared` rather than the extension so a DEBUG build of the app
/// can render every family side by side (`-BPWidgetGallery`) — the simulator
/// can't add a widget to the Home Screen headlessly, so this is how the faces
/// get screenshot-checked.
struct SleepLeftView: View {
    let now: Date
    let inputs: SleepLeft.Inputs?
    let family: WidgetFamily

    var body: some View {
        if let inputs, inputs.enabled {
            face(SleepLeft.solve(inputs, now: now), inputs)
        } else {
            setup
        }
    }

    // MARK: - Faces

    @ViewBuilder
    private func face(_ n: SleepLeft.Night, _ i: SleepLeft.Inputs) -> some View {
        switch family {
        case .accessoryCircular: circular(n)
        case .accessoryRectangular: rectangular(n, i)
        case .accessoryInline: inline(n)
        case .systemMedium: medium(n, i)
        default: small(n, i)
        }
    }

    private func small(_ n: SleepLeft.Night, _ i: SleepLeft.Inputs) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            Spacer(minLength: 6)
            figure(n, size: 34)
            Text(ifNow(i))
                .font(.caption2)
                .foregroundStyle(Color.bpMuted)
            Spacer(minLength: 8)
            bar(n)
            Text(footer(n, i))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink(n.verdict))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ n: SleepLeft.Night, _ i: SleepLeft.Inputs) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                Spacer(minLength: 6)
                figure(n, size: 38)
                Text(ifNow(i))
                    .font(.caption2)
                    .foregroundStyle(Color.bpMuted)
                Spacer(minLength: 8)
                bar(n)
                Text(footer(n, i))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink(n.verdict))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                row(startWord(i), SleepLeft.time(n.startBy), strong: n.verdict == .onTrack)
                row("Wake", SleepLeft.time(n.wake))
                row(i.morningName.isEmpty ? "Morning" : i.morningName, SleepLeft.time(n.morningTarget))
                row(i.sleeper.isEmpty ? "Need" : "\(i.sleeper) needs", SleepLeft.hm(i.sleepNeed))
            }
            .frame(width: 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock Screen: renders tinted/monochrome, so no palette — shape only.
    private func circular(_ n: SleepLeft.Night) -> some View {
        Gauge(value: n.fraction) {
            Image(systemName: "moon.zzz.fill")
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text("\(max(0, n.sleepMinutes) / 60)h")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(String(format: "%02dm", max(0, n.sleepMinutes) % 60))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ n: SleepLeft.Night, _ i: SleepLeft.Inputs) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Sleep left", systemImage: "moon.zzz.fill")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(SleepLeft.hm(n.sleepMinutes))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(footer(n, i))
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ n: SleepLeft.Night) -> some View {
        Label("\(SleepLeft.hm(n.sleepMinutes)) sleep left", systemImage: "moon.zzz.fill")
    }

    /// No night pair, or nothing published yet.
    @ViewBuilder
    private var setup: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "moon.zzz")
            }
        case .accessoryInline:
            Label("Set a wake-up in Backplan", systemImage: "moon.zzz")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Sleep left", systemImage: "moon.zzz").font(.caption.weight(.semibold))
                Text("Chain tomorrow morning in Backplan").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                eyebrow
                Spacer(minLength: 0)
                Text("No morning to count to")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.bpInk)
                Text("In Backplan, turn on \u{201C}Chain tomorrow morning\u{201D} and set the morning target.")
                    .font(.caption2)
                    .foregroundStyle(Color.bpMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
            Text("SLEEP LEFT").kerning(0.6)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.bpPurple)
    }

    private func figure(_ n: SleepLeft.Night, size: CGFloat) -> some View {
        Text(SleepLeft.hm(n.sleepMinutes))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ink(n.verdict))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Sleep left against the need. A notch at 100% so "full" reads as a line
    /// you're above or below, not just a long bar.
    private func bar(_ n: SleepLeft.Night) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.bpRule.opacity(0.6))
                Capsule().fill(fill(n.verdict))
                    .frame(width: max(6, geo.size.width * n.fraction))
            }
        }
        .frame(height: 6)
    }

    private func row(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Color.bpMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(strong ? .bold : .semibold)
                .foregroundStyle(Color.bpInk)
                .monospacedDigit()
        }
        .font(.caption)
    }

    // MARK: - Copy

    /// What has to start now for the figure to be true.
    private func ifNow(_ i: SleepLeft.Inputs) -> String {
        if i.rideMinutes > 0 { return "if you leave now" }
        if i.windDownMinutes > 0 { return "if wind-down starts now" }
        return "if lights out now"
    }

    private func startWord(_ i: SleepLeft.Inputs) -> String {
        if i.rideMinutes > 0 { return "Leave by" }
        if i.windDownMinutes > 0 { return "Start by" }
        return "Lights out"
    }

    private func footer(_ n: SleepLeft.Night, _ i: SleepLeft.Inputs) -> String {
        switch n.verdict {
        case .onTrack:
            return "\(startWord(i)) \(SleepLeft.time(n.startBy))"
        case .tight, .short:
            return "\(SleepLeft.duration(n.deficitMinutes)) short"
        }
    }

    /// Ink on paper. Same three tones as the tracker's verdict pill.
    private func ink(_ v: SleepLeft.Verdict) -> Color {
        switch v {
        case .onTrack: return .bpLimeInk
        case .tight: return .bpGoldInk
        case .short: return .bpCoral
        }
    }

    private func fill(_ v: SleepLeft.Verdict) -> Color {
        switch v {
        case .onTrack: return .bpLime
        case .tight: return .bpGold
        case .short: return .bpCoral
        }
    }
}
