import SwiftUI
import WidgetKit

/// The Day widget's faces, one per family. In `ios/Shared` for the same reason
/// as `SleepLeftView`: the DEBUG gallery renders them in the app.
struct DayWidgetView: View {
    let now: Date
    let snapshot: DayWidget.Snapshot?
    let family: WidgetFamily

    private var r: DayWidget.Reading { DayWidget.read(snapshot, now: now) }

    var body: some View {
        let r = r
        if r.kind == .live {
            switch family {
            case .accessoryRectangular: rectangular(r)
            case .accessoryInline: Label(inlineText(r), systemImage: "calendar")
            case .systemMedium: medium(r)
            default: small(r)
            }
        } else {
            empty(r.kind)
        }
    }

    // MARK: - Faces

    private func small(_ r: DayWidget.Reading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            Spacer(minLength: 6)
            headline(r, titleSize: 22)
            Spacer(minLength: 6)
            status(r, lines: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ r: DayWidget.Reading) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                Spacer(minLength: 6)
                headline(r, titleSize: 22)
                Spacer(minLength: 6)
                status(r, lines: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The next three, as a rail: a dot per block, a stem between them.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(r.upcoming.enumerated()), id: \.offset) { i, b in
                    timelineRow(b, running: b.start <= now, last: i == r.upcoming.count - 1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 150, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangular(_ r: DayWidget.Reading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Day", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            if let n = r.next {
                Text("\(displayName(n)) \(DayWidget.time(stamp(n)))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let l = r.leaveBy {
                    Text(l > now ? "Leave by \(DayWidget.time(l))" : "Leave now")
                        .font(.caption2.weight(.semibold))
                }
            } else if let c = r.current {
                Text(displayName(c))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("until \(DayWidget.time(c.end))").font(.caption2.weight(.semibold))
            }
            Text(statusText(r)).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineText(_ r: DayWidget.Reading) -> String {
        guard let n = r.next else {
            return r.current.map { "\(displayName($0)) until \(DayWidget.time($0.end))" } ?? "Day"
        }
        var s = "\(displayName(n)) \(DayWidget.time(stamp(n)))"
        if let l = r.leaveBy { s += l > now ? " · leave \(DayWidget.time(l))" : " · leave now" }
        return s
    }

    @ViewBuilder
    private func empty(_ k: DayWidget.Reading.Kind) -> some View {
        let (title, sub): (String, String) = {
            switch k {
            case .empty: return ("Nothing on today\u{2019}s Day", "Drop blocks in, pin the fixed times.")
            case .done: return ("Day\u{2019}s done", "Nothing left on today\u{2019}s plan.")
            default: return ("No Day planned for today", "Open Backplan to plan one.")
            }
        }()
        switch family {
        case .accessoryInline:
            Label(title, systemImage: "calendar")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Day", systemImage: "calendar").font(.caption.weight(.semibold))
                Text(title).font(.caption.weight(.semibold))
                Text(sub).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                eyebrow
                Spacer(minLength: 0)
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.bpInk)
                Text(sub).font(.caption2).foregroundStyle(Color.bpMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
            Text("DAY").kerning(0.6)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.bpPurple)
    }

    /// "Pick-up" over "3:00 · leave by 2:35".
    @ViewBuilder
    private func headline(_ r: DayWidget.Reading, titleSize: CGFloat) -> some View {
        if let n = r.next {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(n))
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text((n.doneBy ? "done by " : "") + DayWidget.time(stamp(n)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.bpInk)
                if let l = r.leaveBy {
                    Text(l > now ? "leave by \(DayWidget.time(l))" : "leave now")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(l > now ? Color.bpPurple : Color.bpCoral)
                }
            }
        } else if let c = r.current {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(c))
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("until \(DayWidget.time(c.end))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.bpInk)
            }
        }
    }

    private func status(_ r: DayWidget.Reading, lines: Int) -> some View {
        Text(statusText(r))
            .font(.caption.weight(.semibold))
            .foregroundStyle(r.overMinutes != nil ? Color.bpCoral : Color.bpLimeInk)
            .lineLimit(lines)
            .minimumScaleFactor(0.8)
    }

    /// The free / over line. Over beats everything: it is the one that needs action.
    private func statusText(_ r: DayWidget.Reading) -> String {
        if let o = r.overMinutes { return "Over by \(DayWidget.duration(o))" }
        if let t = r.travelling { return "On the way \u{00B7} arrive \(DayWidget.time(t.end))" }
        if let c = r.current, r.next != nil { return "Now \u{00B7} \(displayName(c)) until \(DayWidget.time(c.end))" }
        if let f = r.freeMinutes { return "\(DayWidget.duration(max(0, f))) free" }
        return ""
    }

    private func timelineRow(_ b: DayWidget.Block, running: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Circle()
                    .fill(b.pinned ? Color.bpPurple : (running ? Color.bpLime : Color.bpMuted.opacity(0.5)))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                if !last { Rectangle().fill(Color.bpRule).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName(b))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                Text(DayWidget.time(b.start))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.bpMuted)
                    .padding(.bottom, 6)
            }
        }
        .frame(height: 38)
    }

    private func displayName(_ b: DayWidget.Block) -> String { b.name.isEmpty ? "Block" : b.name }

    /// The time a block is named by: its start, or its end for a "done by" pin.
    private func stamp(_ b: DayWidget.Block) -> Date { b.doneBy ? b.end : b.start }
}
