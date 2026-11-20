import UIKit
import UserNotifications

/// The system owns delivery, including when Poki is not running. A tap is routed by the shared
/// notification delegate, not by a URL another app could open.
enum DailyTaskNotice {
    static let categoryID = DailyTaskReminder.categoryID
    static let runID = DailyTaskReminder.runID
    @MainActor private static var timer: Timer?
    @MainActor private static let scheduler = DailyTaskScheduler(tasks: .shared,
        foreground: { UIApplication.shared.applicationState == .active },
        locked: { PKInProcess.shared().screenLockState()?.boolValue },
        ready: {
            guard let app = AskPoki.app, let chat = AskPoki.chat else { return false }
            return canStart(app: app, chat: chat) && ModelKeys.hasUsableKey
        }, submit: { prompt, automatic in
            AskPoki.chat?.sendDailyTask(prompt, automatically: automatic)
            AppLog.shared.add("daily-task", "scheduled task submitted")
        })
    @MainActor private static let reminders = DailyTaskReminders(tasks: .shared,
        center: SystemDailyTaskNotifications(), request: reminder,
        logFailure: { AppLog.shared.add("daily-task", "could not refresh a reminder; retrying with backoff") })

    // A background round-trip can fit entirely between two timer ticks. Reset at UIKit's actual
    // lifecycle boundaries, before the next active tick, rather than inferring it from elapsed time.
    @MainActor private static let lifecycleObservers = scheduler.observeActivity(
        resigning: UIApplication.willResignActiveNotification,
        active: UIApplication.didBecomeActiveNotification,
        onActive: { schedulesChanged() })

    @MainActor static func schedulesChanged() {
        _ = lifecycleObservers
        DailyTask.shared.retryLoading()
        if DailyTask.shared.plans.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            scheduler.resetClock()
            let tick = Timer(timeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    didSubmit(scheduler.tick())
                    await reminders.refresh()
                }
            }
            timer = tick
            RunLoop.main.add(tick, forMode: .common)
        }
        Task { await reminders.refresh() }
    }

    @MainActor static func runPending() -> Bool { didSubmit(scheduler.drain()) }

    @MainActor @discardableResult private static func didSubmit(_ delivery: DailyTask.Delivery?) -> Bool {
        guard let delivery else { return false }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [DailyTaskReminder.identifier(delivery.id)])
        Task { await reminders.refresh() }
        return true
    }

    @MainActor static var category: UNNotificationCategory {
        let run = UNNotificationAction(identifier: runID,
                                       title: AppLocalization.text(LocalizedStringResource("Run Task")),
                                       options: [.authenticationRequired, .foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [run], intentIdentifiers: [])
    }

    static func delivery(_ notification: UNNotification) -> DailyTask.Delivery? {
        let request = notification.request
        guard request.content.categoryIdentifier == categoryID, request.identifier.hasPrefix(DailyTaskReminder.prefix),
              let id = UUID(uuidString: String(request.identifier.dropFirst(DailyTaskReminder.prefix.count))) else { return nil }
        return DailyTask.Delivery(id: id, date: notification.date)
    }

    @MainActor static func save(_ plan: DailyTask.Plan, replacing previousID: UUID?) async throws -> Bool {
        guard DailyTask.shared.isAvailable else { throw DailyTask.ChangeError.unavailable }
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
                reminders.remove(previous.noticeID)
            }
        } catch {
            reminders.remove(plan.noticeID)
            throw error
        }
        reminders.invalidate(plan.noticeID)
        schedulesChanged()
        return true
    }

    @MainActor private static func reminder(for plan: DailyTask.Plan, at now: Date) -> UNNotificationRequest {
        DailyTaskReminder.request(for: plan, at: now,
            title: AppLocalization.text(LocalizedStringResource("Daily Task Ready")),
            body: AppLocalization.text(LocalizedStringResource("Tap to run your scheduled task.")))
    }

    @MainActor static func cancel(_ id: UUID) throws {
        if let previous = try DailyTask.shared.remove(id) {
            reminders.remove(previous.noticeID)
        }
        schedulesChanged()
    }

    @MainActor static func canStart(app: AppModel, chat: ChatModel) -> Bool {
        app.sessionOn && !app.ownerPaused && !app.pairingUnderWay && app.signer.installMessage == nil
            && app.approvals.isEmpty && !chat.running && !app.voice.isOn
            && ChatModel.delegatedBusy == nil && SessionStore.shared.activeSessionID == nil && !FirstRun.isDue()
    }

}
