import SwiftUI

/// Saved places — the spots you travel between. The one flagged as home is both
/// the place-search bias and the default origin for a plan's first travel leg.
struct PlacesView: View {
    @Environment(PlanStore.self) private var store

    @State private var isSearching = false
    @State private var pending: GeocodeService.Suggestion?
    @State private var pendingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save the spots you travel between. Mark one as home and travel steps start there by default.")
                .font(.footnote)
                .foregroundStyle(.bpMuted)

            Button {
                isSearching = true
            } label: {
                Label("Add a place", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.bpInk)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .neoPill(fill: .bpLime)
            }
            .buttonStyle(.plain)

            if store.places.isEmpty {
                Text("No saved places yet. Add home first — it becomes the default starting point.")
                    .font(.footnote)
                    .foregroundStyle(.bpMuted)
            } else {
                ForEach(store.places) { place in
                    placeRow(place)
                }
            }
        }
        .sheet(isPresented: $isSearching) {
            PlaceSearchView(
                title: "Add a place",
                saved: [],
                anchor: store.searchAnchor
            ) { suggestion in
                pendingName = suggestion.label
                pending = suggestion
            }
        }
        .alert("Name this place", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            TextField("Home", text: $pendingName)
            Button("Save") {
                if let pending {
                    store.savePlace(name: pendingName, suggestion: pending)
                    Task { await store.refreshAllTravel() }
                }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func placeRow(_ place: SavedPlace) -> some View {
        HStack(spacing: 10) {
            Button {
                store.setHome(place)
                Task { await store.refreshAllTravel() }
            } label: {
                Image(systemName: place.isHome ? "house.fill" : "house")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(place.isHome ? .bpInk : .bpMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(place.isHome ? Color.bpLime : Color.bpCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(place.isHome ? Color.bpInk : Color.bpRule, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(place.isHome ? "This is home" : "Make this home")

            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.bpInk)
                Text(place.label)
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                store.deletePlace(place)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.bpMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete place")
        }
        .padding(.vertical, 4)
    }
}
