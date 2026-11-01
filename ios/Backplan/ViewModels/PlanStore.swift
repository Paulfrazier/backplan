import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class PlanStore {
    /// Both halves of the night pair. This is the storage; `plan` below is a
    /// read/write pointer into it, which is what keeps every existing
    /// `store.plan.steps` call site working unchanged.
    var pair: PlanPair {
        didSet {
            // Assigned inside its own didSet, so this doesn't re-enter; and
            // even if it did, a second pass finds nothing left to stamp.
            var stamped = pair
            if PlanStore.stampBaseDates(&stamped, from: oldValue) { pair = stamped }
            persistLast()
            // Re-saying a date isn't an edit: a linked template keeps the
            // Today / Tomorrow it was saved with.
            if !normalizing { syncLinked() }
        }
    }
    /// Which half the editor is pointed at.
    var activeKey: PlanKey {
        didSet {
            persistLast()
            // A Day link belongs to the half that was open when it was made.
            // Left in place, the first edit to the other half would write
            // *that* plan through to the template and its Day blocks.
            if activeKey != oldValue { linkedTemplateID = nil }
        }
    }
    /// The edge between them. Off by default — a lone plan behaves exactly as
    /// it did before the pair existed.
    var link: NightLink {
        didSet { persistLast() }
    }
    /// Track-to-sleep: a lens on that same edge, plus the one leg the pair has
    /// nowhere to put (the ride home).
    var track: TrackState {
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
    /// The Day view's blocks. Lives here, not in its own store, because a
    /// linked plan writes through to its blocks on every edit.
    var day: DayPlan {
        didSet {
            // Picking Today / Tomorrow anchors it to today's date, exactly as
            // the plan's picker does (see `stampBaseDates`).
            let picked = day.date != oldValue.date && day.baseDate == oldValue.baseDate
            if picked || day.baseDate == nil { day.baseDate = LocalDay.key(Date()) }
            persistDay()
        }
    }
    /// True while `normalizeDates` writes, so the write isn't taken for an edit.
    @ObservationIgnored private var normalizing = false
    /// The template the open plan writes through to (see `syncLinked`).
    var linkedTemplateID: UUID? {
        didSet { defaults.set(linkedTemplateID?.uuidString, forKey: linkedKey) }
    }
    /// Routed minutes for Day legs, keyed by `DayPlanner.legKey`. Persisted so
    /// a relaunch doesn't re-route every leg (or show 0 min while offline).
    var dayLegs: [String: DayLegCacheEntry] = [:]
    /// Failed lookups this session. Not persisted — retry on next launch.
    var dayLegErrors: [String: TravelError] = [:]
    var dayLegsInFlight: Set<String> = []
    var places: [SavedPlace] {
        didSet { persistPlaces() }
    }

    private let lastKey = "backplan.last"
    private let templatesKey = "backplan.templates"
    private let placesKey = "backplan.places"
    private let dayKey = "backplan.day"
    private let linkedKey = "backplan.linked"
    let dayLegsKey = "backplan.daylegs"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let restored = PlanStore.restore(from: defaults)
        self.pair = restored.pair
        self.activeKey = restored.activeKey
        self.link = restored.link
        self.track = restored.track
        self.templates = PlanStore.load([Template].self, key: "backplan.templates", from: defaults) ?? []
        self.places = PlanStore.load([SavedPlace].self, key: "backplan.places", from: defaults) ?? []
        self.day = PlanStore.load(DayPlan.self, key: "backplan.day", from: defaults) ?? .seed
        let linked = defaults.string(forKey: "backplan.linked").flatMap(UUID.init(uuidString:))
        self.linkedTemplateID = templates.contains { $0.id == linked } ? linked : nil
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        self.dayLegs = (PlanStore.load([String: DayLegCacheEntry].self, key: "backplan.daylegs", from: defaults) ?? [:])
            .filter { $0.value.fetchedAt > cutoff }
        // An install that predates the widget has never published; nor has one
        // whose last edit came before it. Cheap: a no-op when nothing changed.
        publishSleepLeft()
        publishDayWidget()
        // Dates are normalized by the app once the armed snapshot is loaded
        // (a roll has to wait while its plan is the armed one) — see BackplanApp.
    }

    // MARK: - Dates

    /// What is armed, for `normalizeDates`: the armed plan's half, or the Day.
    struct DateHold {
        var plan: PlanKey?
        var day = false
    }

    /// Re-anchor every saved date to today (see `Plan.normalizeDate`). Run at
    /// launch, on return to the foreground and when the local date changes
    /// under a running app — the three ways a plan saved "tomorrow" can find
    /// itself read on the day it meant. KEEP IN SYNC with the web
    /// `normalizeDates` — same rules, same order (evening, morning, Day).
    ///
    /// `hold` says what is armed: a roll (which moves the moment) never
    /// happens to the armed plan or an armed Day; re-saying the same moment
    /// from today always does.
    func normalizeDates(hold: DateHold = DateHold(), now: Date = Date()) {
        var p = pair
        let holdEvening: Bool
        if link.enabled {
            // The pair is one night: last night's lights-out stays where it was
            // until this morning's target has gone by — rolling it to tonight at
            // 6:55 AM would push the school run to tomorrow.
            let lastNight = p.evening.effectiveDay(now: now) < Calendar.current.startOfDay(for: now)
            holdEvening = hold.plan != nil
                || (lastNight && PlanStore.chainedMorning(p.morning, after: p.evening, now: now).targetDate(now: now) > now)
        } else {
            holdEvening = hold.plan == .evening
        }
        let evening = p.evening.normalizeDate(now: now, hold: holdEvening)
        let morning = p.morning.normalizeDate(now: now, hold: hold.plan == .morning)
        if evening || morning {
            normalizing = true
            pair = p
            normalizing = false
        }
        var d = day
        if d.normalizeDate(now: now, hold: hold.day) { day = d }
    }

    /// Is this half's date before today? Only a held linked evening can be —
    /// last night's lights-out, read before this morning's target.
    func isLastNight(_ key: PlanKey, now: Date = Date()) -> Bool {
        resolved(key, now: now).effectiveDay(now: now) < Calendar.current.startOfDay(for: now)
    }

    /// The past-target way forward: the same clock time, tomorrow. A linked
    /// morning's day is derived, so it gets there by moving the night —
    /// tonight's evening, or tomorrow's if that still lands the morning today.
    /// KEEP IN SYNC with the web `planForTomorrow`.
    func planForTomorrow(_ key: PlanKey, now: Date = Date()) {
        let today = LocalDay.key(now)
        var p = pair
        if link.enabled && key == .morning {
            p.evening.day = .today
            p.evening.baseDate = today
            let morningDay = PlanStore.chainedMorning(p.morning, after: p.evening, now: now).effectiveDay(now: now)
            if morningDay <= Calendar.current.startOfDay(for: now) { p.evening.day = .tomorrow }
        } else {
            p[key].day = .tomorrow
            p[key].baseDate = today
        }
        pair = p
    }

    /// Choosing Today / Tomorrow or a new target time is a choice made *today*,
    /// so it anchors to today's date — unless the same write set `baseDate`
    /// itself (normalization does), or there was none to begin with (a template
    /// just loaded, a legacy record). Returns true when it stamped anything.
    private static func stampBaseDates(_ pair: inout PlanPair, from old: PlanPair) -> Bool {
        var changed = false
        for key in PlanKey.allCases {
            let was = old[key], now = pair[key]
            let picked = (now.day != was.day || now.target != was.target) && now.baseDate == was.baseDate
            if picked || now.baseDate == nil {
                let today = LocalDay.key(Date())
                if now.baseDate != today {
                    pair[key].baseDate = today
                    changed = true
                }
            }
        }
        return changed
    }

    /// Live computed result for the current plan. Pass `now` so views can drive
    /// recomputation on a ticking clock without mutating the model.
    func result(now: Date = Date()) -> PlanResult {
        // In track mode the plan ends at "asleep by", not at a bedtime anyone
        // typed — so the step rows and the overview tell the same story as the
        // figure on the tracker card rather than a parallel one.
        if let track = sleepTrack(now: now) {
            return BackwardsPlanner.compute(plan, endingAt: track.asleepAt, now: now)
        }
        return BackwardsPlanner.compute(resolved(activeKey, now: now), now: now)
    }

    // MARK: - The night pair

    /// A half as it will actually run. Chained, the morning plan is always the
    /// day *after* the evening one's effective date — something two-valued
    /// `TargetDay` cannot say on its own, so it is derived here, and every
    /// consumer (result, bridge, arming, the stale check) reads this rather
    /// than `pair[key]`. Mirrors the web `dayOffsetFor(plan)`.
    func resolved(_ key: PlanKey, now: Date = Date()) -> Plan {
        guard link.enabled && key == .morning else { return pair[key] }
        return PlanStore.chainedMorning(pair.morning, after: pair.evening, now: now)
    }

    /// The first morning target *after* lights out: normally the next day,
    /// but a 12:30 AM lights-out is followed by that same day's 8:15, not the
    /// one 31 hours away.
    static func chainedMorning(_ morning: Plan, after evening: Plan, now: Date = Date()) -> Plan {
        func mins(_ hhmm: String) -> Int {
            let parts = hhmm.split(separator: ":").map { Int($0) ?? 0 }
            return (parts.first ?? 0) * 60 + (parts.count > 1 ? parts[1] : 0)
        }
        var p = morning
        p.baseDate = LocalDay.key(evening.effectiveDay(now: now))
        p.day = mins(morning.target) > mins(evening.target) ? .today : .tomorrow
        return p
    }

    /// `nil` when the pair is off, which is also what hides the bridge.
    func bridge(now: Date = Date()) -> NightBridge? {
        guard link.enabled else { return nil }
        return NightBridge.make(
            evening: resolved(.evening, now: now),
            morning: resolved(.morning, now: now),
            sleepNeed: link.sleepNeed, now: now
        )
    }

    /// Result for either half, for the tab subtitles.
    func result(for key: PlanKey, now: Date = Date()) -> PlanResult {
        BackwardsPlanner.compute(resolved(key, now: now), now: now)
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
        // The tracker is a lens on this edge, so the edge going away has to take
        // the lens with it or the app strands itself on a card computing nil.
        if !on { track.on = false }
    }

    // MARK: - Track to sleep

    func setTrackMode(_ on: Bool) {
        track.on = on
        guard on else { return }
        // The tracker is a lens on the night edge, so it turns that edge on. It
        // deliberately does NOT seed a morning routine the way `setLinkEnabled`
        // does: the question here is how much sleep, and an empty morning is
        // exactly what makes the wake time itself directly settable.
        link.enabled = true
        // Editing the morning from inside this mode isn't offered, so don't
        // leave the editor pointed at a plan whose tab is about to vanish.
        if activeKey == .morning { activeKey = .evening }
    }

    /// `nil` when the mode is off, which is also what hides the card.
    func sleepTrack(now: Date = Date()) -> SleepTrack? {
        guard track.on, link.enabled else { return nil }
        return SleepTrack.make(
            evening: pair.evening, morning: pair.morning,
            sleepNeed: link.sleepNeed,
            rideMinutes: track.ride.result?.minutes ?? 0,
            now: now
        )
    }

    /// Home as a travel endpoint — the place the tracker plans *to*, and the
    /// default origin of the first leg in any plan.
    var homeRef: PlaceRef? { places.first(where: { $0.isHome })?.ref }

    /// Route the ride home. The destination is looked up fresh every time rather
    /// than stored, so moving house doesn't strand the leg on an old address.
    @discardableResult
    func refreshRide(force: Bool = false) async -> TravelError? {
        guard let home = homeRef else {
            track.ride.to = nil
            track.ride.result = nil
            return nil
        }
        track.ride.to = home
        guard let from = track.ride.from else {
            track.ride.result = nil
            return nil
        }
        do {
            track.ride.result = try await RouteService.shared.route(
                mode: track.ride.mode, from: from, to: home, force: force
            )
            return nil
        } catch let error as TravelError {
            return error
        } catch {
            return .network
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
        // Unlink first: otherwise the swap would be written into the template.
        linkedTemplateID = nil
        var p = plan
        p.steps = starter.steps
        p.baseDate = LocalDay.key(Date())
        plan = p
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
        if let home = homeRef { return (home, true) }
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
            templates[idx].plan = plan.asTemplate
        } else {
            templates.append(Template(name: trimmed, plan: plan.asTemplate))
        }
        refreshLinkedBlocks()
    }

    /// Loading a template is a fresh copy, not an edit of it.
    func loadTemplate(_ template: Template) {
        linkedTemplateID = nil
        // Templates carry no date; a loaded one is planned from today.
        var p = template.plan
        p.baseDate = LocalDay.key(Date())
        plan = p
    }

    func deleteTemplate(_ template: Template) {
        // Linked Day blocks keep their last snapshot; the plan just unlinks.
        if linkedTemplateID == template.id { linkedTemplateID = nil }
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
        /// Optional, not defaulted: a default value does NOT make a key optional
        /// to the synthesized decoder, and records written before track mode
        /// existed have to keep loading. Additive, so it also stays readable by
        /// a build that predates it.
        var track: TrackState?
    }

    private func persistLast() {
        let snap = PairSnapshot(v: 2, active: activeKey, link: link, plans: pair, track: track)
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: lastKey)
        }
        publishSleepLeft()
        publishCountdownInputs(real: defaults === UserDefaults.standard)
    }

    /// What the Sleep Left widget solves from — the same inputs `sleepTrack`
    /// feeds `SleepTrack.make`, so the widget and the tracker card show the same
    /// figure. The ride counts only while track mode is on, as on the card.
    var sleepLeftInputs: SleepLeft.Inputs {
        SleepLeft.Inputs(
            enabled: link.enabled,
            morningTarget: pair.morning.target,
            morningName: pair.morning.eventName,
            morningMinutes: pair.morning.totalMinutes,
            windDownMinutes: pair.evening.totalMinutes,
            rideMinutes: track.on ? (track.ride.result?.minutes ?? 0) : 0,
            sleepNeed: link.sleepNeed,
            sleeper: link.sleeper,
            eveningTarget: pair.evening.target,
            eveningDay: pair.evening.day.rawValue,
            eveningBaseDate: pair.evening.baseDate
        )
    }

    /// Hand the widget its inputs; reload only when they changed, so editing a
    /// step's name (or anything else the figure doesn't read) costs nothing.
    private func publishSleepLeft() {
        // Only the real store. The self-check builds throwaway stores on a test
        // suite, and their scenarios must not land on the user's Lock Screen.
        guard defaults === UserDefaults.standard else { return }
        if SleepLeft.save(sleepLeftInputs) {
            WidgetCenter.shared.reloadTimelines(ofKind: SleepLeft.widgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: Tonight.widgetKind)
        }
    }

    private static func restore(
        from defaults: UserDefaults
    ) -> (pair: PlanPair, activeKey: PlanKey, link: NightLink, track: TrackState) {
        if let snap = load(PairSnapshot.self, key: "backplan.last", from: defaults) {
            // A morning tab that is no longer reachable would strand the editor.
            let key = (snap.active == .morning && !snap.link.enabled) ? .evening : snap.active
            var track = snap.track ?? TrackState()
            // The tracker cannot exist without the edge it is a lens on; a record
            // claiming otherwise would hide the hero and show nothing in its place.
            if !snap.link.enabled { track.on = false }
            return (snap.plans, key, snap.link, track)
        }
        // v1 — a single plan, which becomes the evening one. The pair stays off,
        // so an upgrading user sees exactly what they left behind.
        if let old = load(Plan.self, key: "backplan.last", from: defaults) {
            return (PlanPair(evening: old, morning: seedMorning()), .evening, NightLink(), TrackState())
        }
        return (PlanPair(evening: seed(), morning: seedMorning()), .evening, NightLink(), TrackState())
    }

    /// The morning half before the user has ever switched the pair on. Empty by
    /// design — `setLinkEnabled` seeds it at the moment it first becomes visible.
    private static func seedMorning() -> Plan {
        Plan(eventName: "", target: "08:15", day: .tomorrow, steps: [], baseDate: LocalDay.key(Date()))
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

    private func persistDay() {
        if let data = try? JSONEncoder().encode(day) {
            defaults.set(data, forKey: dayKey)
        }
        publishDayWidget()
    }

    func persistDayLegs() {
        if let data = try? JSONEncoder().encode(dayLegs) {
            defaults.set(data, forKey: dayLegsKey)
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
            ],
            baseDate: LocalDay.key(now, calendar: calendar)
        )
    }
}
