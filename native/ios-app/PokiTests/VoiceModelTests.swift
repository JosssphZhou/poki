import PokiCore
import XCTest
@testable import Poki

/// The voice bridge's token answer, served to URLSession.shared without a Mac.
final class BridgeStub: URLProtocol {
    static let address = "http://voice-bridge.test/voice/0123456789abcdef"
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "voice-bridge.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"value":"ek_test","model":"gpt-realtime","local_tools":["get_ios_version","look","do"]}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// The Realtime connection: the test plays the server's events in and sees whether it was closed.
final class FakeConnection: VoiceConnection, @unchecked Sendable {
    var onEvent: (@MainActor ([String: Any]) -> Void)?
    private(set) var closed = false
    func connect(secret: String, microphone: Bool) async throws {}
    func send(_ event: [String: Any]) -> Bool { true }
    func setRemoteVolume(_ value: Double) {}
    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    func close() { closed = true }
    @MainActor func play(_ events: [String: Any]...) { for event in events { onEvent?(event) } }
}

@MainActor
final class VoiceModelTests: XCTestCase {
    private var savedBridge: String?

    override func setUp() {
        savedBridge = UserDefaults.standard.string(forKey: "voiceBridge")
        URLProtocol.registerClass(BridgeStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(BridgeStub.self)
        UserDefaults.standard.set(savedBridge, forKey: "voiceBridge")
    }

    /// A conversation the person started, connected and listening. `microphone` records what Poki was
    /// told about the microphone (true: the voice session holds it).
    private func talking(phoneTool: @escaping @MainActor (String, String) async -> (String, Bool) = { _, _ in ("", false) }) async -> (VoiceModel, FakeConnection, () -> [Bool]) {
        let link = FakeConnection()
        var microphone: [Bool] = []
        let voice = VoiceModel(clearTap: { _, _, _ in .clear }, phoneTool: phoneTool, holdMicrophone: { microphone.append($0) },
                               connection: { onEvent, _ in link.onEvent = onEvent; return link })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        await voice.start()
        link.play(["type": "session.created"])
        XCTAssertEqual(voice.phase, .listening)
        return (voice, link, { microphone })
    }

    /// Said once, answered once: the microphone is let go and the conversation ends, so iOS's
    /// microphone dot goes off instead of Poki listening on.
    func testTheConversationEndsOnceTheAnswerHasPlayed() async {
        let (voice, link, microphone) = await talking()
        link.play(["type": "input_audio_buffer.speech_started"], ["type": "input_audio_buffer.speech_stopped"],
                  ["type": "response.created", "response": ["id": "r1"]], ["type": "output_audio_buffer.started"],
                  ["type": "response.done", "response": ["id": "r1"]], ["type": "output_audio_buffer.stopped"])
        XCTAssertFalse(voice.isOn)
        XCTAssertTrue(link.closed)
        XCTAssertEqual(voice.phase, .off)
        XCTAssertEqual(microphone(), [true, false])
    }

    /// Poki in the background stops listening, except while a step it was asked for runs (that step
    /// itself brings another app to the front, and its result is still to be said).
    func testInTheBackgroundPokiStopsListeningUnlessAStepIsRunning() async {
        let (step, stepDone) = AsyncStream<Void>.makeStream()
        let (busy, busyLink, _) = await talking(phoneTool: { _, _ in for await _ in step { break }; return ("done", false) })
        busyLink.play(["type": "response.created", "response": ["id": "r1"]],
                      ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"goal":"open Settings"}"#]],
                      ["type": "response.done", "response": ["id": "r1"]])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(busy.isOn)
        stepDone.finish()

        let (idle, idleLink, microphone) = await talking()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(idle.isOn)
        XCTAssertTrue(idleLink.closed)
        XCTAssertEqual(microphone(), [true, false])
    }
}
