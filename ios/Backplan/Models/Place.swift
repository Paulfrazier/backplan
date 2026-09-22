import Foundation

/// A place the user has named and kept — "Home", "School", "Work". One may be
/// flagged as home, which makes it both the place-search bias and the default
/// origin for the first travel leg in a plan.
struct SavedPlace: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// Full descriptive address, shown under the nickname.
    var label: String
    var lat: Double
    var lng: Double
    var isHome: Bool = false

    /// The place as a travel endpoint. The nickname leads, because "Home" reads
    /// better than the street address it stands for.
    var ref: PlaceRef {
        PlaceRef(label: name, sub: label, lat: lat, lng: lng)
    }
}
