#if DEBUG
import Foundation

/// Launch-argument state for simulator screenshots — the simulator can't take
/// injected touches, so every screen state has to be reachable from launch.
///   -BPDemo      reset to the climbing → pick-up scenario
///   -BPAddToDay  then run "Add to Day" and edit the plan (exercises the link)
///   -BPExpand    show every plan-block's steps
///   -BPTab day   open on a tab
///   -BPArmDay    start the Day countdown (BackplanApp)
@MainActor
enum DebugSeed {
    static let home = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
                                 name: "Home", label: "3703 NE 22nd Ave", lat: 45.5497, lng: -122.6434, isHome: true)
    static let gym = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
                                name: "Climbing gym", label: "The Circuit NE", lat: 45.5352, lng: -122.6402)
    static let school = SavedPlace(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!,
                                   name: "School", label: "Sabin", lat: 45.5536, lng: -122.6494)

    static func applyIfRequested(_ defaults: UserDefaults = .standard) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-BPTab"), args.indices.contains(i + 1) {
            defaults.set(args[i + 1], forKey: "backplan.mode")
        }
        guard args.contains("-BPDemo") else { return }
        let enc = JSONEncoder()
        for key in ["backplan.templates", "backplan.linked", "backplan.day", "backplan.last"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(try? enc.encode([home, gym, school]), forKey: "backplan.places")
        let plan = Plan(eventName: "Pick-up", target: "15:00", day: .today, steps: [
            Step(name: "Snack", duration: 10, unit: .min),
            Step(name: "Bike to School", duration: 3, unit: .min, travel: Travel(mode: .bike, to: school.ref)),
        ])
        defaults.set(try? enc.encode(plan), forKey: "backplan.last")
        let day = DayPlan(date: .today, blocks: [DayBlock(name: "Climb", duration: 1, unit: .hr, placeID: gym.id)])
        defaults.set(try? enc.encode(day), forKey: "backplan.day")
    }

    /// Runs after the store exists.
    static func afterLaunch(_ store: PlanStore) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-BPAddToDay") else { return }
        store.addPlanToDay(name: "Pick-up")
        // Edit the linked plan: the Day block must pick this up.
        store.plan.steps[0].duration = 15
        print("BPDEBUG linked=\(store.linkedTemplate?.name ?? "nil") blockSteps=\(store.day.blocks.compactMap { $0.steps?.map(\.minutes) })")
    }
}

extension PlanStore {
    static func debugDayBlockIDs() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: "backplan.day"),
              let day = try? JSONDecoder().decode(DayPlan.self, from: data) else { return [] }
        return day.blocks.map(\.id)
    }
}
#endif
