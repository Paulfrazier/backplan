import SwiftUI

struct ResultHeaderView: View {
    let result: PlanResult
    let eventName: String
    /// Chained, the evening plan's target *is* lights-out and the morning's is
    /// the fixed obligation, so the generic wording stops being true. Defaulted
    /// so the unchained app is untouched.
    var targetLabel: String = "Be ready by"

    private var trimmedName: String {
        eventName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The event name gets its own full-width line. Sharing the row with
            // the two times meant a name like "Flight to Denver" claimed most of
            // the width and squeezed the left column until the meta line wrapped.
            if !trimmedName.isEmpty {
                HStack(spacing: 7) {
                    Text("For")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.bpMuted)
                        .textCase(.uppercase)
                    Text(trimmedName)
                        .font(.display(17))
                        .foregroundStyle(.bpPurple)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start at")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.bpMuted)
                        .textCase(.uppercase)

                    Text(result.overallStart.map { Fmt.time($0) } ?? "—")
                        .font(.display(40))
                        .foregroundStyle(result.overflowsPrevDay || result.isPast ? .bpCoral : .bpLimeInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    metaLine
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(targetLabel)
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.bpMuted)
                        .textCase(.uppercase)
                        .lineLimit(1)

                    Text(Fmt.time(result.target))
                        .font(.display(28))
                        .foregroundStyle(.bpInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        if result.hasSteps {
            let steps = result.startTimes.count
            let parts = "Total \(Fmt.duration(result.totalMinutes)) · \(steps) \(steps == 1 ? "step" : "steps")"
            HStack(spacing: 8) {
                Text(parts)
                    .font(.footnote)
                    .foregroundStyle(.bpMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if result.overflowsPrevDay {
                    Text("← previous day")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.bpCoralTint))
                        .foregroundStyle(.bpCoral)
                }
            }
        } else {
            Text("Add steps below.")
                .font(.footnote)
                .foregroundStyle(.bpMuted)
        }
    }
}
