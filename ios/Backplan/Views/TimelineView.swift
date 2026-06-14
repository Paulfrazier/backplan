import SwiftUI

/// Proportional segment strip + live "now" marker + countdown badge.
/// Recomputes each second via TimelineView(.periodic) so the marker moves.
struct PlanTimeline: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let result = store.result(now: context.date)
            content(result: result, now: context.date)
        }
    }

    @ViewBuilder
    private func content(result: PlanResult, now: Date) -> some View {
        let segments = result.segments
        if let first = segments.first {
            let chainStart = first.start
            let chainEnd = result.target
            let total = max(1, chainEnd.timeIntervalSince(chainStart))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.time(chainStart))
                    Spacer()
                    Text(Fmt.time(chainEnd))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.bpMuted)

                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                                segmentCell(seg, color: Color.timelineTints[idx % 4])
                                    .frame(width: width * CGFloat(seg.minutes) / CGFloat(max(1, result.totalMinutes)))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.bpInk, lineWidth: 1.5)
                        )

                        nowMarker(now: now, chainStart: chainStart, chainEnd: chainEnd, total: total, width: width)
                    }
                }
                .frame(height: 56)

                countdown(result: result, now: now, chainStart: chainStart, chainEnd: chainEnd, total: total)
            }
        } else {
            EmptyView()
        }
    }

    private func segmentCell(_ seg: PlanSegment, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(seg.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(seg.minutes)m")
                .font(.caption2)
                .foregroundStyle(.bpMuted)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .foregroundStyle(.bpInk)
    }

    @ViewBuilder
    private func nowMarker(now: Date, chainStart: Date, chainEnd: Date, total: TimeInterval, width: CGFloat) -> some View {
        if now >= chainStart && now <= chainEnd {
            let pct = min(1, max(0, now.timeIntervalSince(chainStart) / total))
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.bpInk)
                    .frame(width: 2)
                Circle()
                    .fill(.bpCoral)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.bpInk, lineWidth: 1.5))
                    .offset(y: -4)
            }
            .frame(height: 56)
            .offset(x: width * CGFloat(pct) - 1)
        }
    }

    @ViewBuilder
    private func countdown(result: PlanResult, now: Date, chainStart: Date, chainEnd: Date, total: TimeInterval) -> some View {
        let (text, tint): (String, Color) = {
            if now < chainStart {
                let mins = max(1, Int((chainStart.timeIntervalSince(now) / 60).rounded()))
                return ("Start in \(Fmt.duration(mins)) · \(Fmt.time(chainStart))", .bpPurpleElectric)
            } else if now > chainEnd {
                let mins = max(1, Int((now.timeIntervalSince(chainEnd) / 60).rounded()))
                return ("Target was \(Fmt.duration(mins)) ago", .bpMuted)
            } else if let cur = result.segments.first(where: { now >= $0.start && now < $0.end }) {
                let mins = max(1, Int((cur.end.timeIntervalSince(now) / 60).rounded()))
                return ("Now: \(cur.name) · \(Fmt.duration(mins)) left", .bpCoral)
            } else {
                return ("In progress · target \(Fmt.time(chainEnd))", .bpCoral)
            }
        }()

        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.bpInk)
        }
    }
}
