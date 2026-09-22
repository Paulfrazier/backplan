import SwiftUI

/// Debounced place search. Presented as a sheet from a travel step's From/To
/// field, or from the Places section when saving a new place.
struct PlaceSearchView: View {
    let title: String
    /// Saved places offered above live results, so "Home" is one tap away.
    let saved: [SavedPlace]
    let anchor: GeocodeService.Coordinate
    let onPick: (GeocodeService.Suggestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GeocodeService.Suggestion] = []
    @State private var isSearching = false
    @State private var failed = false

    private var savedMatches: [SavedPlace] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return saved }
        let q = GeocodeService.fold(query)
        return saved.filter { GeocodeService.fold($0.name).contains(q) || GeocodeService.fold($0.label).contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !savedMatches.isEmpty {
                    Section("Saved") {
                        ForEach(savedMatches) { place in
                            Button {
                                onPick(GeocodeService.Suggestion(
                                    id: place.id.uuidString, label: place.name, sub: place.label,
                                    lat: place.lat, lng: place.lng
                                ))
                                dismiss()
                            } label: {
                                row(title: place.name, subtitle: place.label, starred: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    if isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.bpMuted)
                        }
                    } else if failed {
                        Text("Couldn't reach the place search.")
                            .foregroundStyle(.bpCoral)
                    } else if results.isEmpty && query.count >= GeocodeService.minQueryLength {
                        Text("Nothing found for “\(query)”.")
                            .foregroundStyle(.bpMuted)
                    }
                    ForEach(results) { suggestion in
                        Button {
                            onPick(suggestion)
                            dismiss()
                        } label: {
                            row(title: suggestion.label, subtitle: suggestion.sub, starred: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .background(.bpPaper)
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .searchable(text: $query, prompt: "Address or place")
        // .task(id:) restarts on every keystroke and cancels the previous run,
        // which gives us debounce + abort in one construct.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= GeocodeService.minQueryLength else {
                results = []; isSearching = false; failed = false
                return
            }
            failed = false
            isSearching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await GeocodeService.shared.search(trimmed, anchor: anchor)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                failed = true
            }
            isSearching = false
        }
    }

    private func row(title: String, subtitle: String, starred: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if starred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.bpGold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.bpInk)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.bpMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
