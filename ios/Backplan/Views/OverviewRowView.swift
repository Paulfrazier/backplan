import SwiftUI

/// One line of the read-only schedule: when it starts, what it is, how long.
///
/// The timeline bar carries a plan's shape and how far through it you are, but
/// it physically cannot name a 15-minute step at phone width — that is what put
/// "Dr…" on screen. The names live here instead.
struct OverviewRowView: View {
    let step: Step
    let start: Date?
    let overflow: Bool
    let state: RowState
    /// Resolved origin for a travel step, chained from the previous leg if needed.
    let origin: PlaceRef?

    enum RowState { case done, now, upcoming }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(start.map { Fmt.time($0) } ?? "—")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(overflow ? Color.bpCoral : .bpLimeInk)
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(named ? Color.bpInk : .bpMuted)
                        .italic(!named)
                        .lineLimit(1)
                    if state == .now {
                        Text("NOW")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(.bpInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .neoPill(fill: .bpLime, offset: 0, lineWidth: 1.5)
                    }
                }
                if let leg, let mode = step.travel?.mode {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbol).font(.caption2)
                        Text(leg).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                }
            }

            Spacer(minLength: 8)

            Text(step.minutes > 0 ? Fmt.duration(step.minutes) : "—")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.bpMuted)
                .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        // State mirrors the bar: done recedes, current is marked.
        .background(state == .now ? Color.bpLimeTint : .clear)
        .opacity(state == .done ? 0.45 : 1)
    }

    private var named: Bool { !step.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var name: String {
        let t = step.name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Untitled step" : t
    }

    /// Same one-line form the collapsed editor row uses.
    private var leg: String? {
        guard let t = step.travel else { return nil }
        let from = origin?.label ?? "no start"
        let to = t.to?.label ?? "no destination"
        var s = "\(from) → \(to)"
        if let r = t.result {
            s += " · \(TravelFmt.distance(r.distanceM)) · \(Fmt.duration(r.minutes))"
        }
        return s
    }
}

/// The target itself, so the list ends where the plan does.
struct OverviewTargetRow: View {
    let target: Date
    let eventName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(Fmt.time(target))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.bpPurple)
                .fixedSize()
            Text(eventName.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Be ready" : eventName.trimmingCharacters(in: .whitespaces))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.bpPurple)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
    }
}
