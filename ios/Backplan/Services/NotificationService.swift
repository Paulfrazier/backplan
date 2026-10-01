import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for scheduling per-step alerts.
/// All Backplan notifications share an identifier prefix so disarm can cancel
/// exactly the ones we created.
final class NotificationService: Sendable {
    static let shared = NotificationService()
    private init() {}

    private let idPrefix = "backplan.step."
    private var center: UNUserNotificationCenter { .current() }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Schedule one local notification per future step boundary plus the target.
    /// Boundaries already in the past are skipped. Returns the count scheduled.
    @discardableResult
    /// `finalAlert` overrides the target alert's title/body — a Day has no
    /// single event to announce, only the end of its last block.
    func arm(name: String, result: PlanResult, finalAlert: (title: String, body: String)? = nil,
             now: Date = Date()) async -> Int {
        cancelAll()

        var requests: [UNNotificationRequest] = []
        for (i, seg) in result.segments.enumerated() {
            guard seg.start > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Time to start: \(seg.name)"
            content.body = name.isEmpty
                ? "Next up in your plan."
                : "Next up for \(name)."
            content.sound = .default
            requests.append(makeRequest(id: "\(idPrefix)\(i)", fireAt: seg.start, content: content, now: now))
        }

        if result.target > now {
            let content = UNMutableNotificationContent()
            content.title = finalAlert?.title ?? (name.isEmpty ? "It's time." : "Time for \(name).")
            content.body = finalAlert?.body ?? "Your target has arrived."
            content.sound = .default
            requests.append(makeRequest(id: "\(idPrefix)target", fireAt: result.target, content: content, now: now))
        }

        for req in requests {
            try? await center.add(req)
        }
        return requests.count
    }

    func cancelAll() {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix(self.idPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func makeRequest(id: String, fireAt: Date, content: UNNotificationContent, now: Date) -> UNNotificationRequest {
        let interval = max(1, fireAt.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
