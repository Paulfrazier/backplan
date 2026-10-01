import Foundation

/// Which edge of a block a pin fixes. A plan arrives pinned at its end — its
/// target is a "be ready by" — while a hand-made fixed time is usually a start.
enum PinEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case start, end
    var id: String { rawValue }
    var label: String { self == .start ? "starts" : "done by" }
}

/// One block in the Day view. KEEP IN SYNC with the web `normalizeBlock` in
/// index.html.
///
/// - `at` set → an anchor at a clock time; nil → floats with its neighbours.
/// - `steps` set → a plan-block: its length comes from the plan's steps, with
///   travel legs re-routed for where the day has you.
/// - `link` → the saved template this block follows; edits to it flow in.
struct DayBlock: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var duration: Double = 30
    var unit: DurationUnit = .min
    /// "HH:mm" (24h) when pinned.
    var at: String?
    var edge: PinEdge = .start
    var placeID: UUID?
    /// How you get to this block's place from the previous one.
    var via: TravelMode = .drive
    var steps: [Step]?
    /// The plan's first travel leg leaves from wherever the day has you, not
    /// the plan's own start. Off = the plan's start (usually home).
    var bridge: Bool = true
    var link: UUID?

    init(id: UUID = UUID(), name: String = "", duration: Double = 30, unit: DurationUnit = .min,
         at: String? = nil, edge: PinEdge = .start, placeID: UUID? = nil, via: TravelMode = .drive,
         steps: [Step]? = nil, bridge: Bool = true, link: UUID? = nil) {
        self.id = id
        self.name = name
        self.duration = duration
        self.unit = unit
        self.at = at
        self.edge = edge
        self.placeID = placeID
        self.via = via
        self.steps = steps
        self.bridge = bridge
        self.link = link
    }

    // Lenient: defaults don't make keys optional to the synthesized decoder,
    // and one bad block must not take the whole day down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 30
        unit = try c.decodeIfPresent(DurationUnit.self, forKey: .unit) ?? .min
        at = try c.decodeIfPresent(String.self, forKey: .at)
        edge = try c.decodeIfPresent(PinEdge.self, forKey: .edge) ?? .start
        placeID = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        via = try c.decodeIfPresent(TravelMode.self, forKey: .via) ?? .drive
        steps = try c.decodeIfPresent([Step].self, forKey: .steps)
        bridge = try c.decodeIfPresent(Bool.self, forKey: .bridge) ?? true
        link = try c.decodeIfPresent(UUID.self, forKey: .link)
    }

    var isAnchor: Bool { at != nil }
    var isPlan: Bool { steps != nil }

    /// Same normalization as `Step.minutes` / the web `stepMinutes`.
    var minutes: Int {
        guard duration.isFinite, duration >= 0 else { return 0 }
        return unit == .hr ? Int((duration * 60).rounded()) : Int(duration.rounded())
    }
}

struct DayPlan: Codable, Equatable, Sendable {
    var date: TargetDay = .today
    var blocks: [DayBlock] = []

    init(date: TargetDay = .today, blocks: [DayBlock] = []) {
        self.date = date
        self.blocks = blocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(TargetDay.self, forKey: .date) ?? .today
        blocks = try c.decodeIfPresent([DayBlock].self, forKey: .blocks) ?? []
    }

    /// First visit: the exact question the Day view exists to answer.
    static let seed = DayPlan(blocks: [
        DayBlock(name: "Climb", duration: 1, unit: .hr),
        DayBlock(name: "Pick-up routine", duration: 30, unit: .min, at: "15:00"),
    ])
}

/// Something you can drop onto the day from the tray.
enum TrayItem: Identifiable, Hashable {
    case flex
    case anchor
    case preset(Int)
    case template(UUID)

    var id: String { payload }

    /// Drag payload — a plain string, so it rides an `NSItemProvider` as text.
    var payload: String {
        switch self {
        case .flex: return "bp.flex"
        case .anchor: return "bp.anchor"
        case .preset(let i): return "bp.preset.\(i)"
        case .template(let id): return "bp.tpl.\(id.uuidString)"
        }
    }

    init?(payload: String) {
        switch payload {
        case "bp.flex": self = .flex
        case "bp.anchor": self = .anchor
        default:
            if payload.hasPrefix("bp.preset."), let i = Int(payload.dropFirst("bp.preset.".count)) {
                self = .preset(i)
            } else if payload.hasPrefix("bp.tpl."), let id = UUID(uuidString: String(payload.dropFirst("bp.tpl.".count))) {
                self = .template(id)
            } else {
                return nil
            }
        }
    }

    /// KEEP IN SYNC with the web `DAY_PRESETS` (names and lengths; iOS uses
    /// SF Symbols where the web uses emoji).
    static let presets: [(symbol: String, name: String, duration: Double, unit: DurationUnit)] = [
        ("figure.climbing", "Climb", 1, .hr),
        ("dumbbell.fill", "Gym", 1, .hr),
        ("laptopcomputer", "Focus work", 90, .min),
        ("takeoutbag.and.cup.and.straw.fill", "Lunch", 30, .min),
        ("cup.and.saucer.fill", "Coffee", 20, .min),
        ("cart.fill", "Errand", 30, .min),
        ("shower.fill", "Shower", 15, .min),
        ("hourglass", "Buffer", 10, .min),
    ]
}
