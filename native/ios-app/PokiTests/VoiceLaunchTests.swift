import XCTest
@testable import Poki

@MainActor
final class VoiceLaunchTests: XCTestCase {
    func testRedeliveredIntentCannotReopenAnEndedTalk() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let hold = defaults.object(forKey: "pokiTalkHold")
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defaults.set("listening", forKey: "pokiTalkHold")
        defer {
            voice.stop()
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
            defaults.set(hold, forKey: "pokiTalkHold")
        }
        let start = AppLog.shared.lines.count
        let intent = TalkToPokiIntent()
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await intent.perform()
        await fulfillment(of: [listening], timeout: 8)

        voice.stop()
        _ = try await intent.perform()
        XCTAssertEqual(AppLog.shared.lines.dropFirst(start).filter { $0.contains("stage=receipt") }.count, 1,
                       "Redelivering the same intent must not issue another voice request after End")
        XCTAssertFalse(voice.isOn)

        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [restarted], timeout: 8)
        XCTAssertEqual(AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=started") }.count, 2)
        #endif
    }

    func testTalkToPokiRecordsTheStartedRequest() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let hold = defaults.object(forKey: "pokiTalkHold")
        let muted = voice.muted
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defaults.set("listening", forKey: "pokiTalkHold")
        defer {
            voice.stop()
            voice.muted = muted
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
            defaults.set(hold, forKey: "pokiTalkHold")
        }
        let start = AppLog.shared.lines.count
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [listening], timeout: 8)

        let log = AppLog.shared.lines.dropFirst(start)
        let started = try XCTUnwrap(log.first { line in
            line.contains("result=started") && line.range(of: #"request=[0-9A-Fa-f-]{36}"#, options: .regularExpression) != nil
        }, "The activity log must record the request that started the talk")
        let session = String(try XCTUnwrap(started.split(separator: " ").last))
        XCTAssertTrue(session.hasPrefix("session="))
        voice.muted = true
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=returned") }.count == 2
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        _ = try await TalkToPokiIntent(fromControl: true).perform()
        await fulfillment(of: [returned], timeout: 3)

        let returns = AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=returned") }
        XCTAssertTrue(returns.allSatisfy { $0.hasSuffix(session) })
        XCTAssertTrue(returns.contains { $0.contains("source=appShortcut") })
        XCTAssertTrue(returns.contains { $0.contains("source=control") })
        for outcome in returns {
            let request = try XCTUnwrap(field("request", in: outcome))
            XCTAssertEqual(stages(for: request).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        }
        XCTAssertEqual(AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=started") }.count, 1)
        XCTAssertTrue(voice.muted)
        XCTAssertTrue(voice.isOn)
        #endif
    }

    func testEndingATalkInvalidatesAQueuedRequestAndItsReplay() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defer {
            voice.stop()
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
        }
        await voice.start(microphone: false)
        XCTAssertTrue(voice.isOn)
        let entry = PokiEntry.shared
        let pending = PokiEntry.Request(id: UUID(), destination: .talk, issuedAt: .now, source: .appShortcut, epoch: entry.epoch)
        let invalidated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.contains { $0.contains("request=\(pending.id)") && $0.contains("result=invalidated reason=voiceEpochChanged") }
        }, object: nil)

        entry.ask(pending)
        voice.stop()
        await fulfillment(of: [invalidated], timeout: 3)

        let expired = PokiEntry.Request(id: UUID(), destination: .talk, issuedAt: Date.now.addingTimeInterval(-16),
                                        source: .appShortcut, epoch: entry.epoch)
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.contains { $0.contains("request=\(expired.id)") && $0.contains("result=shown reason=expired") }
        }, object: nil)
        entry.ask(pending)
        entry.ask(expired)
        await fulfillment(of: [shown], timeout: 3)

        let results = AppLog.shared.lines.filter { $0.contains("request=\(pending.id)") && $0.contains("result=") }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(stages(for: pending.id.uuidString).compactMap { field("stage", in: $0) }, ["receipt"])
        XCTAssertEqual(stages(for: expired.id.uuidString).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        XCTAssertFalse(voice.isOn)
        #endif
    }

    func testLaunchTimingFollowsOneRequestThroughRehearsal() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let hold = defaults.object(forKey: "pokiTalkHold")
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defaults.set("acting", forKey: "pokiTalkHold")
        defer {
            voice.stop()
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
            defaults.set(hold, forKey: "pokiTalkHold")
        }
        let start = AppLog.shared.lines.count
        let utterance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.dropFirst(start).contains { $0.contains("stage=firstUtterance") }
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [utterance], timeout: 12)

        let started = try XCTUnwrap(AppLog.shared.lines.dropFirst(start).first { $0.contains("result=started") })
        let request = try XCTUnwrap(field("request", in: started))
        let session = try XCTUnwrap(field("session", in: started))
        let timing = stages(for: request)
        XCTAssertEqual(timing.compactMap { field("stage", in: $0) }, ["receipt", "pageShown", "transportConnected", "firstUtterance"])
        XCTAssertEqual(timing.compactMap { field("session", in: $0) }, [session, session])
        let elapsed = timing.compactMap { field("elapsedMS", in: $0).flatMap(Int.init) }
        XCTAssertEqual(elapsed.count, 4)
        XCTAssertEqual(elapsed.first, 0)
        XCTAssertEqual(elapsed, elapsed.sorted())
        #endif
    }

    private func stages(for request: String) -> [String] {
        AppLog.shared.lines.filter { field("request", in: $0) == request && field("stage", in: $0) != nil }
    }

    private func field(_ name: String, in line: String) -> String? {
        let prefix = "\(name)="
        return line.split(separator: " ").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
