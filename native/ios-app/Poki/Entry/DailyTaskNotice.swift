import UIKit
import UserNotifications

/// The system owns delivery, including when Poki is not running. A tap is routed by the shared
/// notification delegate, not by a URL another app could open.
enum DailyTaskNotice {
    static let categoryID = "daily-task"
    static let runID = "daily-task.run"
    private static let prefix = "poki.daily-task."

    @MainActor static var category: UNNotificationCategory {
        let run = UNNotificationAction(identifier: runID,
                                       title: AppLocalization.text(LocalizedStringResource("Run Task")),
                                       options: [.authenticationRequired, .foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [run], intentIdentifiers: [])
    }

    static func delivery(_ notification: UNNotification) -> DailyTask.Delivery? {
        let request = notification.request
        guard request.content.categoryIdentifier == categoryID, request.identifier.hasPrefix(prefix),
              let id = UUID(uuidString: String(request.identifier.dropFirst(prefix.count))) else { return nil }
        return DailyTask.Delivery(id: id, date: notification.date)
    }

    @MainActor static func save(_ plan: DailyTask.Plan, replacing previousID: UUID?) async throws -> Bool {
        if previousID == nil, DailyTask.shared.plans.count >= DailyTask.capacity {
            throw DailyTask.ChangeError.tooManyPlans
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { return false }
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { return false }
        }

        let content = UNMutableNotificationContent()
        content.title = plan.name ?? AppLocalization.text(LocalizedStringResource("Daily Task Ready"))
        content.body = AppLocalization.text(LocalizedStringResource("Tap to run your scheduled task."))
        content.categoryIdentifier = categoryID
        content.sound = .default
        // Only the optional public name appears on the Lock Screen, never the instructions.
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: plan.hour, minute: plan.minute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: identifier(plan.noticeID), content: content, trigger: trigger))
        do {
            if let previous = try DailyTask.shared.save(plan, replacing: previousID) {
                remove(previous.noticeID)
            }
        } catch {
            remove(plan.noticeID)
            throw error
        }
        return true
    }

    @MainActor static func cancel(_ id: UUID) throws {
        if let previous = try DailyTask.shared.remove(id) {
            remove(previous.noticeID)
        }
    }

    private static func identifier(_ id: UUID) -> String { prefix + id.uuidString }

    private static func remove(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
    }

    @MainActor static func runIfInFront(_ delivery: DailyTask.Delivery) -> DailyTask.Result {
        guard UIApplication.shared.applicationState == .active,
              let app = AskPoki.app, let chat = AskPoki.chat else { return .waiting }
        return run(delivery, app: app, chat: chat)
    }

    @MainActor static func canStart(app: AppModel, chat: ChatModel) -> Bool {
        app.sessionOn && !app.ownerPaused && !app.pairingUnderWay && app.signer.installMessage == nil
            && app.approvals.isEmpty && !chat.running && !app.voice.isOn
            && ChatModel.delegatedBusy == nil && SessionStore.shared.activeSessionID == nil && !FirstRun.isDue()
    }

    @MainActor @discardableResult
    static func run(_ delivery: DailyTask.Delivery, app: AppModel, chat: ChatModel) -> DailyTask.Result {
        let ready = canStart(app: app, chat: chat) && ModelKeys.hasUsableKey
        let result = DailyTask.shared.run(delivery, ready: ready) { prompt in
            chat.newConversation()
            chat.send(prompt)
            app.log.add("daily-task", "scheduled task submitted")
        }
        if result == .submitted {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(delivery.id)])
        }
        return result
    }
}
