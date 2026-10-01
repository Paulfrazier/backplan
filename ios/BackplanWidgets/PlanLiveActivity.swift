import ActivityKit
import SwiftUI
import WidgetKit

/// The armed plan on the Lock Screen and in the Dynamic Island.
///
/// Every countdown here is a `Text(timerInterval:)`, never a pre-formatted
/// string: the system owns the seconds, so the app never has to wake up just to
/// advance a number. The app only pushes a new state when the *words* change —
/// at a step boundary — which is also the only rate ActivityKit will tolerate.
struct PlanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanActivityAttributes.self) { context in
            lockScreen(context)
                // A dark card, not Backplan's paper. The first build tinted the
                // card `bpPaper` with plum ink on it, but the system does not keep
                // that tint opaque — it blends it toward the wallpaper and dims it
                // with the Lock Screen, so plum #4A154B landed on near-black and
                // the countdown was unreadable. A dark ground reads on any
                // wallpaper, matches the Dynamic Island, and lets the card share
                // its lifted accents. The tint is backed by an opaque fill inside
                // `lockScreen` so the blend cannot wash it out.
                .activityBackgroundTint(Self.cardGround)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                        Text(context.state.phaseWord)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(islandAccent(context.state.phase))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state)
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(islandAccent(context.state.phase))
                        .frame(maxWidth: 108, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.detail)
                            .font(.subheadline.weight(.semibold))
                        if !context.state.next.isEmpty {
                            Text("Next: \(context.state.next)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        progress(context, accent: islandAccent(context.state.phase))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: glyph(context.state.phase))
                    .foregroundStyle(islandAccent(context.state.phase))
            } compactTrailing: {
                timer(context.state)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    // No width cap. Capped at 54pt an H:MM:SS countdown rendered
                    // as "11:08…" — the ellipsis eats the part that says which
                    // unit you are looking at. The system bounds the compact
                    // region on its own; let it size to the text.
                    .foregroundStyle(islandAccent(context.state.phase))
            } minimal: {
                Image(systemName: glyph(context.state.phase))
                    .foregroundStyle(islandAccent(context.state.phase))
            }
            .keylineTint(.bpLime)
        }
    }

    // MARK: - Lock Screen

    private func lockScreen(_ context: ActivityViewContext<PlanActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.eventName.isEmpty ? "Backplan" : context.attributes.eventName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.state.phaseWord.uppercased())
                    .font(.caption2.weight(.heavy))
                    .kerning(0.6)
                    .foregroundStyle(.bpInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(islandAccent(context.state.phase)))
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .kerning(0.7)
                        .foregroundStyle(Self.cardMuted)
                    timer(context.state)
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(islandAccent(context.state.phase))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.detail)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !context.state.next.isEmpty {
                        Text("Next: \(context.state.next)")
                            .font(.caption2)
                            .foregroundStyle(Self.cardMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            progress(context, accent: islandAccent(context.state.phase))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Self.cardGround)
    }

    /// Backplan's ink, used as the Lock Screen card's ground.
    private static let cardGround = Color.bpInk
    /// Secondary text on `cardGround`. `bpMuted` #696969 is tuned for paper and
    /// sinks into the dark card; this stays well above 4.5:1 on it.
    private static let cardMuted = Color.white.opacity(0.68)

    /// The whole plan's span, not the current step's — it is the only bar that
    /// answers "how much of tonight is left", which is the question the card is
    /// on the Lock Screen to answer.
    private func progress(_ context: ActivityViewContext<PlanActivityAttributes>,
                          accent: Color) -> some View {
        ProgressView(
            timerInterval: range(from: context.attributes.chainStart, to: context.attributes.target),
            countsDown: false
        ) { EmptyView() } currentValueLabel: { EmptyView() }
        .progressViewStyle(.linear)
        .tint(accent)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func timer(_ state: PlanActivityAttributes.ContentState) -> some View {
        if state.phase == .past {
            // Counting *up* from the target is what "over by" means. The far end
            // only has to outlast anyone's willingness to look at it.
            Text(timerInterval: state.boundary...state.boundary.addingTimeInterval(24 * 3600),
                 countsDown: false)
        } else {
            Text(timerInterval: range(from: state.windowStart, to: state.boundary), countsDown: true)
        }
    }

    /// `Text(timerInterval:)` traps on an empty or inverted range, which a
    /// boundary that has just gone by will produce.
    private func range(from start: Date, to end: Date) -> ClosedRange<Date> {
        let safeEnd = max(end, start.addingTimeInterval(1))
        return start...safeEnd
    }

    private func glyph(_ phase: PlanActivityAttributes.Phase) -> String {
        switch phase {
        case .future: return "hourglass"
        case .active: return "figure.walk"
        case .past: return "exclamationmark.triangle.fill"
        }
    }

    /// Accents for a dark ground — the Dynamic Island, which is always black, and
    /// the Lock Screen card, which is dark to match. The paper palette's inks —
    /// `bpPurple` #4A154B, `bpLimeInk` #3F6212 — are near-invisible on it: the first build shipped them and the island opened
    /// to its wider Live Activity shape with nothing legible inside it. These are
    /// the same three hues lifted for a dark ground.
    private func islandAccent(_ phase: PlanActivityAttributes.Phase) -> Color {
        switch phase {
        case .future: return Color(hex: 0xC4B5FD)  // purple-electric, lightened
        case .active: return .bpLime
        case .past: return .bpCoral
        }
    }
}
