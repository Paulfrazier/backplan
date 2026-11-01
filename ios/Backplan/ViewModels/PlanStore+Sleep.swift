import Foundation

/// The wake-up sheet's writes. Kept apart from `PlanStore.swift` so the sheet
/// (and the widget that opens it) can grow without touching the store's core.
extension PlanStore {
    /// Wake is a free variable only while the morning has no routine; with one,
    /// wake is derived (target − routine) and the editable time is the morning
    /// target itself. Same rule as the tracker's "Wake at" picker.
    var wakeIsDerived: Bool { !pair.morning.steps.isEmpty }

    /// Save the sheet: the morning target (which *is* the wake time when the
    /// morning is empty), the sleep need, the sleeper — the same fields the night
    /// controls and the tracker read and write, never a copy — and the sheet's
    /// own wind-down.
    ///
    /// It does NOT switch "Chain tomorrow morning" on. The first cut did, and
    /// that quietly re-read whatever plan was open as tonight's bedtime: an
    /// 88-minute errand run with a 5:43 PM target became "wind-down" and
    /// "lights out", and the widget said 21 hours. The sheet's night stands on
    /// its own (`link.windDown`); chaining stays an explicit choice.
    func saveSleep(morningTarget: String, sleepNeed: Int, sleeper: String, windDown: Int) {
        if pair.morning.target != morningTarget {
            pair.morning.target = morningTarget
        }
        var l = link
        l.sleepNeed = max(0, sleepNeed)
        l.sleeper = sleeper.trimmingCharacters(in: .whitespaces)
        l.windDown = max(0, windDown)
        if l != link { link = l }
    }
}
