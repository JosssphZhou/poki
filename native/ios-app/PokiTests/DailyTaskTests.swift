import Foundation
import XCTest
@testable import Poki

@MainActor
final class DailyTaskTests: XCTestCase {
    func testColdLaunchTapWaitsUntilActiveAndSubmitsExactlyOnce() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let delivery = delivery(plan, on: 18)
            var submitted: [String] = []
            app.request(delivery, at: time(18), calendar: utc)
            let pending = try XCTUnwrap(app.pending.first)
            XCTAssertEqual(app.run(pending, ready: false, at: time(18), calendar: utc) { submitted.append($0) }, .waiting)
            XCTAssertEqual(app.pending, [delivery])
            XCTAssertTrue(submitted.isEmpty)

            XCTAssertEqual(app.run(pending, ready: true, at: time(18), calendar: utc) {
                let otherLaunch = DailyTask(file: file)
                otherLaunch.request(delivery, at: time(18), calendar: utc)
                XCTAssertTrue(otherLaunch.pending.isEmpty, "The claim must already be durable when submission begins")
                submitted.append($0)
            }, .submitted)
            XCTAssertTrue(app.pending.isEmpty)
            XCTAssertEqual(app.run(delivery, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .ignored)

            let reopened = DailyTask(file: file)
            reopened.request(delivery, at: time(18), calendar: utc)
            XCTAssertTrue(reopened.pending.isEmpty)
            XCTAssertEqual(reopened.run(delivery, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .ignored)
            XCTAssertEqual(submitted, [plan.prompt])
        }
    }

    func testForegroundCanSubmitAndTapDoesNotReplayIt() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let delivery = delivery(plan, on: 18)
            var submitted: [String] = []
            XCTAssertEqual(app.run(delivery, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            app.request(delivery, at: time(18), calendar: utc)
            XCTAssertTrue(app.pending.isEmpty)
            XCTAssertEqual(submitted, [plan.prompt])
        }
    }

    func testOpeningPokiWithoutATapDoesNotQueueAnOccurrence() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let delivery = delivery(plan, on: 18)
            XCTAssertTrue(app.pending.isEmpty)
            XCTAssertEqual(app.run(delivery, ready: false, at: time(18), calendar: utc) { _ in
                XCTFail("A foreground delivery that cannot run must only present the notification")
            }, .waiting)
            XCTAssertTrue(app.pending.isEmpty)
            XCTAssertTrue(DailyTask(file: file).pending.isEmpty)
        }
    }

    func testOnlyLatestDueDayCanRunAndTomorrowCanRunAgain() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let yesterday = delivery(plan, on: 17)
            let delayed = DailyTask.Delivery(id: plan.noticeID, date: time(18, hour: 7))
            let today = delivery(plan, on: 18)
            let tomorrow = delivery(plan, on: 19)
            var submitted: [String] = []
            XCTAssertEqual(app.run(delayed, ready: true, at: time(18, hour: 8), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(app.run(yesterday, ready: true, at: time(18, hour: 8), calendar: utc) { submitted.append($0) }, .ignored)
            XCTAssertEqual(app.run(yesterday, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .ignored)
            XCTAssertEqual(app.run(today, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(app.run(tomorrow, ready: true, at: time(19), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(submitted, [plan.prompt, plan.prompt, plan.prompt])
        }
    }

    func testEditingOrCancellingRejectsAnAlreadyDeliveredNotification() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let old = delivery(plan, on: 18)
            app.request(old, at: time(18), calendar: utc)
            let edited = DailyTask.Plan(id: plan.id, prompt: "Read the date.", hour: 9, minute: 0)
            try app.save(edited, replacing: plan.noticeID)
            XCTAssertTrue(app.pending.isEmpty)
            let editedDelivery = delivery(edited, on: 18)
            app.request(old, at: time(18), calendar: utc)
            XCTAssertTrue(app.pending.isEmpty)
            try app.remove(edited.id)
            app.request(editedDelivery, at: time(18), calendar: utc)
            XCTAssertTrue(app.pending.isEmpty)
            XCTAssertTrue(DailyTask(file: file).plans.isEmpty)
        }
    }

    func testTwoSameTimeTasksWaitInTapOrderAndClaimIndependently() async throws {
        try withSchedule { file, first in
            let second = DailyTask.Plan(name: "Date", prompt: "Read the date.", hour: 9, minute: 0)
            try DailyTask(file: file).save(second)
            let app = DailyTask(file: file)
            XCTAssertEqual(app.plans, [first, second])

            let a = delivery(first, on: 18), b = delivery(second, on: 18)
            var submitted: [String] = []
            app.request(b, at: time(18), calendar: utc)
            app.request(a, at: time(18), calendar: utc)
            app.request(b, at: time(18), calendar: utc)
            XCTAssertEqual(app.pending, [b, a])
            XCTAssertEqual(app.run(b, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(app.pending, [a])
            XCTAssertEqual(app.run(a, ready: false, at: time(18), calendar: utc) { submitted.append($0) }, .waiting)
            XCTAssertEqual(app.pending, [a])
            XCTAssertEqual(app.run(a, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(submitted, [second.prompt, first.prompt])

            let reopened = DailyTask(file: file)
            for entry in [a, b] { reopened.request(entry, at: time(18), calendar: utc) }
            XCTAssertTrue(reopened.pending.isEmpty)
        }
    }

    func testEditingKeepsTodaysClaimAndRemovingLeavesOthersWaiting() async throws {
        try withSchedule { file, first in
            let app = DailyTask(file: file)
            let second = DailyTask.Plan(prompt: "Check the date.", hour: 9, minute: 0)
            try app.save(second)
            let secondDelivery = delivery(second, on: 18)
            app.request(secondDelivery, at: time(18), calendar: utc)
            XCTAssertEqual(app.run(delivery(first, on: 18), ready: true, at: time(18), calendar: utc) { _ in }, .submitted)

            let edited = DailyTask.Plan(id: first.id, prompt: "Read the build number.", hour: 9, minute: 0)
            try app.save(edited, replacing: first.noticeID)
            app.request(delivery(edited, on: 18), at: time(18), calendar: utc)
            XCTAssertEqual(app.pending, [secondDelivery])
            try app.remove(first.id)
            XCTAssertEqual(app.pending, [secondDelivery])
            XCTAssertEqual(DailyTask(file: file).plans, [second])
        }
    }

    func testAnEditInFlightCannotResurrectADeletedSchedule() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let edit = DailyTask.Plan(id: plan.id, prompt: "Read the date.", hour: 9, minute: 0)
            try app.remove(plan.id)
            XCTAssertThrowsError(try app.save(edit, replacing: plan.noticeID))
            XCTAssertTrue(app.plans.isEmpty)
        }
    }

    func testAtCapacityEditingIsAllowedButAddingDoesNotReplaceAnyTask() async throws {
        try withSchedule { file, first in
            let app = DailyTask(file: file)
            for index in 1..<DailyTask.capacity {
                try app.save(.init(prompt: "Task \(index)", hour: 12, minute: 0))
            }
            let before = app.plans
            XCTAssertThrowsError(try app.save(.init(prompt: "One too many", hour: 9, minute: 0)))
            XCTAssertEqual(app.plans, before)
            let edited = DailyTask.Plan(id: first.id, prompt: "Edited task", hour: 11, minute: 0)
            try app.save(edited, replacing: first.noticeID)
            XCTAssertEqual(app.plans.count, DailyTask.capacity)
            XCTAssertEqual(app.plans.first, edited)
        }
    }

    func testMigratingPreservesOldNotificationIdentifierAndDayClaim() async throws {
        try withSchedule { file, plan in
            let legacy: [String: Any] = [
                "plan": ["id": plan.id.uuidString, "prompt": plan.prompt, "hour": 9, "minute": 0],
                "lastDay": 20261118
            ]
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let app = DailyTask(file: file)
            let migrated = try XCTUnwrap(app.plans.first)
            XCTAssertEqual(migrated.id, plan.id)
            XCTAssertEqual(migrated.noticeID, plan.id)
            app.request(delivery(migrated, on: 18), at: time(18), calendar: utc)
            XCTAssertTrue(app.pending.isEmpty)
            app.request(delivery(migrated, on: 19), at: time(19), calendar: utc)
            XCTAssertEqual(app.pending, [delivery(migrated, on: 19)])
        }
    }

    func testPersistenceFailureDoesNotSubmit() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            XCTAssertEqual(app.run(delivery(plan, on: 18), ready: true, at: time(18), calendar: utc) { _ in
                XCTFail("The claim must be saved before the task can act")
            }, .waiting)
        }
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func time(_ day: Int, hour: Int = 9) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: 0))!
    }

    private func delivery(_ plan: DailyTask.Plan, on day: Int) -> DailyTask.Delivery {
        DailyTask.Delivery(id: plan.noticeID, date: time(day))
    }

    private func withSchedule(_ exercise: (URL, DailyTask.Plan) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("daily-task.json")
        let plan = DailyTask.Plan(prompt: "Read the iOS version.", hour: 9, minute: 0)
        try DailyTask(file: file).save(plan)
        try exercise(file, plan)
    }
}
