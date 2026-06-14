import SwiftUI

struct ResultHeaderView: View {
    let result: PlanResult
    let eventName: String

    private var trimmedName: String {
        eventName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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
                Text(trimmedName.isEmpty ? "Be ready by" : "For")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.bpMuted)
                    .textCase(.uppercase)

                if !trimmedName.isEmpty {
                    Text(trimmedName)
                        .font(.display(18))
                        .foregroundStyle(.bpPurple)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }

                Text(Fmt.time(result.target))
                    .font(.display(28))
                    .foregroundStyle(.bpInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
