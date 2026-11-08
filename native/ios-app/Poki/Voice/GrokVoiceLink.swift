import AVFoundation
import Foundation

/// xAI's Realtime WebSocket carries both JSON events and 24 kHz PCM audio.
@MainActor
final class GrokVoiceLink: NSObject, VoiceConnection, URLSessionTaskDelegate {
    static let model = "grok-voice-latest"

    enum Failure: LocalizedError {
        case signInRequired, accessDenied, configuration, connection, microphone

        var errorDescription: String? {
            switch self {
            case .signInRequired: String(localized: "Sign in with Grok again to use live voice.")
            case .accessDenied: String(localized: "xAI refused live voice for this Grok account.")
            case .configuration: String(localized: "xAI rejected the Grok voice session settings.")
            case .connection: String(localized: "Poki could not connect to Grok live voice.")
            case .microphone: String(localized: "Poki could not prepare the microphone for Grok live voice.")
            }
        }
    }

    private let onEvent: @MainActor ([String: Any]) -> Void
    private let onClosed: @MainActor (String) -> Void
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private lazy var network = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var pending: [String] = []
    private var closed = false
    private var audioStarted = false
    private var tapInstalled = false
    private var queuedAudio = 0
    private var playbackGeneration = 0
    private var outputAudible = true
    private var ignoreMicrophoneUntil: ContinuousClock.Instant?
    private var caption: InputCaption?
    private var captionDeadline: Task<Void, Never>?

    private struct InputCaption {
        var itemID: String?
        var candidates: [String: Bool] = [:]
        var ended = false
    }

    init(onEvent: @escaping @MainActor ([String: Any]) -> Void,
         onClosed: @escaping @MainActor (String) -> Void) {
        self.onEvent = onEvent
        self.onClosed = onClosed
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                                completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func connect(secret: String, microphone: Bool, direct _: Bool) async throws {
        guard !closed else { throw CancellationError() }
        var request = URLRequest(url: URL(string: "wss://api.x.ai/v1/realtime?model=\(Self.model)")!)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let socket = network.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        let timeout = Task {
            try await Task.sleep(for: .seconds(15))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }
        do {
            var configured = false
            while !configured {
                let event = try await receive(socket)
                switch event["type"] as? String {
                case "session.created":
                    let configuration = try JSONSerialization.data(withJSONObject: VoiceDirect.grokSession)
                    try await socket.send(.string(String(decoding: configuration, as: UTF8.self)))
                case "session.updated":
                    configured = true
                case "error":
                    throw Failure.configuration
                default:
                    break
                }
            }
        } catch {
            if closed || Task.isCancelled { throw CancellationError() }
            let status = (socket.response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { throw Failure.signInRequired }
            if status == 403 { throw Failure.accessDenied }
            throw (error as? Failure) ?? Failure.connection
        }
        guard self.socket === socket else { throw CancellationError() }
        try startAudio(microphone: microphone)
        onEvent(["type": "session.created"])
        reader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let self else { return }
                    self.handle(try await self.receive(socket))
                }
            } catch {
                self?.reportFailure(socket, reason: "Grok voice WebSocket closed")
            }
        }
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return [:]
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @discardableResult
    func send(_ event: [String: Any]) -> Bool {
        guard let socket else { return false }
        if event["type"] as? String == "output_audio_buffer.clear" {
            clearPlayback()
            return true
        }
        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return false }
        guard pending.count < 50 else {
            reportFailure(socket, reason: "Grok voice network is too slow")
            return false
        }
        pending.append(String(decoding: data, as: UTF8.self))
        if writer == nil {
            writer = Task { [weak self] in
                guard let self else { return }
                defer { self.writer = nil }
                do {
                    while self.socket === socket, !self.pending.isEmpty, !Task.isCancelled {
                        try await socket.send(.string(self.pending.removeFirst()))
                    }
                } catch {
                    self.reportFailure(socket, reason: "Could not send to Grok voice")
                }
            }
        }
        return true
    }

    private func reportFailure(_ socket: URLSessionWebSocketTask, reason: String) {
        guard self.socket === socket else { return }
        onClosed(reason)
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "response.output_audio.delta":
            if let encoded = event["delta"] as? String, let data = Data(base64Encoded: encoded) { play(data) }
        case "conversation.item.input_audio_transcription.completed":
            guard var caption else { return }
            let text = (event["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let id = event["item_id"] as? String
            let matches = id != nil && id == caption.itemID
            caption.candidates[text] = matches || (caption.candidates[text] ?? false)
            self.caption = caption
        case "input_audio_buffer.speech_started":
            if microphoneIsBlocked(at: .now) { return }
            finishCaption()
            caption = InputCaption(itemID: event["item_id"] as? String)
            clearPlayback()
            onEvent(event)
        case "input_audio_buffer.speech_stopped", "input_audio_buffer.committed":
            if var caption {
                if let id = event["item_id"] as? String { caption.itemID = id }
                if !caption.ended {
                    caption.ended = true
                    captionDeadline = Task { [weak self] in
                        do { try await Task.sleep(for: .milliseconds(1000)) }
                        catch { return }
                        self?.finishCaption()
                    }
                }
                self.caption = caption
            }
            onEvent(event)
        case "response.function_call_arguments.done":
            guard let callID = event["call_id"] as? String, let name = event["name"] as? String else { return }
            onEvent(["type": "response.output_item.done",
                     "item": ["type": "function_call", "call_id": callID, "name": name,
                              "arguments": event["arguments"] as? String ?? "{}"]])
        case "error":
            let server = event["error"] as? [String: Any]
            var failure = ["message": String(localized: "Grok reported a live voice error.")]
            if let id = server?["event_id"] as? String { failure["event_id"] = id }
            onEvent(["type": "error", "error": failure])
        default:
            onEvent(event)
        }
    }

    private func finishCaption() {
        captionDeadline?.cancel()
        captionDeadline = nil
        guard let caption else { return }
        self.caption = nil
        guard caption.ended else { return }
        let matched = caption.candidates.filter { $0.value }.keys
        let candidates = matched.isEmpty ? Array(caption.candidates.keys) : Array(matched)
        // A caption is only a display aid. Never show conflicting fragments as separate user messages.
        let text = candidates.count == 1 ? candidates[0] : (Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "［语音指令］" : "[Voice command]")
        onEvent(["type": "conversation.item.input_audio_transcription.completed", "transcript": text])
    }

    private func startAudio(microphone: Bool) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        audioStarted = true
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        if microphone {
            let input = engine.inputNode
            try input.setVoiceProcessingEnabled(true)
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: format, to: pcm) else {
                throw Failure.microphone
            }
            Self.installTap(input, format: format, pcm: pcm, converter: converter) { [weak self] data, capturedAt in
                guard let self, !self.microphoneIsBlocked(at: capturedAt) else { return }
                self.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
            }
            tapInstalled = true
        }
        engine.prepare()
        try engine.start()
        player.play()
    }

    nonisolated private static func installTap(_ input: AVAudioInputNode, format: AVAudioFormat,
                                                pcm: AVAudioFormat, converter: AVAudioConverter,
                                                deliver: @escaping @MainActor (Data, ContinuousClock.Instant) -> Void) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            let count = AVAudioFrameCount(ceil(Double(buffer.frameLength) * pcm.sampleRate / format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: count) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in
                state.pointee = supplied ? .noDataNow : .haveData
                defer { supplied = true }
                return supplied ? nil : buffer
            }
            guard status != .error, let samples = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
            let data = Data(bytes: samples, count: Int(converted.frameLength) * 2)
            let capturedAt = ContinuousClock.now
            Task { @MainActor in deliver(data, capturedAt) }
        }
    }

    private func play(_ data: Data) {
        let count = data.count / 2
        guard count > 0, data.count.isMultiple(of: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        data.withUnsafeBytes { bytes in
            for i in 0..<count {
                let value = UInt16(bytes[i * 2]) | (UInt16(bytes[i * 2 + 1]) << 8)
                samples[i] = Float(Int16(bitPattern: value)) / 32_768
            }
        }
        let wasIdle = queuedAudio == 0
        queuedAudio += 1
        let generation = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.audioPlayed(generation: generation) }
        }
        if wasIdle { onEvent(["type": "output_audio_buffer.started"]) }
    }

    private func audioPlayed(generation: Int) {
        guard generation == playbackGeneration, queuedAudio > 0 else { return }
        queuedAudio -= 1
        if queuedAudio == 0 {
            keepMicrophoneQuietAfterOutput()
            onEvent(["type": "output_audio_buffer.stopped"])
        }
    }

    private func microphoneIsBlocked(at time: ContinuousClock.Instant) -> Bool {
        (outputAudible && queuedAudio > 0) || (ignoreMicrophoneUntil.map { time < $0 } ?? false)
    }

    private func keepMicrophoneQuietAfterOutput() {
        if outputAudible { ignoreMicrophoneUntil = ContinuousClock.now.advanced(by: .milliseconds(300)) }
    }

    private func clearPlayback() {
        if queuedAudio > 0 { keepMicrophoneQuietAfterOutput() }
        playbackGeneration += 1
        queuedAudio = 0
        player.stop()
        if engine.isRunning { player.play() }
        onEvent(["type": "output_audio_buffer.cleared"])
    }

    func setRemoteVolume(_ value: Double) {
        if value <= 0 && queuedAudio > 0 { keepMicrophoneQuietAfterOutput() }
        outputAudible = value > 0
        player.volume = Float(value)
    }

    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}

    func close() {
        guard !closed else { return }
        closed = true
        finishCaption()
        let closing = socket
        socket = nil
        reader?.cancel()
        writer?.cancel()
        pending.removeAll()
        closing?.cancel(with: .normalClosure, reason: nil)
        network.finishTasksAndInvalidate()
        playbackGeneration += 1
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if audioStarted {
            player.stop()
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioStarted = false
        }
    }
}
