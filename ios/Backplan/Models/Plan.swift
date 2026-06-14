import Foundation

enum TargetDay: String, Codable, CaseIterable, Identifiable {
    case today, tomorrow
    var id: String { rawValue }
    var label: String { self == .today ? "Today" : "Tomorrow" }
}

enum DurationUnit: String, Codable, CaseIterable, Identifiable {
    case min, hr
    var id: String { rawValue }
    var label: String { self == .min ? "min" : "hr" }
}

struct Step: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var duration: Double = 5
    var unit: DurationUnit = .min

    /// Normalized duration in whole minutes, matching the web `stepMinutes`:
    /// clamps negatives/NaN to 0, rounds, converts hours → minutes.
    var minutes: Int {
        guard duration.isFinite, duration >= 0 else { return 0 }
        return unit == .hr ? Int((duration * 60).rounded()) : Int(duration.rounded())
    }
}

struct Plan: Codable, Equatable {
    var eventName: String = ""
    /// Target time of day in "HH:mm" (24h), mirroring the web `state.target`.
    var target: String = "18:20"
    var day: TargetDay = .today
    var steps: [Step] = []
}

extension Plan {
    /// Resolve the target "HH:mm" + day into an absolute Date relative to `now`,
    /// matching the web `targetDate()` (seconds/millis zeroed).
    func targetDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let parts = target.split(separator: ":")
        let h = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        var base = now
        if day == .tomorrow {
            base = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        return calendar.date(
            bySettingHour: min(max(h, 0), 23),
            minute: min(max(m, 0), 59),
            second: 0,
            of: base
        ) ?? base
    }
}
