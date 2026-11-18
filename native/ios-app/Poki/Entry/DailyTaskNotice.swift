import UIKit
import UserNotifications

/// The system owns delivery, including when Poki is not running. A tap is routed by the shared
/// notification delegate, not by a URL another app could open.
enum DailyTaskNotice {
    static let categoryID = "daily-task"
    static let runID = "daily-task.run"
    private static let prefix = "poki.daily-task."
    @MainActor private static var clock = DailyTaskClock()
    @MainActor private static var timer: Timer?
    @MainActor private static var reminderSeconds: [UUID: Int] = [:]
    @MainActor private static var updatingReminders: Set<UUID> = []

    /// Uses the app's existing background lifetime, never requests extra background privileges.
    @MainActor static func schedulesChanged() {
        guard !DailyTask.shared.plans.isEmpty else {
            timer?.invalidate()
            timer = nil
            clock = DailyTaskClock()
            reminderSeconds.removeAll()
            return
        }
        if timer == nil {
            clock = DailyTaskClock()
            let tick = Timer(timeInterval: 1, repeats: true) { _ in
                Task { @MainActor in checkClock() }
            }
            timer = tick
            RunLoop.main.add(tick, forMode: .common)
        }
        refreshReminders()
    }

    @MainActor private static func checkClock() {
        let now = Date()
        let due = clock.advance(to: now, plans: DailyTask.shared.plans)
        let state = UIApplication.shared.applicationState
        // An unlocked phone may be showing another app. Inactive means a system interruption:
        // don't seize the phone then, or when the lock state is unknown.
        if state == .active || state == .background,
           PKInProcess.shared().screenLockState()?.boolValue == false,
           let app = AskPoki.app, let chat = AskPoki.chat {
            for delivery in due { run(delivery, app: app, chat: chat) }
        }
        refreshReminders()
    }

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

        let request = reminder(for: plan, at: .now)
        try await center.add(request)
        do {
            if let previous = try DailyTask.shared.save(plan, replacing: previousID) {
                remove(previous.noticeID)
            }
        } catch {
            remove(plan.noticeID)
            throw error
        }
        reminderSeconds[plan.noticeID] = nil
        schedulesChanged()
        return true
    }

    @MainActor private static func reminder(for plan: DailyTask.Plan, at now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.name ?? AppLocalization.text(LocalizedStringResource("Daily Task Ready"))
        content.body = AppLocalization.text(LocalizedStringResource("Tap to run your scheduled task."))
        content.categoryIdentifier = categoryID
        content.sound = .default
        // Only the optional public name appears on the Lock Screen, never the instructions.
        // Give the live clock ten seconds to start and suppress the fallback. If it isn't running
        // (including a force quit), iOS still owns this repeating reminder.
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: plan.hour, minute: plan.minute,
                                                    second: DailyTask.reminderSecond(for: plan, at: now)), repeats: true)
        return UNNotificationRequest(identifier: identifier(plan.noticeID), content: content, trigger: trigger)
    }

    @MainActor private static func refreshReminders() {
        let plans = DailyTask.shared.plans
        let now = Date()
        let ids = Set(plans.map(\.noticeID))
        reminderSeconds = reminderSeconds.filter { ids.contains($0.key) }
        for plan in plans {
            let second = DailyTask.reminderSecond(for: plan, at: now)
            guard reminderSeconds[plan.noticeID] != second, !updatingReminders.contains(plan.noticeID) else { continue }
            updatingReminders.insert(plan.noticeID)
            let request = reminder(for: plan, at: now)
            Task { @MainActor in
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    reminderSeconds[plan.noticeID] = second
                    updatingReminders.remove(plan.noticeID)
                    if !DailyTask.shared.plans.contains(where: { $0.noticeID == plan.noticeID }) {
                        remove(plan.noticeID)
                        reminderSeconds[plan.noticeID] = nil
                    } else if let current = DailyTask.shared.plans.first(where: { $0.noticeID == plan.noticeID }),
                              DailyTask.reminderSecond(for: current, at: .now) != second {
                        // A claim arrived while add() was in flight. Serialize the correction so an
                        // older request cannot restore today's fallback after it was suppressed.
                        refreshReminders()
                    }
                } catch {
                    updatingReminders.remove(plan.noticeID)
                    reminderSeconds[plan.noticeID] = nil
                    AppLog.shared.add("daily-task", "could not refresh a reminder; will retry while Poki runs")
                }
            }
        }
    }

    @MainActor static func cancel(_ id: UUID) throws {
        if let previous = try DailyTask.shared.remove(id) {
            remove(previous.noticeID)
        }
        schedulesChanged()
    }

    private static func identifier(_ id: UUID) -> String { prefix + id.uuidString }

    private static func remove(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
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
            refreshReminders()
        }
        return result
    }
}
