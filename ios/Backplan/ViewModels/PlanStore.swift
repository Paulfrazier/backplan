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
    var places: [SavedPlace] {
        didSet { persistPlaces() }
    }

    private let lastKey = "backplan.last"
    private let templatesKey = "backplan.templates"
    private let placesKey = "backplan.places"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.plan = PlanStore.load(Plan.self, key: "backplan.last", from: defaults) ?? PlanStore.seed()
        self.templates = PlanStore.load([Template].self, key: "backplan.templates", from: defaults) ?? []
        self.places = PlanStore.load([SavedPlace].self, key: "backplan.places", from: defaults) ?? []
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

    /// Append a fully-formed preset step (Quick Add) — no typing required.
    func addQuickStep(_ quick: Starters.QuickAdd) {
        plan.steps.append(quick.step)
    }

    /// Load a prebuilt routine, replacing the current steps. Keeps target/event.
    func loadStarter(_ starter: Starters.Starter) {
        plan.steps = starter.steps
    }

    /// True if there's anything worth warning about before a starter replaces it.
    var hasMeaningfulSteps: Bool {
        plan.steps.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.minutes > 0 }
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

    // MARK: - Travel steps

    /// Append a travel step and immediately try to resolve it.
    func addTravelStep() {
        var step = Step(name: "", duration: 5, unit: .min)
        step.travel = Travel()
        step.name = PlanStore.travelStepName(step)
        plan.steps.append(step)
    }

    /// Turn travel lookup on or off for an existing step.
    func toggleTravel(stepID: Step.ID) {
        guard let idx = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        if plan.steps[idx].travel != nil {
            plan.steps[idx].travel = nil
        } else {
            plan.steps[idx].travel = Travel()
            if plan.steps[idx].name.trimmingCharacters(in: .whitespaces).isEmpty {
                plan.steps[idx].name = PlanStore.travelStepName(plan.steps[idx])
            }
        }
    }

    static func travelStepName(_ step: Step) -> String {
        guard let travel = step.travel else { return step.name }
        guard let to = travel.to else { return "\(travel.mode.verb) there" }
        return "\(travel.mode.verb) to \(to.label)"
    }

    /// Chain rule: an explicit origin wins; otherwise inherit the nearest earlier
    /// leg's destination; otherwise fall back to home. This is what lets a
    /// home → school → work plan fill itself in with one address typed per stop.
    /// KEEP IN SYNC with the web `resolveOrigin` in index.html.
    func resolveOrigin(for stepID: Step.ID) -> (place: PlaceRef, chained: Bool)? {
        guard let idx = plan.steps.firstIndex(where: { $0.id == stepID }),
              let travel = plan.steps[idx].travel else { return nil }
        if let explicit = travel.from { return (explicit, false) }
        for j in stride(from: idx - 1, through: 0, by: -1) {
            if let to = plan.steps[j].travel?.to { return (to, true) }
        }
        if let home = places.first(where: { $0.isHome }) { return (home.ref, true) }
        return nil
    }

    /// Place-search bias: home when it's set, a Portland default until then.
    var searchAnchor: GeocodeService.Coordinate {
        guard let home = places.first(where: { $0.isHome }) else { return GeocodeService.defaultAnchor }
        return GeocodeService.Coordinate(lat: home.lat, lng: home.lng)
    }

    /// Fetch (or re-fetch) the routed duration for one travel leg. Resolves the
    /// step by id, never by index — a reorder or delete mid-flight would
    /// otherwise write the answer onto the wrong row.
    @discardableResult
    func refreshTravel(stepID: Step.ID, force: Bool = false) async -> TravelError? {
        guard let travel = plan.steps.first(where: { $0.id == stepID })?.travel,
              let to = travel.to,
              let origin = resolveOrigin(for: stepID) else { return nil }
        do {
            let result = try await RouteService.shared.route(
                mode: travel.mode, from: origin.place, to: to, force: force
            )
            applyTravelResult(result, to: stepID)
            return nil
        } catch let error as TravelError {
            return error
        } catch {
            return .network
        }
    }

    func applyTravelResult(_ result: TravelResult, to stepID: Step.ID) {
        guard let idx = plan.steps.firstIndex(where: { $0.id == stepID }),
              plan.steps[idx].travel != nil else { return }
        plan.steps[idx].travel?.result = result
        // A hand-typed duration is a deliberate override; never stomp it.
        if plan.steps[idx].travel?.manual != true {
            plan.steps[idx].duration = Double(result.minutes)
            plan.steps[idx].unit = .min
        }
    }

    /// Re-resolve every leg — used after a change that can shift origins (a new
    /// destination upstream, or a different home).
    func refreshAllTravel(force: Bool = false) async {
        for step in plan.steps where step.travel?.to != nil {
            await refreshTravel(stepID: step.id, force: force)
        }
    }

    // MARK: - Places

    func savePlace(name: String, suggestion: GeocodeService.Suggestion) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let label = [suggestion.label, suggestion.sub].filter { !$0.isEmpty }.joined(separator: ", ")
        if let idx = places.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            places[idx].label = label
            places[idx].lat = suggestion.lat
            places[idx].lng = suggestion.lng
        } else {
            places.append(SavedPlace(
                name: trimmed, label: label,
                lat: suggestion.lat, lng: suggestion.lng,
                // The first place saved is almost always home.
                isHome: places.isEmpty
            ))
        }
    }

    func setHome(_ place: SavedPlace) {
        let makeHome = !place.isHome
        for i in places.indices {
            places[i].isHome = makeHome && places[i].id == place.id
        }
    }

    func deletePlace(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
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

    private func persistPlaces() {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: placesKey)
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
