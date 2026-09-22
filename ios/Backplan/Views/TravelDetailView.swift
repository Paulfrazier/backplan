import SwiftUI

/// The panel under a travel step: a one-line summary that expands into the mode
/// picker, From/To endpoints, and the routed result. Once both endpoints resolve
/// the panel folds itself away — a settled leg costs one line, not five.
struct TravelDetailView: View {
    @Environment(PlanStore.self) private var store
    let stepID: Step.ID

    @State private var editing: Endpoint?
    @State private var isLoading = false
    @State private var error: TravelError?
    /// Whether the user has explicitly opened a settled leg. Deliberately not
    /// persisted — reopening the app on a sorted leg should show the tidy
    /// version. KEEP IN SYNC with index.html → `travelOpen` / `travelSettled`.
    @State private var userExpanded = false

    private enum Endpoint: String, Identifiable {
        case from, to
        var id: String { rawValue }
        var title: String { self == .from ? "Starting point" : "Destination" }
    }

    private var step: Step? { store.plan.steps.first { $0.id == stepID } }
    private var travel: Travel? { step?.travel }
    private var origin: (place: PlaceRef, chained: Bool)? { store.resolveOrigin(for: stepID) }

    /// A leg is settled once both ends resolve and the lookup is neither
    /// in-flight nor broken. Only a settled leg is allowed to collapse — an
    /// error or a missing endpoint means the fields are what the user needs.
    private var isSettled: Bool {
        travel?.to != nil && origin != nil && error == nil && !isLoading
    }
    private var isExpanded: Bool { !isSettled || userExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    modePicker
                    endpointRow(
                        label: "From",
                        value: origin?.place.label,
                        chained: origin?.chained ?? false,
                        endpoint: .from
                    )
                    endpointRow(
                        label: "To",
                        value: travel?.to?.label,
                        chained: false,
                        endpoint: .to
                    )
                    resultLine
                }
                .padding(10)
                .overlay(alignment: .top) {
                    Rectangle().fill(.bpRule).frame(height: 1.5)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.bpPaper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.bpRule, lineWidth: 1.5)
        )
        .padding(.top, 8)
        .animation(.snappy(duration: 0.2), value: isExpanded)
        .sheet(item: $editing) { endpoint in
            PlaceSearchView(
                title: endpoint.title,
                saved: store.places,
                anchor: store.searchAnchor
            ) { suggestion in
                apply(suggestion, to: endpoint)
            }
        }
        .task(id: travelKey) { await load(force: false) }
    }

    /// The collapsed face of the panel, and the header when it's open.
    private var summaryRow: some View {
        Button {
            userExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: travel?.mode.symbol ?? "car.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bpInk)
                Text(routeText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.bpInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let stat = statText {
                    Text(stat)
                        .font(.caption)
                        .foregroundStyle(.bpMuted)
                        .layoutPriority(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.bpMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide travel details" : "Show travel details")
        .accessibilityValue(routeText)
    }

    private var routeText: String {
        let from = origin?.place.label ?? "Set a starting point"
        let to = travel?.to?.label ?? "Pick a destination"
        return "\(from) → \(to)"
    }

    /// Shared with `resultLine` so the two can never disagree.
    private var statText: String? {
        guard let result = travel?.result else { return nil }
        return "\(TravelFmt.distance(result.distanceM)) · \(Fmt.duration(result.minutes))"
    }

    /// Changing mode or either endpoint should re-route; nothing else should.
    private var travelKey: String {
        guard let travel else { return "none" }
        let from = origin.map { "\($0.place.lat),\($0.place.lng)" } ?? "-"
        let to = travel.to.map { "\($0.lat),\($0.lng)" } ?? "-"
        return "\(travel.mode.rawValue)|\(from)|\(to)"
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(TravelMode.allCases) { mode in
                Button {
                    setMode(mode)
                } label: {
                    Label(mode.label, systemImage: mode.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .neoPill(fill: travel?.mode == mode ? .bpPurpleElectric : .bpCard)
                        .foregroundStyle(travel?.mode == mode ? Color.white : .bpInk)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func endpointRow(label: String, value: String?, chained: Bool, endpoint: Endpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.bpMuted)
            Button {
                editing = endpoint
            } label: {
                HStack(spacing: 6) {
                    if chained {
                        Image(systemName: "arrow.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.bpLimeInk)
                    }
                    Text(value ?? (endpoint == .from ? "Set a starting point" : "Pick a destination"))
                        .font(.subheadline)
                        .foregroundStyle(value == nil ? .bpMuted : .bpInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(chained ? Color.bpLimeTint : Color.bpCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.bpRule, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var resultLine: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small)
                Text("Looking up route…")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
            } else if let error {
                Text(error.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bpCoral)
                refreshButton
            } else if let result = travel?.result {
                // "free-flow" is the honest label: BRouter has no traffic model,
                // so this is the uncongested time. Padding stays the user's call.
                Text("\(TravelFmt.distance(result.distanceM)) · \(Fmt.duration(result.minutes)) free-flow \(travel?.mode.label.lowercased() ?? "")")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                if travel?.manual == true {
                    Text("edited by hand")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .neoPill(fill: .bpGold)
                        .foregroundStyle(.bpInk)
                }
                refreshButton
            } else {
                Text(travel?.to == nil
                     ? "Pick a destination to get a real travel time."
                     : "Set a starting point.")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await load(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(.bpMuted)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.bpRule, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Re-fetch travel time")
    }

    // MARK: - Actions

    private func setMode(_ mode: TravelMode) {
        guard let idx = store.plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        store.plan.steps[idx].travel?.mode = mode
        if store.plan.steps[idx].travel?.manual != true {
            store.plan.steps[idx].name = PlanStore.travelStepName(store.plan.steps[idx])
        }
    }

    private func apply(_ suggestion: GeocodeService.Suggestion, to endpoint: Endpoint) {
        guard let idx = store.plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        switch endpoint {
        case .from: store.plan.steps[idx].travel?.from = suggestion.ref
        case .to: store.plan.steps[idx].travel?.to = suggestion.ref
        }
        if store.plan.steps[idx].travel?.manual != true {
            store.plan.steps[idx].name = PlanStore.travelStepName(store.plan.steps[idx])
        }
        // Picking an endpoint is the user finishing with this panel — drop the
        // explicit-open flag so it folds itself up once the route lands.
        if store.plan.steps[idx].travel?.to != nil, origin != nil { userExpanded = false }
        // Later legs inherit from this one, so they need re-resolving too.
        Task { await store.refreshAllTravel() }
    }

    private func load(force: Bool) async {
        guard travel?.to != nil, origin != nil else {
            error = nil
            return
        }
        isLoading = true
        error = await store.refreshTravel(stepID: stepID, force: force)
        isLoading = false
        // A broken lookup reopens the panel: the fields are what needs fixing.
        if error != nil { userExpanded = true }
    }
}
