import Foundation
import Observation

/// `backplan://` routes — the contract widgets (and later App Intents) link
/// into the app with. Hosts only, no parameters: a widget tap says *where*, and
/// the app already knows *what* from its own state.
///
///   backplan://sleep  the wake-up sheet (wake, sleep need, who's sleeping)
///   backplan://now    the countdown: the Now tab, or in Classic the tab whose
///                     arm bar holds the armed chain (Day if the Day is armed)
///   backplan://day    the Day tab
///   backplan://kid    the kid view (sets `backplan.kidView`; its owner reads it)
enum DeepLink: String, CaseIterable, Sendable {
    case sleep, now, day, kid

    static let scheme = "backplan"
    /// `@AppStorage` key the kid view reads.
    static let kidViewKey = "backplan.kidView"

    /// Accepts `backplan://sleep` and the host-less `backplan:sleep`.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let name = url.host() ?? url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let route = DeepLink(rawValue: name.lowercased()) else { return nil }
        self = route
    }

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }
}

/// What a link asks the UI to do. Lives in the environment; `BackplanApp`
/// presents the sheet, `RootView` answers tab requests.
@MainActor
@Observable
final class DeepLinkRouter {
    var showSleep = false

    /// A tab to open. A fresh id per request, so following the same link twice
    /// still moves the UI after the user has wandered off.
    struct TabRequest: Equatable {
        /// "now", "plan" or "day".
        let tab: String
        /// Where "now" lands in Classic, which has no Now tab.
        let classicTab: String
        let id = UUID()
    }
    private(set) var tabRequest: TabRequest?

    /// Returns false for a URL that isn't one of ours.
    @discardableResult
    func handle(_ url: URL, armedIsDay: Bool) -> Bool {
        guard let route = DeepLink(url) else { return false }
        switch route {
        case .sleep:
            showSleep = true
        case .now:
            showSleep = false
            tabRequest = TabRequest(tab: "now", classicTab: armedIsDay ? "day" : "plan")
        case .day:
            showSleep = false
            tabRequest = TabRequest(tab: "day", classicTab: "day")
        case .kid:
            showSleep = false
            UserDefaults.standard.set(true, forKey: DeepLink.kidViewKey)
        }
        return true
    }
}
