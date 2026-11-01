import Foundation

/// What the Sleep Left widget shows at a given minute. "Hours of sleep left" is
/// the evening's question; at 7:37 AM it's "21h" — true and useless. So the
/// widget is the day's question until the evening flips it:
///
/// 1. A running countdown always wins — you started it; it's what you're doing.
/// 2. The morning window (wake − 1 h … the bell) shows the morning countdown.
/// 3. From the flip — 8 PM, or the wind-down's start-by if that's earlier — to
///    wake: hours of sleep left.
/// 4. Otherwise the Day's next thing ("Pick-up 3:00 · leave by 2:45").
/// 5. Nothing at all: the sleep face, which in the daytime reads "full night
///    if down by 10:20 PM".
///
/// Pure, so `DebugSeed` can check the switch points without a widget host.
enum UpNext {
    enum Mode: Equatable {
        case countdown(CountdownFace)
        case day
        case sleep
    }

    /// The evening hour the widget turns to sleep, unless the wind-down has to
    /// start before it.
    static let flipHour = 20

    /// When tonight's sleep face takes over: the earlier of 8 PM on the evening
    /// before the next wake and that night's start-by. `nil` without a night.
    static func flip(_ i: SleepLeft.Inputs?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let i, i.enabled else { return nil }
        let n = SleepLeft.solve(i, now: now, calendar: calendar)
        // The evening that belongs to this wake: for a morning wake, the day
        // before it. Twelve hours back finds it without caring about AM/PM.
        let evening = calendar.startOfDay(for: n.wake.addingTimeInterval(-12 * 3600))
        let eight = calendar.date(bySettingHour: flipHour, minute: 0, second: 0, of: evening) ?? evening
        return min(eight, n.startBy)
    }

    static func mode(
        inputs: SleepLeft.Inputs?, chain: ArmedChain?, morning: MorningInputs?,
        day: DayWidget.Snapshot?, now: Date, calendar: Calendar = .current
    ) -> Mode {
        if let chain, chain.isLive(at: now) { return .countdown(.armed(chain)) }
        if let m = morning?.window(at: now) { return .countdown(.morning(m)) }
        if let f = flip(inputs, now: now, calendar: calendar), now >= f { return .sleep }
        if DayWidget.read(day, now: now, calendar: calendar).kind == .live { return .day }
        return .sleep
    }
}
