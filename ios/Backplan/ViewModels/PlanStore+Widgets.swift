import Foundation
import WidgetKit

/// What the Countdown widget reads from the store when nothing is armed: the
/// morning plan as written, so it can show the school-morning chain in the
/// morning window and "Tomorrow: School 8:05" the rest of the time.
///
/// Its own file, hooked from `persistLast` by a single call, so the publish
/// path that Sleep Left already owns isn't restructured around it.
extension PlanStore {
    /// Plan-level inputs, not a solved morning: the widget picks the next
    /// target that hasn't gone by, so these stay true until the user edits.
    /// The morning plan's own `target` and steps — what `resolved(.morning)`
    /// computes from — and `link.enabled`, without which there is no morning.
    var morningInputs: MorningInputs {
        MorningInputs(
            enabled: link.enabled,
            eventName: pair.morning.eventName,
            target: pair.morning.target,
            steps: pair.morning.steps
                .filter { $0.minutes > 0 }
                .map { MorningInputs.Step(name: $0.name, minutes: $0.minutes) }
        )
    }

    /// Hand the widget its morning; reload only when it changed. `real` is
    /// false for the self-check's throwaway stores, whose scenarios must not
    /// reach the user's Home Screen.
    func publishCountdownInputs(real: Bool) {
        guard real else { return }
        if CountdownStore.save(morning: morningInputs) {
            WidgetCenter.shared.reloadTimelines(ofKind: CountdownStore.widgetKind)
        }
    }
}
