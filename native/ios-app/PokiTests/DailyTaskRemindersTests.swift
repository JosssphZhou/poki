import Foundation
import UserNotifications
import XCTest
@testable import Poki

@MainActor
final class DailyTaskRemindersTests: XCTestCase {
    func testRefreshRegistersARepeatingRequestAndSkipsTheClaimedOccurrence() async throws {
        try await withReminders { h in
            await h.reminders.refresh()
            let initial = try XCTUnwrap(h.center.pending.values.first)
            XCTAssertEqual(initial.content.title, "Public name")
            XCTAssertFalse(initial.content.body.contains(h.plan.prompt))
            let firstTrigger = try XCTUnwrap(initial.trigger as? UNCalendarNotificationTrigger)
            XCTAssertTrue(firstTrigger.repeats)
            XCTAssertEqual(firstTrigger.dateComponents.second, 10)
            _ = h.tasks.run(.init(id: h.plan.noticeID, date: h.due), ready: true, at: h.due, calendar: h.calendar) { _ in }
            h.now = h.due.addingTimeInterval(1)
            await h.reminders.refresh()
            let suppressed = try XCTUnwrap(h.center.pending.values.first?.trigger as? UNCalendarNotificationTrigger)
            XCTAssertTrue(suppressed.repeats)
            let next = h.calendar.nextDate(after: h.now, matching: suppressed.dateComponents, matchingPolicy: .nextTime)
            XCTAssertEqual(next, h.calendar.date(byAdding: .day, value: 1, to: h.due))
            h.now = h.due.addingTimeInterval(11)
            await h.reminders.refresh()
            let future = try XCTUnwrap(h.center.pending.values.first?.trigger as? UNCalendarNotificationTrigger)
            XCTAssertTrue(future.repeats)
            XCTAssertEqual(future.dateComponents.second, 10)
            XCTAssertTrue(try XCTUnwrap(h.calendar.nextDate(after: h.now, matching: future.dateComponents, matchingPolicy: .nextTime)) > h.now)
        }
    }

    func testDeniedAuthorizationDoesNotAddOrLogEveryTick() async throws {
        try await withReminders { h in
            h.center.authorized = false
            for second in 0..<60 {
                h.now = h.due.addingTimeInterval(Double(second))
                await h.reminders.refresh()
            }
            XCTAssertEqual(h.center.authorizationChecks, 1)
            XCTAssertEqual(h.center.adds, 0)
            XCTAssertEqual(h.logs, 0)
            h.now = h.due.addingTimeInterval(60); h.center.authorized = true
            await h.reminders.refresh()
            XCTAssertEqual(h.center.adds, 1)
        }
    }

    func testFailedAddsBackOffAndRecoverWithoutPerSecondLogs() async throws {
        try await withReminders { h in
            h.center.failing = true
            for second in 0..<90 {
                h.now = h.due.addingTimeInterval(Double(second))
                await h.reminders.refresh()
            }
            XCTAssertEqual(h.center.adds, 2, "Attempts at seconds zero and thirty only")
            XCTAssertEqual(h.logs, 2)
            h.now = h.due.addingTimeInterval(90); h.center.failing = false
            await h.reminders.refresh()
            XCTAssertEqual(h.center.adds, 3)
            XCTAssertEqual(h.center.pending.count, 1)
            XCTAssertEqual(h.logs, 2)
        }
    }

    func testClaimWhileAddIsInFlightCannotRestoreTodaysReminder() async throws {
        try await withReminders { h in
            h.now = h.due.addingTimeInterval(1)
            h.center.duringAdd = {
                _ = h.tasks.run(.init(id: h.plan.noticeID, date: h.due), ready: true, at: h.now, calendar: h.calendar) { _ in }
            }
            await h.reminders.refresh()
            XCTAssertEqual(h.center.adds, 2)
            XCTAssertEqual((h.center.pending.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.second, 0)
        }
    }

    func testDeletionWhileAddIsInFlightRemovesTheStaleRequest() async throws {
        try await withReminders { h in
            h.center.duringAdd = { _ = try? h.tasks.remove(h.plan.id) }
            await h.reminders.refresh()
            XCTAssertTrue(h.center.pending.isEmpty)
            await h.reminders.refresh()
            XCTAssertEqual(h.center.adds, 1)
        }
    }

    private func withReminders(_ test: (Harness) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await test(Harness(file: folder.appendingPathComponent("tasks.json")))
    }

    @MainActor private final class Harness {
        let calendar = DailyTask.localCalendar
        let due: Date
        var now: Date
        let tasks: DailyTask
        let plan = DailyTask.Plan(name: "Public name", prompt: "Private task instructions", hour: 9, minute: 0)
        let center = FakeCenter()
        var logs = 0
        var reminders: DailyTaskReminders!
        init(file: URL) throws {
            due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
            now = due
            tasks = DailyTask(file: file)
            try tasks.save(plan)
            reminders = DailyTaskReminders(tasks: tasks, center: center, now: { [unowned self] in now }, request: {
                DailyTaskReminder.request(for: $0, at: $1, title: "Daily Task Ready", body: "Tap to run.")
            }, logFailure: { [unowned self] in logs += 1 })
        }
    }

    private final class FakeCenter: DailyTaskNotificationCenter {
        var authorized = true
        var failing = false
        var authorizationChecks = 0
        var adds = 0
        var pending: [String: UNNotificationRequest] = [:]
        var duringAdd: (() -> Void)?
        func allowed() async -> Bool { authorizationChecks += 1; return authorized }
        func add(_ request: UNNotificationRequest) async throws {
            adds += 1
            if failing { throw URLError(.notConnectedToInternet) }
            let callback = duringAdd; duringAdd = nil
            callback?()
            pending[request.identifier] = request
        }
        func remove(_ identifiers: [String]) { for id in identifiers { pending[id] = nil } }
    }
}
