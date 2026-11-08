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

/// The Realtime connection: the test plays the server's events in and sees what was sent and whether it was closed.
final class FakeConnection: VoiceConnection, @unchecked Sendable {
    var onEvent: (@MainActor ([String: Any]) -> Void)?
    private(set) var closed = false
    private(set) var sent: [[String: Any]] = []
    func connect(secret: String, microphone: Bool) async throws {}
    func send(_ event: [String: Any]) -> Bool { sent.append(event); return true }
    func setRemoteVolume(_ value: Double) {}
    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    func close() { closed = true }
    @MainActor func play(_ events: [String: Any]...) { for event in events { onEvent?(event) } }
    /// The text of every system note sent on this connection.
    var notes: [String] {
        sent.compactMap { event in
            guard let item = event["item"] as? [String: Any], item["role"] as? String == "system" else { return nil }
            return ((item["content"] as? [[String: Any]])?.first?["text"] as? String)
        }
    }
}

/// Time the test moves by hand: waits finish only when it advances.
@MainActor
final class FakeTime {
    var now = Date(timeIntervalSince1970: 1_000_000)
    private(set) var waits: [Duration] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var clock: VoiceClock {
        VoiceClock(now: { self.now }, sleep: { duration in
            self.waits.append(duration)
            await withCheckedContinuation { self.waiting.append($0) }
        })
    }

    func advance(_ seconds: TimeInterval) async {
        await settle()
        now += seconds
        let due = waiting
        waiting = []
        due.forEach { $0.resume() }
        await settle()
    }

    /// Lets the model's own tasks (a step, a wait) run up to their next suspension.
    func settle() async { for _ in 0..<50 { await Task.yield() } }
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

    /// One VoiceModel with its connections (one per conversation), its time, and what Poki was told about
    /// the microphone (true: the voice session holds it).
    private final class Harness {
        let voice: VoiceModel
        let time: FakeTime
        private(set) var links: [FakeConnection] = []
        private(set) var microphone: [Bool] = []
        var link: FakeConnection { links.last! }

        @MainActor init(phoneTool: @escaping @MainActor (String, String) async -> (String, Bool) = { _, _ in ("", false) }) {
            let time = FakeTime()
            self.time = time
            var made: (() -> FakeConnection)!
            var held: ((Bool) -> Void)!
            voice = VoiceModel(clearTap: { _, _, _ in .clear }, phoneTool: phoneTool, holdMicrophone: { held($0) },
                               connection: { onEvent, _ in let link = made(); link.onEvent = onEvent; return link }, time: time.clock)
            made = { [unowned self] in let link = FakeConnection(); self.links.append(link); return link }
            held = { [unowned self] in self.microphone.append($0) }
            _ = voice.setBridge(BridgeStub.address)
        }

        /// Connected, before the server's session.created.
        @MainActor func connect() async { await voice.start() }

        /// Connected and listening.
        @MainActor func talk() async {
            await voice.start()
            link.play(["type": "session.created"])
        }

        /// The person says `said` and Poki answers `answer` out loud.
        @MainActor func turn(_ said: String, _ answer: String, id: String) {
            link.play(["type": "input_audio_buffer.speech_started"], ["type": "input_audio_buffer.speech_stopped"],
                      ["type": "conversation.item.input_audio_transcription.completed", "transcript": said],
                      ["type": "response.created", "response": ["id": id]], ["type": "output_audio_buffer.started"],
                      ["type": "response.output_audio_transcript.done", "transcript": answer],
                      ["type": "response.done", "response": ["id": id]], ["type": "output_audio_buffer.stopped"])
        }
    }

    /// Said once, answered once: the conversation waits 8 s for the person to go on, then ends and lets
    /// go of the microphone, so iOS's microphone dot goes off instead of Poki listening on.
    func testTheConversationEndsWhenNobodySpeaksForEightSecondsAfterTheAnswer() async {
        let h = Harness()
        await h.talk()
        h.turn("What iOS version is this?", "iOS 26.1.", id: "r1")
        await h.time.settle()
        XCTAssertTrue(h.voice.isOn)
        XCTAssertEqual(h.time.waits, [.seconds(8)])
        await h.time.advance(8)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.link.closed)
        XCTAssertEqual(h.voice.phase, .off)
        XCTAssertEqual(h.microphone, [true, false])
    }

    /// Speaking again within the 8 s goes on in the same conversation: the model keeps what was said.
    func testSpeakingAgainWithinEightSecondsGoesOnInTheSameConversation() async {
        let h = Harness()
        await h.talk()
        h.turn("Open Settings.", "Settings is open.", id: "r1")
        await h.time.settle()
        h.link.play(["type": "input_audio_buffer.speech_started"])
        await h.time.advance(8)
        XCTAssertTrue(h.voice.isOn)
        XCTAssertEqual(h.links.count, 1)
        XCTAssertFalse(h.link.closed)
    }

    /// Talking again within 5 minutes of the end: the new conversation is told what was said last time,
    /// so Poki does not start from nothing. Later than that, it starts fresh.
    func testANewConversationWithinFiveMinutesIsToldTheLastTurns() async {
        let h = Harness()
        await h.talk()
        h.turn("Open Settings.", "Settings is open.", id: "r1")
        await h.time.advance(8)
        XCTAssertFalse(h.voice.isOn)

        await h.time.advance(4 * 60)
        await h.talk()
        let carried = h.link.notes.joined(separator: "\n")
        XCTAssertTrue(carried.contains("Open Settings."), carried)
        XCTAssertTrue(carried.contains("Settings is open."), carried)
        h.voice.stop()

        await h.time.advance(5 * 60 + 1)
        await h.talk()
        XCTAssertFalse(h.link.notes.joined().contains("Open Settings."))
    }

    /// A step that finishes while its request's answer is still out: the conversation stays until the
    /// answer that carries the result has played.
    func testAStepsResultIsSaidBeforeTheConversationEnds() async {
        let h = Harness(phoneTool: { _, _ in ("Settings is open", false) })
        await h.talk()
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"goal":"open Settings"}"#]])
        await h.time.settle()
        XCTAssertEqual(h.voice.calls.first?.delivered, true)
        h.link.play(["type": "response.done", "response": ["id": "r1"]])
        await h.time.advance(8)
        XCTAssertTrue(h.voice.isOn)
        h.link.play(["type": "response.created", "response": ["id": "r2"]], ["type": "output_audio_buffer.started"],
                    ["type": "response.done", "response": ["id": "r2"]], ["type": "output_audio_buffer.stopped"])
        await h.time.advance(8)
        XCTAssertFalse(h.voice.isOn)
    }

    /// The voice page's button let go while the conversation was still connecting: nothing was heard, so
    /// it ends as soon as it connects instead of listening on.
    func testLettingGoWhileConnectingEndsTheConversationOnceConnected() async {
        let h = Harness()
        await h.connect()
        h.voice.held = true
        h.voice.held = false
        h.link.play(["type": "session.created"])
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.link.closed)
        XCTAssertEqual(h.microphone, [true, false])
    }

    /// Poki in the background stops listening at once, except while a step it was asked for runs (that
    /// step itself brings another app to the front, and its result is still to be said).
    func testInTheBackgroundPokiStopsListeningUnlessAStepIsRunning() async {
        let (step, stepDone) = AsyncStream<Void>.makeStream()
        let busy = Harness(phoneTool: { _, _ in for await _ in step { break }; return ("done", false) })
        await busy.talk()
        busy.link.play(["type": "response.created", "response": ["id": "r1"]],
                       ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"goal":"open Settings"}"#]],
                       ["type": "response.done", "response": ["id": "r1"]])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(busy.voice.isOn)
        stepDone.finish()

        let idle = Harness()
        await idle.talk()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(idle.voice.isOn)
        XCTAssertTrue(idle.link.closed)
        XCTAssertEqual(idle.microphone, [true, false])
    }
}
