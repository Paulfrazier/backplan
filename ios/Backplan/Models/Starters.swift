import Foundation

/// One-tap presets, mirroring the web `QUICK_ADDS` / `STARTERS` constants.
/// Quick adds append a single fully-formed step; starters load a whole routine.
enum Starters {

    /// A single tap-to-add step preset. `name`/`duration`/`unit` only — a fresh
    /// `Step` (with its own id) is built on each add so rows stay uniquely identified.
    struct QuickAdd: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let unit: DurationUnit

        var step: Step { Step(name: name, duration: duration, unit: unit) }

        /// Compact duration label, e.g. "15m" / "2h".
        var durationLabel: String {
            let n = duration.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(duration)) : String(duration)
            return n + (unit == .hr ? "h" : "m")
        }
    }

    /// A prebuilt routine. Loading it replaces the current step list but keeps the
    /// user's target time / event name.
    struct Starter: Identifiable {
        let id = UUID()
        let name: String
        let glyph: String
        let seeds: [(String, Double, DurationUnit)]

        var steps: [Step] { seeds.map { Step(name: $0.0, duration: $0.1, unit: $0.2) } }
        var stepCount: Int { seeds.count }
    }

    static let quickAdds: [QuickAdd] = [
        QuickAdd(name: "Shower", duration: 15, unit: .min),
        QuickAdd(name: "Get dressed", duration: 10, unit: .min),
        QuickAdd(name: "Breakfast", duration: 15, unit: .min),
        QuickAdd(name: "Brush teeth", duration: 5, unit: .min),
        QuickAdd(name: "Make coffee", duration: 5, unit: .min),
        QuickAdd(name: "Pack bag", duration: 5, unit: .min),
        QuickAdd(name: "Walk dog", duration: 15, unit: .min),
        QuickAdd(name: "Drive there", duration: 20, unit: .min),
        QuickAdd(name: "Find parking", duration: 10, unit: .min),
        QuickAdd(name: "Buffer", duration: 10, unit: .min),
    ]

    static let plans: [Starter] = [
        Starter(name: "School drop-off", glyph: "🎒", seeds: [
            ("Wake & get dressed", 15, .min),
            ("Breakfast", 15, .min),
            ("Pack bag", 5, .min),
            ("Drive there", 15, .min),
            ("Buffer", 5, .min),
        ]),
        Starter(name: "Out the door", glyph: "☀️", seeds: [
            ("Shower", 15, .min),
            ("Get dressed", 10, .min),
            ("Breakfast", 15, .min),
            ("Make coffee", 5, .min),
            ("Pack bag", 5, .min),
        ]),
        Starter(name: "Catch a flight", glyph: "✈️", seeds: [
            ("Finish packing", 15, .min),
            ("Drive to airport", 40, .min),
            ("Park & shuttle", 20, .min),
            ("Check bag", 15, .min),
            ("Security", 30, .min),
            ("Walk to gate", 15, .min),
            ("Buffer", 20, .min),
        ]),
        Starter(name: "Dinner reservation", glyph: "🍽️", seeds: [
            ("Get ready", 25, .min),
            ("Drive there", 20, .min),
            ("Find parking", 10, .min),
            ("Buffer", 5, .min),
        ]),
        Starter(name: "Kids' bedtime", glyph: "🌙", seeds: [
            ("Bath", 15, .min),
            ("PJs & teeth", 10, .min),
            ("Story", 15, .min),
            ("Lights out", 5, .min),
        ]),
    ]
}
