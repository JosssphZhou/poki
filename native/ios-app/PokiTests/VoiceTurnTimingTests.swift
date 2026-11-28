import Foundation
import PokiCore
import XCTest
@testable import Poki

private final class DirectVoiceTimingStub: URLProtocol {
    static let baseURL = "https://voice-direct-timing.test/v1"
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "voice-direct-timing.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"value":"ek_direct_timing","model":"gpt-realtime-2.1"}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class MacToolsBridgeStub: URLProtocol {
    static let address = "http://voice-mac-tools-timing.test/voice/0123456789abcdef"
    private static let lock = NSLock()
    nonisolated(unsafe) static var tapChangesScreen = true
    nonisolated(unsafe) static var tapConfirmsTarget = true
    nonisolated(unsafe) static var readConfirmsTarget = true
    nonisolated(unsafe) static var legacyMode = false
    nonisolated(unsafe) static var tapBridgeMS = 180
    nonisolated(unsafe) static var readBridgeMS = 95
    nonisolated(unsafe) private static var recordedRequests: [[String: Any]] = []

    static var requests: [[String: Any]] { lock.withLock { recordedRequests } }
    static func reset() {
        lock.withLock {
            tapChangesScreen = true
            tapConfirmsTarget = true
            readConfirmsTarget = true
            legacyMode = false
            tapBridgeMS = 180
            readBridgeMS = 95
            recordedRequests.removeAll()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "voice-mac-tools-timing.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.lastPathComponent ?? ""
        let body: String
        if path == "token" {
            body = #"{"value":"ek_mac_bridge","model":"gpt-realtime-2.1","local_tools":["get_ios_version"]}"#
        } else if path == "tool" {
            let payload = readBody(request)
            let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
            Self.lock.withLock { Self.recordedRequests.append(json) }
            let name = json["name"] as? String ?? ""
            let checked = json["checked"] as? [String: Any]
            let afterAction = json["after_action"] as? Bool ?? false
            let (changesScreen, tapConfirms, readConfirms, legacy, tapMS, readMS) = Self.lock.withLock {
                (Self.tapChangesScreen, Self.tapConfirmsTarget, Self.readConfirmsTarget, Self.legacyMode, Self.tapBridgeMS, Self.readBridgeMS)
            }
            if legacy {
                body = #"{"call_id":"legacy-1","state":"done","output":"{\"sent\":true,\"screen_change\":\"changed\",\"screen_change_verified\":true}","ms":90,"replayed":false}"#
            } else if name == "tap_text", checked == nil {
                body = #"{"call_id":"t1","state":"check","app":{"bundle_id":"com.apple.calculator","name":"Calculator"},"target":{"text":"7","says":"7"},"ms":45,"action_host":"mac_tools","observation_source":"mac_mcp_accessibility","effective_action":false,"target_confirmed":false,"replayed":false}"#
            } else if name == "tap_text" {
                let change = changesScreen ? "changed" : "unchanged"
                let effective = changesScreen ? "true" : "false"
                let confirmed = (changesScreen && tapConfirms) ? "true" : "false"
                body = #"{"call_id":"t1","state":"done","output":"{\"sent\":true,\"screen_change\":\"\#(change)\",\"screen_change_verified\":true}","ms":\#(tapMS),"action_host":"mac_tools","observation_source":"mac_mcp_action_readback","effective_action":\#(effective),"target_confirmed":\#(confirmed),"replayed":false}"#
            } else if name == "read_screen" {
                let confirmed = (afterAction && readConfirms) ? "true" : "false"
                body = #"{"call_id":"r1","state":"done","output":"{\"source\":\"accessibility\",\"elements\":[{\"role\":\"StaticText\",\"label\":\"7\"}]}","ms":\#(readMS),"action_host":"mac_tools","observation_source":"mac_mcp_accessibility","effective_action":false,"target_confirmed":\#(confirmed),"replayed":false}"#
            } else {
                body = #"{"call_id":"x","state":"done","output":"{\"bundle_id\":\"com.apple.Preferences\",\"foreground_verified\":true}","ms":60,"action_host":"mac_tools","observation_source":"mac_mcp_action_readback","effective_action":true,"target_confirmed":true,"replayed":false}"#
            }
        } else {
            body = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private func readBody(_ request: URLRequest) -> Data {
        if let data = request.httpBody, !data.isEmpty { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
private final class TimingSubscriptionVoiceStub: SubscriptionVoice {
    private var onEvent: ((String, [String: Any]) -> Void)?
    private var onTool: ((String, String) async -> PhoneAnswer)?

    func prepare(onEvent: @escaping (String, [String: Any]) -> Void, onTool: @escaping (String, String) async -> PhoneAnswer) async throws {
        self.onEvent = onEvent
        self.onTool = onTool
    }

    func start(offer: String) async throws -> String { "fixture-sdp-answer" }
    func stop() { onEvent = nil; onTool = nil }
    func notify(_ method: String, _ params: [String: Any]) { onEvent?(method, params) }
    func callTool(_ name: String, _ arguments: String) async -> PhoneAnswer? { await onTool?(name, arguments) }
}

@MainActor
final class VoiceTurnTimingTests: XCTestCase {
    private var storage: IsolatedTestStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storage = try IsolatedTestStorage(prefix: "voice-turn-timing")
        VoiceDirect.setEnabled(false, in: storage.storage)
        AppLog.shared.clear()
        URLProtocol.registerClass(BridgeStub.self)
        URLProtocol.registerClass(DirectVoiceTimingStub.self)
        URLProtocol.registerClass(MacToolsBridgeStub.self)
        MacToolsBridgeStub.reset()
    }

    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(BridgeStub.self)
        URLProtocol.unregisterClass(DirectVoiceTimingStub.self)
        URLProtocol.unregisterClass(MacToolsBridgeStub.self)
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
        try super.tearDownWithError()
    }

    private func makeModel(
        time: FakeTime,
        clearTap: @escaping @MainActor (String, String?, String?) async -> TapClearance = { _, _, _ in .clear },
        phoneTool: @escaping @MainActor (String, String) async -> PhoneAnswer = { _, _ in ("", false, nil) },
        codex: (any SubscriptionVoice)? = nil
    ) -> (voice: VoiceModel, link: () -> FakeConnection) {
        var latest: FakeConnection!
        let voice = VoiceModel(
            clearTap: clearTap,
            phoneTool: { name, arguments, _ in await phoneTool(name, arguments) },
            holdMicrophone: { _ in },
            readyCue: {},
            connection: { onEvent, onClosed in
                let conn = FakeConnection()
                conn.onEvent = onEvent
                conn.onClosed = onClosed
                latest = conn
                return conn
            },
            time: time.clock,
            recentAppAudio: { nil },
            codex: codex,
            storage: storage.storage
        )
        voice.onConversationEnded = { _, _ in }
        return (voice, { latest })
    }

    private func timingLines() -> [String] {
        AppLog.shared.lines.filter { $0.contains("[\(VoiceTurnTiming.logArea)]") }
    }

    func testPhoneDirectSilentTurnLogsCompleteTimelineAndAnnotations() async throws {
        var provider = CustomProvider(name: "Direct Test", endpoints: [CustomEndpoint(url: DirectVoiceTimingStub.baseURL)], model: "gpt-realtime-2.1")
        provider.liveVoice = true
        CustomProviders.setAll([provider], in: storage.storage)

        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { name, _ in
            await time.clock.sleep(.milliseconds(140))
            if name == "look" {
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (40 ms)
                    elements (2):
                     1 StaticText "0" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("before".utf8)
                )
            }
            return (
                """
                app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (50 ms)
                did: tap "7" (sent, 30 ms)
                screen_changed: true (the elements changed)
                elements (2):
                ~1 StaticText "7" [10,10,40,40]
                 2 Button "7" [10,200,40,40]
                """,
                false,
                Data("after".utf8)
            )
        })
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.08)
        link.play(
            ["type": "conversation.item.added", "item": ["role": "user"]],
            ["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"]
        )
        await time.advance(0.12)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-look", "name": "look", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.14)
        XCTAssertNil(voice.clock.firstEffectiveAction, "look is read-only")
        XCTAssertNil(voice.clock.targetConfirmed, "pre-action look showing 0 must not confirm target 7")

        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-tap", "name": "do", "arguments": #"{"actions":[{"tap":2}]}"#]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        await time.advance(0.14)
        await time.advance(0.09)
        link.play(
            ["type": "response.created", "response": ["id": "r3"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "7 is entered."],
            ["type": "response.done", "response": ["id": "r3"]],
            ["type": "output_audio_buffer.stopped"]
        )

        XCTAssertEqual(voice.clock.entryRoute, .directEphemeralCredential)
        XCTAssertEqual(voice.clock.voiceHost, .phoneDirect)
        XCTAssertEqual(voice.clock.actionHost, .phoneLocal)
        XCTAssertEqual(voice.clock.observationSource, .phoneTreeAndScreenshot)
        XCTAssertEqual(voice.clock.ms(.said), 0)
        XCTAssertEqual(voice.clock.ms(.heard), 80)
        XCTAssertEqual(voice.clock.ms(.call), 200)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 440)
        XCTAssertEqual(voice.clock.ms(.toolDone), 580)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 580)
        XCTAssertEqual(voice.clock.ms(.delivered), 580)
        XCTAssertEqual(voice.clock.ms(.spoken), 670)
        XCTAssertEqual(voice.clock.phoneLocalMS, 280)
        XCTAssertEqual(voice.clock.macToolsMS, 0)
        XCTAssertEqual(voice.clock.macToolsRoundtripMS, 0)

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        XCTAssertTrue(entry.contains("entry_route=direct_ephemeral_credential"), entry)
        XCTAssertTrue(entry.contains("voice_host=phone_direct"), entry)
        XCTAssertTrue(entry.contains("default_action_host=phone_local"), entry)
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        for expected in [
            "flow=voice", "entry_route=direct_ephemeral_credential", "voice_host=phone_direct",
            "action_host=phone_local", "observation_source=phone_tree_and_screenshot",
            "said_ms=0", "heard_ms=80", "call_ms=200", "first_effective_action_ms=440",
            "tool_done_ms=580", "target_confirmed_ms=580", "delivered_ms=580", "spoken_ms=670",
            "phone_local_ms=280", "mac_tools_ms=0", "mac_tools_roundtrip_ms=0",
        ] {
            XCTAssertTrue(spoken.contains(expected), "missing \(expected) in \(spoken)")
        }
        voice.stop()
    }

    func testVoiceBridgePhoneLocalSilentTurnSeparatesVoiceHostFromActionHost() async throws {
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in
            await time.clock.sleep(.milliseconds(160))
            return (
                """
                app: Settings (com.apple.Preferences)   read: 2026-11-27T01:00:00Z (60 ms)
                did: launch com.apple.Preferences (sent, 90 ms)
                screen_changed: true (the elements changed)
                elements (1):
                 1 StaticText "Settings" [0,0,100,40]
                """,
                false,
                Data("settings".utf8)
            )
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.06)
        link.play(["type": "conversation.item.added", "item": ["role": "user"]])
        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-open", "name": "do", "arguments": #"{"actions":[{"launch":"com.apple.Preferences"}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.16)
        await time.advance(0.09)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "Settings is open."],
            ["type": "response.done", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.stopped"]
        )

        XCTAssertEqual(voice.clock.entryRoute, .voiceBridge)
        XCTAssertEqual(voice.clock.voiceHost, .voiceBridge)
        XCTAssertEqual(voice.clock.actionHost, .phoneLocal)
        XCTAssertEqual(voice.clock.observationSource, .phoneTreeAndScreenshot)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 160)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 320)
        XCTAssertEqual(voice.clock.ms(.spoken), 410)
        XCTAssertEqual(voice.clock.phoneLocalMS, 160)
        XCTAssertEqual(voice.clock.macToolsMS, 0)

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        XCTAssertTrue(entry.contains("entry_route=voice_bridge"), entry)
        XCTAssertTrue(entry.contains("default_action_host=phone_local"), entry)
        for expected in [
            "entry_route=voice_bridge", "voice_host=voice_bridge", "action_host=phone_local",
            "observation_source=phone_tree_and_screenshot", "said_ms=0", "heard_ms=60",
            "call_ms=160", "first_effective_action_ms=160", "tool_done_ms=320",
            "target_confirmed_ms=320", "delivered_ms=320", "spoken_ms=410",
            "phone_local_ms=160", "mac_tools_ms=0",
        ] {
            XCTAssertTrue(spoken.contains(expected), "missing \(expected) in \(spoken)")
        }
        voice.stop()
    }

    func testMacToolsTurnAttributesDurationSeparatesRoundtripPassesTargetAndNeverPhoneDirect() async throws {
        let time = FakeTime()
        let approvalEntered = expectation(description: "tap_text reached phone approval check")
        let (voice, getLink) = makeModel(time: time, clearTap: { _, _, _ in
            approvalEntered.fulfill()
            await time.clock.sleep(.milliseconds(200))
            return .approved("owner tapped allow")
        })
        XCTAssertTrue(voice.setBridge(MacToolsBridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.05)
        link.play(
            ["type": "conversation.item.added", "item": ["role": "user"]],
            ["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"]
        )
        await time.advance(0.07)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "t1", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await fulfillment(of: [approvalEntered], timeout: 2)
        await time.advance(0.20)
        let delivered = expectation(for: NSPredicate { _, _ in voice.clock.delivered != nil }, evaluatedWith: nil)
        await fulfillment(of: [delivered], timeout: 2)
        await time.advance(0.08)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "Tapped 7."],
            ["type": "response.done", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.stopped"]
        )

        let checkedRequest = try XCTUnwrap(MacToolsBridgeStub.requests.last)
        let targetPayload = try XCTUnwrap(checkedRequest["target_condition"] as? [String: Any])
        XCTAssertEqual(targetPayload["kind"] as? String, "screen_text")
        XCTAssertEqual(targetPayload["expected"] as? String, "7")
        XCTAssertEqual(targetPayload["app"] as? String, "Calculator")

        XCTAssertEqual(voice.clock.entryRoute, .voiceBridge)
        XCTAssertEqual(voice.clock.voiceHost, .voiceBridge)
        XCTAssertEqual(voice.clock.actionHost, .macTools)
        XCTAssertEqual(voice.clock.observationSource, .macMCPActionReadback)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        XCTAssertEqual(voice.clock.macToolsMS, 225)
        XCTAssertLessThan(voice.clock.macToolsRoundtripMS, 200, "phone approval wait must not be charged to Mac roundtrip")
        XCTAssertEqual(voice.clock.ms(.call), 120)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 320)
        XCTAssertNotNil(voice.clock.ms(.targetConfirmed))

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        let actionEnd = try XCTUnwrap(logs.last { $0.contains("event=action_end") })
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        XCTAssertTrue(entry.contains("default_action_host=mac_tools"), entry)
        XCTAssertTrue(actionEnd.contains("action_host=mac_tools"), actionEnd)
        XCTAssertTrue(actionEnd.contains("bridge_ms=225"), actionEnd)
        XCTAssertTrue(actionEnd.contains("roundtrip_ms="), actionEnd)
        XCTAssertTrue(spoken.contains("voice_host=voice_bridge"), spoken)
        XCTAssertTrue(spoken.contains("action_host=mac_tools"), spoken)
        XCTAssertTrue(spoken.contains("observation_source=mac_mcp_action_readback"), spoken)
        XCTAssertTrue(spoken.contains("phone_local_ms=0"), spoken)
        XCTAssertTrue(spoken.contains("mac_tools_ms=225"), spoken)
        XCTAssertTrue(spoken.contains("mac_tools_roundtrip_ms="), spoken)
        XCTAssertFalse(spoken.contains("phone_direct"), spoken)
        voice.stop()
    }

    func testLegacyMacBridgeWithoutClassificationFieldsFailsClosed() async throws {
        MacToolsBridgeStub.legacyMode = true
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time)
        XCTAssertTrue(voice.setBridge(MacToolsBridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"])
        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "legacy-1", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        let delivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "legacy-1" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [delivered], timeout: 2)

        XCTAssertEqual(voice.clock.actionHost, .macTools)
        XCTAssertEqual(voice.clock.macToolsMS, 90)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        XCTAssertEqual(voice.clock.observationSource, .none, "legacy Mac bridge without classification fields must fail closed")
        XCTAssertNil(voice.clock.firstEffectiveAction, "legacy Mac bridge without effective_action must fail closed")
        XCTAssertNil(voice.clock.targetConfirmed, "legacy Mac bridge without target_confirmed must fail closed")
        voice.stop()
    }

    func testPhoneCalculatorTarget7RejectsUnconfirmedTouchAndWrongScreen9() async throws {
        let time = FakeTime()
        var step = 0
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in
            step += 1
            await time.clock.sleep(.milliseconds(50))
            switch step {
            case 1:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (30 ms)
                    elements (2):
                     1 StaticText "9" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("pre-9".utf8)
                )
            case 2:
                return ("not_sent: element 9 is not in the latest read; nothing was sent.", true, nil)
            case 3:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (30 ms)
                    did: tap "7" (sent, 20 ms)
                    screen_changed: false (the elements and the picture are the same)
                    touch effect: unconfirmed (sent reports the input request, not the app's response).
                    elements (2):
                     1 StaticText "9" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("unconfirmed".utf8)
                )
            case 4:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (30 ms)
                    elements (2):
                     1 StaticText "9" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("still-9".utf8)
                )
            case 5:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (35 ms)
                    did: tap "9" (sent, 20 ms)
                    screen_changed: true (the elements changed)
                    elements (3):
                    ~1 StaticText "9" [10,10,40,40]
                    +2 StaticText "Error" [10,55,40,20]
                     3 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("changed-wrong".utf8)
                )
            case 6:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (35 ms)
                    elements (2):
                     1 StaticText "9" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("post-still-9".utf8)
                )
            default:
                return (
                    """
                    app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (35 ms)
                    elements (2):
                     1 StaticText "7" [10,10,40,40]
                     2 Button "7" [10,200,40,40]
                    """,
                    false,
                    Data("verified-7".utf8)
                )
            }
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"])

        func runToolCall(_ id: String, _ name: String, _ args: String) async {
            await time.advance(0.05)
            link.play(
                ["type": "response.created", "response": ["id": "resp-\(id)"]],
                ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": id, "name": name, "arguments": args]],
                ["type": "response.done", "response": ["id": "resp-\(id)"]]
            )
            await time.advance(0.05)
        }

        await runToolCall("c1", "look", "{}")
        XCTAssertNil(voice.clock.firstEffectiveAction)
        XCTAssertNil(voice.clock.targetConfirmed, "pre-action look showing 9 must not confirm target 7")

        await runToolCall("c2", "do", #"{"actions":[{"tap":9}]}"#)
        XCTAssertNil(voice.clock.firstEffectiveAction, "not_sent refusal must not count as effective")
        XCTAssertNil(voice.clock.targetConfirmed)

        await runToolCall("c3", "do", #"{"actions":[{"tap":2}]}"#)
        XCTAssertNil(voice.clock.firstEffectiveAction, "touch effect: unconfirmed with screen_changed: false must not count as effective")
        XCTAssertNil(voice.clock.targetConfirmed)

        await runToolCall("c4", "look", "{}")
        XCTAssertNil(voice.clock.targetConfirmed, "read showing 9 after an unconfirmed touch must not confirm target 7")

        await runToolCall("c5", "do", #"{"actions":[{"tap":2}]}"#)
        XCTAssertNotNil(voice.clock.firstEffectiveAction, "verified screen_changed: true counts as first effective action")
        XCTAssertNil(voice.clock.targetConfirmed, "screen showing display 9 alongside keypad button 7 must not confirm target 7")

        await runToolCall("c6", "look", "{}")
        XCTAssertNil(voice.clock.targetConfirmed, "post-action read still showing 9 must not confirm target 7")

        await runToolCall("c7", "look", "{}")
        let firstConfirmedMS = try XCTUnwrap(voice.clock.ms(.targetConfirmed), "post-action independent read showing display 7 confirms target 7")
        XCTAssertEqual(voice.clock.observationSource, .phoneTreeAndScreenshot)

        await runToolCall("c8", "look", "{}")
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), firstConfirmedMS, "follow-up read-only look must preserve the first target_confirmed timestamp")
        XCTAssertEqual(timingLines().filter { $0.contains("event=target_confirmed") }.count, 1)
        voice.stop()
    }

    func testMacToolsUnchangedTapIsNotEffectiveAndPostActionReadConfirmsTarget() async throws {
        MacToolsBridgeStub.tapChangesScreen = false
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time)
        XCTAssertTrue(voice.setBridge(MacToolsBridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"])

        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "t1", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        let tap1Delivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "t1" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [tap1Delivered], timeout: 2)
        XCTAssertNil(voice.clock.firstEffectiveAction, "unchanged Mac tap must not set first_effective_action")
        XCTAssertNil(voice.clock.targetConfirmed)

        MacToolsBridgeStub.tapChangesScreen = true
        MacToolsBridgeStub.tapConfirmsTarget = false
        await time.advance(0.05)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "t2", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        let tap2Delivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "t2" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [tap2Delivered], timeout: 2)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 150)
        XCTAssertNil(voice.clock.targetConfirmed)

        await time.advance(0.06)
        link.play(
            ["type": "response.created", "response": ["id": "r3"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "r1", "name": "read_screen", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r3"]]
        )
        let readDelivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "r1" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [readDelivered], timeout: 2)
        let readReq = try XCTUnwrap(MacToolsBridgeStub.requests.last)
        XCTAssertEqual(readReq["after_action"] as? Bool, true)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 210)
        XCTAssertEqual(voice.clock.observationSource, .macMCPAccessibility)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        voice.stop()
    }

    func testUntargetedReadAndGetIOSVersionFailClosedUnlessRequested() async throws {
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in
            return (
                """
                app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (30 ms)
                elements (1):
                 1 StaticText "9" [10,10,40,40]
                """,
                false,
                Data("screen".utf8)
            )
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Check something"])
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "v1", "name": "get_ios_version", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.settle()
        XCTAssertNil(voice.clock.targetConfirmed, "get_ios_version must fail closed when no device_info target was requested")

        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "l1", "name": "look", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        await time.settle()
        XCTAssertNil(voice.clock.targetConfirmed, "look must fail closed when no screen_read target was requested")

        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "What iOS version is this phone running?"])
        link.play(
            ["type": "response.created", "response": ["id": "r3"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "v2", "name": "get_ios_version", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r3"]]
        )
        await time.settle()
        XCTAssertNotNil(voice.clock.targetConfirmed)
        XCTAssertEqual(voice.clock.observationSource, .phoneDeviceInfo)
        voice.stop()
    }

    func testDictationEmptyPlanDoesNotFabricateEffectiveActionOrConfirmation() async throws {
        let keys = ["chat.provider", "chat.customURL", "chat.customModel", "custom.providers", "chat.customProvider", "chat.model.custom"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        let previousApp = AskPoki.app
        let previousChat = AskPoki.chat
        defer {
            for key in keys { UserDefaults.standard.set(saved[key] ?? nil, forKey: key) }
            if let previousApp, let previousChat { AskPoki.install(app: previousApp, chat: previousChat) }
        }

        let server = try FakeCompletions(replies: [
            FakeCompletions.tool("report_plan", ["steps": ["Check Calculator"], "currentStep": 1]),
            FakeCompletions.text("I made a plan without touching the phone."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(server.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom

        let automation = FakeAutomation()
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: automation, transport: SessionScreenTransport(session: automation))
        let chat = ChatModel(app: app, kind: .poki)
        AskPoki.install(app: app, chat: chat)

        storage.defaults.set(ModelProvider.anthropic.rawValue, forKey: "chat.provider")
        let time = FakeTime()
        let (voice, _) = makeModel(time: time)
        voice.muted = true
        let dictation = Dictation()
        voice.activateDictation(dictation, listen: {})

        let task = voice.finishDictation(dictation) { "Calculator show 7" }
        await task.value

        XCTAssertEqual(voice.clock.entryRoute, .dictationChatTTS)
        XCTAssertEqual(voice.clock.voiceHost, .phoneDirect)
        XCTAssertEqual(voice.clock.actionHost, .none, "plan-only chat turn must not attribute phone_local action host")
        XCTAssertEqual(voice.clock.observationSource, .phoneChatLoop)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        XCTAssertNil(voice.clock.firstEffectiveAction, "empty plan card must not fabricate first_effective_action")
        XCTAssertNil(voice.clock.targetConfirmed, "empty plan card must not fabricate target_confirmed")
        XCTAssertNotNil(voice.clock.spoken)
        voice.stop()
    }

    func testLateTranscriptDuringPhoneToolStillConfirmsTarget() async throws {
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in
            await time.clock.sleep(.milliseconds(120))
            return (
                """
                app: Calculator (com.apple.calculator)   read: 2026-11-27T01:00:00Z (40 ms)
                did: tap "7" (sent, 20 ms)
                screen_changed: true (the elements changed)
                elements (2):
                ~1 StaticText "7" [10,10,40,40]
                 2 Button "7" [10,200,40,40]
                """,
                false,
                Data("after-7".utf8)
            )
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        await time.advance(0.05)
        link.play(
            ["type": "conversation.item.added", "item": ["role": "user"]],
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-late", "name": "do", "arguments": #"{"actions":[{"tap":2}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.04)
        link.play(["type": "conversation.item.input_audio_transcription.completed", "transcript": "Calculator show 7"])
        await time.advance(0.08)

        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 50)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 170)
        voice.stop()
    }

    func testRealEntryRoutesViaVoiceModelCoverAllFourRoutesAndCodexTurn() async throws {
        var provider = CustomProvider(name: "Direct Route", endpoints: [CustomEndpoint(url: DirectVoiceTimingStub.baseURL)], model: "gpt-realtime-2.1")
        provider.liveVoice = true
        CustomProviders.setAll([provider], in: storage.storage)
        let time = FakeTime()
        let (directVoice, _) = makeModel(time: time)
        directVoice.muted = true
        await directVoice.start(microphone: false)
        XCTAssertTrue(timingLines().contains { $0.contains("event=entry_selected") && $0.contains("entry_route=direct_ephemeral_credential") && $0.contains("voice_host=phone_direct") })
        directVoice.stop()

        CustomProviders.setAll([], in: storage.storage)
        AppLog.shared.clear()
        let (bridgeVoice, _) = makeModel(time: time)
        bridgeVoice.muted = true
        XCTAssertTrue(bridgeVoice.setBridge(BridgeStub.address))
        await bridgeVoice.start(microphone: false)
        XCTAssertTrue(timingLines().contains { $0.contains("event=entry_selected") && $0.contains("entry_route=voice_bridge") && $0.contains("voice_host=voice_bridge") })
        bridgeVoice.stop()

        _ = try storage.seedCodexCredential()
        storage.defaults.set(ModelProvider.chatgpt.rawValue, forKey: "chat.provider")
        AppLog.shared.clear()
        let codex = TimingSubscriptionVoiceStub()
        let (codexVoice, getCodexLink) = makeModel(time: time, phoneTool: { _, _ in
            await time.clock.sleep(.milliseconds(90))
            return (
                """
                app: Settings (com.apple.Preferences)   read: 2026-11-27T01:00:00Z (30 ms)
                elements (1):
                 1 StaticText "Settings" [0,0,100,40]
                """,
                false,
                Data("settings".utf8)
            )
        }, codex: codex)
        codexVoice.muted = true
        await codexVoice.start(microphone: true)
        XCTAssertTrue(timingLines().contains {
            $0.contains("event=entry_selected")
                && $0.contains("entry_route=chatgpt_responses")
                && $0.contains("voice_host=phone_direct")
                && $0.contains("transport=codex_live")
        })
        codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "Open Settings"])
        await time.advance(0.05)
        async let toolAnswer = codex.callTool("open_app", #"{"app":"Settings"}"#)
        await time.advance(0.09)
        let answer = await toolAnswer
        XCTAssertEqual(answer?.failed, false)
        getCodexLink().remoteSpeech = true
        await time.advance(0.20)
        XCTAssertEqual(codexVoice.clock.entryRoute, .chatgptResponses)
        XCTAssertEqual(codexVoice.clock.voiceHost, .phoneDirect)
        XCTAssertEqual(codexVoice.clock.actionHost, .phoneLocal)
        XCTAssertEqual(codexVoice.clock.ms(.firstEffectiveAction), 50)
        XCTAssertEqual(codexVoice.clock.ms(.targetConfirmed), 140)
        XCTAssertNotNil(codexVoice.clock.spoken)
        codexVoice.stop()

        AppLog.shared.clear()
        let (dictationVoice, _) = makeModel(time: time)
        dictationVoice.muted = true
        dictationVoice.activateDictation(Dictation(), listen: {})
        XCTAssertTrue(timingLines().contains {
            $0.contains("event=entry_selected") && $0.contains("entry_route=chatgpt_responses") && $0.contains("transport=responses")
        })
        dictationVoice.stop()

        storage.defaults.set(ModelProvider.anthropic.rawValue, forKey: "chat.provider")
        AppLog.shared.clear()
        dictationVoice.activateDictation(Dictation(), listen: {})
        XCTAssertTrue(timingLines().contains {
            $0.contains("event=entry_selected") && $0.contains("entry_route=dictation_chat_tts") && $0.contains("transport=dictation")
        })
        dictationVoice.stop()

        let custom = VoiceAccount.custom(UUID())
        XCTAssertEqual(
            VoiceEntryRoute.resolve(usesChatGPTSubscription: true, directAccount: .openai, hasDirectKey: true, hasBridge: true, canDictate: true, microphone: true, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false),
            .chatgptResponses
        )
        XCTAssertEqual(
            VoiceEntryRoute.resolve(usesChatGPTSubscription: false, directAccount: custom, hasDirectKey: true, hasBridge: true, canDictate: true, microphone: true, chatProvider: .anthropic, chatGPTSignedIn: false, rehearsing: false),
            .directEphemeralCredential
        )
        XCTAssertNil(
            VoiceEntryRoute.resolve(usesChatGPTSubscription: false, directAccount: nil, hasDirectKey: false, hasBridge: false, canDictate: true, microphone: false, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false)
        )
    }

    func testTimingMetadataKeepsToolOutputsAndPromptsByteIdentical() async throws {
        let time = FakeTime()
        let rawOutput = "Settings is open"
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in (rawOutput, false, nil) })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"actions":[{"tap":1}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.settle()

        let toolOutputEvent = try XCTUnwrap(link.sent.first { ($0["item"] as? [String: Any])?["type"] as? String == "function_call_output" })
        let sentOutput = try XCTUnwrap((toolOutputEvent["item"] as? [String: Any])?["output"] as? String)
        XCTAssertEqual(sentOutput, rawOutput)
        let realtimePrompt = try XCTUnwrap(VoiceDirect.session(in: storage.storage)["instructions"] as? String)
        for prompt in [realtimePrompt, VoiceDirect.codexFrontendInstructions, VoiceDirect.codexBackendInstructions] {
            for forbidden in ["voice_host", "action_host", "observation_source", "first_effective_action", "target_confirmed"] {
                XCTAssertFalse(prompt.contains(forbidden), "prompt must not contain \(forbidden)")
            }
        }
        voice.stop()
    }
}
