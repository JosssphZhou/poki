import os
import UIKit
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
        let mark = markLog()
        let intent = TalkToPokiIntent()
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await intent.perform()
        await fulfillment(of: [listening], timeout: 8)

        voice.stop()
        _ = try await intent.perform()
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("stage=receipt") }.count, 1,
                       "Redelivering the same intent must not issue another voice request after End")
        XCTAssertFalse(voice.isOn)

        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [restarted], timeout: 8)
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("result=started") }.count, 2)
        #endif
    }

    func testDelayedIntentAfterEndingTalkIsInvalidated() async throws {
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
        let mark = markLog()
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [listening], timeout: 8)

        let delayedShortcut = TalkToPokiIntent()
        let delayedControl = TalkToPokiIntent(fromControl: true)
        voice.stop()
        XCTAssertFalse(voice.isOn)

        let invalidated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).filter { $0.contains("result=invalidated reason=voiceEpochChanged") }.count == 2
        }, object: nil)
        _ = try await delayedShortcut.perform()
        _ = try await delayedControl.perform()
        await fulfillment(of: [invalidated], timeout: 3)

        let rejected = linesAfter(mark).filter { $0.contains("result=invalidated reason=voiceEpochChanged") }
        XCTAssertTrue(rejected.contains { $0.contains("source=appShortcut") })
        XCTAssertTrue(rejected.contains { $0.contains("source=control") })
        let rejectedIDs = Set(rejected.compactMap { field("request", in: $0) })
        XCTAssertEqual(rejectedIDs.count, 2)
        for request in rejectedIDs {
            XCTAssertEqual(stages(for: request).compactMap { field("stage", in: $0) }, ["receipt"])
        }
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("result=started") }.count, 1)
        XCTAssertFalse(voice.isOn)

        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [restarted], timeout: 8)
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("result=started") }.count, 2)
        #endif
    }

    func testDelayedIntentPastWindowOnlyShowsChat() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let hold = defaults.object(forKey: "pokiTalkHold")
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))
        let savedNow = PokiEntry.now
        PokiEntry.now = { clock.withLock { $0 } }
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defaults.set("listening", forKey: "pokiTalkHold")
        defer {
            PokiEntry.now = savedNow
            voice.stop()
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
            defaults.set(hold, forKey: "pokiTalkHold")
        }
        voice.stop()
        XCTAssertFalse(voice.isOn)
        let mark = markLog()
        let staleIntent = TalkToPokiIntent()
        clock.withLock { $0 = $0.addingTimeInterval(16) }

        let expired = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).contains { $0.contains("result=shown reason=expired") }
        }, object: nil)
        _ = try await staleIntent.perform()
        await fulfillment(of: [expired], timeout: 3)

        let outcome = try XCTUnwrap(linesAfter(mark).first { $0.contains("result=shown reason=expired") })
        let request = try XCTUnwrap(field("request", in: outcome))
        XCTAssertEqual(stages(for: request).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("result=started") }.count, 0)
        XCTAssertFalse(voice.isOn)
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
        let mark = markLog()
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [listening], timeout: 8)

        let log = linesAfter(mark)
        let started = try XCTUnwrap(log.first { line in
            line.contains("result=started") && line.range(of: #"request=[0-9A-Fa-f-]{36}"#, options: .regularExpression) != nil
        }, "The activity log must record the request that started the talk")
        let session = String(try XCTUnwrap(started.split(separator: " ").last))
        XCTAssertTrue(session.hasPrefix("session="))
        voice.muted = true
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).filter { $0.contains("result=returned") }.count == 2
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        _ = try await TalkToPokiIntent(fromControl: true).perform()
        await fulfillment(of: [returned], timeout: 3)

        let returns = linesAfter(mark).filter { $0.contains("result=returned") }
        XCTAssertTrue(returns.allSatisfy { $0.hasSuffix(session) })
        XCTAssertTrue(returns.contains { $0.contains("source=appShortcut") })
        XCTAssertTrue(returns.contains { $0.contains("source=control") })
        for outcome in returns {
            let request = try XCTUnwrap(field("request", in: outcome))
            XCTAssertEqual(stages(for: request).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        }
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("result=started") }.count, 1)
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
        let mark = markLog()
        let utterance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).contains { $0.contains("stage=firstUtterance") }
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [utterance], timeout: 12)

        let started = try XCTUnwrap(linesAfter(mark).first { $0.contains("result=started") })
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

    func testPokiVoiceLinkAndUnconfiguredTalkRecordShownAndBlocked() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let savedRehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let savedBridge = VoiceBridge.saved
        let savedKeyAsked = voice.keyAsked
        defaults.removeObject(forKey: "pokiTalkRehearsal")
        voice.removeBridge()
        voice.stop()
        voice.keyAsked = false
        defer {
            voice.stop()
            voice.keyAsked = savedKeyAsked
            VoiceBridge.saved = savedBridge
            defaults.set(savedRehearsal, forKey: "pokiTalkRehearsal")
        }
        try XCTSkipIf(voice.canTalkLive, "Requires an unconfigured simulator without real voice credentials")

        let linkMark = markLog()
        let linkShown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(linkMark).contains { $0.contains("source=link result=shown reason=link") }
        }, object: nil)
        let opened = await UIApplication.shared.open(try XCTUnwrap(URL(string: "poki://voice")))
        XCTAssertTrue(opened)
        await fulfillment(of: [linkShown], timeout: 5)

        let linkLines = linesAfter(linkMark)
        XCTAssertTrue(linkLines.contains { $0.contains("[app] opened by link poki://voice") })
        let linkOutcome = try XCTUnwrap(linkLines.first { $0.contains("source=link result=shown reason=link") })
        let linkRequest = try XCTUnwrap(field("request", in: linkOutcome))
        XCTAssertEqual(stages(for: linkRequest).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        XCTAssertFalse(voice.isOn)

        let blockedMark = markLog()
        let blocked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(blockedMark).contains { $0.contains("source=appShortcut result=blocked reason=voiceNotConfigured") }
        }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [blocked], timeout: 5)

        let blockedOutcome = try XCTUnwrap(linesAfter(blockedMark).first {
            $0.contains("source=appShortcut result=blocked reason=voiceNotConfigured")
        })
        let blockedRequest = try XCTUnwrap(field("request", in: blockedOutcome))
        XCTAssertEqual(stages(for: blockedRequest).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        XCTAssertFalse(voice.isOn)
        #endif
    }

    func testBusyTaskBlocksTalkToPokiWithoutStartingMicrophone() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let savedRehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let savedDelegatedBusy = ChatModel.delegatedBusy
        defaults.set("1", forKey: "pokiTalkRehearsal")
        voice.stop()
        ChatModel.delegatedBusy = "External Agent"
        defer {
            ChatModel.delegatedBusy = savedDelegatedBusy
            voice.stop()
            defaults.set(savedRehearsal, forKey: "pokiTalkRehearsal")
        }

        let mark = markLog()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).contains {
                $0.contains("result=blocked reason=taskRunning") || $0.contains("result=started")
            }
        }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [settled], timeout: 5)

        let added = linesAfter(mark)
        let blockedOutcome = try XCTUnwrap(added.first { $0.contains("source=appShortcut result=blocked reason=taskRunning") })
        let blockedRequest = try XCTUnwrap(field("request", in: blockedOutcome))
        XCTAssertEqual(stages(for: blockedRequest).compactMap { field("stage", in: $0) }, ["receipt", "pageShown"])
        XCTAssertFalse(added.contains { $0.contains("result=started") })
        XCTAssertFalse(voice.isOn)
        #endif
    }

    private func markLog() -> String {
        let marker = "voice-launch-test-\(UUID().uuidString)"
        AppLog.shared.add("test", marker)
        return marker
    }

    private func linesAfter(_ marker: String) -> [String] {
        let lines = AppLog.shared.lines
        guard let index = lines.lastIndex(where: { $0.contains(marker) }) else { return [] }
        return Array(lines.dropFirst(index + 1))
    }

    private func stages(for request: String) -> [String] {
        AppLog.shared.lines.filter { field("request", in: $0) == request && field("stage", in: $0) != nil }
    }

    private func field(_ name: String, in line: String) -> String? {
        let prefix = "\(name)="
        return line.split(separator: " ").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
