#if DEBUG && targetEnvironment(simulator)
import Foundation

/// `-pokiTalkRehearsal 1`, in a simulator's development build: Talk with Poki connects to this instead of
/// OpenAI. It plays one talk's worth of the Realtime API's events into VoiceModel, the way the unit
/// tests' FakeConnection does, so every state of the talk's screens can be seen without a key, a
/// microphone or sound: Poki listens, hears a request, thinks, runs a step on the phone (a stand-in
/// that only waits), speaks, is spoken over, and answers again. VoiceModel handles the events as it
/// would OpenAI's: its phases, lines and the end after a quiet while are the real ones. Nothing is
/// sent anywhere and no step runs on the phone.
///
/// `-pokiTalkRehearsal lost` drops the connection at the end, for the talk's error state.
/// `-pokiTalkRehearsal behaviors` exercises quiet, pause, and continue transitions in order.
/// `-pokiTalkHold <state>` stops the script where the talk first reaches that state (`TalkState.named`),
/// for a screenshot of it.
final class TalkRehearsal: VoiceConnection, @unchecked Sendable {
    static var asked: Bool { UserDefaults.standard.string(forKey: "pokiTalkRehearsal") != nil }
    private static var mode: String { UserDefaults.standard.string(forKey: "pokiTalkRehearsal") ?? "" }
    private static var loses: Bool { mode == "lost" }
    private static var behaviors: Bool { mode == "behaviors" }
    static var hold: TalkState? { UserDefaults.standard.string(forKey: "pokiTalkHold").flatMap(TalkState.named) }

    /// The stand-in for the key exchange, which a rehearsal skips. `do` is on the phone's list, so the
    /// step goes to `step()` below instead of a voice bridge.
    static let token = VoiceBridge.Token(value: "rehearsal", model: "rehearsal", local_tools: ["do"])

    /// The step on the phone: it waits as long as a short one takes and says it went well. Held for a
    /// screenshot, it does not come back.
    static func step() async -> PhoneAnswer {
        let delay: Double = hold == .acting ? 3600 : (behaviors ? 1.2 : 3.2)
        try? await Task.sleep(for: .seconds(delay))
        return ("done", false, nil)
    }

    private let onEvent: @MainActor ([String: Any]) -> Void
    private let onClosed: @MainActor (String) -> Void
    private var script: Task<Void, Never>?

    init(onEvent: @escaping @MainActor ([String: Any]) -> Void, onClosed: @escaping @MainActor (String) -> Void) {
        self.onEvent = onEvent
        self.onClosed = onClosed
    }

    func connect(secret: String, base: URL?, microphone: Bool, direct: Bool) async throws {
        try await Task.sleep(for: .milliseconds(Self.hold == .connecting ? 3_600_000 : 900))
        let zh = AppLocalization.language.hasPrefix("zh")
        let asks = zh ? "打开设置，把屏幕调亮一点" : "Open Settings and turn the brightness up a little"
        let answer = zh ? "已经把亮度调高了。现在大约是百分之八十，还需要" : "Brightness is up. It’s at about eighty percent now, do you want"
        let stops = zh ? "够了，谢谢" : "That’s enough, thanks"
        let closing = zh ? "好的。" : "Okay."
        let step: [String: Any] = ["type": "function_call", "call_id": "rehearsal-step", "name": "do", "arguments": "{}"]
        // Seconds from the connection, what OpenAI would send then, and the state the talk is in after it.
        let turn: [(Double, [String: Any], TalkState?)] = Self.behaviors ? Self.behaviorTurn() : [
            (0.3, ["type": "session.created"], .listening),
            (1.9, ["type": "input_audio_buffer.speech_started"], .hearing),
            (4.3, ["type": "input_audio_buffer.speech_stopped"], .thinking),
            (4.6, ["type": "conversation.item.input_audio_transcription.completed", "transcript": asks], nil),
            (5.6, ["type": "response.created", "response": ["id": "rehearsal-1"]], nil),
            (5.8, ["type": "response.output_item.done", "item": step], .acting),
            (5.9, ["type": "response.done", "response": ["id": "rehearsal-1"]], nil),
            // The step takes 3.2 s; VoiceModel hands its result over and asks for the answer.
            (9.4, ["type": "response.created", "response": ["id": "rehearsal-2"]], nil),
            (9.6, ["type": "output_audio_buffer.started"], nil),
            (9.7, ["type": "response.output_audio_transcript.done", "transcript": answer], .speaking),
            // Spoken over.
            (13.2, ["type": "input_audio_buffer.speech_started"], .interrupted),
            (13.3, ["type": "output_audio_buffer.cleared"], nil),
            (13.4, ["type": "response.done", "response": ["id": "rehearsal-2"]], nil),
            (15.6, ["type": "input_audio_buffer.speech_stopped"], nil),
            (15.8, ["type": "conversation.item.input_audio_transcription.completed", "transcript": stops], nil),
            (16.6, ["type": "response.created", "response": ["id": "rehearsal-3"]], nil),
            (16.8, ["type": "output_audio_buffer.started"], nil),
            (16.9, ["type": "response.output_audio_transcript.done", "transcript": closing], nil),
            (18.4, ["type": "response.done", "response": ["id": "rehearsal-3"]], nil),
            (18.5, ["type": "output_audio_buffer.stopped"], nil),
        ]
        let (onEvent, onClosed) = (onEvent, onClosed)
        let (hold, loses) = (Self.hold, Self.loses)
        script = Task { @MainActor in
            var clock = 0.0
            for (at, event, reaches) in turn {
                try? await Task.sleep(for: .seconds(at - clock))
                guard !Task.isCancelled else { return }
                clock = at
                onEvent(event)
                if let hold, reaches == hold { return }
                if hold?.isFailed == true, reaches == .listening { break }
            }
            guard loses || hold?.isFailed == true else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            onClosed("rehearsal")
        }
    }

    private static func logOnMain(_ message: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { AppLog.shared.add("voice", message) }
        } else {
            Task { @MainActor in AppLog.shared.add("voice", message) }
        }
    }

    func send(_ event: [String: Any]) -> Bool {
        if Self.behaviors, let type = event["type"] as? String {
            Self.logOnMain("rehearsal sent: \(type)")
        }
        return true
    }

    func connectLive(microphone: Bool, direct: Bool, exchange: (String) async throws -> String) async throws {
        throw VoiceError.noBridge
    }

    func hasRemoteSpeech() async -> Bool { false }

    func setRemoteVolume(_ value: Double) {
        if Self.behaviors {
            Self.logOnMain("rehearsal remoteVolume=\(value)")
        }
    }

    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    func close() { script?.cancel() }

    private static func behaviorTurn() -> [(Double, [String: Any], TalkState?)] {
        let step1: [String: Any] = ["type": "function_call", "call_id": "beh-step-1", "name": "do", "arguments": #"{"step":"open-settings"}"#]
        let step2: [String: Any] = ["type": "function_call", "call_id": "beh-step-2", "name": "do", "arguments": #"{"step":"scroll-while-quiet"}"#]
        let step3: [String: Any] = ["type": "function_call", "call_id": "beh-step-3", "name": "do", "arguments": #"{"step":"blocked-while-paused"}"#]
        let step4: [String: Any] = ["type": "function_call", "call_id": "beh-step-4", "name": "do", "arguments": #"{"step":"resumed-finish"}"#]
        return [
            (0.3, ["type": "session.created"], .listening),
            (1.2, ["type": "input_audio_buffer.speech_started"], .hearing),
            (2.2, ["type": "input_audio_buffer.speech_stopped"], .thinking),
            (2.4, ["type": "conversation.item.input_audio_transcription.completed", "transcript": "打开设置查电池健康"], nil),
            (2.8, ["type": "response.created", "response": ["id": "beh-r1"]], nil),
            (3.0, ["type": "output_audio_buffer.started"], .speaking),
            (3.1, ["type": "response.output_audio_transcript.done", "transcript": "好，我来打开设置帮你看电池健康。"], nil),
            (3.3, ["type": "response.output_item.done", "item": step1], .acting),
            (5.0, ["type": "output_audio_buffer.started"], .speaking),
            (5.5, ["type": "conversation.item.input_audio_transcription.completed", "transcript": "别说话"], nil),
            (6.0, ["type": "response.output_item.done", "item": step2], .acting),
            (8.2, ["type": "conversation.item.input_audio_transcription.completed", "transcript": "暂停操作"], nil),
            (8.6, ["type": "response.output_item.done", "item": step3], nil),
            (10.5, ["type": "conversation.item.input_audio_transcription.completed", "transcript": "继续"], nil),
            (11.0, ["type": "response.output_item.done", "item": step4], .acting),
            (12.8, ["type": "response.done", "response": ["id": "beh-r1"]], nil),
            (13.0, ["type": "output_audio_buffer.stopped"], nil),
        ]
    }
}

extension TalkState {
    /// A state by its name in `-pokiTalkHold`.
    static func named(_ name: String) -> TalkState? {
        switch name {
        case "connecting": .connecting
        case "listening": .listening
        case "hearing": .hearing
        case "thinking": .thinking
        case "acting": .acting
        case "speaking": .speaking
        case "interrupted": .interrupted
        case "failed": .failed(TalkState.connectionLost)
        default: nil
        }
    }
}
#endif
