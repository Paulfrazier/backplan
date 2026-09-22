import Foundation

/// Place search. Mirrors the web implementation in index.html — see the comments
/// there for the measurements behind the two-pass merge and the fold synonyms.
///
/// Photon (komoot) is primary, Nominatim the fallback. Neither needs a key.
actor GeocodeService {
    static let shared = GeocodeService()

    private static let photonURL = "https://photon.komoot.io/api/"
    private static let nominatimURL = "https://nominatim.openstreetmap.org/search"
    static let defaultAnchor = Coordinate(lat: 45.5231, lng: -122.6765) // Portland, OR
    static let minQueryLength = 3

    struct Coordinate: Sendable, Hashable {
        var lat: Double
        var lng: Double
    }

    struct Suggestion: Sendable, Hashable, Identifiable {
        var id: String
        var label: String
        var sub: String
        var lat: Double
        var lng: Double
        var ref: PlaceRef { PlaceRef(label: label, sub: sub, lat: lat, lng: lng) }
    }

    private var cache: [String: [Suggestion]] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 120

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    func search(_ query: String, anchor: Coordinate = defaultAnchor) async throws -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= Self.minQueryLength else { return [] }

        let key = "\(Self.fold(q))|\(String(format: "%.2f,%.2f", anchor.lat, anchor.lng))"
        if let hit = cache[key] { return hit }

        var results: [Suggestion]
        do {
            results = try await photonSearch(q, anchor: anchor)
            // Photon matches every term strictly, so a "name + neighbourhood"
            // query either returns nothing or drifts to another state entirely.
            // Retry without the trailing qualifier when empty or absurdly far.
            let far = results.first.map { Self.distanceM(anchor, $0) > 150_000 } ?? false
            if results.isEmpty || (far && q.split(separator: " ").count >= 3) {
                if let relaxed = Self.relaxQuery(q) {
                    let alt = try await photonSearch(relaxed, anchor: anchor)
                    if let first = alt.first,
                       results.isEmpty || Self.distanceM(anchor, first) < Self.distanceM(anchor, results[0]) {
                        results = alt
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            results = try await nominatimSearch(q, anchor: anchor)
        }

        results = Self.reorderByHouseNumber(q, results)
        store(results, for: key)
        return results
    }

    private func store(_ results: [Suggestion], for key: String) {
        cache[key] = results
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    // MARK: - Photon

    /// Photon's two bias modes each fail on the other's cases (measured):
    /// proximity-only sends "salt and straw" to Anaheim; a bbox sends
    /// "Forest Grove Oregon" to "South Forest Grove Loop". Run both, merge, and
    /// rank by textual match first, distance second.
    private func photonSearch(_ query: String, anchor: Coordinate) async throws -> [Suggestion] {
        async let proximity = photonFetch(query, anchor: anchor, useBbox: false)
        async let boxed = photonFetch(query, anchor: anchor, useBbox: true)

        var features: [PhotonFeature] = []
        var failures = 0
        for attempt in [try? await proximity, try? await boxed] {
            if let attempt { features.append(contentsOf: attempt) } else { failures += 1 }
        }
        if failures == 2 { throw TravelError.network }

        var seen = Set<String>()
        var merged: [PhotonFeature] = []
        for f in features where seen.insert(f.dedupeKey).inserted {
            merged.append(f)
        }

        let folded = Self.fold(query)
        return merged
            .map { feature -> (PhotonFeature, Int, Int, Double) in
                let coord = Coordinate(lat: feature.lat, lng: feature.lng)
                return (feature,
                        Self.matchTier(folded, feature.haystack),
                        Self.matchTier(folded, feature.nameFold),
                        Self.distanceM(anchor, coord))
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.2 != b.2 { return a.2 < b.2 }
                return a.3 < b.3
            }
            .prefix(6)
            .map { $0.0.suggestion }
    }

    private func photonFetch(_ query: String, anchor: Coordinate, useBbox: Bool) async throws -> [PhotonFeature] {
        var comps = URLComponents(string: Self.photonURL)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "lat", value: String(anchor.lat)),
            URLQueryItem(name: "lon", value: String(anchor.lng)),
        ]
        if useBbox {
            let box = [anchor.lng - 0.35, anchor.lat - 0.20, anchor.lng + 0.35, anchor.lat + 0.20]
                .map { String(format: "%.4f", $0) }
                .joined(separator: ",")
            items.append(URLQueryItem(name: "bbox", value: box))
        }
        comps.queryItems = items

        let (data, response) = try await session.data(from: comps.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TravelError.network }
        let decoded = try JSONDecoder().decode(PhotonResponse.self, from: data)
        return decoded.features.compactMap(PhotonFeature.init)
    }

    // MARK: - Nominatim fallback

    private func nominatimSearch(_ query: String, anchor: Coordinate) async throws -> [Suggestion] {
        let viewbox: String = [anchor.lng - 0.6, anchor.lat + 0.4, anchor.lng + 0.6, anchor.lat - 0.4]
            .map { String(format: "%.4f", $0) }
            .joined(separator: ",")
        var comps = URLComponents(string: Self.nominatimURL)!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "bounded", value: "0"),
            URLQueryItem(name: "viewbox", value: viewbox),
        ]
        var request = URLRequest(url: comps.url!)
        // Nominatim's usage policy requires identifying the caller.
        request.setValue("Backplan/1.0 (website.fairpoint.backplan)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TravelError.network }
        let rows = try JSONDecoder().decode([NominatimRow].self, from: data)
        return rows.compactMap { row in
            guard let lat = Double(row.lat), let lng = Double(row.lon) else { return nil }
            let parts = row.display_name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return Suggestion(
                id: "n\(row.place_id)",
                label: Self.shortenStreet(parts.first ?? row.display_name),
                sub: parts.dropFirst().prefix(2).joined(separator: ", "),
                lat: lat, lng: lng
            )
        }
    }
}

// MARK: - Text + geometry helpers

extension GeocodeService {
    /// People type "3703 NE 22nd Ave"; OSM stores "3703 Northeast 22nd Avenue".
    /// Collapsing both sides onto the short form is what makes that query match —
    /// note "northeast" does NOT contain the substring "ne".
    private static let foldSynonyms: [(String, String)] = [
        ("northeast", "ne"), ("northwest", "nw"), ("southeast", "se"), ("southwest", "sw"),
        ("north", "n"), ("south", "s"), ("east", "e"), ("west", "w"),
        ("avenue", "ave"), ("street", "st"), ("saint", "st"), ("boulevard", "blvd"),
        ("drive", "dr"), ("road", "rd"), ("court", "ct"), ("lane", "ln"),
        ("place", "pl"), ("terrace", "ter"), ("parkway", "pkwy"), ("highway", "hwy"),
    ]

    static func fold(_ s: String) -> String {
        let base = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
        let cleaned = String(base.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var tokens = cleaned.split(separator: " ").map(String.init)
        for i in tokens.indices {
            if let match = foldSynonyms.first(where: { $0.0 == tokens[i] }) {
                tokens[i] = match.1
            }
        }
        return tokens.joined(separator: " ")
    }

    private static let streetAbbrev: [(String, String)] = [
        ("Northeast", "NE"), ("Northwest", "NW"), ("Southeast", "SE"), ("Southwest", "SW"),
        ("North", "N"), ("South", "S"), ("East", "E"), ("West", "W"),
        ("Avenue", "Ave"), ("Street", "St"), ("Boulevard", "Blvd"), ("Drive", "Dr"),
        ("Road", "Rd"), ("Court", "Ct"), ("Lane", "Ln"), ("Terrace", "Ter"),
        ("Parkway", "Pkwy"), ("Highway", "Hwy"),
    ]

    /// Applied to street strings only — abbreviating inside a POI name would
    /// mangle things like "Pioneer Courthouse Square".
    static func shortenStreet(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            streetAbbrev.first { $0.0 == String(word) }?.1 ?? String(word)
        }.joined(separator: " ")
    }

    /// 0 = exact, 1 = prefix, 2 = all query tokens present, 3 = no textual match.
    static func matchTier(_ q: String, _ hay: String) -> Int {
        guard !hay.isEmpty else { return 3 }
        if hay == q { return 0 }
        if hay.hasPrefix(q) { return 1 }
        let tokens = q.split(separator: " ")
        if !tokens.isEmpty, tokens.allSatisfy({ hay.contains($0) }) { return 2 }
        return 3
    }

    private static let connectors: Set<String> = ["on", "in", "near", "at", "by", "the", "of", "and"]

    /// Drop the trailing qualifier token, plus any dangling connector.
    static func relaxQuery(_ query: String) -> String? {
        var tokens = query.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }
        tokens.removeLast()
        while let last = tokens.last, connectors.contains(last.lowercased()) { tokens.removeLast() }
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }

    /// A leading house number is a strong signal Photon's own ranking ignores.
    static func reorderByHouseNumber(_ query: String, _ results: [Suggestion]) -> [Suggestion] {
        let digits = query.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        guard !digits.isEmpty else { return results }
        let number = String(digits)
        let matches = results.filter { $0.label.hasPrefix(number) }
        let rest = results.filter { !$0.label.hasPrefix(number) }
        return matches + rest
    }

    /// Equirectangular metres — plenty accurate at city scale, much cheaper than
    /// haversine.
    static func distanceM(_ a: Coordinate, _ b: Coordinate) -> Double {
        let mLat = 111_320.0
        let mLng = 111_320.0 * cos(a.lat * .pi / 180)
        let dy = (a.lat - b.lat) * mLat
        let dx = (a.lng - b.lng) * mLng
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func distanceM(_ a: Coordinate, _ s: Suggestion) -> Double {
        distanceM(a, Coordinate(lat: s.lat, lng: s.lng))
    }

    private static func distanceM(_ a: Coordinate, _ f: PhotonFeature) -> Double {
        distanceM(a, Coordinate(lat: f.lat, lng: f.lng))
    }
}

// MARK: - Wire formats

private struct PhotonResponse: Decodable {
    var features: [RawFeature]

    struct RawFeature: Decodable {
        var geometry: Geometry
        var properties: Properties

        struct Geometry: Decodable { var coordinates: [Double] }
        struct Properties: Decodable {
            var name: String?
            var housenumber: String?
            var street: String?
            var district: String?
            var city: String?
            var state: String?
            var osm_id: Int?
            var osm_type: String?
        }
    }
}

private struct NominatimRow: Decodable {
    var place_id: Int
    var lat: String
    var lon: String
    var display_name: String
}

private struct PhotonFeature {
    var suggestion: GeocodeService.Suggestion
    var haystack: String
    var nameFold: String
    var dedupeKey: String
    var lat: Double
    var lng: Double

    init?(_ raw: PhotonResponse.RawFeature) {
        guard raw.geometry.coordinates.count >= 2 else { return nil }
        let lng = raw.geometry.coordinates[0]
        let lat = raw.geometry.coordinates[1]
        let p = raw.properties
        let (primary, context) = PhotonFeature.buildLabel(p)

        self.lat = lat
        self.lng = lng
        self.dedupeKey = (p.osm_type.map { "\($0)\(p.osm_id ?? 0)" })
            ?? String(format: "%.5f,%.5f", lat, lng)
        // Everything the query could plausibly be matching against — the town
        // case ("Forest Grove Oregon") only ranks right if `state` is in here.
        self.haystack = GeocodeService.fold(
            [p.name, p.housenumber, p.street, p.district, p.city, p.state]
                .compactMap { $0 }.joined(separator: " ")
        )
        self.nameFold = GeocodeService.fold(p.name ?? "")
        self.suggestion = GeocodeService.Suggestion(
            id: dedupeKey, label: primary, sub: context, lat: lat, lng: lng
        )
    }

    private static func buildLabel(_ p: PhotonResponse.RawFeature.Properties) -> (String, String) {
        let street = GeocodeService.shortenStreet(p.street ?? "")
        let addr = [p.housenumber, street.isEmpty ? nil : street]
            .compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let town = p.city ?? p.district ?? ""

        // No street means a locality or region. Photon fills `county` there, but
        // "Forest Grove, Washington" reads as the wrong state — the state is what
        // actually disambiguates, so county gets dropped.
        if addr.isEmpty {
            let primary = p.name ?? (town.isEmpty ? (p.state ?? "Unknown") : town)
            let context = p.name != nil ? uniqJoin([town, p.state]) : uniqJoin([p.state])
            return (primary, context)
        }
        if let name = p.name { return (name, uniqJoin([addr, town])) }
        return (addr, uniqJoin([p.district, p.city, p.state]))
    }

    private static func uniqJoin(_ parts: [String?]) -> String {
        var out: [String] = []
        for raw in parts {
            let v = (raw ?? "").trimmingCharacters(in: .whitespaces)
            if !v.isEmpty && !out.contains(v) { out.append(v) }
        }
        return out.joined(separator: ", ")
    }
}
