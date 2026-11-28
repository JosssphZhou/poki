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
        XCTAssertEqual(timingLinesAfter(mark).filter { field("event", in: $0) == "launch_receipt" }.count, 1,
                       "Redelivering the same intent must not issue another voice request after End")
        XCTAssertFalse(voice.isOn)

        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [restarted], timeout: 8)
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=started") }.count, 2)
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
            XCTAssertEqual(stages(for: request).compactMap { field("event", in: $0) }, ["launch_receipt"])
            let timingOutcome = try XCTUnwrap(outcomeTiming(for: request))
            XCTAssertEqual(field("session", in: timingOutcome), "none")
            XCTAssertEqual(field("flow", in: timingOutcome), "voice")
            XCTAssertEqual(field("turn", in: timingOutcome), "0")
            XCTAssertEqual(field("result", in: timingOutcome), "invalidated")
            XCTAssertEqual(field("reason", in: timingOutcome), "voice_epoch_changed")
        }
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=started") }.count, 1)
        XCTAssertFalse(voice.isOn)

        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)
        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [restarted], timeout: 8)
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=started") }.count, 2)
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
        XCTAssertEqual(stages(for: request).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
        let timingOutcome = try XCTUnwrap(outcomeTiming(for: request))
        XCTAssertEqual(field("session", in: timingOutcome), "none")
        XCTAssertEqual(field("result", in: timingOutcome), "shown")
        XCTAssertEqual(field("reason", in: timingOutcome), "expired")
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=started") }.count, 0)
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
            line.contains("launch request=") && line.contains("result=started") && line.range(of: #"request=[0-9A-Fa-f-]{36}"#, options: .regularExpression) != nil
        }, "The activity log must record the request that started the talk")
        let session = try XCTUnwrap(field("session", in: started))
        voice.muted = true
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=returned") }.count == 2
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        _ = try await TalkToPokiIntent(fromControl: true).perform()
        await fulfillment(of: [returned], timeout: 3)

        let returns = linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=returned") }
        XCTAssertTrue(returns.allSatisfy { field("session", in: $0) == session })
        XCTAssertTrue(returns.contains { $0.contains("source=appShortcut") })
        XCTAssertTrue(returns.contains { $0.contains("source=control") })
        for outcome in returns {
            let request = try XCTUnwrap(field("request", in: outcome))
            XCTAssertEqual(stages(for: request).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
            let timingOutcome = try XCTUnwrap(outcomeTiming(for: request))
            XCTAssertEqual(field("session", in: timingOutcome), session)
            XCTAssertEqual(field("result", in: timingOutcome), "returned")
            XCTAssertEqual(field("reason", in: timingOutcome), "active_talk")
        }
        XCTAssertEqual(linesAfter(mark).filter { $0.contains("launch request=") && $0.contains("result=started") }.count, 1)
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

        let results = AppLog.shared.lines.filter { $0.contains("launch request=\(pending.id)") && $0.contains("result=") }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(stages(for: pending.id.uuidString).compactMap { field("event", in: $0) }, ["launch_receipt"])
        XCTAssertEqual(stages(for: expired.id.uuidString).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
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
            self.timingLinesAfter(mark).contains { self.field("event", in: $0) == "launch_first_utterance" }
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [utterance], timeout: 12)

        let started = try XCTUnwrap(linesAfter(mark).first { $0.contains("launch request=") && $0.contains("result=started") })
        let request = try XCTUnwrap(field("request", in: started))
        let session = try XCTUnwrap(field("session", in: started))
        let timing = stages(for: request)
        XCTAssertEqual(timing.compactMap { field("event", in: $0) }, [
            "launch_receipt",
            "launch_page_shown",
            "launch_transport_connected",
            "launch_first_utterance",
        ])
        XCTAssertEqual(timing.compactMap { field("session", in: $0) }, ["none", "none", session, session])
        XCTAssertTrue(timing.allSatisfy {
            field("flow", in: $0) == "voice" && field("turn", in: $0) == "0" && field("source", in: $0) == "app_shortcut"
        })
        let timestamps = timing.compactMap { field("t_ms", in: $0).flatMap(UInt64.init) }
        let elapsed = timing.compactMap { field("since_receipt_ms", in: $0).flatMap(Int.init) }
        XCTAssertEqual(timestamps.count, 4)
        XCTAssertEqual(timestamps, timestamps.sorted())
        XCTAssertEqual(elapsed.count, 4)
        XCTAssertEqual(elapsed.first, 0)
        XCTAssertEqual(elapsed, elapsed.sorted())
        let baseTimestamp = try XCTUnwrap(timestamps.first)
        XCTAssertEqual(elapsed, timestamps.map { Int($0 - baseTimestamp) })
        let timingOutcome = try XCTUnwrap(outcomeTiming(for: request))
        XCTAssertEqual(field("session", in: timingOutcome), session)
        XCTAssertEqual(field("result", in: timingOutcome), "started")
        XCTAssertEqual(field("reason", in: timingOutcome), "new_talk")
        XCTAssertFalse(linesAfter(mark).contains { $0.contains("request=\(request)") && $0.contains("stage=") })
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
        XCTAssertEqual(stages(for: linkRequest).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
        let linkTimingOutcome = try XCTUnwrap(outcomeTiming(for: linkRequest))
        XCTAssertEqual(field("source", in: linkTimingOutcome), "link")
        XCTAssertEqual(field("result", in: linkTimingOutcome), "shown")
        XCTAssertEqual(field("reason", in: linkTimingOutcome), "link")
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
        XCTAssertEqual(stages(for: blockedRequest).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
        let blockedTimingOutcome = try XCTUnwrap(outcomeTiming(for: blockedRequest))
        XCTAssertEqual(field("result", in: blockedTimingOutcome), "blocked")
        XCTAssertEqual(field("reason", in: blockedTimingOutcome), "voice_not_configured")
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
        XCTAssertEqual(stages(for: blockedRequest).compactMap { field("event", in: $0) }, ["launch_receipt", "launch_page_shown"])
        let blockedTimingOutcome = try XCTUnwrap(outcomeTiming(for: blockedRequest))
        XCTAssertEqual(field("result", in: blockedTimingOutcome), "blocked")
        XCTAssertEqual(field("reason", in: blockedTimingOutcome), "task_running")
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

    private func timingLinesAfter(_ marker: String) -> [String] {
        linesAfter(marker).filter { $0.contains("[voice-timing]") }
    }

    private func stages(for request: String) -> [String] {
        let stageEvents: Set<String> = [
            "launch_receipt",
            "launch_page_shown",
            "launch_transport_connected",
            "launch_input_ready",
            "launch_first_utterance",
        ]
        return AppLog.shared.lines.filter {
            $0.contains("[voice-timing]")
                && field("request_id", in: $0) == request
                && field("event", in: $0).map(stageEvents.contains) == true
        }
    }

    private func outcomeTiming(for request: String) -> String? {
        AppLog.shared.lines.last {
            $0.contains("[voice-timing]")
                && field("request_id", in: $0) == request
                && field("event", in: $0) == "launch_outcome"
        }
    }

    private func field(_ name: String, in line: String) -> String? {
        let prefix = "\(name)="
        return line.split(separator: " ").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
