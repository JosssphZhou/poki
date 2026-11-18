import Foundation

/// The production scheduling path. UIKit and the lock probe supply observations at the boundary;
/// tests supply the same observations and a controllable clock, without substituting readiness for a lock.
@MainActor
final class DailyTaskScheduler {
    private let tasks: DailyTask
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let foreground: () -> Bool
    private let locked: () -> Bool?
    private let ready: () -> Bool
    private let submit: (String, Bool) -> Void
    private var clock: DailyTaskClock

    init(tasks: DailyTask, now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { DailyTask.localCalendar },
         foreground: @escaping () -> Bool, locked: @escaping () -> Bool?,
         ready: @escaping () -> Bool, submit: @escaping (String, Bool) -> Void) {
        self.tasks = tasks
        self.now = now
        self.calendar = calendar
        self.foreground = foreground
        self.locked = locked
        self.ready = ready
        self.submit = submit
        clock = DailyTaskClock(now: now())
    }

    func resetClock() { clock = DailyTaskClock(now: now()) }

    @discardableResult func tick() -> DailyTask.Delivery? {
        let date = now()
        let calendar = calendar()
        let due = clock.advance(to: date, plans: tasks.plans, calendar: calendar)
        if foreground(), locked() == false, ready() {
            // Queue the whole batch before starting its first task: starting it makes Poki busy.
            for delivery in due { tasks.request(delivery, automatic: true, at: date, calendar: calendar) }
        }
        return drain()
    }

    /// Called on readiness/foreground changes too. Queued automatic starts still cannot take over
    /// another app. A notification tap is manual and iOS already requires an authenticated foreground.
    @discardableResult func drain() -> DailyTask.Delivery? {
        guard foreground() else { return nil }
        for request in tasks.pending {
            if request.automatic, locked() != false { continue }
            switch tasks.run(request.delivery, ready: ready(), at: now(), calendar: calendar(), submit: {
                submit($0, request.automatic)
            }) {
            case .ignored: continue
            case .waiting: return nil
            case .submitted: return request.delivery
            }
        }
        return nil
    }
}
