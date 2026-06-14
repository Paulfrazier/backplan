import Foundation
import Observation

@MainActor
@Observable
final class PlanStore {
    var plan: Plan {
        didSet { persistLast() }
    }
    var templates: [Template] {
        didSet { persistTemplates() }
    }

    private let lastKey = "backplan.last"
    private let templatesKey = "backplan.templates"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.plan = PlanStore.load(Plan.self, key: "backplan.last", from: defaults) ?? PlanStore.seed()
        self.templates = PlanStore.load([Template].self, key: "backplan.templates", from: defaults) ?? []
    }

    /// Live computed result for the current plan. Pass `now` so views can drive
    /// recomputation on a ticking clock without mutating the model.
    func result(now: Date = Date()) -> PlanResult {
        BackwardsPlanner.compute(plan, now: now)
    }

    // MARK: - Step mutations

    func addStep() {
        plan.steps.append(Step(name: "", duration: 5, unit: .min))
    }

    func removeStep(at offsets: IndexSet) {
        plan.steps.remove(atOffsets: offsets)
    }

    func moveStep(from source: IndexSet, to destination: Int) {
        plan.steps.move(fromOffsets: source, toOffset: destination)
    }

    func clearSteps() {
        plan.steps.removeAll()
    }

    // MARK: - Templates

    func saveTemplate(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let idx = templates.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            templates[idx].plan = plan
        } else {
            templates.append(Template(name: trimmed, plan: plan))
        }
    }

    func loadTemplate(_ template: Template) {
        plan = template.plan
    }

    func deleteTemplate(_ template: Template) {
        templates.removeAll { $0.id == template.id }
    }

    // MARK: - Persistence

    private func persistLast() {
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: lastKey)
        }
    }

    private func persistTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            defaults.set(data, forKey: templatesKey)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func seed(now: Date = Date(), calendar: Calendar = .current) -> Plan {
        // Default target is 6:20 PM. If that's already past today, default to
        // Tomorrow so a first-run (often evening) user sees a live plan rather
        // than one stuck hours in the past.
        let todayTarget = calendar.date(bySettingHour: 18, minute: 20, second: 0, of: now) ?? now
        let day: TargetDay = todayTarget > now ? .today : .tomorrow
        return Plan(
            eventName: "",
            target: "18:20",
            day: day,
            steps: [
                Step(name: "Get dressed", duration: 10, unit: .min),
                Step(name: "Drive there", duration: 25, unit: .min),
                Step(name: "Find parking", duration: 10, unit: .min),
            ]
        )
    }
}
