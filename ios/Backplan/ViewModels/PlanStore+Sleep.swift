import Foundation

/// The wake-up sheet's writes. Kept apart from `PlanStore.swift` so the sheet
/// (and the widget that opens it) can grow without touching the store's core.
extension PlanStore {
    /// Wake is a free variable only while the morning has no routine; with one,
    /// wake is derived (target − routine) and the editable time is the morning
    /// target itself. Same rule as the tracker's "Wake at" picker.
    var wakeIsDerived: Bool { !pair.morning.steps.isEmpty }

    /// Save the sheet: the morning target (which *is* the wake time when the
    /// morning is empty), the sleep need and the sleeper — the same three fields
    /// the night controls and the tracker read and write, never a copy — and
    /// switch the night edge on.
    ///
    /// Deliberately not `setLinkEnabled(true)`: that seeds an empty morning with
    /// a starter routine, which would quietly move wake an hour earlier than the
    /// time the user just typed. A bare wake time is a complete answer.
    func saveSleep(morningTarget: String, sleepNeed: Int, sleeper: String) {
        if pair.morning.target != morningTarget {
            pair.morning.target = morningTarget
        }
        var l = link
        l.sleepNeed = max(0, sleepNeed)
        l.sleeper = sleeper.trimmingCharacters(in: .whitespaces)
        l.enabled = true
        if l != link { link = l }
    }
}
