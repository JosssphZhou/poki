import Foundation
import XCTest
@testable import PokiCore

/// What the model gets to decide the usual music app from: the owner's own uses of each music app in
/// the past week, and only apps used at least three times.
final class ScreenHabitTests: XCTestCase {
    static let netease = "com.netease.cloudmusic"
    static let appleMusic = "com.apple.Music"
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2026-11-18 20:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_032_000)

    /// One use of `app`: a few reads a minute apart, `daysAgo` days before `now` at `hour` UTC.
    static func use(_ app: String, daysAgo: Int, hour: Int, reads: Int = 3) -> [ScreenHabitRawObservation] {
        let day = utc.startOfDay(for: now).addingTimeInterval(Double(-daysAgo) * 86_400)
        let start = day.addingTimeInterval(Double(hour) * 3600)
        return (0..<reads).map { ScreenHabitRawObservation(at: start.addingTimeInterval(Double($0) * 60), bundleID: app) }
    }

    static func usages(_ rows: [ScreenHabitRawObservation], spans: [AgentAppSpan] = [], watermark: Date? = nil,
                       keeps: @escaping (String) -> Bool = { _ in true }) -> [MusicAppUsage] {
        MusicUsageSummary.usages(observations: rows, agentSpans: spans, watermarkAt: watermark, keepsApp: keeps, now: now)
    }

    func testAHundredReadsOfOnePageAreOneUse() {
        let rows = Self.use(Self.netease, daysAgo: 1, hour: 10, reads: 100)
        XCTAssertEqual(Self.usages(rows).first?.uses.count, 1)
    }

    func testThreeUsesInAWeekAreOfferedWithTheirDaysAndTimes() {
        let rows = Self.use(Self.netease, daysAgo: 3, hour: 21) + Self.use(Self.netease, daysAgo: 2, hour: 21) + Self.use(Self.netease, daysAgo: 1, hour: 9)
        let offered = MusicUsageSummary.candidates(Self.usages(rows))
        XCTAssertEqual(offered.map(\.bundleID), [Self.netease])
        let text = MusicUsageSummary.text(offered, name: { _ in "NetEase Cloud Music" }, now: Self.now, calendar: Self.utc)
        XCTAssertTrue(text.contains("3 uses on 3 days: 2026-11-15 (Sun) ×1, 2026-11-16 (Mon) ×1, 2026-11-17 (Tue) ×1. Times of day: morning 1, evening 2."), text)
    }

    func testFewerThanThreeUsesInAWeekAreNotOffered() {
        let old = (8...12).flatMap { Self.use(Self.netease, daysAgo: $0, hour: 21) }
        let rows = old + Self.use(Self.netease, daysAgo: 2, hour: 21) + Self.use(Self.netease, daysAgo: 1, hour: 21)
        XCTAssertEqual(Self.usages(rows).first?.uses.count, 2, "uses older than a week are left out")
        XCTAssertTrue(MusicUsageSummary.candidates(Self.usages(rows)).isEmpty)
    }

    func testPokisOwnLaunchesAreNotTheOwnersUses() {
        var rows: [ScreenHabitRawObservation] = []
        var spans: [AgentAppSpan] = []
        for i in 0..<20 {
            let use = Self.use(Self.netease, daysAgo: i % 3, hour: 6 + i / 3 * 2)
            rows += use
            spans.append(AgentAppSpan(bundleID: Self.netease, startAt: use[0].at.addingTimeInterval(-5), endAt: use[use.count - 1].at.addingTimeInterval(90)))
        }
        XCTAssertTrue(Self.usages(rows, spans: spans).isEmpty)
        XCTAssertEqual(Self.usages(rows).first?.uses.count, 20, "the same reads without the spans")
    }

    func testUsesBeforeTheOwnerSaidForgetAreLeftOut() {
        let rows = Self.use(Self.netease, daysAgo: 2, hour: 9) + Self.use(Self.netease, daysAgo: 0, hour: 9)
        XCTAssertEqual(Self.usages(rows, watermark: Self.now.addingTimeInterval(-86_400)).first?.uses.count, 1)
    }

    func testAnAppLeftOutOfScreenHistoryIsLeftOut() {
        let rows = Self.use(Self.netease, daysAgo: 1, hour: 9) + Self.use(Self.appleMusic, daysAgo: 1, hour: 13)
        XCTAssertEqual(Self.usages(rows, keeps: { $0 != Self.appleMusic }).map(\.bundleID), [Self.netease])
    }

    func testOnlyAnAppFromTheSummaryIsTakenFromTheModel() throws {
        let usages = Self.usages(Self.use(Self.netease, daysAgo: 1, hour: 9))
        let taken = try XCTUnwrap(MusicHabitJudgment.parse(#"{"habit": true, "bundle_id": "com.netease.cloudmusic", "evidence": "用了一次"}"#, offered: usages, now: Self.now))
        XCTAssertEqual(taken?.bundleID, Self.netease)
        XCTAssertEqual(taken?.evidence, "用了一次")
        XCTAssertNil(MusicHabitJudgment.parse(#"{"habit": true, "bundle_id": "com.spotify.client"}"#, offered: usages), "not in the summary")
        XCTAssertEqual(MusicHabitJudgment.parse(#"{"habit": false}"#, offered: usages), .some(nil))
        XCTAssertNil(MusicHabitJudgment.parse("I think so", offered: usages))
    }
}
