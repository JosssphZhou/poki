import Foundation
import UIKit
import XCTest
@testable import Poki

@MainActor
final class DailyTaskSchedulerTests: XCTestCase {
    func testForegroundTickSubmitsOnceAndALaterTapCannotReplayIt() async throws {
        try withScheduler { h in
            h.now = h.due
            XCTAssertEqual(h.scheduler.tick()?.id, h.first.noticeID)
            XCTAssertEqual(h.sent.map(\.prompt), [h.first.prompt])
            XCTAssertEqual(h.sent.map(\.automatic), [true])
            h.now = h.due.addingTimeInterval(11)
            h.tasks.request(.init(id: h.first.noticeID, date: h.now), at: h.now, calendar: h.calendar)
            XCTAssertNil(h.scheduler.tick())
            XCTAssertTrue(h.tasks.pending.isEmpty)
            XCTAssertEqual(h.sent.count, 1)
        }
    }

    func testBackgroundDueTimeRequiresATapEvenAfterReturningToForeground() async throws {
        try withScheduler { h in
            h.foreground = false; h.now = h.due
            XCTAssertNil(h.scheduler.tick())
            XCTAssertTrue(h.tasks.pending.isEmpty)
            h.foreground = true; h.now = h.due.addingTimeInterval(11)
            XCTAssertNil(h.scheduler.tick())
            h.tasks.request(.init(id: h.first.noticeID, date: h.now), at: h.now, calendar: h.calendar)
            XCTAssertNotNil(h.scheduler.drain())
            XCTAssertEqual(h.sent.map(\.automatic), [false])
        }
    }

    func testShortBackgroundRoundTripWithoutATimerTickRequiresATap() async throws {
        try withScheduler { h in
            let center = NotificationCenter()
            var activations = 0
            let observers = h.scheduler.observeActivity(in: center,
                resigning: UIApplication.willResignActiveNotification,
                active: UIApplication.didBecomeActiveNotification,
                onActive: { activations += 1 })
            defer { observers.forEach(center.removeObserver) }
            h.foreground = false
            center.post(name: UIApplication.willResignActiveNotification, object: nil)
            // The process has no tick while away; the whole trip is shorter than ten seconds.
            h.now = h.due.addingTimeInterval(1)
            h.foreground = true
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(activations, 1, "Recovery uses the same production activation subscription")
            h.now = h.due.addingTimeInterval(2)
            XCTAssertNil(h.scheduler.tick())
            XCTAssertTrue(h.tasks.pending.isEmpty)
            XCTAssertTrue(h.sent.isEmpty)
            let delivery = DailyTask.Delivery(id: h.first.noticeID, date: h.now)
            XCTAssertTrue(h.tasks.shouldRemind(delivery, at: h.now, calendar: h.calendar))
            h.tasks.request(delivery, at: h.now, calendar: h.calendar)
            XCTAssertNotNil(h.scheduler.drain())
            XCTAssertEqual(h.sent.map(\.automatic), [false])
        }
    }

    func testLockedOrUnknownLockStateCannotQueueAnAutomaticRun() async throws {
        for lock in [true, nil] as [Bool?] {
            try withScheduler { h in
                h.locked = lock; h.now = h.due
                XCTAssertNil(h.scheduler.tick())
                XCTAssertTrue(h.tasks.pending.isEmpty)
                h.locked = false; h.now = h.due.addingTimeInterval(1)
                XCTAssertNil(h.scheduler.tick())
                XCTAssertTrue(h.sent.isEmpty)
            }
        }
    }

    func testBusyAtDueTimeLeavesTheOccurrenceForNotification() async throws {
        try withScheduler { h in
            h.ready = false; h.now = h.due
            XCTAssertNil(h.scheduler.tick())
            XCTAssertTrue(h.tasks.pending.isEmpty)
            h.ready = true; h.now = h.due.addingTimeInterval(1)
            XCTAssertNil(h.scheduler.tick())
            XCTAssertTrue(h.tasks.shouldRemind(.init(id: h.first.noticeID, date: h.now), at: h.now, calendar: h.calendar))
        }
    }

    func testTwoTasksDueTogetherQueueBeforeTheFirstMakesPokiBusy() async throws {
        try withScheduler { h in
            let second = DailyTask.Plan(prompt: "Read the build.", hour: 9, minute: 0)
            try h.tasks.save(second)
            h.now = h.due
            XCTAssertEqual(h.scheduler.tick()?.id, h.first.noticeID)
            XCTAssertEqual(h.tasks.pending.map(\.delivery.id), [second.noticeID])
            XCTAssertNil(h.scheduler.drain(), "The first task is still running")
            h.ready = true
            XCTAssertEqual(h.scheduler.drain()?.id, second.noticeID)
            XCTAssertEqual(h.sent.map(\.prompt), [h.first.prompt, second.prompt])
            XCTAssertEqual(h.sent.map(\.automatic), [true, true])
            XCTAssertTrue(h.tasks.pending.isEmpty)
        }
    }

    func testColdStartAndLongSuspensionDoNotBackfillAutomaticRuns() async throws {
        for cold in [false, true] {
            try withScheduler { h in
                if cold {
                    h.now = h.due.addingTimeInterval(1)
                    h.resetScheduler()
                    h.now = h.due.addingTimeInterval(2)
                } else { h.now = h.due.addingTimeInterval(15) }
                XCTAssertNil(h.scheduler.tick())
                XCTAssertTrue(h.tasks.pending.isEmpty)
                XCTAssertTrue(h.sent.isEmpty)
            }
        }
    }

    func testTappedRequestWaitsForForegroundAndReadinessWithoutBecomingAutomatic() async throws {
        try withScheduler { h in
            h.now = h.due; h.foreground = false
            h.tasks.request(.init(id: h.first.noticeID, date: h.now), at: h.now, calendar: h.calendar)
            XCTAssertNil(h.scheduler.drain())
            h.foreground = true; h.ready = false
            XCTAssertNil(h.scheduler.drain())
            XCTAssertEqual(h.tasks.pending.count, 1)
            h.ready = true
            XCTAssertNotNil(h.scheduler.drain())
            XCTAssertEqual(h.sent.map(\.automatic), [false])
        }
    }

    func testRestartingTheClockAfterAnIdlePeriodObservesTheNextCrossing() async throws {
        try withScheduler { h in
            h.now = h.due.addingTimeInterval(-60)
            h.resetScheduler()
            h.now = h.due.addingTimeInterval(-1)
            h.scheduler.resetClock()
            h.now = h.due
            XCTAssertNotNil(h.scheduler.tick())
        }
    }

    private func withScheduler(_ test: (Harness) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try test(Harness(file: folder.appendingPathComponent("tasks.json")))
    }

    @MainActor private final class Harness {
        let calendar: Calendar
        let due: Date
        var now: Date
        var foreground = true
        var locked: Bool? = false
        var ready = true
        let tasks: DailyTask
        let first = DailyTask.Plan(prompt: "Read the date.", hour: 9, minute: 0)
        var sent: [(prompt: String, automatic: Bool)] = []
        var scheduler: DailyTaskScheduler!

        init(file: URL) throws {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            self.calendar = calendar
            due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
            now = due.addingTimeInterval(-1)
            tasks = DailyTask(file: file)
            try tasks.save(first)
            resetScheduler()
        }

        func resetScheduler() {
            scheduler = DailyTaskScheduler(tasks: tasks, now: { [unowned self] in now }, calendar: { [unowned self] in calendar },
                foreground: { [unowned self] in foreground }, locked: { [unowned self] in locked }, ready: { [unowned self] in ready },
                submit: { [unowned self] in sent.append(($0, $1)); ready = false })
        }
    }
}
