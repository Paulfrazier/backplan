import SwiftUI

/// One block in the day: its slack row (if it opens a gap), its travel leg (if
/// it has one), then the block card. One List row, so the leg moves with it.
struct DayBlockRow: View {
    @Environment(PlanStore.self) private var store
    @Binding var block: DayBlock
    let item: DayItem
    let gap: DayGap?
    let nextAnchorName: String?
    let places: [SavedPlace]
    let linked: Bool
    let now: Date
    @Binding var expanded: Bool
    let onEditPlan: () -> Void

    @FocusState private var durationFocused: Bool

    private var isDone: Bool { item.minutes > 0 && item.end <= now }
    private var isNow: Bool { item.start <= now && now < item.end }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let gap { slackRow(gap) }
            if let leg = item.leg { legRow(leg) }
            card
        }
        .opacity(isDone ? 0.5 : 1)
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(block.isAnchor ? "What’s fixed? e.g. Pick-up" : "What’s this block?", text: $block.name)
                    .font(.body.weight(block.isPlan ? .bold : .semibold))
                    .foregroundStyle(block.isAnchor ? .bpPurple : .bpInk)
                    .submitLabel(.done)
                startPill
            }
            if block.isPlan {
                planControls
            } else {
                plainControls
            }
            if block.isPlan && expanded, let comp = item.comp {
                stepList(comp)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isNow ? Color.bpLimeTint : block.isAnchor ? Color(hex: 0xF8F4FD) : .bpCard)
        )
        .overlay(alignment: .leading) {
            if block.isAnchor {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(.bpPurple)
                    .frame(width: 5)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.bpInk, lineWidth: 2)
        )
    }

    private var startPill: some View {
        let fixed = block.isAnchor
        let over = item.over && !fixed
        return Text(Fmt.time(item.start))
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(fixed ? Color.white : over ? Color(hex: 0xB91C1C) : .bpLimeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(fixed ? Color.bpPurple : over ? Color.bpCoralTint : Color.bpLimeTint))
            .overlay(Capsule().strokeBorder(fixed ? Color.bpPurple : over ? Color.bpCoral : Color.bpLime, lineWidth: 1.5))
            .fixedSize()
            .accessibilityLabel("Starts \(Fmt.time(item.start)), ends \(Fmt.time(item.end))")
    }

    private var plainControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                durationField
                Spacer(minLength: 0)
                placeMenu
            }
            pinControls
        }
    }

    private var planControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation { expanded.toggle() } } label: {
                    let n = block.steps?.count ?? 0
                    HStack(spacing: 5) {
                        Image(systemName: linked ? "link" : "list.bullet")
                        Text("\(n) step\(n == 1 ? "" : "s") · \(Fmt.duration(item.minutes))")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundStyle(.bpMuted)
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.bpInk)
                    .chip(fill: Color(hex: 0xFFF6E0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide the plan's steps" : "Show the plan's steps")

                if linked {
                    Button(action: onEditPlan) {
                        Label("Edit plan", systemImage: "pencil")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.bpPurpleElectric)
                            .chip(fill: .bpCard)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            pinControls
            if let bridge = item.comp?.bridge { bridgeButton(bridge) }
        }
    }

    // MARK: Controls

    private var durationField: some View {
        HStack(spacing: 6) {
            TextField("0", value: $block.duration, format: .number)
                .keyboardType(.decimalPad)
                .focused($durationFocused)
                .multilineTextAlignment(.center)
                .frame(width: 50)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.bpRule, lineWidth: 1.5))
                .toolbar {
                    if durationFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { durationFocused = false }
                        }
                    }
                }
            Picker("Unit", selection: $block.unit) {
                ForEach(DurationUnit.allCases) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
    }

    private var placeMenu: some View {
        Menu {
            Button {
                block.placeID = nil
            } label: {
                Label("No place", systemImage: block.placeID == nil ? "checkmark" : "")
            }
            ForEach(places) { p in
                Button {
                    block.placeID = p.id
                } label: {
                    Label(p.name + (p.isHome ? " (home)" : ""), systemImage: block.placeID == p.id ? "checkmark" : "mappin")
                }
            }
        } label: {
            let name = places.first { $0.id == block.placeID }?.name
            Label(name ?? (places.isEmpty ? "No places" : "Place"), systemImage: "mappin.and.ellipse")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(name == nil ? .bpMuted : .bpInk)
                .lineLimit(1)
                .chip(fill: .bpCard)
        }
        .disabled(places.isEmpty)
    }

    @ViewBuilder
    private var pinControls: some View {
        if block.isAnchor {
            HStack(spacing: 6) {
                Button { store.togglePin(block.id) } label: {
                    Image(systemName: "pin.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.bpPurple))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unpin time")

                Menu {
                    Picker("Pinned edge", selection: $block.edge) {
                        ForEach(PinEdge.allCases) { e in Text(e.label).tag(e) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(block.edge.label)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.bpPurple)
                    .lineLimit(1)
                    .fixedSize()
                    .chip(fill: .bpCard)
                }

                DatePicker("Pinned time", selection: atBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        } else {
            Button { store.togglePin(block.id) } label: {
                Label("Pin time", systemImage: "pin")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.bpMuted)
                    .chip(fill: .bpCard)
            }
            .buttonStyle(.plain)
        }
    }

    private func bridgeButton(_ bridge: DayComposite.Bridge) -> some View {
        let fallback = bridge.natural?.label ?? "the plan’s start"
        return Button { block.bridge.toggle() } label: {
            Label(bridge.on ? "from \(bridge.here.label)" : "from \(fallback)",
                  systemImage: bridge.on ? "arrow.turn.down.right" : "house")
                .font(.footnote.weight(.bold))
                .foregroundStyle(bridge.on ? .bpLimeInk : .bpMuted)
                .lineLimit(1)
                .chip(fill: bridge.on ? .bpLimeTint : .bpCard, border: bridge.on ? .bpLime : .bpRule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(bridge.on
            ? "Leaving from where your day has you. Double-tap to leave from \(fallback) instead."
            : "Leaving from the plan’s own start. Double-tap to leave from \(bridge.here.label).")
    }

    private var atBinding: Binding<Date> {
        Binding(
            get: { DayPlanner.clock(block.at ?? "12:00", on: store.day.date, now: Date()) },
            set: { block.at = DayPlanner.hhmm($0) }
        )
    }

    // MARK: Leg, slack, steps

    private func legRow(_ leg: DayLeg) -> some View {
        HStack(spacing: 8) {
            Button { store.cycleVia(block.id) } label: {
                Label(leg.mode.label, systemImage: leg.mode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.bpInk)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(.bpCard))
                    .overlay(Capsule().strokeBorder(.bpInk, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes how you get there")
            Text("\(leg.from.label) → \(leg.to.label)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.bpInk)
                .lineLimit(1)
            Spacer(minLength: 4)
            legStatus(leg)
        }
        .padding(.leading, 18)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { spine(color: .bpRule) }
    }

    @ViewBuilder
    private func legStatus(_ leg: DayLeg) -> some View {
        switch leg.lookup {
        case .loading:
            Text("routing…").font(.caption).foregroundStyle(.bpMuted)
        case .error(let e):
            Button { store.retryDayLeg(leg.key) } label: {
                Label(e == .noRoute ? "no route" : "offline", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.bpCoral)
            }
            .buttonStyle(.plain)
        case .ok:
            Text("\(Fmt.duration(leg.minutes)) · leave \(Fmt.time(leg.start))")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(item.over ? .bpCoral : .bpMuted)
        }
    }

    private func slackRow(_ gap: DayGap) -> some View {
        let text: String
        let color: Color
        if gap.slack < 0 {
            text = "Over by \(Fmt.duration(-gap.slack)) — won’t make \(nextAnchorName ?? "the next fixed time")"
            color = Color(hex: 0x9A2A16)
        } else if gap.slack < 5 {
            text = gap.slack == 0 ? "No slack — back to back" : "Tight · \(gap.slack) min spare"
            color = Color(hex: 0x8A6100)
        } else {
            text = "Free · \(Fmt.duration(gap.slack)) (\(Fmt.time(gap.freeFrom))–\(Fmt.time(gap.depart)))"
            color = .bpLimeInk
        }
        return Text(text)
            .font(.footnote.weight(.bold))
            .foregroundStyle(color)
            .padding(.leading, 18)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gap.slack < 0 ? Color.bpCoralTint : .clear)
            .overlay(alignment: .leading) { spine(color: gap.slack < 0 ? .bpCoral : .bpRule) }
    }

    private func spine(color: Color) -> some View {
        Rectangle().fill(color).frame(width: 2).padding(.leading, 6)
    }

    private func stepList(_ comp: DayComposite) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(comp.rows.enumerated()), id: \.offset) { idx, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.time(item.start.addingTimeInterval(TimeInterval(row.offset * 60))))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.bpLimeInk)
                        .frame(width: 70, alignment: .leading)
                    stepName(row)
                        .font(.footnote)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    stepDuration(row)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    if idx > 0 { Rectangle().fill(.bpRule).frame(height: 1) }
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func stepName(_ row: DayStepRow) -> some View {
        if let leg = row.leg {
            HStack(spacing: 4) {
                Image(systemName: leg.mode.symbol).foregroundStyle(.bpMuted)
                Text(leg.status == .there ? "already at \(leg.to.label)" : "\(leg.from.label) → \(leg.to.label)")
            }
        } else {
            Text(row.name)
        }
    }

    @ViewBuilder
    private func stepDuration(_ row: DayStepRow) -> some View {
        if let leg = row.leg, leg.status == .loading {
            Text("routing…").font(.caption).foregroundStyle(.bpMuted)
        } else if let leg = row.leg, leg.status == .error, let key = leg.key {
            Button { store.retryDayLeg(key) } label: {
                Label("retry", systemImage: "arrow.clockwise").font(.caption.weight(.bold)).foregroundStyle(.bpCoral)
            }
            .buttonStyle(.plain)
        } else {
            Text(Fmt.duration(row.minutes)).font(.footnote).monospacedDigit().foregroundStyle(.bpMuted)
        }
    }
}

private extension View {
    /// A small bordered control surface — the web `.d-pin` / `.d-place` look.
    func chip(fill: Color, border: Color = .bpRule) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1.5))
    }
}
