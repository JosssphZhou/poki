import Foundation
import Network
import os
import PokiCore
import XCTest
@testable import Poki

final class LocalWebSocketServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var active: NWConnection?
    private var receivedFrames: [[String: Any]] = []
    private var onClientFrame: (@Sendable ([String: Any], LocalWebSocketServer) -> Void)?

    var port: UInt16 { listener.port?.rawValue ?? 0 }
    var received: [[String: Any]] { lock.withLock { receivedFrames } }
    /// The handshake request's headers, names lowercased.
    var headers: [String: String] { handshake.withLock { $0 } }
    private let handshake: OSAllocatedUnfairLock<[String: String]>

    init(onClientFrame: (@Sendable ([String: Any], LocalWebSocketServer) -> Void)? = nil) throws {
        self.onClientFrame = onClientFrame
        let queue = DispatchQueue(label: "poki-test-websocket")
        let handshake = OSAllocatedUnfairLock<[String: String]>(initialState: [:])
        self.queue = queue
        self.handshake = handshake
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.setClientRequestHandler(queue) { _, headers in
            handshake.withLock { seen in headers.forEach { seen[$0.name.lowercased()] = $0.value } }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw URLError(.cannotConnectToHost) }
    }

    deinit {
        stop()
    }

    func stop() {
        listener.cancel()
        lock.withLock {
            active?.cancel()
            active = nil
        }
    }

    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        let connection = lock.withLock { active }
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    func close(code: NWProtocolWebSocket.CloseCode, reason: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = code
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        let connection = lock.withLock { active }
        connection?.send(content: Data(reason.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { active = connection }
        connection.start(queue: queue)
        receiveNext(connection)
    }

    private func receiveNext(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let callback = self.lock.withLock { () -> (@Sendable ([String: Any], LocalWebSocketServer) -> Void)? in
                    self.receivedFrames.append(json)
                    return self.onClientFrame
                }
                callback?(json, self)
            }
            if error == nil {
                self.receiveNext(connection)
            }
        }
    }
}

@MainActor
private final class LoopbackSocketAdapter: VoiceSocketAdapter {
    let url: URL

    init(port: UInt16) {
        self.url = URL(string: "ws://127.0.0.1:\(port)/realtime")!
    }

    func makeRequest(secret: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        return request
    }

    func handshake(send: (String) async throws -> Void,
                   receive: () async throws -> [String: Any]) async throws {
        try await send(#"{"hello":true}"#)
        while true {
            let reply = try await receive()
            if reply["ready"] as? Bool == true { return }
        }
    }

    func encodeMicrophonePCM(_ pcm16LE: Data) -> [String: Any]? {
        ["mic": pcm16LE.base64EncodedString()]
    }

    func translateClientEvent(_ event: [String: Any], controls: VoiceSocketControls) -> [[String: Any]] {
        if event["type"] as? String == "output_audio_buffer.clear" {
            controls.clearPlayback()
            return []
        }
        return [event]
    }

    func translateServerMessage(_ message: [String: Any], controls: VoiceSocketControls) {
        if let audio = message["pcm"] as? String, let data = Data(base64Encoded: audio) {
            controls.playPCM16LE(data)
        }
        if message["clear"] as? Bool == true {
            controls.clearPlayback()
        }
        if let forwarded = message["event"] as? [String: Any] {
            controls.emitEvent(forwarded)
        }
    }

    func mapConnectionError(_ error: Error, httpStatus: Int, closeCode: Int, closeReason: String) -> Error {
        error
    }
}

/// Drives VoiceModel through a real VoiceSocketAdapter and VoiceSocketPlaybackQueue without hardware I/O.
private final class AdapterHarnessConnection: VoiceConnection, @unchecked Sendable {
    let adapter: VoiceSocketAdapter
    let onEvent: @MainActor ([String: Any]) -> Void
    let onClosed: @MainActor (String) -> Void

    @MainActor private(set) var setupFrame: [String: Any]?
    @MainActor private(set) var wireFrames: [[String: Any]] = []
    @MainActor private(set) var playedChunks: [Data] = []
    @MainActor private(set) var clearCount = 0
    @MainActor private(set) var playback = VoiceSocketPlaybackQueue()
    @MainActor private var activeGenerations: [Int] = []
    @MainActor private(set) var closed = false

    @MainActor
    init(adapter: VoiceSocketAdapter,
         onEvent: @escaping @MainActor ([String: Any]) -> Void,
         onClosed: @escaping @MainActor (String) -> Void) {
        self.adapter = adapter
        self.onEvent = onEvent
        self.onClosed = onClosed
    }

    @MainActor
    func connect(secret: String, microphone: Bool, direct: Bool) async throws {
        _ = try adapter.makeRequest(secret: secret)
        var answered = false
        try await adapter.handshake(
            send: { [weak self] frame in
                if let data = frame.data(using: .utf8) {
                    self?.setupFrame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
            },
            receive: {
                guard !answered else { return [:] }
                answered = true
                return ["setupComplete": [String: Any]()]
            }
        )
        onEvent(["type": "session.created"])
    }

    @discardableResult
    func send(_ event: [String: Any]) -> Bool {
        MainActor.assumeIsolated {
            let frames = adapter.translateClientEvent(event, controls: controls)
            wireFrames.append(contentsOf: frames)
            return true
        }
    }

    @MainActor
    func receiveServer(_ message: [String: Any]) {
        adapter.translateServerMessage(message, controls: controls)
    }

    @MainActor
    func finishNextAudioChunk() {
        guard !activeGenerations.isEmpty else { return }
        let generation = activeGenerations.removeFirst()
        if playback.complete(generation: generation) == .stopped {
            onEvent(["type": "output_audio_buffer.stopped"])
        }
    }

    @MainActor
    private var controls: VoiceSocketControls {
        VoiceSocketControls(
            playPCM16LE: { [weak self] data in
                guard let self else { return }
                self.playedChunks.append(data)
                let enqueued = self.playback.enqueue()
                self.activeGenerations.append(enqueued.generation)
                if enqueued.transition == .started {
                    self.onEvent(["type": "output_audio_buffer.started"])
                }
            },
            clearPlayback: { [weak self] in
                guard let self else { return }
                self.clearCount += 1
                _ = self.playback.clear()
                self.onEvent(["type": "output_audio_buffer.cleared"])
            },
            emitEvent: { [weak self] event in
                self?.onEvent(event)
            }
        )
    }

    func setRemoteVolume(_ value: Double) {}
    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    func close() {
        MainActor.assumeIsolated {
            closed = true
            playback.invalidate()
        }
    }
}

@MainActor
final class GeminiVoiceTests: XCTestCase {
    private var savedGeminiKey: String?
    private var savedOpenAIKey: String?
    private var savedOpenAIEnabled: Any?
    private var savedGeminiEnabled: Any?
    private var savedVoiceProvider: Any?
    private var savedOpenAIModel: Any?
    private var savedGeminiModel: Any?
    private var savedBridge: String?

    override func setUp() {
        savedGeminiKey = ModelKeys.key(.gemini)
        savedOpenAIKey = ModelKeys.key(.openai)
        savedOpenAIEnabled = UserDefaults.standard.object(forKey: "voice.openai.enabled")
        savedGeminiEnabled = UserDefaults.standard.object(forKey: "voice.gemini.enabled")
        savedVoiceProvider = UserDefaults.standard.object(forKey: "voice.provider")
        savedOpenAIModel = UserDefaults.standard.object(forKey: "voice.model")
        savedGeminiModel = UserDefaults.standard.object(forKey: "voice.model.gemini")
        savedBridge = UserDefaults.standard.string(forKey: "voiceBridge")
        ModelKeys.remove(.gemini)
        ModelKeys.remove(.openai)
        UserDefaults.standard.removeObject(forKey: "voiceBridge")
        UserDefaults.standard.removeObject(forKey: "voice.provider")
    }

    override func tearDown() {
        if let savedGeminiKey { try? ModelKeys.save(savedGeminiKey, for: .gemini) } else { ModelKeys.remove(.gemini) }
        if let savedOpenAIKey { try? ModelKeys.save(savedOpenAIKey, for: .openai) } else { ModelKeys.remove(.openai) }
        UserDefaults.standard.set(savedOpenAIEnabled, forKey: "voice.openai.enabled")
        UserDefaults.standard.set(savedGeminiEnabled, forKey: "voice.gemini.enabled")
        UserDefaults.standard.set(savedVoiceProvider, forKey: "voice.provider")
        UserDefaults.standard.set(savedOpenAIModel, forKey: "voice.model")
        UserDefaults.standard.set(savedGeminiModel, forKey: "voice.model.gemini")
        UserDefaults.standard.set(savedBridge, forKey: "voiceBridge")
        UserDefaults.standard.removeObject(forKey: "pokiGeminiLiveURL")
    }

    func testVoiceSocketLinkSendsAndPlaysOverItsWebSocketAndClearsQueuedPlayback() async throws {
        let server = try LocalWebSocketServer { frame, server in
            if frame["hello"] as? Bool == true {
                server.send(["ready": true])
            }
        }
        defer { server.stop() }

        var events: [String] = []
        let adapter = LoopbackSocketAdapter(port: server.port)
        let link = VoiceSocketLink(
            adapter: adapter,
            onEvent: { event in if let type = event["type"] as? String { events.append(type) } },
            onClosed: { _ in }
        )
        defer { link.close() }

        try await link.connect(secret: "test-token", microphone: false, direct: false)
        link.setRemoteVolume(0)
        XCTAssertEqual(events, ["session.created"])

        let halfSecondSilence = Data(repeating: 0, count: 12_000 * 2).base64EncodedString()
        server.send(["pcm": halfSecondSilence])
        server.send(["pcm": halfSecondSilence])
        let started = expectation(for: NSPredicate { _, _ in events.contains("output_audio_buffer.started") }, evaluatedWith: nil)
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(events.filter { $0 == "output_audio_buffer.started" }.count, 1)

        let micChunk = adapter.encodeMicrophonePCM(Data([1, 0, 2, 0]))!
        XCTAssertTrue(link.send(micChunk))
        let delivered = expectation(for: NSPredicate { _, _ in server.received.contains { $0["mic"] != nil } }, evaluatedWith: nil)
        await fulfillment(of: [delivered], timeout: 3)

        XCTAssertTrue(link.send(["type": "output_audio_buffer.clear"]))
        XCTAssertTrue(events.contains("output_audio_buffer.cleared"))
    }

    func testGeminiToolCallTranslatesToVoiceModelExecutionAndSendsToolResponse() async throws {
        try ModelKeys.save("test-gemini-placeholder", for: .gemini)
        VoiceDirect.setEnabled(true, for: .gemini)

        let time = FakeTime()
        var ranCalls: [(String, String)] = []
        var activeLink: AdapterHarnessConnection!
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, args in
                ranCalls.append((name, args))
                return ("Settings is open on screen", false)
            },
            connection: { onEvent, onClosed in
                let adapter = VoiceDirect.geminiAdapter()
                let conn = AdapterHarnessConnection(adapter: adapter, onEvent: onEvent, onClosed: onClosed)
                activeLink = conn
                return conn
            },
            time: time.clock
        )

        await voice.start(microphone: false)
        XCTAssertEqual(voice.talkState, .listening)

        let setup = try XCTUnwrap(activeLink.setupFrame?["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.8-live")
        XCTAssertNotNil(setup["inputAudioTranscription"])
        XCTAssertNotNil(setup["outputAudioTranscription"])
        let declarations = try XCTUnwrap(((setup["tools"] as? [[String: Any]])?.first)?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.map { $0["name"] as? String }, ["get_ios_version", "look", "do"])
        XCTAssertTrue(declarations.allSatisfy { $0["parametersJsonSchema"] != nil })

        activeLink.receiveServer(["serverContent": ["inputTranscription": ["text": "打开"]]])
        activeLink.receiveServer(["serverContent": ["inputTranscription": ["text": "设置"]]])
        XCTAssertEqual(voice.phase, .hearing)

        activeLink.receiveServer([
            "toolCall": [
                "functionCalls": [[
                    "id": "call-settings-1",
                    "name": "do",
                    "args": ["actions": [["launch": "com.apple.Preferences"]]],
                ]],
            ],
        ])
        XCTAssertEqual(voice.lines.first { $0.role == .you }?.text, "打开设置")
        await time.settle()

        XCTAssertEqual(ranCalls.count, 1)
        XCTAssertEqual(ranCalls.first?.0, "do")
        XCTAssertEqual(ranCalls.first?.1, #"{"actions":[{"launch":"com.apple.Preferences"}]}"#)

        let toolResponse = try XCTUnwrap(activeLink.wireFrames.last?["toolResponse"] as? [String: Any])
        let responses = try XCTUnwrap(toolResponse["functionResponses"] as? [[String: Any]])
        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?["id"] as? String, "call-settings-1")
        XCTAssertEqual(responses.first?["name"] as? String, "do")
        XCTAssertEqual((responses.first?["response"] as? [String: Any])?["result"] as? String, "Settings is open on screen")

        let pcmBytes = Data([0x10, 0x00, 0x20, 0x00]).base64EncodedString()
        activeLink.receiveServer([
            "serverContent": [
                "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcmBytes]]]],
                "outputTranscription": ["text": "设置已打开。"],
            ],
        ])
        XCTAssertEqual(voice.talkState, .speaking)
        activeLink.receiveServer(["serverContent": ["generationComplete": true, "turnComplete": true]])
        activeLink.finishNextAudioChunk()

        XCTAssertEqual(voice.lines.last { $0.role == .poki }?.text, "设置已打开。")
        XCTAssertEqual(voice.talkState, .listening)
        voice.stop()
    }

    func testGeminiBargeInClearsPlaybackQueueAndMarksTalkInterrupted() async throws {
        try ModelKeys.save("test-gemini-placeholder", for: .gemini)
        VoiceDirect.setEnabled(true, for: .gemini)

        let time = FakeTime()
        var activeLink: AdapterHarnessConnection!
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { _, _ in ("", false) },
            connection: { onEvent, onClosed in
                let adapter = VoiceDirect.geminiAdapter()
                let conn = AdapterHarnessConnection(adapter: adapter, onEvent: onEvent, onClosed: onClosed)
                activeLink = conn
                return conn
            },
            time: time.clock
        )

        await voice.start(microphone: false)
        let pcmBytes = Data([0x01, 0x00, 0x02, 0x00]).base64EncodedString()
        activeLink.receiveServer([
            "serverContent": [
                "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcmBytes]]]],
                "outputTranscription": ["text": "正在播报一段较长的回复"],
            ],
        ])
        activeLink.receiveServer([
            "serverContent": [
                "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcmBytes]]]],
            ],
        ])
        XCTAssertEqual(activeLink.playback.pendingBuffers, 2)
        XCTAssertEqual(voice.talkState, .speaking)

        // User speaks over Poki: Gemini sends interrupted=true, playback clears at once, and VoiceModel shows Interrupted.
        activeLink.receiveServer(["serverContent": ["interrupted": true]])
        XCTAssertEqual(activeLink.clearCount, 1)
        XCTAssertEqual(activeLink.playback.pendingBuffers, 0)
        XCTAssertEqual(voice.talkState, .interrupted)
        // The interrupted turn then ends with turnComplete while the user is still talking.
        activeLink.receiveServer(["serverContent": ["turnComplete": true]])
        XCTAssertEqual(voice.talkState, .interrupted)

        // Late completion callbacks from the cleared audio generation must not overwrite the hearing state.
        activeLink.finishNextAudioChunk()
        activeLink.finishNextAudioChunk()
        await time.advance(1.4)
        XCTAssertEqual(voice.talkState, .hearing)
        voice.stop()
    }

    func testGeminiAccountEnablesLiveVoiceAndTalkHereWithoutBreakingOpenAI() async throws {
        XCTAssertTrue(ModelAccounts.canTalkLive(.openai))
        XCTAssertTrue(ModelAccounts.canTalkLive(.gemini))
        XCTAssertFalse(ModelAccounts.canTalkLive(.anthropic))

        try ModelKeys.save("sk-openai-placeholder", for: .openai)
        try ModelKeys.save("gemini-placeholder", for: .gemini)
        VoiceDirect.setEnabled(true, for: .openai)
        XCTAssertEqual(VoiceDirect.activeProvider, .openai)
        XCTAssertEqual(VoiceDirect.model, "gpt-realtime-2.1")

        // Switching to Gemini updates Live Voice and keeps OpenAI's saved model untouched.
        VoiceDirect.setEnabled(true, for: .gemini)
        XCTAssertEqual(VoiceDirect.activeProvider, .gemini)
        XCTAssertEqual(VoiceDirect.model, "gemini-3.8-live")
        XCTAssertEqual(ModelCatalog.voiceModel(for: .openai), "gpt-realtime-2.1")

        // Talk Here (Action Button in background) runs with only a Gemini key configured.
        ModelKeys.remove(.openai)
        let time = FakeTime()
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { _, _ in ("", false) },
            connection: { onEvent, onClosed in
                let adapter = VoiceDirect.geminiAdapter()
                return AdapterHarnessConnection(adapter: adapter, onEvent: onEvent, onClosed: onClosed)
            },
            time: time.clock
        )
        XCTAssertTrue(voice.canTalkLive)
        let activity = ActivityController()
        activity.canStart = { false }
        let talk = TalkActivity(voice: voice, activity: activity, deviceName: { "Test iPhone" }, keepsActivity: { false })
        defer { activity.end() }

        let started = await talk.startHere()
        XCTAssertTrue(started)
        XCTAssertTrue(activity.isRunning)
        await time.settle()
        XCTAssertEqual(activity.state.voice, .listening)
        voice.stop()

        // A Mac voice bridge that talked before keeps talking until the owner turns Gemini on.
        UserDefaults.standard.removeObject(forKey: "voice.gemini.enabled")
        UserDefaults.standard.removeObject(forKey: "voice.provider")
        VoiceBridge.saved = VoiceBridge("http://192.168.1.2:47830/voice/0123456789abcdef")
        XCTAssertNil(VoiceDirect.activeProvider)
        VoiceDirect.setEnabled(true, for: .gemini)
        XCTAssertEqual(VoiceDirect.activeProvider, .gemini)
    }

    /// A wrong key closes Gemini Live's socket with 1007 before setup completes; the talk says to check the key.
    func testARejectedGeminiKeySaysToCheckItAndTheKeyTravelsOnlyInAHeader() async throws {
        let server = try LocalWebSocketServer { frame, server in
            if frame["setup"] != nil { server.close(code: .protocolCode(.invalidFramePayloadData), reason: "API key not valid. Please pass a valid API key.") }
        }
        defer { server.stop() }
        UserDefaults.standard.set("ws://127.0.0.1:\(server.port)/ws", forKey: "pokiGeminiLiveURL")
        try ModelKeys.save("AIza-test-placeholder", for: .gemini)
        VoiceDirect.setEnabled(true, for: .gemini)

        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { _, _ in ("", false) },
            connection: { onEvent, onClosed in VoiceDirect.makeConnection(for: .gemini, onEvent: onEvent, onClosed: onClosed) },
            time: FakeTime().clock
        )
        await voice.start(microphone: false)

        XCTAssertEqual(voice.phase, .lost("Check your Gemini key in Settings › Models. Gemini rejected it."))
        XCTAssertEqual(server.headers["x-goog-api-key"], "AIza-test-placeholder")
    }
}
