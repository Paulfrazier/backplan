import Foundation
import Observation

@MainActor
@Observable
final class PlanStore {
    /// Both halves of the night pair. This is the storage; `plan` below is a
    /// read/write pointer into it, which is what keeps every existing
    /// `store.plan.steps` call site working unchanged.
    var pair: PlanPair {
        didSet { persistLast() }
    }
    /// Which half the editor is pointed at.
    var activeKey: PlanKey {
        didSet { persistLast() }
    }
    /// The edge between them. Off by default — a lone plan behaves exactly as
    /// it did before the pair existed.
    var link: NightLink {
        didSet { persistLast() }
    }

    /// The plan currently being edited. Computed, so it cannot carry `didSet`;
    /// writes land in `pair`, whose `didSet` does the persisting.
    var plan: Plan {
        get { pair[activeKey] }
        set { pair[activeKey] = newValue }
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
        let restored = PlanStore.restore(from: defaults)
        self.pair = restored.pair
        self.activeKey = restored.activeKey
        self.link = restored.link
        self.templates = PlanStore.load([Template].self, key: "backplan.templates", from: defaults) ?? []
        self.places = PlanStore.load([SavedPlace].self, key: "backplan.places", from: defaults) ?? []
    }

    /// Live computed result for the current plan. Pass `now` so views can drive
    /// recomputation on a ticking clock without mutating the model.
    func result(now: Date = Date()) -> PlanResult {
        BackwardsPlanner.compute(plan, now: now)
    }

    // MARK: - The night pair

    /// Chained, the morning plan is always the day *after* the evening one — an
    /// offset two-valued `TargetDay` cannot express, so it is derived here.
    /// Mirrors the web `dayOffsetFor(plan)`.
    func dayOffset(for key: PlanKey) -> Int {
        if link.enabled && key == .morning {
            return (pair.evening.day == .tomorrow ? 1 : 0) + 1
        }
        return pair[key].day == .tomorrow ? 1 : 0
    }

    /// `nil` when the pair is off, which is also what hides the bridge.
    func bridge(now: Date = Date()) -> NightBridge? {
        guard link.enabled else { return nil }
        return NightBridge.make(
            evening: pair.evening, eveningOffset: dayOffset(for: .evening),
            morning: pair.morning, morningOffset: dayOffset(for: .morning),
            sleepNeed: link.sleepNeed, now: now
        )
    }

    /// Result for either half, for the tab subtitles.
    func result(for key: PlanKey, now: Date = Date()) -> PlanResult {
        BackwardsPlanner.compute(pair[key], now: now)
    }

    func switchTo(_ key: PlanKey) {
        guard key != activeKey else { return }
        activeKey = key
    }

    /// Turning the pair on seeds an empty morning; turning it off falls back to
    /// the evening plan, since the morning tab is about to disappear.
    func setLinkEnabled(_ on: Bool) {
        link.enabled = on
        if on, pair.morning.steps.isEmpty {
            pair.morning.eventName = MorningSeed.eventName
            pair.morning.steps = MorningSeed.steps
        }
        if !on, activeKey == .morning {
            activeKey = .evening
        }
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

    /// v2 holds the pair; v1 was a bare `Plan` at the top level and still loads
    /// (see `restore`). The Edit/Overview flag lives in `@AppStorage` and stays
    /// out of this deliberately — it is view state, not plan state.
    private struct PairSnapshot: Codable {
        var v: Int = 2
        var active: PlanKey = .evening
        var link: NightLink = NightLink()
        var plans: PlanPair
    }

    private func persistLast() {
        let snap = PairSnapshot(v: 2, active: activeKey, link: link, plans: pair)
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: lastKey)
        }
    }

    private static func restore(
        from defaults: UserDefaults
    ) -> (pair: PlanPair, activeKey: PlanKey, link: NightLink) {
        if let snap = load(PairSnapshot.self, key: "backplan.last", from: defaults) {
            // A morning tab that is no longer reachable would strand the editor.
            let key = (snap.active == .morning && !snap.link.enabled) ? .evening : snap.active
            return (snap.plans, key, snap.link)
        }
        // v1 — a single plan, which becomes the evening one. The pair stays off,
        // so an upgrading user sees exactly what they left behind.
        if let old = load(Plan.self, key: "backplan.last", from: defaults) {
            return (PlanPair(evening: old, morning: seedMorning()), .evening, NightLink())
        }
        return (PlanPair(evening: seed(), morning: seedMorning()), .evening, NightLink())
    }

    /// The morning half before the user has ever switched the pair on. Empty by
    /// design — `setLinkEnabled` seeds it at the moment it first becomes visible.
    private static func seedMorning() -> Plan {
        Plan(eventName: "", target: "08:15", day: .tomorrow, steps: [])
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
