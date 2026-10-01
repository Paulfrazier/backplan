import SwiftUI

/// The block tray, pinned above the tab bar — the thumb zone. Tap a chip to
/// append it; long-press and drag it up to drop it between two blocks.
struct DayTrayView: View {
    @Environment(PlanStore.self) private var store
    /// Called with the new block's id after a tap-add, so the list can scroll to it.
    let onAdd: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drag onto your day, or tap to add")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.bpMuted)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(.flex, symbol: "plus", label: "Block", fill: .bpLimeTint)
                    chip(.anchor, symbol: "pin.fill", label: "Fixed time", fill: Color(hex: 0xEFE6FB))
                    ForEach(TrayItem.presets.indices, id: \.self) { i in
                        let p = TrayItem.presets[i]
                        chip(.preset(i), symbol: p.symbol, label: p.name,
                             detail: p.unit == .hr ? "\(p.duration.formatted())h" : "\(Int(p.duration))m",
                             fill: .bpLimeTint)
                    }
                    // Saved plans come in as linked plan-blocks.
                    ForEach(store.templates) { t in
                        chip(.template(t.id), symbol: "list.bullet.clipboard", label: t.name,
                             detail: Fmt.duration(t.plan.steps.reduce(0) { $0 + $1.minutes }),
                             fill: Color(hex: 0xFFF6E0))
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Color.bpPaper.opacity(0.97)
                .overlay(alignment: .top) { Rectangle().fill(.bpInk).frame(height: 2) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func chip(_ item: TrayItem, symbol: String, label: String, detail: String? = nil, fill: Color) -> some View {
        Button {
            if let id = store.addBlock(item) { onAdd(id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(item == .anchor ? .bpPurple : .bpLimeInk)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.bpInk)
                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.bpMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .neoPill(fill: fill)
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: item.payload as NSString) }
        .accessibilityHint("Adds it to the end of your day. Long-press and drag to place it.")
    }
}
