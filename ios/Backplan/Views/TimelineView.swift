import SwiftUI

/// Progress bar for the plan: elapsed fill + tick boundaries + live now-flag,
/// with the naming in a Now/Next block underneath.
///
/// The old version tinted each segment from a four-colour cycle and drew the step
/// name inside it. The colours repeated past four steps and meant nothing, and a
/// 15-minute step inside a three-hour plan had no room for its name — so most
/// segments came out as anonymous blocks. Colour now encodes elapsed / current /
/// upcoming, and no text is drawn inside the bar at all.
///
/// Recomputes each second via TimelineView(.periodic) so the fill and flag move.
struct PlanTimeline: View {
    @Environment(PlanStore.self) private var store
    @State private var flagWidth: CGFloat = 0

    private static let railHeight: CGFloat = 26
    /// No flag outside the plan window — don't hold open an empty band of white
    /// above the track for it.
    private static let emptyRailHeight: CGFloat = 4
    private static let trackHeight: CGFloat = 34
    private static let railGap: CGFloat = 4

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
            let pct = min(1, max(0, now.timeIntervalSince(chainStart) / total))
            let inWindow = now >= chainStart && now <= chainEnd
            let status = PlanStatus.make(result: result, now: now)
            let currentID = segments.first(where: { now >= $0.start && now < $0.end })?.id

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Fmt.time(chainStart))
                    Spacer()
                    Text(Fmt.time(chainEnd))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.bpMuted)

                let rail = inWindow ? Self.railHeight : Self.emptyRailHeight
                GeometryReader { geo in
                    let width = geo.size.width
                    VStack(alignment: .leading, spacing: Self.railGap) {
                        // The flag rides above the track, not inside it: clipped to
                        // the capsule it collided with the corner radius and punched
                        // a notch through the last segment.
                        flagRail(now: now, pct: pct, width: width, visible: inWindow)
                            .frame(height: rail)
                        track(result: result, currentID: currentID, phase: status.phase,
                              pct: pct, width: width, showMarker: inWindow)
                            .frame(height: Self.trackHeight)
                    }
                }
                .frame(height: rail + Self.railGap + Self.trackHeight)

                statusBlock(status)
            }
            .onPreferenceChange(FlagWidthKey.self) { flagWidth = $0 }
            // The bar carries no text of its own, so the whole picture has to
            // reach VoiceOver through one composed label.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Timeline: \(segments.count) step\(segments.count == 1 ? "" : "s") from "
                + "\(Fmt.time(chainStart)) to \(Fmt.time(chainEnd)). \(status.key): \(status.now)."
            )
        } else {
            EmptyView()
        }
    }

    // MARK: - Track

    private func track(result: PlanResult, currentID: UUID?, phase: PlanPhase,
                       pct: CGFloat, width: CGFloat, showMarker: Bool) -> some View {
        // A full lime bar reads as "all good" — but a full bar means the target
        // has already passed. Match the overrun to its coral status pill.
        let fillColor: Color = phase == .past ? .bpCoral : .bpLime
        let nowTint: Color = phase == .past ? .bpCoralTint : .bpLimeTint
        let segments = result.segments
        let totalMinutes = CGFloat(max(1, result.totalMinutes))

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                    // Segments are tick boundaries now, so a 5-minute step being a
                    // few points wide is correct rather than broken. Two tones of
                    // one hue, alternating: before the plan starts nothing is
                    // elapsed and nothing is current, so state-colour alone leaves
                    // the bar blank — and "when do I start" is the state you open
                    // this app in. The alternation carries the plan's shape without
                    // assigning meaning to any particular colour. 16%, not 7% —
                    // at 7% it vanished on a phone.
                    Rectangle()
                        .fill(seg.id == currentID ? nowTint
                              : (idx % 2 == 1 ? Color.bpPurple.opacity(0.16) : .clear))
                        .frame(width: width * CGFloat(seg.minutes) / totalMinutes)
                        .overlay(alignment: .trailing) {
                            if seg.id != segments.last?.id {
                                // Ticks sit under the fill, so bpRule washes out to
                                // nothing inside the elapsed span; ink at low alpha
                                // survives the overlay at both ends.
                                Rectangle().fill(Color.bpInk.opacity(0.28)).frame(width: 1)
                            }
                        }
                }
            }
            // One overlay for the whole elapsed span. Because it cuts across the
            // active segment, progress *through* the current step comes for free.
            Rectangle()
                .fill(fillColor)
                .opacity(0.28)
                .frame(width: width * pct)
            if showMarker {
                Rectangle()
                    .fill(.bpInk)
                    .frame(width: 2)
                    .offset(x: width * pct - 1)
            }
        }
        .frame(width: width)
        .background(.bpCard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.bpInk, lineWidth: 2))
    }

    // MARK: - Now flag

    @ViewBuilder
    private func flagRail(now: Date, pct: CGFloat, width: CGFloat, visible: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if visible {
                flagPill(Fmt.time(now))
                    // Centred on the marker, then clamped so the pill never hangs
                    // off the card at either extreme.
                    .offset(x: min(max(width * pct - flagWidth / 2, 0), max(0, width - flagWidth)))
            }
        }
    }

    private func flagPill(_ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.bpCoral)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.bpInk, lineWidth: 1.5))
            Text(text)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.bpInk)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .neoPill(fill: .bpCard)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: FlagWidthKey.self, value: g.size.width)
            }
        )
    }

    // MARK: - Status

    private func statusBlock(_ status: PlanStatus) -> some View {
        let dot: Color
        let fill: Color
        let ink: Color
        switch status.phase {
        case .future: dot = .bpCoral;    fill = Color(hex: 0xF3EEFC); ink = .bpPurple
        case .active: dot = .bpLime;     fill = .bpLimeTint;          ink = .bpLimeInk
        case .past:   dot = .bpCoral;    fill = .bpCoralTint;         ink = Color(hex: 0x9A2A16)
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 9, height: 9)
                Text(status.key.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.8)
                    .opacity(0.75)
                Text(status.now).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .neoPill(fill: fill)

            if !status.next.isEmpty {
                HStack(spacing: 8) {
                    Text("NEXT")
                        .font(.caption2.weight(.bold))
                        .kerning(0.8)
                        .opacity(0.75)
                    Text(status.next).font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.bpMuted)
                // Lines the NEXT key up with the status key: padding 12 + dot 9 + gap 8.
                .padding(.leading, 29)
            }
        }
    }
}

/// Measures the now-flag so it can be clamped inside the track's width.
private struct FlagWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
