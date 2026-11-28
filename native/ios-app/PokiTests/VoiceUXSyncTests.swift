import ActivityKit
import Foundation
import PokiCore
import Security
import XCTest
@testable import Poki

@MainActor
private final class SyncFakeCodexVoice: SubscriptionVoice {
    private var onEvent: ((String, [String: Any]) -> Void)?
    private var onTool: ((String, String) async -> PhoneAnswer)?

    func prepare(onEvent: @escaping (String, [String: Any]) -> Void,
                 onTool: @escaping (String, String) async -> PhoneAnswer) async throws {
        self.onEvent = onEvent
        self.onTool = onTool
    }

    func start(offer: String) async throws -> String { "fixture-sdp-answer" }
    func stop() { onEvent = nil; onTool = nil }
    func notify(_ method: String, _ params: [String: Any]) { onEvent?(method, params) }
    func callTool(_ name: String, _ arguments: String) async -> PhoneAnswer? { await onTool?(name, arguments) }
}

@MainActor
final class VoiceUXSyncTests: XCTestCase {
    private var storage: IsolatedTestStorage!
    private var savedLanguage = AppLocalization.system

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        URLProtocol.registerClass(BridgeStub.self)
        storage = try IsolatedTestStorage()
    }

    override func tearDownWithError() throws {
        AppLocalization.shared.preference = savedLanguage
        URLProtocol.unregisterClass(BridgeStub.self)
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
        try super.tearDownWithError()
    }

    private func makeChatGPTStorage() throws -> IsolatedTestStorage {
        let isolated = try IsolatedTestStorage(prefix: "voice-ux-sync")
        VoiceDirect.setEnabled(false, in: isolated.storage)
        try isolated.seedCodexCredential(
            accessToken: "fixture-codex-voice-ux-sync",
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
        ModelKeys.setSelectedProvider(.chatgpt, in: isolated.storage)
        return isolated
    }

    private func makeVoice(
        time: FakeTime,
        codex: (any SubscriptionVoice)? = nil,
        storage: PokiStorage? = nil,
        phoneTool: @escaping @MainActor (String, String) async -> PhoneAnswer = { _, _ in ("app: WeChat\nok", false, nil) }
    ) -> (voice: VoiceModel, link: () -> FakeConnection) {
        var links: [FakeConnection] = []
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, arguments, cancellation in
                await PhoneOperationCancellation.$current.withValue(cancellation) { await phoneTool(name, arguments) }
            },
            holdMicrophone: { _ in },
            readyCue: {},
            connection: { onEvent, onClosed in
                let link = FakeConnection()
                link.onEvent = onEvent
                link.onClosed = onClosed
                links.append(link)
                return link
            },
            time: time.clock,
            codex: codex,
            storage: storage ?? self.storage.storage
        )
        _ = voice.setBridge(BridgeStub.address)
        voice.onConversationEnded = { _, _ in }
        return (voice, { links.last! })
    }

    // MARK: - Bug 1: Dynamic Island / Live Activity immediate reset on voice follow-up

    func testLiveSpeechStartClearsFinishedActivityBeforeNextBackendEvent() async throws {
        let clock = FakeTime()
        let activity = ActivityController()
        activity.foldAfter = .seconds(30)
        let (voice, currentLink) = makeVoice(time: clock) { _, _ in
            activity.update { $0.phase = .working; $0.headline = "Check Settings" }
            activity.record(step: "Check Settings", ok: true)
            return ("app: Settings\nChecked Settings", false, nil)
        }
        let watcher = TalkActivity(voice: voice, activity: activity, deviceName: { "Test iPhone" }, keepsActivity: { false })
        defer {
            voice.stop()
            activity.end(dismissalPolicy: .immediate)
            withExtendedLifetime(watcher) {}
        }
        _ = voice.setBridge(BridgeStub.liveAddress)
        await voice.start()
        let link = currentLink()
        link.play(["type": "session.started"],
                  ["type": "session.input_transcript.delta", "delta": "Check Settings", "start_ms": 0, "end_ms": 400],
                  ["type": "session.delegation.created", "delegation": ["id": "d1"]])
        link.call("check-settings", "look")
        await clock.settle()
        link.backend("response.created", ["response": ["id": "reply-1"]])
        link.play(["type": "session.output_transcript.delta", "delta": "Settings checked."])
        link.backend("response.completed", ["response": ["id": "reply-1"]])
        link.remoteSpeech = true
        await clock.advance(0.2)
        link.remoteSpeech = false
        for _ in 0..<3 { await clock.advance(0.2) }
        await clock.settle()

        XCTAssertEqual(voice.phase, .listening)
        XCTAssertFalse(voice.midTurn)
        XCTAssertEqual(activity.state.phase, .done)
        XCTAssertEqual(activity.state.face.compact, .symbol("checkmark", .accent))
        print("Live follow-up before: voice=\(voice.phase), midTurn=\(voice.midTurn), activity=\(activity.state.phase)")

        link.play(["type": "input_audio_buffer.speech_started", "event_id": "follow-up-1", "item_id": "user-2"])
        await clock.settle()

        print("Live follow-up after speech_started only: voice=\(voice.phase), midTurn=\(voice.midTurn), activity=\(activity.state.phase)")
        XCTAssertEqual(activity.state.phase, .idle, "Speech start must clear the previous outcome before the next backend event")
        XCTAssertEqual(activity.state.face.compact, .symbol("waveform", .accent))
        XCTAssertNil(activity.state.result)
        XCTAssertEqual(activity.state.stepCount, 0)

        activity.update { $0.phase = .working; $0.headline = "Current step" }
        activity.record(step: "Current step", ok: true)
        link.play(["type": "input_audio_buffer.speech_started", "event_id": "follow-up-2", "item_id": "user-3"])
        await clock.settle()
        XCTAssertEqual(activity.state.phase, .working)
        XCTAssertEqual(activity.state.stepCount, 1)
    }

    func testFollowUpVoiceTurnImmediatelyClearsPreviousDoneOutcomeOnLiveActivity() async throws {
        let chatGPT = try makeChatGPTStorage()
        defer { try? chatGPT.tearDown() }
        let clock = FakeTime()
        let codex = SyncFakeCodexVoice()
        let (voice, currentLink) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage)
        let activity = ActivityController()
        activity.foldAfter = .seconds(30)
        let watcher = TalkActivity(voice: voice, activity: activity, deviceName: { "Test iPhone" }, keepsActivity: { false })
        defer {
            voice.stop()
            activity.end(dismissalPolicy: .immediate)
            withExtendedLifetime(watcher) {}
        }

        await voice.start()
        await clock.settle()
        let link = currentLink()

        // Round 1 finishes a phone task and leaves Live Activity in .done with checkmark.
        codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "查高铁并发微信"])
        codex.notify("poki/backend/turnStarted", [:])
        activity.update { $0.phase = .working; $0.headline = "Open WeChat" }
        activity.record(step: "Open WeChat", ok: true)
        codex.notify("poki/backend/turnCompleted", ["status": "completed"])
        codex.notify("thread/realtime/transcript/done", ["role": "assistant", "text": "已将高铁行程发给文件传输助手。"])
        link.remoteSpeech = true
        await clock.advance(0.2)
        link.remoteSpeech = false
        for _ in 0..<3 { await clock.advance(0.2) }
        await clock.settle()

        XCTAssertEqual(activity.state.phase, .done, "Finished voice round must show .done before follow-up starts")
        XCTAssertEqual(activity.state.face.compact, .symbol("checkmark", .accent))

        // Follow-up begins immediately while .done is still visible (far before 30s foldAfter).
        codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": "把出门时间也同步过去"])
        await clock.settle()

        XCTAssertEqual(activity.state.phase, .idle, "Starting a follow-up voice turn must clear previous .done immediately")
        XCTAssertEqual(activity.state.stepCount, 0, "Previous turn's step count must reset when clearing .done")
        XCTAssertNil(activity.state.result, "Previous turn's result must clear for the new voice turn")
        XCTAssertEqual(activity.state.face.content, StatusWord.listening.text)
        XCTAssertEqual(activity.state.face.compact, .symbol("waveform", .accent))
        XCTAssertTrue(activity.state.face.endsTalk)

        // Complete a second round, then start follow-up directly via handoff_request (.thinking).
        codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "把出门时间也同步过去"])
        codex.notify("poki/backend/turnStarted", [:])
        activity.update { $0.phase = .working; $0.headline = "Send WeChat" }
        activity.record(step: "Send WeChat", ok: true)
        codex.notify("poki/backend/turnCompleted", ["status": "completed"])
        codex.notify("thread/realtime/transcript/done", ["role": "assistant", "text": "出门时间已同步。"])
        await clock.settle()
        XCTAssertEqual(activity.state.phase, .done)

        codex.notify("thread/realtime/itemAdded", ["item": ["type": "handoff_request"]])
        await clock.settle()
        XCTAssertEqual(activity.state.phase, .idle, "Entering thinking for a new turn must immediately clear .done")
        XCTAssertEqual(activity.state.voice, .thinking)
        XCTAssertEqual(activity.state.face.content, StatusWord.thinking.text)
        XCTAssertEqual(activity.state.face.compact, .symbol("waveform", .accent))
    }

    func testActivityFacePrefersActiveVoiceTurnOverStaleDoneWhilePreservingNormalDone() {
        // Non-voice chat completion keeps Lock Screen / island .done result intact.
        var chatDone = PokiState(phase: .done, headline: "Finished", thumbnailVersion: 0)
        chatDone.result = "Sent message in WeChat"
        XCTAssertEqual(chatDone.face.content, "Sent message in WeChat")
        XCTAssertEqual(chatDone.face.compact, .symbol("checkmark", .accent))
        XCTAssertFalse(chatDone.face.endsTalk)

        // Finished voice turn while idle-listening keeps .done summary visible.
        var voiceDone = chatDone
        voiceDone.voice = .listening
        XCTAssertEqual(voiceDone.face.content, "Sent message in WeChat")
        XCTAssertEqual(voiceDone.face.compact, .symbol("checkmark", .accent))

        // Active follow-up voice states (.thinking / .speaking) must never stay stuck on stale .done.
        var staleThinking = chatDone
        staleThinking.voice = .thinking
        XCTAssertEqual(staleThinking.face.content, StatusWord.thinking.text)
        XCTAssertEqual(staleThinking.face.compact, .symbol("waveform", .accent))
        XCTAssertTrue(staleThinking.face.endsTalk)

        var staleSpeaking = chatDone
        staleSpeaking.voice = .speaking
        XCTAssertEqual(staleSpeaking.face.content, StatusWord.speaking.text)
        XCTAssertEqual(staleSpeaking.face.compact, .symbol("waveform", .accent))
        XCTAssertTrue(staleSpeaking.face.endsTalk)
    }

    // MARK: - Bug 2: Multi-step long-silence factual progress sync

    func testPriorTurnToolsDoNotTriggerOrCountTowardCurrentProgress() async throws {
        for oldFinishesFirst in [false, true] {
            let chatGPT = try makeChatGPTStorage()
            defer { try? chatGPT.tearDown() }
            let clock = FakeTime()
            let codex = SyncFakeCodexVoice()
            var finishOld: CheckedContinuation<PhoneAnswer, Never>?
            let (voice, _) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage) { _, arguments in
                if arguments == #"{"turn":"old"}"# {
                    return await withCheckedContinuation { finishOld = $0 }
                }
                return ("app: Settings\nChecked current step", false, nil)
            }
            defer { voice.stop() }
            await voice.start()
            codex.notify("poki/backend/turnStarted", [:])
            let old = Task { await codex.callTool("look", #"{"turn":"old"}"#) }
            await clock.settle()
            let release = try XCTUnwrap(finishOld, "Previous turn's tool must actually be suspended")
            var released = false
            defer {
                if !released { release.resume(returning: ("app: OldApp\nOld step", false, nil)) }
                old.cancel()
            }

            codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "Check Settings instead"])
            codex.notify("poki/backend/turnStarted", [:])
            await clock.advance(22)

            if oldFinishesFirst {
                release.resume(returning: ("app: OldApp\nOld step", false, nil))
                released = true
                let returnedOld = await old.value
                let oldAnswer = try XCTUnwrap(returnedOld)
                XCTAssertFalse(oldAnswer.text.contains("[Poki progress sync]"))
            }
            let first = await codex.callTool("look", #"{"step":1}"#)
            let firstAnswer = try XCTUnwrap(first)
            XCTAssertFalse(firstAnswer.text.contains("[Poki progress sync]"),
                           "A prior turn's result cannot count as the first current step")
            let second = await codex.callTool("look", #"{"step":2}"#)
            let secondAnswer = try XCTUnwrap(second)

            if oldFinishesFirst {
                XCTAssertTrue(secondAnswer.text.hasPrefix("[Poki progress sync]"),
                              "Two current steps with no pending tools must report progress")
            } else {
                XCTAssertFalse(secondAnswer.text.contains("[Poki progress sync]"),
                               "An old tool is still running when the current turn finishes two steps")
                release.resume(returning: ("app: OldApp\nOld step", false, nil))
                released = true
                let returnedOld = await old.value
                let oldAnswer = try XCTUnwrap(returnedOld)
                XCTAssertFalse(oldAnswer.text.contains("[Poki progress sync]"),
                               "An old result must not describe a current progress milestone")
                let third = await codex.callTool("look", #"{"step":3}"#)
                XCTAssertTrue(try XCTUnwrap(third).text.hasPrefix("[Poki progress sync]"),
                              "Current progress becomes eligible once every older tool has finished")
            }
        }
    }

    func testMultiStepLiveAndCodexOperationsEmitFactualProgressUpdateAfterSilenceInterval() async throws {
        // 1. OpenAI Live path: single quick step stays silent, multi-step across silence threshold sends factual commentary.
        do {
            let clock = FakeTime()
            let (voice, currentLink) = makeVoice(time: clock) { name, arguments in
                if name == "open_app" { return ("app: 12306\nOpened 12306", false, nil) }
                if arguments.contains("WeChat") { return ("app: WeChat\nMessage sent to File Transfer", false, nil) }
                return ("app: Amap\nRoute loaded", false, nil)
            }
            defer { voice.stop() }
            _ = voice.setBridge(BridgeStub.liveAddress)
            await voice.start()
            let link = currentLink()
            link.play(["type": "session.started"])
            link.play(["type": "session.input_transcript.delta", "delta": "查高铁发微信再查高德", "start_ms": 0, "end_ms": 400],
                      ["type": "session.delegation.created", "delegation": ["id": "d1"]])

            // Step 1 at t=0: single step must NOT emit mid-task progress commentary.
            link.call("s1", "open_app", arguments: #"{"app":"12306"}"#)
            await clock.settle()
            let initialCommentary = link.sent.filter { $0["type"] as? String == "session.commentary.append" }
            XCTAssertTrue(initialCommentary.isEmpty, "Single quick step must not emit mid-task progress commentary")

            // Step 2 completes after 22s of silence -> must emit one factual progress commentary.
            await clock.advance(22)
            link.call("s2", "do", arguments: #"{"actions":[{"tap":1,"note":"WeChat"}]}"#)
            await clock.settle()
            let afterLongSilence = link.sent.filter { $0["type"] as? String == "session.commentary.append" }
            XCTAssertEqual(afterLongSilence.count, 1, "Crossing the silence threshold after a confirmed step must emit one progress commentary")
            let content = try XCTUnwrap(afterLongSilence.first?["content"] as? String)
            XCTAssertTrue(content.contains("WeChat"), "Progress update must ground in the confirmed step/app: \(content)")
            XCTAssertTrue(content.localizedCaseInsensitiveContains("still in progress") || content.localizedCaseInsensitiveContains("do not claim"),
                          "Progress update must explicitly avoid claiming the whole task is finished: \(content)")

            // Step 3 right after (3s later) must respect cooldown and not spam commentary.
            await clock.advance(3)
            link.call("s3", "look", arguments: "{}")
            await clock.settle()
            XCTAssertEqual(link.sent.filter { $0["type"] as? String == "session.commentary.append" }.count, 1,
                           "Cooldown must prevent consecutive progress updates within the silence interval")
        }

        // 2. ChatGPT / Codex path: long multi-step returns factual progress sync directive at the top of tool output.
        do {
            let chatGPT = try makeChatGPTStorage()
            defer { try? chatGPT.tearDown() }
            let clock = FakeTime()
            let codex = SyncFakeCodexVoice()
            let (voice, _) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage) { name, _ in
                if name == "open_app" { return ("app: 12306\nOpened 12306", false, nil) }
                // Simulate a large UI dump (>6000 chars) to verify progress sync is never truncated by prefix(6000).
                let largeDump = "app: WeChat\nMessage sent\n" + String(repeating: "1 Button Item\n", count: 500)
                return (largeDump, false, nil)
            }
            defer { voice.stop() }
            await voice.start()
            await clock.settle()

            codex.notify("poki/backend/turnStarted", [:])
            let firstResult = await codex.callTool("open_app", #"{"app":"12306"}"#)
            let first = try XCTUnwrap(firstResult)
            XCTAssertFalse(first.text.contains("progress sync"), "First step must not inject progress sync")

            await clock.advance(22)
            let secondResult = await codex.callTool("do", #"{"actions":[{"tap":5}]}"#)
            let second = try XCTUnwrap(secondResult)
            let head = String(second.text.prefix(400))
            XCTAssertTrue(head.contains("[Poki progress sync]"), "Codex multi-step silence must prepend progress sync before 6000-char truncation: \(head)")
            XCTAssertTrue(head.contains("WeChat"), "Progress sync must reference the confirmed app: \(head)")
        }

        // 3. Standard Realtime path: emits a factual progress sync system note after silence threshold.
        do {
            let clock = FakeTime()
            let (voice, currentLink) = makeVoice(time: clock) { name, _ in
                name == "look" ? ("app: 12306\nOpened", false, nil) : ("app: WeChat\nSent", false, nil)
            }
            defer { voice.stop() }
            await voice.start()
            let link = currentLink()
            link.play(["type": "session.created"])
            link.play(["type": "input_audio_buffer.speech_started"],
                      ["type": "input_audio_buffer.speech_stopped"])
            await clock.advance(22)
            link.play(["type": "response.created", "response": ["id": "r1"]],
                      ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "rt1", "name": "look", "arguments": "{}"]])
            await clock.settle()
            XCTAssertFalse(link.notes.contains { $0.hasPrefix("Progress sync:") },
                           "Even a slow first step must not send a progress note")

            link.play(["type": "response.done", "response": ["id": "r1"]])
            await clock.advance(22)
            link.play(["type": "response.created", "response": ["id": "r2"]],
                      ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "rt2", "name": "do", "arguments": "{}"]])
            await clock.settle()
            XCTAssertTrue(link.notes.contains { $0.contains("WeChat") && $0.localizedCaseInsensitiveContains("progress") },
                          "Realtime path must send a factual progress sync note after long silence: \(link.notes)")
        }
    }

    // MARK: - Bug 3: Immediate barge-in interruption during long playback

    func testBargeInMutesImmediatelyButOnlyClearsConfirmedInterruptions() async throws {
        // 1. ChatGPT / Codex path: substantive barge-in mutes immediately and stays muted while draining.
        do {
            let chatGPT = try makeChatGPTStorage()
            defer { try? chatGPT.tearDown() }
            let clock = FakeTime()
            let codex = SyncFakeCodexVoice()
            let (voice, currentLink) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage)
            defer { voice.stop() }
            await voice.start()
            await clock.settle()
            let link = currentLink()

            link.remoteSpeech = true
            await clock.advance(0.2)
            XCTAssertEqual(voice.phase, .speaking)
            XCTAssertEqual(link.remoteVolume, 1)

            // Chunk 1 is only a backchannel ("好，") -> must not mute yet.
            codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": "好，"])
            XCTAssertEqual(link.remoteVolume, 1, "Initial brief backchannel alone must not mute playback")

            // Chunk 2 turns the utterance into substantive barge-in ("那这样吧") -> immediate mute + buffer clear + .hearing + interrupted.
            codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": "那这样吧"])
            XCTAssertEqual(link.remoteVolume, 0, "Substantive barge-in on Codex must immediately mute remote playback")
            XCTAssertTrue(link.sent.contains { $0["type"] as? String == "output_audio_buffer.clear" },
                          "Barge-in must immediately request clearing any buffered remote output audio")
            XCTAssertEqual(voice.phase, .hearing)
            XCTAssertTrue(voice.interrupted)

            // Residual remote RTP audio for >1s must NOT unmute or overwrite .hearing back to .speaking.
            for _ in 0..<8 { await clock.advance(0.2) }
            XCTAssertEqual(link.remoteVolume, 0, "Residual playback tail must stay muted while user is speaking")
            XCTAssertEqual(voice.phase, .hearing, "Residual playback tail must not revert phase back to .speaking")

            // Once old playback drains and user finishes speaking, remote audio unmutes for the new reply.
            link.remoteSpeech = false
            for _ in 0..<3 { await clock.advance(0.2) }
            codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "好，那这样吧"])
            await clock.settle()
            XCTAssertEqual(voice.phase, .thinking)
            XCTAssertEqual(link.remoteVolume, 1, "Remote volume must restore after barge-in completes so the new reply is audible")
        }

        for live in [true, false] {
            let clock = FakeTime()
            let (voice, currentLink) = makeVoice(time: clock)
            defer { voice.stop() }
            if live { _ = voice.setBridge(BridgeStub.liveAddress) }
            await voice.start()
            let link = currentLink()
            if live {
                link.play(["type": "session.started"])
                link.remoteSpeech = true
                await clock.advance(0.2)
            } else {
                link.play(["type": "session.created"],
                          ["type": "response.created", "response": ["id": "r1"]],
                          ["type": "output_audio_buffer.started"])
            }
            XCTAssertEqual(voice.phase, .speaking)
            XCTAssertEqual(link.remoteVolume, 1)

            link.play(["type": "input_audio_buffer.speech_started", "item_id": "ack-1"])
            XCTAssertEqual(link.remoteVolume, 0, "Speech detection must mute immediately, live=\(live)")
            XCTAssertFalse(link.sent.contains { $0["type"] as? String == "output_audio_buffer.clear" },
                           "Detection alone must preserve the buffered reply, live=\(live)")
            XCTAssertEqual(voice.phase, .hearing)
            link.play(["type": "input_audio_buffer.speech_stopped"])
            if live {
                link.play(["type": "session.input_transcript.delta", "item_id": "ack-1", "delta": "嗯", "start_ms": 0, "end_ms": 400])
            } else {
                link.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "ack-1", "transcript": "嗯"])
            }
            await clock.settle()
            XCTAssertEqual(link.remoteVolume, 1, "A backchannel must restore the existing reply, live=\(live)")
            XCTAssertFalse(link.sent.contains { $0["type"] as? String == "output_audio_buffer.clear" },
                           "A backchannel cannot recover audio after a clear, live=\(live)")
            XCTAssertEqual(voice.phase, .speaking)
            XCTAssertFalse(voice.interrupted, "A backchannel must not mark the old reply interrupted, live=\(live)")

            link.play(["type": "input_audio_buffer.speech_started", "item_id": "barge-2"])
            XCTAssertEqual(link.remoteVolume, 0)
            if live {
                link.play(["type": "session.input_transcript.delta", "item_id": "barge-2", "delta": "Check the weather instead", "start_ms": 1000, "end_ms": 1600])
            } else {
                link.play(["type": "input_audio_buffer.speech_stopped"],
                          ["type": "conversation.item.input_audio_transcription.completed", "item_id": "barge-2", "transcript": "Check the weather instead"])
            }
            XCTAssertEqual(link.remoteVolume, 0, "Confirmed interruption must stay muted, live=\(live)")
            XCTAssertTrue(link.sent.contains { $0["type"] as? String == "output_audio_buffer.clear" },
                          "A substantive transcript must clear the old reply, live=\(live)")
            XCTAssertEqual(voice.phase, .hearing)
            XCTAssertTrue(voice.interrupted)

            if live {
                for _ in 0..<8 { await clock.advance(0.2) }
                XCTAssertEqual(link.remoteVolume, 0)
                XCTAssertEqual(voice.phase, .hearing)
                link.remoteSpeech = false
                for _ in 0..<3 { await clock.advance(0.2) }
            } else {
                link.play(["type": "output_audio_buffer.cleared"])
            }
            XCTAssertEqual(link.remoteVolume, 1, "Audio must recover once the interrupted reply drains, live=\(live)")
        }
    }

    // MARK: - Failure / Edge Cases: Anti-false-trigger, running task protection, no premature completion

    func testSpuriousNoiseEmptyTranscriptsAndInFlightToolsDoNotMisInterruptOrJumpTheGun() async throws {
        // 1. Blank/punctuation transcripts during Codex playback must NOT mute or leave .speaking.
        do {
            let chatGPT = try makeChatGPTStorage()
            defer { try? chatGPT.tearDown() }
            let clock = FakeTime()
            let codex = SyncFakeCodexVoice()
            let (voice, currentLink) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage)
            defer { voice.stop() }
            await voice.start()
            await clock.settle()
            let link = currentLink()

            link.remoteSpeech = true
            await clock.advance(0.2)
            XCTAssertEqual(voice.phase, .speaking)

            for noise in ["", "   ", "...", "，。", "：", "“”", "「」", "——", "（）", "---"] {
                codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": noise])
                XCTAssertEqual(voice.phase, .speaking, "Noise transcript '\(noise)' must not interrupt speaking")
                XCTAssertEqual(link.remoteVolume, 1, "Noise transcript '\(noise)' must not mute playback")
                XCTAssertFalse(voice.interrupted)
            }
        }

        // 2. Active .working task on Live Activity must NOT be cleared when voice phase changes.
        do {
            let chatGPT = try makeChatGPTStorage()
            defer { try? chatGPT.tearDown() }
            let clock = FakeTime()
            let codex = SyncFakeCodexVoice()
            let (voice, _) = makeVoice(time: clock, codex: codex, storage: chatGPT.storage)
            let activity = ActivityController()
            let watcher = TalkActivity(voice: voice, activity: activity, deviceName: { "Test iPhone" }, keepsActivity: { false })
            defer {
                voice.stop()
                activity.end(dismissalPolicy: .immediate)
                withExtendedLifetime(watcher) {}
            }
            await voice.start()
            await clock.settle()

            activity.update { $0.phase = .working; $0.headline = "Open WeChat" }
            activity.record(step: "Open WeChat", ok: true)
            codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": "嗯"])
            await clock.settle()
            XCTAssertEqual(activity.state.phase, .working, "Voice updates must never clear an active .working task")
            XCTAssertEqual(activity.state.stepCount, 1)
        }

        // 3. In-flight or failed tools must NEVER trigger premature completion progress sync.
        do {
            let clock = FakeTime()
            var releaseSecondTool: CheckedContinuation<PhoneAnswer, Never>?
            let (voice, currentLink) = makeVoice(time: clock) { name, _ in
                if name == "open_app" { return ("app: 12306\nOpened", false, nil) }
                return await withCheckedContinuation { continuation in
                    releaseSecondTool = continuation
                }
            }
            defer { voice.stop() }
            _ = voice.setBridge(BridgeStub.liveAddress)
            await voice.start()
            let link = currentLink()
            link.play(["type": "session.started"])
            link.play(["type": "session.input_transcript.delta", "delta": "查高铁发微信", "start_ms": 0, "end_ms": 400],
                      ["type": "session.delegation.created", "delegation": ["id": "d1"]])

            link.call("s1", "open_app", arguments: #"{"app":"12306"}"#)
            await clock.settle()

            // Start s2 and hold it in-flight past 30s silence threshold -> must emit ZERO commentary while still running!
            link.call("s2", "do", arguments: "{}")
            await clock.settle()
            await clock.advance(30)
            XCTAssertTrue(link.sent.filter { $0["type"] as? String == "session.commentary.append" }.isEmpty,
                          "In-flight tool must never trigger premature progress commentary")

            // Complete s2 as FAILED -> must NOT announce a completed milestone.
            releaseSecondTool?.resume(returning: ("error: element not found", true, nil))
            await clock.settle()
            XCTAssertTrue(link.sent.filter { $0["type"] as? String == "session.commentary.append" }.isEmpty,
                          "Failed tool must never announce a completed progress milestone")
        }
    }
}
