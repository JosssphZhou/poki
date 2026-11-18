import Foundation
import UserNotifications

enum DailyTaskReminder {
    static let categoryID = "daily-task"
    static let runID = "daily-task.run"
    static let prefix = "poki.daily-task."
    static func identifier(_ id: UUID) -> String { prefix + id.uuidString }

    @MainActor static func request(for plan: DailyTask.Plan, at now: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.name ?? title
        content.body = body
        content.categoryIdentifier = categoryID
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: plan.hour, minute: plan.minute,
            second: DailyTask.reminderSecond(for: plan, at: now)), repeats: true)
        return UNNotificationRequest(identifier: identifier(plan.noticeID), content: content, trigger: trigger)
    }
}

@MainActor
protocol DailyTaskNotificationCenter {
    func allowed() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor
struct SystemDailyTaskNotifications: DailyTaskNotificationCenter {
    let center = UNUserNotificationCenter.current()
    func allowed() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional: return true
        #if os(iOS)
        case .ephemeral: return true
        #endif
        default: return false
        }
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Reconciles repeating reminders, serializing add() with edits and claims. Failed adds back off
/// 30, 60, 120 ... seconds (at most an hour); denied authorization is checked only once a minute.
@MainActor
final class DailyTaskReminders {
    private let tasks: DailyTask
    private let center: any DailyTaskNotificationCenter
    private let now: () -> Date
    private let request: (DailyTask.Plan, Date) -> UNNotificationRequest
    private let logFailure: () -> Void
    private var installed: [UUID: Int] = [:]
    private var failures: [UUID: (count: Int, next: Date)] = [:]
    private var authorizationRetryAt: Date?
    private var refreshing = false
    private var refreshAgain = false

    init(tasks: DailyTask, center: any DailyTaskNotificationCenter, now: @escaping () -> Date = Date.init,
         request: @escaping (DailyTask.Plan, Date) -> UNNotificationRequest, logFailure: @escaping () -> Void) {
        self.tasks = tasks; self.center = center; self.now = now
        self.request = request; self.logFailure = logFailure
    }

    func remove(_ id: UUID) {
        center.remove([DailyTaskReminder.identifier(id)])
        installed[id] = nil; failures[id] = nil
    }

    func invalidate(_ id: UUID) { installed[id] = nil; failures[id] = nil }

    func refresh() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            await reconcile()
        } while refreshAgain
    }

    private func reconcile() async {
        let ids = Set(tasks.plans.map(\.noticeID))
        for id in Set(installed.keys).union(failures.keys).subtracting(ids) { remove(id) }
        let date = now()
        guard authorizationRetryAt.map({ date >= $0 }) ?? true else { return }
        let needed = tasks.plans.filter {
            installed[$0.noticeID] != DailyTask.reminderSecond(for: $0, at: date)
                && (failures[$0.noticeID].map { date >= $0.next } ?? true)
        }
        guard !needed.isEmpty else { return }
        guard await center.allowed() else {
            authorizationRetryAt = now().addingTimeInterval(60)
            return
        }
        authorizationRetryAt = nil
        for plan in needed {
            guard let current = tasks.plans.first(where: { $0.noticeID == plan.noticeID }) else { continue }
            let value = request(current, now())
            let second = (value.trigger as? UNCalendarNotificationTrigger)?.dateComponents.second
            do {
                try await center.add(value)
                installed[current.noticeID] = second
                failures[current.noticeID] = nil
                if let latest = tasks.plans.first(where: { $0.noticeID == current.noticeID }) {
                    if DailyTask.reminderSecond(for: latest, at: now()) != second { refreshAgain = true }
                } else {
                    // Deletion may have happened while add() was suspended.
                    remove(current.noticeID)
                }
            } catch {
                let count = (failures[current.noticeID]?.count ?? 0) + 1
                let delay = min(3600, 30 * pow(2, Double(min(count - 1, 7))))
                failures[current.noticeID] = (count, now().addingTimeInterval(delay))
                logFailure()
            }
        }
    }
}
