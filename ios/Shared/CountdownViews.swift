import AppIntents
import SwiftUI
import WidgetKit

/// The Countdown widget's faces, one per family, in each of its three states
/// (armed / morning window / idle).
///
/// Lives in `ios/Shared`, like `SleepLeftView`, so a DEBUG app build can render
/// every face side by side (`-BPCountdownGallery`) for screenshots.
///
/// Every clock is a `Text(timerInterval:)` or `ProgressView(timerInterval:)`:
/// the system ticks them, so the timeline only needs an entry when the *words*
/// change — one per step boundary.
struct CountdownView: View {
    let now: Date
    let face: CountdownFace
    let family: WidgetFamily

    var body: some View {
        switch face {
        case .armed(let chain):
            if let r = chain.reading(at: now) { running(chain, r, armed: true) } else { idle(nil) }
        case .morning(let chain):
            if let r = chain.reading(at: now) { running(chain, r, armed: false) } else { idle(nil) }
        case .idle(let m):
            idle(m)
        }
    }

    // MARK: - Running (armed, or the morning window)

    @ViewBuilder
    private func running(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        switch family {
        case .accessoryCircular: circular(c, r, armed: armed)
        case .accessoryRectangular: rectangular(c, r, armed: armed)
        case .accessoryInline: inline(c, r, armed: armed)
        case .systemMedium: medium(c, r, armed: armed)
        default: small(c, r, armed: armed)
        }
    }

    private func small(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow(c, r, armed: armed)
            Spacer(minLength: 4)
            Text(clockLabel(c, r, armed: armed).uppercased())
                .font(.system(size: 9, weight: .bold)).kerning(0.5)
                .foregroundStyle(Color.bpMuted)
            clock(c, r, armed: armed)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(ink(r, armed: armed))
            Text(nowLine(c, r, armed: armed))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.bpInk)
                .lineLimit(1)
            if let n = nextLine(c, r, armed: armed) {
                Text(n).font(.caption2).foregroundStyle(Color.bpMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            buttons(r, armed: armed, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow(c, r, armed: armed)
                Spacer(minLength: 4)
                Text(clockLabel(c, r, armed: armed).uppercased())
                    .font(.system(size: 9, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Color.bpMuted)
                clock(c, r, armed: armed)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(ink(r, armed: armed))
                Text(nowLine(c, r, armed: armed))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                Spacer(minLength: 6)
                bar(c, r)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(upNext(c, r).enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.name).lineLimit(1).foregroundStyle(Color.bpInk)
                        Spacer(minLength: 4)
                        Text(SleepLeft.time(s.start)).monospacedDigit().foregroundStyle(Color.bpMuted)
                    }
                    .font(.caption)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(c.kind == .day ? "Last block" : c.eventName.isEmpty ? "Target" : c.eventName)
                        .lineLimit(1).fontWeight(.bold)
                    Spacer(minLength: 4)
                    Text(SleepLeft.time(c.target)).monospacedDigit().fontWeight(.bold)
                }
                .font(.caption)
                .foregroundStyle(Color.bpInk)
                Spacer(minLength: 2)
                buttons(r, armed: armed, compact: false)
            }
            .frame(width: 140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock Screen: tinted / monochrome, so shape and weight only.
    private func rectangular(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // One concatenated line: a `Text(timerInterval:)` in an HStack
            // claims its widest possible width and pushes out of the 170pt face.
            (Text(nowLine(c, r, armed: armed)).fontWeight(.bold)
                + Text(" \u{00B7} ")
                + Text(clockEnd(c, r, armed: armed), style: .timer).fontWeight(.bold))
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .widgetAccentable()
            Text(nextLine(c, r, armed: armed) ?? clockLabel(c, r, armed: armed))
                .font(.caption2)
                .lineLimit(1)
            buttons(r, armed: armed, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// No progress ring: a timer-driven circular `ProgressView` is a ring only
    /// in some renderers (in-app it is a spinner), so the clock carries it.
    private func circular(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: armed ? (r.phase == .past ? "exclamationmark.triangle.fill" : "hourglass")
                                        : "sunrise.fill")
                    .font(.system(size: 12, weight: .bold))
                    .widgetAccentable()
                Text(clockEnd(c, r, armed: armed), style: .timer)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
    }

    private func inline(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        let words = armed ? nowLine(c, r, armed: true) : "\(c.eventName)"
        // Inline takes one line of text; a `.timer` date concatenates where a
        // timerInterval text can't.
        return Text("\(words) \u{00B7} ") + Text(clockEnd(c, r, armed: armed), style: .timer)
    }

    /// What a `.timer`-style date counts to — and, once past, up from, which
    /// is exactly "over by".
    private func clockEnd(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> Date {
        clockRange(c, r, armed: armed).1
    }

    // MARK: - Idle

    @ViewBuilder
    private func idle(_ m: MorningInputs?) -> some View {
        if let m, m.enabled, m.totalMinutes > 0 {
            let target = m.nextTarget(after: now)
            let wake = target.addingTimeInterval(TimeInterval(-m.totalMinutes * 60))
            let day = Calendar.current.isDate(target, inSameDayAs: now) ? "Today" : "Tomorrow"
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "sunrise.fill").font(.system(size: 13))
                        Text(SleepLeft.time(wake)).font(.system(size: 11, weight: .bold))
                            .minimumScaleFactor(0.6).lineLimit(1)
                    }
                    .padding(4)
                }
            case .accessoryInline:
                Label("\(m.displayName) \(SleepLeft.time(target)) \u{00B7} wake \(SleepLeft.time(wake))",
                      systemImage: "sunrise")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(day): \(m.displayName) \(SleepLeft.time(target))")
                        .font(.caption.weight(.bold)).lineLimit(1).widgetAccentable()
                    Text("Wake \(SleepLeft.time(wake))").font(.caption2)
                    startButton(compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 2) {
                    idleEyebrow
                    Spacer(minLength: 4)
                    Text(day.uppercased())
                        .font(.system(size: 9, weight: .bold)).kerning(0.5)
                        .foregroundStyle(Color.bpMuted)
                    Text("\(m.displayName) \(SleepLeft.time(target))")
                        .font(.system(size: family == .systemMedium ? 24 : 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    // The routine's length only fits beside wake on the medium face.
                    Text(family == .systemMedium
                         ? "Wake \(SleepLeft.time(wake)) \u{00B7} \(SleepLeft.duration(m.totalMinutes))"
                         : "Wake \(SleepLeft.time(wake))")
                        .font(.caption).foregroundStyle(Color.bpMuted).lineLimit(1)
                    Spacer(minLength: 4)
                    startButton(compact: family != .systemMedium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryCircular:
                ZStack { AccessoryWidgetBackground(); Image(systemName: "hourglass") }
            case .accessoryInline:
                Label("Nothing armed", systemImage: "hourglass")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label("Countdown", systemImage: "hourglass").font(.caption.weight(.semibold))
                    Text("Nothing armed in Backplan").font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    idleEyebrow
                    Spacer(minLength: 0)
                    Text("Nothing armed")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.bpInk)
                    Text("Start a plan in Backplan and its countdown shows here.")
                        .font(.caption2).foregroundStyle(Color.bpMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Copy

    private func eyebrow(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: armed ? "hourglass" : "sunrise.fill")
            Text((c.eventName.isEmpty ? "Backplan" : c.eventName).uppercased())
                .kerning(0.6).lineLimit(1)
            Spacer(minLength: 2)
            // Only the medium face has room for the pill. Not armed: say so, or a schedule nobody started reads as a
            // countdown that will alert you.
            if family == .systemMedium {
                Text(armed ? r.phaseWord : "Not started")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.bpMuted)
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.bpPurple)
    }

    private var idleEyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "sunrise.fill")
            Text("COUNTDOWN").kerning(0.6)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.bpPurple)
    }

    /// Armed, the clock counts to the next boundary (as the Live Activity
    /// does). In the morning window it counts to the bell: nothing is armed, so
    /// step boundaries are only advice, but the bell is real.
    private func clockLabel(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> String {
        armed ? r.label : "\(c.eventName) in"
    }

    private func clockRange(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> (Date, Date) {
        armed ? (r.windowStart, r.boundary) : (c.armedAt, c.target)
    }

    private func nowLine(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> String {
        if armed { return r.detail }
        if let cur = r.current { return "Now: \(cur)" }
        if r.phase == .future, let first = c.segments.first { return "Wake \(SleepLeft.time(first.start))" }
        return r.detail
    }

    private func nextLine(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> String? {
        // Before the start, `detail` already names the first step.
        if armed && r.phase == .future { return nil }
        guard let n = r.next else { return r.phase == .active ? "Then \(c.eventName.isEmpty ? "done" : c.eventName)" : nil }
        return "Next: \(n)"
    }

    @ViewBuilder
    private func clock(_ c: ArmedChain, _ r: ChainReading, armed: Bool) -> some View {
        if armed && r.phase == .past {
            // Counting *up* from the target is what "over by" means.
            Text(timerInterval: r.boundary...r.boundary.addingTimeInterval(24 * 3600), countsDown: false)
                .monospacedDigit()
        } else {
            let (start, end) = clockRange(c, r, armed: armed)
            Text(timerInterval: safe(start, end), countsDown: true)
                .monospacedDigit()
        }
    }

    /// The whole chain's span, like the Live Activity's bar.
    private func bar(_ c: ArmedChain, _ r: ChainReading) -> some View {
        ProgressView(timerInterval: safe(c.spanStart, c.spanEnd), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(r.phase == .past ? Color.bpCoral : Color.bpLimeInk)
    }

    private func upNext(_ c: ArmedChain, _ r: ChainReading) -> [ArmedChain.Segment] {
        Array(c.segments.filter { $0.start > now }.prefix(3))
    }

    private func ink(_ r: ChainReading, armed: Bool) -> Color {
        switch r.phase {
        case .past: return .bpCoral
        case .active: return armed ? .bpLimeInk : .bpPurple
        case .future: return .bpPurpleElectric
        }
    }

    // MARK: - Buttons

    /// Armed: Done / +5, which run in the app (`LiveActivityIntent`). In the
    /// morning window: Start, because there's nothing armed to adjust yet.
    @ViewBuilder
    private func buttons(_ r: ChainReading, armed: Bool, compact: Bool) -> some View {
        if armed {
            HStack(spacing: 6) {
                if r.canFinish {
                    Button(intent: FinishStepIntent()) {
                        pill("Done", systemImage: "checkmark", filled: true, compact: compact)
                    }
                    .buttonStyle(.plain)
                }
                if r.canSlip {
                    Button(intent: RunningLateIntent(minutes: 5)) {
                        pill("+5", systemImage: nil, filled: false, compact: compact)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            startButton(compact: compact)
        }
    }

    private func startButton(compact: Bool) -> some View {
        Button(intent: StartMorningIntent()) {
            pill("Start", systemImage: "play.fill", filled: true, compact: compact)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pill(_ title: String, systemImage: String?, filled: Bool, compact: Bool) -> some View {
        let label = HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: compact ? 8 : 10, weight: .bold)) }
            Text(title).font(.system(size: compact ? 11 : 13, weight: .bold))
        }
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 3 : 5)
        if isLock {
            // Tinted Lock Screen: the system recolours everything, so a fill
            // can't carry meaning — an outline reads in every rendering mode.
            label.overlay(Capsule().stroke(lineWidth: 1))
        } else {
            label
                .foregroundStyle(filled ? Color.bpPaper : Color.bpInk)
                .background(Capsule().fill(filled ? Color.bpInk : Color.clear))
                .overlay(Capsule().stroke(Color.bpInk, lineWidth: 1.5))
        }
    }

    /// `WidgetFamily.isAccessory` lives in the extension; the gallery needs this too.
    private var isLock: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    /// `Text(timerInterval:)` traps on an empty or inverted range.
    private func safe(_ start: Date, _ end: Date) -> ClosedRange<Date> {
        start...max(end, start.addingTimeInterval(1))
    }
}
