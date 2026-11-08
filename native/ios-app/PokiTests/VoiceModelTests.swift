import PokiCore
import XCTest
@testable import Poki

/// The voice bridge and OpenAI's client_secrets endpoint, served to URLSession.shared without a Mac or
/// OpenAI. Every request is kept, so a test sees whom the phone asked for a key.
final class NetworkStub: URLProtocol {
    static let bridgeAddress = "http://voice-bridge.test/voice/0123456789abcdef"
    static let clientSecrets = "https://api.openai.com/v1/realtime/client_secrets"
    struct Asked { let url: String; let method: String; let authorization: String?; let body: Data }
    nonisolated(unsafe) private static var asked: [Asked] = []
    /// OpenAI's answer to client_secrets: status and body.
    nonisolated(unsafe) static var openAI = (200, #"{"value":"ek_direct","expires_at":1000060}"#)
    private static let lock = NSLock()

    static var taken: [Asked] { lock.withLock { asked } }
    static func reset() {
        lock.withLock { asked = [] }
        openAI = (200, #"{"value":"ek_direct","expires_at":1000060}"#)
    }

    override class func canInit(with request: URLRequest) -> Bool { ["voice-bridge.test", "api.openai.com"].contains(request.url?.host() ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.asked.append(Asked(url: url.absoluteString, method: request.httpMethod ?? "GET", authorization: request.value(forHTTPHeaderField: "Authorization"), body: Self.body(request))) }
        let (status, body) = url.host() == "api.openai.com" ? Self.openAI : (200, #"{"value":"ek_test","model":"gpt-realtime","local_tools":["get_ios_version","look","do"]}"#)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    /// A POST's body reaches a URLProtocol as a stream.
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// The Realtime connection: the test plays the server's events in and sees what was sent and whether it was closed.
final class FakeConnection: VoiceConnection, @unchecked Sendable {
    var onEvent: (@MainActor ([String: Any]) -> Void)?
    private(set) var closed = false
    private(set) var sent: [[String: Any]] = []
    /// The client secret the connection was opened with.
    private(set) var secret: String?
    func connect(secret: String, microphone: Bool) async throws { self.secret = secret }
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

/// Time the test moves by hand: a wait finishes once the test has advanced past its end.
@MainActor
final class FakeTime {
    var now = Date(timeIntervalSince1970: 1_000_000)
    private var waiting: [(until: Date, done: CheckedContinuation<Void, Never>)] = []

    var clock: VoiceClock {
        VoiceClock(now: { self.now }, sleep: { duration in
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            let until = self.now.addingTimeInterval(seconds)
            await withCheckedContinuation { self.waiting.append((until, $0)) }
        })
    }

    func advance(_ seconds: TimeInterval) async {
        await settle()
        now += seconds
        let due = waiting.filter { $0.until <= now }
        waiting.removeAll { $0.until <= now }
        due.forEach { $0.done.resume() }
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
        NetworkStub.reset()
        URLProtocol.registerClass(NetworkStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(NetworkStub.self)
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

        /// `openAIKey`: the OpenAI key saved on the phone; none unless a test says so.
        @MainActor init(openAIKey: @escaping @MainActor () -> String? = { nil },
                        phoneTool: @escaping @MainActor (String, String) async -> (String, Bool) = { _, _ in ("", false) }) {
            let time = FakeTime()
            self.time = time
            var made: (() -> FakeConnection)!
            var held: ((Bool) -> Void)!
            voice = VoiceModel(clearTap: { _, _, _ in .clear }, phoneTool: phoneTool, holdMicrophone: { held($0) },
                               connection: { onEvent, _ in let link = made(); link.onEvent = onEvent; return link }, time: time.clock,
                               openAIKey: openAIKey)
            made = { [unowned self] in let link = FakeConnection(); self.links.append(link); return link }
            held = { [unowned self] in self.microphone.append($0) }
            _ = voice.setBridge(NetworkStub.bridgeAddress)
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
        await h.time.advance(7)
        XCTAssertTrue(h.voice.isOn)
        await h.time.advance(1)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.link.closed)
        XCTAssertEqual(h.voice.phase, .off)
        XCTAssertEqual(h.microphone, [true, false])
    }

    /// Talk to Poki and then nothing said: the same 8 s end it.
    func testTheConversationEndsWhenNobodySpeaksForEightSecondsAfterItOpens() async {
        let h = Harness()
        await h.talk()
        await h.time.advance(7)
        XCTAssertTrue(h.voice.isOn)
        await h.time.advance(1)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.microphone, [true, false])
    }

    /// Speech the server answers only with an error: no answer is coming, so the 8 s still end it.
    func testSpeechAnsweredOnlyWithAnErrorStillEndsAfterEightSeconds() async {
        let h = Harness()
        await h.talk()
        h.link.play(["type": "input_audio_buffer.speech_started"], ["type": "input_audio_buffer.speech_stopped"],
                    ["type": "error", "error": ["message": "Conversation already has an active response"]])
        await h.time.advance(8)
        XCTAssertFalse(h.voice.isOn)
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
        h.turn("Turn on Wi-Fi.", "Wi-Fi is on.", id: "r2")
        h.voice.stop()

        // Only the last conversation's lines, not the ones before it.
        await h.time.advance(60)
        await h.talk()
        let again = h.link.notes.joined(separator: "\n")
        XCTAssertTrue(again.contains("Turn on Wi-Fi."), again)
        XCTAssertFalse(again.contains("Open Settings."), again)
        h.voice.stop()

        await h.time.advance(5 * 60 + 1)
        await h.talk()
        XCTAssertFalse(h.link.notes.joined().contains("Wi-Fi"))
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

    /// The voice page's button let go while the conversation was still connecting (the voice bridge's
    /// token not back yet): nothing was heard, so it never opens the microphone.
    func testLettingGoWhileConnectingEndsTheConversation() async {
        let h = Harness()
        h.voice.held = true
        let opening = Task { await h.connect() }
        for _ in 0..<1000 where h.voice.phase != .connecting { await Task.yield() }
        XCTAssertEqual(h.voice.phase, .connecting)
        h.voice.held = false
        await opening.value
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.voice.phase, .off)
        XCTAssertTrue(h.links.isEmpty)
        XCTAssertEqual(h.microphone, [])
    }

    /// Talk to Poki, then Home before it has connected: it never opens the microphone in the background.
    func testGoingToTheBackgroundWhileConnectingEndsTheConversation() async {
        let h = Harness()
        let opening = Task { await h.connect() }
        for _ in 0..<1000 where h.voice.phase != .connecting { await Task.yield() }
        XCTAssertEqual(h.voice.phase, .connecting)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await opening.value
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.links.isEmpty)
        XCTAssertEqual(h.microphone, [])
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// Poki in the background stops listening at once, except while a step it was asked for runs (that
    /// step itself brings another app to the front): then it ends as soon as the step's result is said,
    /// with no 8 s to go on.
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
        await busy.time.settle()
        XCTAssertEqual(busy.voice.calls.first?.delivered, true)
        busy.link.play(["type": "response.created", "response": ["id": "r2"]], ["type": "output_audio_buffer.started"],
                       ["type": "response.done", "response": ["id": "r2"]], ["type": "output_audio_buffer.stopped"])
        XCTAssertFalse(busy.voice.isOn)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        let idle = Harness()
        await idle.talk()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(idle.voice.isOn)
        XCTAssertTrue(idle.link.closed)
        XCTAssertEqual(idle.microphone, [true, false])
    }

    /// A step's result is handed to the model and Poki goes to the background before the answer has
    /// started: the answer still gets said, then the conversation ends.
    func testAStepsResultHandedOverJustBeforeTheBackgroundIsStillSaid() async {
        let h = Harness(phoneTool: { _, _ in ("Settings is open", false) })
        await h.talk()
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": "{}"]],
                    ["type": "response.done", "response": ["id": "r1"]])
        await h.time.settle()
        XCTAssertEqual(h.voice.calls.first?.delivered, true)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(h.voice.isOn)
        h.link.play(["type": "response.created", "response": ["id": "r2"]], ["type": "output_audio_buffer.started"],
                    ["type": "response.done", "response": ["id": "r2"]], ["type": "output_audio_buffer.stopped"])
        XCTAssertFalse(h.voice.isOn)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// In the background, an error that is not about the request for the step's answer (a stale cancel,
    /// say) does not end the conversation before that answer is said. The error that is about it does.
    func testInTheBackgroundOnlyAnErrorForTheAnswerRequestEndsTheConversation() async {
        for ownError in [false, true] {
            let (step, stepDone) = AsyncStream<Void>.makeStream()
            let h = Harness(phoneTool: { _, _ in for await _ in step { break }; return ("done", false) })
            await h.talk()
            h.link.play(["type": "response.created", "response": ["id": "r1"]],
                        ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": "{}"]],
                        ["type": "response.done", "response": ["id": "r1"]])
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            stepDone.finish()
            await h.time.settle()
            let request = h.link.sent.last { $0["type"] as? String == "response.create" }
            XCTAssertNotNil(request)
            let id = request?["event_id"] as? String
            XCTAssertNotNil(id, "the request for the answer carries an id its error can name")

            h.link.play(["type": "error", "error": ["message": "x", "event_id": ownError ? id ?? "" : "event_other"]])
            XCTAssertEqual(h.voice.isOn, !ownError, ownError ? "the answer request failed, nothing is coming" : "an unrelated error ended it before the answer")
            if !ownError {
                h.link.play(["type": "response.created", "response": ["id": "r2"]], ["type": "output_audio_buffer.started"],
                            ["type": "response.done", "response": ["id": "r2"]], ["type": "output_audio_buffer.stopped"])
                XCTAssertFalse(h.voice.isOn)
            }
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        }
    }

    /// A conversation in which nobody said anything does not wipe what the one before it said: a third
    /// opened within 5 minutes of that one still hears it.
    func testASilentConversationInBetweenKeepsTheLastTurnsToCarryOver() async {
        let h = Harness()
        await h.talk()
        h.turn("Open Settings.", "Settings is open.", id: "r1")
        h.voice.stop()

        await h.time.advance(30)
        await h.talk()
        await h.time.advance(8)
        XCTAssertFalse(h.voice.isOn)

        await h.time.advance(30)
        await h.talk()
        let carried = h.link.notes.joined(separator: "\n")
        XCTAssertTrue(carried.contains("Open Settings."), carried)
        XCTAssertTrue(carried.contains("Settings is open."), carried)
    }

    /// A step's result is handed over and the server's answer to the request never comes (its error names
    /// no request, so Poki cannot tell it is about this one): the conversation does not wait for ever.
    /// 60 s without a word from the server in the foreground ends it.
    func testAnAnswerThatNeverComesEndsTheConversationAfterSixtySecondsInTheForeground() async {
        let h = Harness(phoneTool: { _, _ in ("Settings is open", false) })
        await h.talk()
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": "{}"]],
                    ["type": "response.done", "response": ["id": "r1"]])
        await h.time.settle()
        h.link.play(["type": "error", "error": ["message": "x"]])
        await h.time.advance(59)
        XCTAssertTrue(h.voice.isOn)
        await h.time.advance(1)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.microphone, [true, false])
    }

    /// The same in the background, and the person's microphone is off 30 s after Poki went there, counted
    /// from going there and not from the start of the conversation. Speech whose end never arrives is the
    /// same wait.
    func testAnAnswerThatNeverComesEndsTheConversationThirtySecondsAfterTheBackground() async {
        let h = Harness(phoneTool: { _, _ in ("Settings is open", false) })
        await h.talk()
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": "{}"]],
                    ["type": "response.done", "response": ["id": "r1"]])
        await h.time.settle()
        h.link.play(["type": "error", "error": ["message": "x"]])
        await h.time.advance(20)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await h.time.advance(29)
        XCTAssertTrue(h.voice.isOn)
        await h.time.advance(1)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.microphone, [true, false])

        let hearing = Harness()
        await hearing.talk()
        hearing.link.play(["type": "input_audio_buffer.speech_started"])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await hearing.time.advance(29)
        XCTAssertTrue(hearing.voice.isOn)
        await hearing.time.advance(1)
        XCTAssertFalse(hearing.voice.isOn)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// The cap is for waiting on the server. A step that runs for minutes in the background is not cut
    /// off, and its result is still said.
    func testAStepRunningLongerThanTheCapInTheBackgroundIsNotCutOff() async {
        let (step, stepDone) = AsyncStream<Void>.makeStream()
        let h = Harness(phoneTool: { _, _ in for await _ in step { break }; return ("done", false) })
        await h.talk()
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": "{}"]],
                    ["type": "response.done", "response": ["id": "r1"]])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await h.time.advance(100)
        XCTAssertTrue(h.voice.isOn)
        stepDone.finish()
        await h.time.settle()
        XCTAssertEqual(h.voice.calls.first?.delivered, true)
        await h.time.advance(29)
        XCTAssertTrue(h.voice.isOn, "the wait for the answer starts when the result is handed over")
        h.link.play(["type": "response.created", "response": ["id": "r2"]], ["type": "output_audio_buffer.started"],
                    ["type": "response.done", "response": ["id": "r2"]], ["type": "output_audio_buffer.stopped"])
        XCTAssertFalse(h.voice.isOn)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// With an OpenAI key saved on this iPhone, voice asks OpenAI itself for the one-minute key, for the
    /// session the voice bridge asks for (src/voice-session.mjs), and never reaches the Mac, also not for
    /// a step: so it works away from the Mac's network. Once the key is gone, the next conversation asks
    /// the Mac's voice bridge again.
    func testWithAnOpenAIKeyOnThePhoneVoiceNeverAsksTheMac() async throws {
        var key: String? = "sk-test-phone-key"
        let h = Harness(openAIKey: { key }, phoneTool: { _, _ in ("Settings is open", false) })
        await h.talk()
        let asked = NetworkStub.taken
        XCTAssertEqual(asked.map(\.url), [NetworkStub.clientSecrets])
        let request = try XCTUnwrap(asked.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.authorization, "Bearer sk-test-phone-key")
        XCTAssertEqual(h.link.secret, "ek_direct")

        // The body bin/voice-bridge.mjs sends by default.
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let expires = body["expires_after"] as? [String: Any]
        XCTAssertEqual(expires?["anchor"] as? String, "created_at")
        XCTAssertEqual(expires?["seconds"] as? Int, 60)
        let session = try XCTUnwrap(body["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "realtime")
        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2.1")
        XCTAssertEqual(session["output_modalities"] as? [String], ["audio"])
        XCTAssertEqual((session["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["get_ios_version", "look", "do"])
        XCTAssertEqual(session["tool_choice"] as? String, "auto")
        XCTAssertEqual(session["parallel_tool_calls"] as? Bool, false)
        XCTAssertEqual((session["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        let instructions = try XCTUnwrap(session["instructions"] as? String)
        XCTAssertTrue(instructions.hasPrefix("You are Poki, a voice assistant that operates the user's iPhone with tools."), instructions)
        XCTAssertTrue(instructions.contains("With do, open an app by its bundle id"), instructions)
        let audio = session["audio"] as? [String: Any]
        let input = audio?["input"] as? [String: Any]
        let turn = input?["turn_detection"] as? [String: Any]
        XCTAssertEqual(turn?["type"] as? String, "server_vad")
        XCTAssertEqual(turn?["silence_duration_ms"] as? Int, 450)
        XCTAssertEqual((input?["transcription"] as? [String: Any])?["model"] as? String, "gpt-4o-mini-transcribe")
        XCTAssertEqual((audio?["output"] as? [String: Any])?["voice"] as? String, "marin")

        // A step runs on the phone.
        h.link.play(["type": "response.created", "response": ["id": "r1"]],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"actions":[{"launch":"com.apple.Preferences"}]}"#]])
        await h.time.settle()
        XCTAssertEqual(h.voice.calls.first?.state, .done)
        XCTAssertEqual(h.voice.calls.first?.output, "Settings is open")
        XCTAssertEqual(NetworkStub.taken.map(\.url), [NetworkStub.clientSecrets])
        h.voice.stop()

        key = nil
        await h.talk()
        XCTAssertEqual(NetworkStub.taken.map(\.url), [NetworkStub.clientSecrets, NetworkStub.bridgeAddress + "/token"])
        XCTAssertEqual(NetworkStub.taken.last?.authorization, nil)
        XCTAssertEqual(h.link.secret, "ek_test")
    }

    /// OpenAI turns the phone's key down and its answer quotes the key, in full and masked: the voice page
    /// and Poki's log say what went wrong without any of it.
    func testOpenAIRefusingThePhonesKeyNeverShowsTheKey() async {
        NetworkStub.openAI = (401, #"{"error":{"message":"Incorrect API key provided: sk-test-phone-key. You can find your API key at https://platform.openai.com/account/api-keys (sk-proj-ab12****cd34).","type":"invalid_request_error"}}"#)
        let h = Harness(openAIKey: { "sk-test-phone-key" })
        await h.connect()
        guard case .lost(let why) = h.voice.phase else { return XCTFail("still \(h.voice.phase)") }
        XCTAssertTrue(why.contains("401"), why)
        XCTAssertTrue(why.contains("Incorrect API key"), why)
        for text in [why] + AppLog.shared.lines {
            XCTAssertFalse(text.contains("test-phone-key") || text.contains("ab12****cd34"), text)
        }
        XCTAssertTrue(h.links.isEmpty)
        XCTAssertEqual(h.microphone, [])
    }
}
