import Foundation

struct DayLegCacheEntry: Codable, Sendable {
    var minutes: Int
    var fetchedAt: Date
}

/// Day view state and the Plan ↔ Day link. KEEP IN SYNC with the web Day view
/// in index.html (`computeDay`, `syncLinked`, `refreshLinkedBlocks`).
extension PlanStore {
    // MARK: - Computing

    func dayResult(now: Date = Date()) -> DayResult {
        DayPlanner.compute(day, places: places, now: now) { mode, from, to in
            let key = DayPlanner.legKey(mode, from, to)
            if let hit = dayLegs[key] { return .ok(hit.minutes) }
            if let err = dayLegErrors[key] { return .error(err) }
            return .loading
        }
    }

    /// Route every leg the last compute couldn't answer. Called from a `.task`
    /// keyed on the set of missing legs, so it reruns only when that changes.
    func fetchDayLegs(_ requests: [LegRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for req in requests where !dayLegsInFlight.contains(req.key) {
                dayLegsInFlight.insert(req.key)
                group.addTask { [weak self] in
                    let outcome: Result<TravelResult, TravelError>
                    do {
                        outcome = .success(try await RouteService.shared.route(mode: req.mode, from: req.from, to: req.to))
                    } catch let e as TravelError {
                        outcome = .failure(e)
                    } catch {
                        outcome = .failure(.network)
                    }
                    await self?.applyDayLeg(req.key, outcome)
                }
            }
        }
    }

    private func applyDayLeg(_ key: String, _ outcome: Result<TravelResult, TravelError>) {
        dayLegsInFlight.remove(key)
        switch outcome {
        case .success(let r):
            dayLegs[key] = DayLegCacheEntry(minutes: r.minutes, fetchedAt: r.fetchedAt)
            persistDayLegs()
        case .failure(let e):
            dayLegErrors[key] = e
        }
    }

    func retryDayLeg(_ key: String) {
        dayLegErrors.removeValue(forKey: key)
    }

    // MARK: - Editing

    func addBlock(_ item: TrayItem, at index: Int? = nil) -> UUID? {
        var block: DayBlock
        var pin = false
        switch item {
        case .flex:
            block = DayBlock()
        case .anchor:
            block = DayBlock()
            pin = true
        case .preset(let i):
            guard TrayItem.presets.indices.contains(i) else { return nil }
            let p = TrayItem.presets[i]
            block = DayBlock(name: p.name, duration: p.duration, unit: p.unit)
        case .template(let id):
            guard let t = templates.first(where: { $0.id == id }) else { return nil }
            // A template comes in as a linked plan-block, steps intact.
            block = DayBlock(name: t.name, steps: t.plan.steps, link: t.id)
        }
        let at = min(max(index ?? day.blocks.count, 0), day.blocks.count)
        day.blocks.insert(block, at: at)
        if pin {
            // Pin it where it landed, so a dropped fixed time doesn't reshuffle the day.
            let start = dayResult().items[at].start
            day.blocks[at].at = DayPlanner.hhmm(DayPlanner.round5(start))
        }
        return block.id
    }

    func togglePin(_ id: UUID) {
        guard let i = day.blocks.firstIndex(where: { $0.id == id }) else { return }
        if day.blocks[i].at != nil {
            day.blocks[i].at = nil
        } else {
            let it = dayResult().items[i]
            day.blocks[i].at = DayPlanner.hhmm(DayPlanner.round5(day.blocks[i].edge == .end ? it.end : it.start))
        }
    }

    func cycleVia(_ id: UUID) {
        guard let i = day.blocks.firstIndex(where: { $0.id == id }) else { return }
        let all = TravelMode.allCases
        day.blocks[i].via = all[(all.firstIndex(of: day.blocks[i].via)! + 1) % all.count]
    }

    // MARK: - Plan ↔ Day link
    //
    // Saved templates are the identity a Day block links to. While the plan is
    // linked, every edit is written through to that template and to every Day
    // block made from it. Pins stay per block — they belong to the day.

    var linkedTemplate: Template? {
        linkedTemplateID.flatMap { id in templates.first { $0.id == id } }
    }

    /// Called from `plan.didSet`.
    func syncLinked() {
        guard let id = linkedTemplateID else { return }
        guard let idx = templates.firstIndex(where: { $0.id == id }) else {
            linkedTemplateID = nil
            return
        }
        if templates[idx].plan != plan { templates[idx].plan = plan }
        refreshLinkedBlocks()
    }

    func refreshLinkedBlocks() {
        let byID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        var blocks = day.blocks
        var changed = false
        for i in blocks.indices {
            guard let link = blocks[i].link, let t = byID[link] else { continue }
            if blocks[i].steps != t.plan.steps {
                blocks[i].steps = t.plan.steps
                changed = true
            }
        }
        if changed { day.blocks = blocks }
    }

    /// The name "Add to Day" will link under, or nil if the plan needs one.
    var addToDayName: String? {
        if let t = linkedTemplate { return t.name }
        let n = plan.eventName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    /// True when adding under `name` would overwrite an unrelated template.
    func addToDayConflicts(_ name: String) -> Bool {
        guard let t = templates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        return t.id != linkedTemplateID
    }

    /// Plan → Day: save the plan as a template, link to it, and drop it into
    /// the day as one block pinned "done by" the target, slotted in where it
    /// falls chronologically.
    @discardableResult
    func addPlanToDay(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !plan.steps.isEmpty else { return nil }
        let templateID: UUID
        if let idx = templates.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            templates[idx].plan = plan
            templateID = templates[idx].id
        } else {
            let t = Template(name: trimmed, plan: plan)
            templates.append(t)
            templateID = t.id
        }
        linkedTemplateID = templateID
        // An empty day adopts the plan's day; otherwise the day keeps its own.
        if day.blocks.isEmpty { day.date = plan.day }
        let due = DayPlanner.clock(plan.target, on: day.date, now: Date())
        let idx = dayResult().items.firstIndex { $0.start >= due } ?? day.blocks.count
        let block = DayBlock(name: trimmed, at: plan.target, edge: .end, steps: plan.steps, link: templateID)
        day.blocks.insert(block, at: idx)
        return block.id
    }

    /// Day → Plan: open a linked block's plan, linked, so edits flow back.
    func editLinkedPlan(_ templateID: UUID) {
        guard let t = templates.first(where: { $0.id == templateID }) else { return }
        // Set the link before the plan, so syncLinked writes to the right template.
        linkedTemplateID = templateID
        plan = t.plan
    }

    func unlink() {
        linkedTemplateID = nil
    }

    /// Would opening a linked block's plan replace unsaved work in Plan?
    func editingWouldReplace(_ templateID: UUID) -> Bool {
        linkedTemplateID != templateID && hasMeaningfulSteps
    }
}
