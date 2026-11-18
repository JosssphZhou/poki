import Foundation
import Observation

/// Local-time schedules. Automatic starts and notification taps share the same durable claim.
@Observable @MainActor
final class DailyTask {
    struct Plan: Codable, Equatable, Identifiable {
        let id: UUID
        private let revision: UUID
        let name: String?
        let prompt: String
        let hour: Int
        let minute: Int
        fileprivate var lastDue: Date?

        var noticeID: UUID { revision }

        init(id: UUID = UUID(), name: String? = nil, prompt: String, hour: Int, minute: Int) {
            self.id = id
            revision = UUID()
            self.name = name
            self.prompt = prompt
            self.hour = hour
            self.minute = minute
        }
    }

    struct Delivery: Equatable, Sendable {
        let id: UUID
        let date: Date
    }

    struct Request: Equatable {
        let delivery: Delivery
        var automatic: Bool
    }

    enum Result: Equatable { case ignored, waiting, submitted }

    static let shared = DailyTask(file: URL.applicationSupportDirectory.appending(path: "PokiDailyTask.json"))
    // Reserve most of iOS's notification budget for suggestions and to-do reminders.
    static let capacity = 20

    private struct Saved: Codable {
        var plans: [Plan] = []
    }

    enum ChangeError: Error { case scheduleChanged, tooManyPlans }

    private let file: URL
    private var saved: Saved
    var plans: [Plan] { saved.plans }
    private(set) var pending: [Request] = []

    init(file: URL) {
        self.file = file
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: file) {
            if let saved = try? decoder.decode(Saved.self, from: data) {
                self.saved = saved
                return
            }
        }
        saved = Saved()
    }

    /// Check the old revision after the notification request is installed. An edit never replaces
    /// a newer save or resurrects a schedule deleted while the system was processing the request.
    @discardableResult
    func save(_ plan: Plan, replacing noticeID: UUID? = nil) throws -> Plan? {
        var next = saved
        let index = next.plans.firstIndex { $0.id == plan.id }
        let previous = index.map { next.plans[$0] }
        guard previous?.noticeID == noticeID else { throw ChangeError.scheduleChanged }
        if let index {
            next.plans[index] = plan
            next.plans[index].lastDue = previous?.lastDue
        } else {
            guard next.plans.count < Self.capacity else { throw ChangeError.tooManyPlans }
            next.plans.append(plan)
        }
        try persist(next)
        if let previous { pending.removeAll { $0.delivery.id == previous.noticeID } }
        return previous
    }

    @discardableResult
    func remove(_ id: UUID) throws -> Plan? {
        var next = saved
        guard let index = next.plans.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = next.plans.remove(at: index)
        try persist(next)
        pending.removeAll { $0.delivery.id == previous.noticeID }
        return previous
    }

    /// Keep one requested occurrence per schedule, in request order. A new request cannot replace
    /// another schedule's request while a task is running or the first scene is still starting.
    func request(_ delivery: Delivery, automatic: Bool = false, at now: Date = .now, calendar: Calendar = localCalendar) {
        guard eligible(delivery, at: now, calendar: calendar) != nil else { return }
        if let index = pending.firstIndex(where: { $0.delivery.id == delivery.id }) {
            let existing = pending[index]
            let latest = existing.delivery.date < delivery.date ? delivery : existing.delivery
            // An actual tap changes a waiting automatic request into a manually started one.
            pending[index] = Request(delivery: latest, automatic: existing.automatic && automatic)
        } else {
            pending.append(Request(delivery: delivery, automatic: automatic))
        }
    }

    func shouldRemind(_ delivery: Delivery, at now: Date = .now, calendar: Calendar = localCalendar) -> Bool {
        eligible(delivery, at: now, calendar: calendar) != nil
    }

    @discardableResult
    func run(_ delivery: Delivery, ready: Bool, at now: Date = .now, calendar: Calendar = localCalendar,
             submit: (String) -> Void) -> Result {
        guard let (index, due) = eligible(delivery, at: now, calendar: calendar) else {
            pending.removeAll { $0.delivery == delivery }
            return .ignored
        }
        guard ready else { return .waiting }
        var next = saved
        next.plans[index].lastDue = due
        // Claim before any side effects. A duplicate callback or a cold launch must not resubmit
        // a task that may already have acted, even if the previous process didn't finish the run.
        do { try persist(next) } catch { return .waiting }
        pending.removeAll { $0.delivery.id == delivery.id }
        submit(next.plans[index].prompt)
        return .submitted
    }

    private func persist(_ next: Saved) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        saved = next
    }

    private func eligible(_ delivery: Delivery, at now: Date, calendar: Calendar) -> (index: Int, due: Date)? {
        guard delivery.date <= now,
              let index = plans.firstIndex(where: { $0.noticeID == delivery.id }) else { return nil }
        let plan = plans[index]
        guard let due = Self.due(at: delivery.date, plan: plan, calendar: calendar),
              due == Self.due(at: now, plan: plan, calendar: calendar),
              plan.lastDue.map({ $0 < due }) ?? true else { return nil }
        return (index, due)
    }

    /// A late tap on yesterday's reminder can run until the next scheduled occurrence.
    private static func due(at date: Date, plan: Plan, calendar: Calendar) -> Date? {
        guard let today = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: date) else { return nil }
        if date >= today { return today }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: yesterday)
    }

    /// Give the running app ten seconds to start before iOS presents the fallback reminder.
    /// Immediately after a successful start, second zero is already past: the repeating reminder
    /// then points to tomorrow. After the grace window the clock can restore second ten.
    static func reminderSecond(for plan: Plan, at now: Date, calendar: Calendar = localCalendar) -> Int {
        guard let due = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: now),
              now >= due, now < due.addingTimeInterval(10),
              plan.lastDue.map({ $0 >= due }) == true else { return 10 }
        return 0
    }

    nonisolated static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

/// Observes time only while the process actually runs. Restarting, returning from suspension or
/// unlocking must not silently start an old occurrence that already asked the owner to tap.
@MainActor
final class DailyTaskClock {
    private var checkedAt: Date

    init(now: Date = .now) { checkedAt = now }

    func advance(to now: Date, plans: [DailyTask.Plan], calendar: Calendar = DailyTask.localCalendar) -> [DailyTask.Delivery] {
        let previous = checkedAt
        checkedAt = now
        guard now > previous, now.timeIntervalSince(previous) <= 10 else { return [] }
        return plans.compactMap { plan in
            guard let due = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: now),
                  due > previous, due <= now else { return nil }
            return DailyTask.Delivery(id: plan.noticeID, date: due)
        }
    }
}
