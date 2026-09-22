import Foundation

enum TravelError: Error, Sendable {
    /// The service answered, but there is no route between the two points
    /// (or they're outside its tile coverage).
    case noRoute
    /// The service couldn't be reached, or answered with a server error.
    case network

    var message: String {
        switch self {
        case .noRoute: return "No route found between those two points."
        case .network: return "Couldn't reach the routing service."
        }
    }
}

/// Travel-time lookup via brouter.de — key-free, and the only free service
/// checked that genuinely honours drive/bike/walk as separate profiles.
///
/// Times are free-flow: BRouter has no traffic model. That's surfaced in the UI
/// wording rather than papered over with a made-up multiplier.
actor RouteService {
    static let shared = RouteService()

    private static let baseURL = "https://brouter.de/brouter"

    private var cache: [String: TravelResult] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 200

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    func route(mode: TravelMode, from: PlaceRef, to: PlaceRef, force: Bool = false) async throws -> TravelResult {
        let key = Self.cacheKey(mode, from, to)
        if !force, let hit = cache[key] { return hit }

        let lonlats = String(format: "%.6f,%.6f|%.6f,%.6f", from.lng, from.lat, to.lng, to.lat)
        var comps = URLComponents(string: Self.baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "lonlats", value: lonlats),
            URLQueryItem(name: "profile", value: mode.profile),
            URLQueryItem(name: "alternativeidx", value: "0"),
            URLQueryItem(name: "format", value: "geojson"),
        ]

        // brouter.de is a volunteer-run host and intermittently answers a routable
        // request with a non-JSON body. That's indistinguishable from a real "no
        // route", so retry once before telling the user their trip is impossible.
        var decoded: BRouterResponse?
        var status = 0
        for attempt in 0..<2 where decoded == nil {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(600)) }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(from: comps.url!)
            } catch let error as CancellationError {
                throw error
            } catch {
                throw TravelError.network
            }
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // BRouter reports routing problems as a plain-text body, not as JSON
            // and not consistently by status: "can't route" comes back 200,
            // "outside tile coverage" comes back 400 ("datafile ... not found").
            // So parse first and let the shape decide — only a 5xx is genuinely
            // "service down".
            decoded = try? JSONDecoder().decode(BRouterResponse.self, from: data)
        }
        guard let props = decoded?.features.first?.properties else {
            throw status >= 500 ? TravelError.network : TravelError.noRoute
        }

        let meters = Int(Double(props.trackLength) ?? 0)
        let seconds = Int(Double(props.totalTime) ?? 0)
        guard seconds > 0 else { throw TravelError.noRoute }

        let result = TravelResult(
            minutes: max(1, Int((Double(seconds) / 60).rounded())),
            distanceM: meters,
            fetchedAt: Date()
        )
        store(result, for: key)
        return result
    }

    /// Cached value for a leg, if one is already known — lets the UI show a
    /// result immediately instead of flashing a spinner on every render.
    func cached(mode: TravelMode, from: PlaceRef, to: PlaceRef) -> TravelResult? {
        cache[Self.cacheKey(mode, from, to)]
    }

    private func store(_ result: TravelResult, for key: String) {
        cache[key] = result
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func cacheKey(_ mode: TravelMode, _ from: PlaceRef, _ to: PlaceRef) -> String {
        String(format: "%@|%.5f,%.5f|%.5f,%.5f", mode.rawValue, from.lat, from.lng, to.lat, to.lng)
    }
}

private struct BRouterResponse: Decodable {
    var features: [Feature]

    struct Feature: Decodable {
        var properties: Properties
    }
    struct Properties: Decodable {
        var trackLength: String
        var totalTime: String

        enum CodingKeys: String, CodingKey {
            case trackLength = "track-length"
            case totalTime = "total-time"
        }
    }
}

// MARK: - Formatting

enum TravelFmt {
    static func distance(_ meters: Int) -> String {
        let miles = Double(meters) / 1609.34
        if miles < 0.1 { return "\(Int((Double(meters) * 3.28084).rounded())) ft" }
        return miles < 10
            ? String(format: "%.1f mi", miles)
            : "\(Int(miles.rounded())) mi"
    }
}
