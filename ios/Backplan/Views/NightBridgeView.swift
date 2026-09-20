import SwiftUI

/// The night pair's payoff surface. Tonight's lights-out and tomorrow's wake are
/// one chain with sleep as the elastic middle, and this is the only place that
/// says what the evening costs the morning — which planning backwards from a
/// single target hides by construction, because the target is the end of the
/// story.
///
/// Mirrors the web `.bridge` section in index.html. Colour follows the verdict,
/// not the section.
struct NightBridgeView: View {
    let bridge: NightBridge
    let sleepNeed: Int
    let sleeper: String
    let morningEventName: String
    /// Driven by the parent's ticking clock so the live line counts down.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chain
            Rectangle()
                .fill(.bpRule)
                .frame(height: 1.5)
            verdict
        }
    }

    // MARK: Chain

    /// Two rows of two rather than four across: at phone widths four columns
    /// crushes "Lights out by" into two truncated lines. Reading order is still
    /// left-to-right, top-to-bottom along the chain.
    private var chain: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                node("Lights out by", Fmt.time(bridge.deadline), tint: deadlineColor)
                divider
                node("Sleep", Fmt.duration(sleepNeed), tint: .bpPurple)
            }
            HStack(alignment: .top, spacing: 0) {
                node("Wake", Fmt.time(bridge.wake), tint: .bpInk)
                divider
                node(morningLabel, Fmt.time(bridge.morningTarget), tint: .bpInk)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.bpRule)
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)
    }

    private func node(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.bpMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(.display(21))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var morningLabel: String {
        let trimmed = morningEventName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Out the door" : trimmed
    }

    // MARK: Verdict

    private var verdict: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(bridge.pillText)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .neoPill(fill: pillFill, border: pillBorder)
                .foregroundStyle(pillInk)
                .fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                Text(bridge.verdictText(sleeper: sleeper, sleepNeed: sleepNeed))
                    .font(.subheadline)
                    .foregroundStyle(.bpInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let live = bridge.liveText(now: now) {
                    Text(live)
                        .font(.footnote)
                        .foregroundStyle(.bpMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Verdict colours

    private var deadlineColor: Color {
        switch bridge.verdict {
        case .onTrack: return .bpLimeInk
        case .tight: return .bpGoldInk
        case .late: return .bpCoral
        }
    }

    private var pillFill: Color {
        switch bridge.verdict {
        case .onTrack: return .bpLimeTint
        case .tight: return .bpGoldTint
        case .late: return .bpCoralTint
        }
    }

    private var pillBorder: Color {
        switch bridge.verdict {
        case .onTrack: return .bpLime
        case .tight: return .bpGold
        case .late: return .bpCoral
        }
    }

    private var pillInk: Color {
        switch bridge.verdict {
        case .onTrack: return .bpLimeInk
        case .tight: return .bpGoldInk
        case .late: return .bpCoral
        }
    }
}

/// Tonight / Tomorrow AM. Sits above the result card rather than in the Steps
/// header, which the Edit/Overview toggle already occupies.
struct PlanTabsView: View {
    let activeKey: PlanKey
    /// Subtitle per tab, so switching is never blind.
    let subtitle: (PlanKey) -> String
    let onSelect: (PlanKey) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlanKey.allCases.enumerated()), id: \.element.id) { idx, key in
                if idx > 0 {
                    Rectangle().fill(.bpInk).frame(width: 2)
                }
                tab(key)
            }
        }
        .background(.bpCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.bpInk, lineWidth: 2)
        )
    }

    private func tab(_ key: PlanKey) -> some View {
        let active = key == activeKey
        return Button {
            onSelect(key)
        } label: {
            VStack(spacing: 3) {
                Text(key.label)
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text(subtitle(key))
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(active ? Color.bpPurple : Color.bpCard)
            .foregroundStyle(active ? Color.white : Color.bpMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}
