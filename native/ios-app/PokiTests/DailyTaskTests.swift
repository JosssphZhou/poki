import Foundation
import XCTest
@testable import Poki

@MainActor
final class DailyTaskTests: XCTestCase {
    func testClaimIsPersistedBeforeSubmissionAndSurvivesReopening() async throws {
        try withSchedule { file, plan in
            let app = DailyTask(file: file)
            let delivery = delivery(plan, on: 18)
            var submitted: [String] = []
            app.request(delivery, at: time(18), calendar: utc)
            let pending = try XCTUnwrap(app.pending.first?.delivery)
            XCTAssertEqual(app.run(pending, ready: false, at: time(18), calendar: utc) { submitted.append($0) }, .waiting)
            XCTAssertEqual(app.pending.map(\.delivery), [delivery])
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

    func testOnlyLatestDueOccurrenceCanRunAndTomorrowCanRunAgain() async throws {
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
            XCTAssertEqual(app.pending.map(\.delivery), [b, a])
            XCTAssertEqual(app.run(b, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(app.pending.map(\.delivery), [a])
            XCTAssertEqual(app.run(a, ready: false, at: time(18), calendar: utc) { submitted.append($0) }, .waiting)
            XCTAssertEqual(app.pending.map(\.delivery), [a])
            XCTAssertEqual(app.run(a, ready: true, at: time(18), calendar: utc) { submitted.append($0) }, .submitted)
            XCTAssertEqual(submitted, [second.prompt, first.prompt])

            let reopened = DailyTask(file: file)
            for entry in [a, b] { reopened.request(entry, at: time(18), calendar: utc) }
            XCTAssertTrue(reopened.pending.isEmpty)
        }
    }

    func testEditingKeepsTheDueClaimAndRemovingLeavesOthersWaiting() async throws {
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
            XCTAssertEqual(app.pending.map(\.delivery), [secondDelivery])
            try app.remove(first.id)
            XCTAssertEqual(app.pending.map(\.delivery), [secondDelivery])
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
        XCTAssertEqual(DailyTask.capacity, 20)
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

    func testUnreadableSchedulesCannotBeOverwrittenAndRecoverOnRetry() async throws {
        try withSchedule { file, plan in
            let original = DailyTask(file: file)
            let due = delivery(plan, on: 18)
            XCTAssertEqual(original.run(due, ready: true, at: time(18), calendar: utc) { _ in }, .submitted)
            let bytes = try Data(contentsOf: file)
            var readable = false
            let tasks = DailyTask(file: file, read: { url in
                guard readable else { throw CocoaError(.fileReadNoPermission) }
                return try Data(contentsOf: url)
            })
            XCTAssertFalse(tasks.isAvailable)
            XCTAssertThrowsError(try tasks.save(.init(prompt: "Must not replace existing data", hour: 10, minute: 0)))
            XCTAssertThrowsError(try tasks.remove(plan.id))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            tasks.retryLoading()
            XCTAssertFalse(tasks.isAvailable)
            readable = true
            tasks.retryLoading()
            XCTAssertTrue(tasks.isAvailable)
            XCTAssertEqual(tasks.plans, original.plans)
            XCTAssertEqual(tasks.run(due, ready: true, at: time(18), calendar: utc) { _ in XCTFail("The saved claim must survive") }, .ignored)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            let next = DailyTask.Plan(prompt: "A new task after recovery", hour: 10, minute: 0)
            try tasks.save(next)
            XCTAssertEqual(DailyTask(file: file).plans, original.plans + [next])
        }
    }

    func testInvalidExistingSchedulesAreNotReplacedWithAnEmptyList() async throws {
        try withSchedule { file, plan in
            let bytes = Data("not valid schedule JSON".utf8)
            try bytes.write(to: file)
            let tasks = DailyTask(file: file)
            XCTAssertFalse(tasks.isAvailable)
            XCTAssertThrowsError(try tasks.save(.init(prompt: "Must not overwrite", hour: 10, minute: 0)))
            XCTAssertThrowsError(try tasks.remove(plan.id))
            tasks.retryLoading()
            XCTAssertFalse(tasks.isAvailable)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testWestwardTravelDoesNotSkipTheNextLocalDueInstant() async throws {
        try withSchedule { file, plan in
            let tasks = DailyTask(file: file)
            var tokyo = utc; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let day = DateComponents(year: 2026, month: 11, day: 18, hour: 9)
            let first = tokyo.date(from: day)!, next = losAngeles.date(from: day)!
            XCTAssertTrue(next > first)
            XCTAssertEqual(tasks.run(.init(id: plan.noticeID, date: first), ready: true, at: first, calendar: tokyo) { _ in }, .submitted)
            let reopened = DailyTask(file: file)
            XCTAssertEqual(reopened.run(.init(id: plan.noticeID, date: next), ready: true, at: next, calendar: losAngeles) { _ in }, .submitted)
            XCTAssertEqual(reopened.run(.init(id: plan.noticeID, date: next), ready: true, at: next, calendar: losAngeles) { _ in }, .ignored)
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
