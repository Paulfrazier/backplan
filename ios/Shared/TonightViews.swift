import SwiftUI
import WidgetKit

/// The Tonight widget's faces. Shared (like `SleepLeftView`) so the DEBUG
/// gallery can render them in the app for screenshots.
///
/// The headline is the deadline, not the bedtime the user set: the deadline is
/// the one fact the evening can't negotiate with, and the set bedtime is
/// judged against it underneath.
struct TonightView: View {
    let now: Date
    let inputs: SleepLeft.Inputs?
    let family: WidgetFamily
    /// The gallery's stand-in for StandBy, which it can't enter; `nil` reads
    /// the real environment.
    var standBy: Bool? = nil

    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var isStandBy: Bool { standBy ?? (!showsBackground && !family.isAccessoryFace) }

    var body: some View {
        if let inputs, let night = Tonight.solve(inputs, now: now) {
            if isStandBy {
                nightstand(night)
            } else {
                face(night, inputs)
            }
        } else {
            setup
        }
    }

    @ViewBuilder
    private func face(_ n: Tonight.Night, _ i: SleepLeft.Inputs) -> some View {
        switch family {
        case .accessoryRectangular: rectangular(n)
        case .accessoryInline: inline(n)
        case .systemMedium: medium(n, i)
        default: small(n)
        }
    }

    private func small(_ n: Tonight.Night) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            Spacer(minLength: 4)
            Text("Lights out by")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.bpInk)
            deadline(n, size: 30)
            Text("or tomorrow starts short")
                .font(.caption2)
                .foregroundStyle(Color.bpMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            // The small face has room for the short start line, so the verdict
            // on the set bedtime can take two lines rather than truncate.
            if let live = n.liveShort.map(shortStart(n)) {
                Text(live)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(n.setLine)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ink(n.verdict))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ n: Tonight.Night, _ i: SleepLeft.Inputs) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                Spacer(minLength: 4)
                Text("Lights out by")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.bpInk)
                deadline(n, size: 34)
                Text("or tomorrow starts short")
                    .font(.caption2)
                    .foregroundStyle(Color.bpMuted)
                Spacer(minLength: 6)
                if let live = n.liveShort {
                    Text(live)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                if n.eveningMinutes > 0 { row("Start by", SleepLeft.time(n.latestStart), strong: true) }
                row("You set", SleepLeft.time(n.lightsOut), tint: ink(n.verdict))
                row("Wake", SleepLeft.time(n.wake))
                row(i.morningName.isEmpty ? "Morning" : i.morningName, SleepLeft.time(n.morningTarget))
                Text(n.pillText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ink(n.verdict))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint(n.verdict)))
                    .overlay(Capsule().strokeBorder(fill(n.verdict), lineWidth: 1))
            }
            .frame(width: 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock Screen: tinted / monochrome, so shape and weight only.
    private func rectangular(_ n: Tonight.Night) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Lights out by", systemImage: "bed.double.fill")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(SleepLeft.time(n.deadline))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(n.liveShort.map(shortStart(n)) ?? n.setLine)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ n: Tonight.Night) -> some View {
        Label("Lights out by \(SleepLeft.time(n.deadline))", systemImage: "bed.double.fill")
    }

    /// StandBy: read from across a dark room, so one huge number and one line.
    /// No paper, no brand inks — the system tints it red at night, and dark ink
    /// on black would vanish.
    private func nightstand(_ n: Tonight.Night) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LIGHTS OUT BY")
                .font(.caption.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(SleepLeft.time(n.deadline))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.primary)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(n.eveningMinutes > 0 && n.now < n.latestStart
                 ? "Start by \(SleepLeft.time(n.latestStart))"
                 : "Wake \(SleepLeft.time(n.wake))")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The pair is off (or the payload predates Tonight). The whole widget is a
    /// link to the wake-up sheet, so the copy says so.
    @ViewBuilder
    private var setup: some View {
        switch family {
        case .accessoryInline:
            Label("Tap to set a wake-up", systemImage: "bed.double")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Tonight", systemImage: "bed.double").font(.caption.weight(.semibold))
                Text("Tap to set a wake-up").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                if !isStandBy { eyebrow }
                Spacer(minLength: 0)
                Text("Tap to set a wake-up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isStandBy ? Color.primary : Color.bpInk)
                Text("Tonight\u{2019}s lights-out comes from tomorrow\u{2019}s wake and how much sleep you need.")
                    .font(.caption2)
                    .foregroundStyle(isStandBy ? Color.secondary : Color.bpMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "bed.double.fill")
            Text("TONIGHT").kerning(0.6)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.bpPurple)
    }

    private func deadline(_ n: Tonight.Night, size: CGFloat) -> some View {
        Text(SleepLeft.time(n.deadline))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.bpPurple)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func row(_ label: String, _ value: String, strong: Bool = false, tint: Color = .bpInk) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Color.bpMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(strong ? .bold : .semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .font(.caption)
    }

    /// The small and rectangular faces have one short line; "Start the evening by" doesn't fit.
    private func shortStart(_ n: Tonight.Night) -> (String) -> String {
        { live in
            guard n.now < n.latestStart, n.startNowSlackMinutes >= 0 else { return live }
            return "Start by \(SleepLeft.time(n.latestStart)) \u{00B7} \(SleepLeft.duration(n.minutesToLatestStart))"
        }
    }

    /// Same tones as the bridge's pill. Check times reads in the tight tone.
    private func ink(_ v: Tonight.Verdict) -> Color {
        switch v {
        case .onTrack: return .bpLimeInk
        case .tight, .checkTimes: return .bpGoldInk
        case .late: return .bpCoral
        }
    }

    private func fill(_ v: Tonight.Verdict) -> Color {
        switch v {
        case .onTrack: return .bpLime
        case .tight, .checkTimes: return .bpGold
        case .late: return .bpCoral
        }
    }

    private func tint(_ v: Tonight.Verdict) -> Color {
        switch v {
        case .onTrack: return .bpLimeTint
        case .tight, .checkTimes: return .bpGoldTint
        case .late: return .bpCoralTint
        }
    }
}

extension WidgetFamily {
    /// Lock Screen families. StandBy only ever shows the system sizes, and the
    /// Lock Screen also hides the container background — so "no background"
    /// means StandBy only off the accessory families.
    var isAccessoryFace: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}
