import SwiftUI

/// Horizontal row of one-tap step presets. Tapping appends a fully-formed step —
/// no typing. Mirrors the web "Quick add" chips.
struct QuickAddBar: View {
    @Environment(PlanStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick add")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.bpMuted)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Starters.quickAdds) { item in
                        Button {
                            store.addQuickStep(item)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.bpLimeInk)
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.bpInk)
                                Text(item.durationLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.bpMuted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .neoPill(fill: .bpLimeTint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 4)
            }
        }
    }
}
