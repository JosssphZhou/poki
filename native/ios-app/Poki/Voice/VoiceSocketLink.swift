// Adapted from pull request #61 (commit deab77e3, native/ios-app/Poki/Voice/GrokVoiceLink.swift,
// by xiaweiyi713), under this repository's AGPL-3.0-only license.
// Changed: extracted the provider-agnostic WebSocket and AVAudioEngine PCM transport behind
// VoiceSocketAdapter, moved microphone capture to 16 kHz Int16 mono PCM with voice processing enabled
// before graph wiring, and removed playback-time microphone blocking so hardware echo cancellation
// keeps barge-in active while Poki speaks.
import AVFoundation
import Foundation

struct VoiceSocketControls {
    var playPCM16LE: @MainActor (Data) -> Void
    var clearPlayback: @MainActor () -> Void
    var emitEvent: @MainActor ([String: Any]) -> Void
}

@MainActor
protocol VoiceSocketAdapter: AnyObject {
    var inputSampleRate: Double { get }
    var outputSampleRate: Double { get }
    func makeRequest(secret: String) throws -> URLRequest
    func handshake(send: (String) async throws -> Void,
                   receive: () async throws -> [String: Any]) async throws
    func encodeMicrophonePCM(_ pcm16LE: Data) -> [String: Any]?
    func translateClientEvent(_ event: [String: Any], controls: VoiceSocketControls) -> [[String: Any]]
    func translateServerMessage(_ message: [String: Any], controls: VoiceSocketControls)
    /// `closeCode` is 0 and `closeReason` empty when the server sent no close frame.
    func mapConnectionError(_ error: Error, httpStatus: Int, closeCode: Int, closeReason: String) -> Error
}

extension VoiceSocketAdapter {
    var inputSampleRate: Double { 16_000 }
    var outputSampleRate: Double { 24_000 }
}

struct VoiceSocketPlaybackQueue {
    enum Transition: Equatable {
        case started
        case stopped
        case cleared
    }

    private(set) var generation = 0
    private(set) var pendingBuffers = 0

    mutating func enqueue() -> (generation: Int, transition: Transition?) {
        let wasIdle = pendingBuffers == 0
        pendingBuffers += 1
        return (generation, wasIdle ? .started : nil)
    }

    mutating func complete(generation finished: Int) -> Transition? {
        guard finished == generation, pendingBuffers > 0 else { return nil }
        pendingBuffers -= 1
        return pendingBuffers == 0 ? .stopped : nil
    }

    mutating func clear() -> Transition {
        generation += 1
        pendingBuffers = 0
        return .cleared
    }

    mutating func invalidate() {
        generation += 1
        pendingBuffers = 0
    }
}

enum VoiceSocketFailure: LocalizedError {
    case microphone

    var errorDescription: String? {
        switch self {
        case .microphone:
            AppLocalization.text(LocalizedStringResource("Poki could not prepare the microphone for live voice."))
        }
    }
}

final class VoiceSocketLink: NSObject, VoiceConnection, URLSessionTaskDelegate, @unchecked Sendable {
    private static let maxPendingOutbound = 120

    private let adapter: VoiceSocketAdapter
    private let onEvent: @MainActor ([String: Any]) -> Void
    private let onClosed: @MainActor (String) -> Void
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat: AVAudioFormat
    private lazy var network = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var pending: [String] = []
    private var playback = VoiceSocketPlaybackQueue()
    private var closed = false
    private var audioStarted = false
    private var playerAttached = false
    private var tapInstalled = false
    private var remoteVolume: Float = 1.0
    private var capturedBytes = 0
    private var capturedChunks = 0
    private var playedBytes = 0

    @MainActor
    init(adapter: VoiceSocketAdapter,
         onEvent: @escaping @MainActor ([String: Any]) -> Void,
         onClosed: @escaping @MainActor (String) -> Void) {
        self.adapter = adapter
        self.onEvent = onEvent
        self.onClosed = onClosed
        self.playbackFormat = AVAudioFormat(standardFormatWithSampleRate: adapter.outputSampleRate, channels: 1)!
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials ride on the handshake request; never follow a redirect to another host.
        completionHandler(nil)
    }

    @MainActor
    func connect(secret: String, microphone: Bool, direct _: Bool) async throws {
        guard !closed else { throw CancellationError() }
        let request = try adapter.makeRequest(secret: secret)
        let socket = network.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        let timeout = Task {
            try await Task.sleep(for: .seconds(15))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }
        do {
            try await adapter.handshake(
                send: { frame in try await socket.send(.string(frame)) },
                receive: { try await self.receive(socket) }
            )
        } catch {
            if closed || Task.isCancelled { throw CancellationError() }
            let failure = mapFailure(error, socket)
            socket.cancel(with: .goingAway, reason: nil)
            self.socket = nil
            throw failure
        }
        guard !closed, self.socket === socket else { throw CancellationError() }
        try startAudio(microphone: microphone)
        onEvent(["type": "session.created"])
        reader = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    guard let self else { return }
                    let message = try await self.receive(socket)
                    self.handleServerMessage(message)
                }
            } catch {
                guard let self else { return }
                self.reportFailure(socket, reason: "voice WebSocket closed: \(self.mapFailure(error, socket).localizedDescription)")
            }
        }
    }

    /// The server's reason (a rejected key, a used-up quota) rides on the close frame or the HTTP status.
    @MainActor
    private func mapFailure(_ error: Error, _ socket: URLSessionWebSocketTask) -> Error {
        let status = (socket.response as? HTTPURLResponse)?.statusCode ?? 0
        let reason = socket.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return adapter.mapConnectionError(error, httpStatus: status, closeCode: socket.closeCode.rawValue, closeReason: reason)
    }

    @MainActor
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
        if Thread.isMainThread {
            return MainActor.assumeIsolated { sendOnMain(event) }
        }
        Task { @MainActor [weak self] in _ = self?.sendOnMain(event) }
        return true
    }

    @MainActor
    private func sendOnMain(_ event: [String: Any]) -> Bool {
        guard socket != nil, !closed else { return false }
        let frames = adapter.translateClientEvent(event, controls: controls)
        for frame in frames {
            if !enqueueWireObject(frame) { return false }
        }
        return true
    }

    @MainActor
    private func enqueueWireObject(_ object: [String: Any]) -> Bool {
        guard let socket, !closed,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        guard pending.count < Self.maxPendingOutbound else {
            reportFailure(socket, reason: "voice network is too slow")
            return false
        }
        pending.append(String(decoding: data, as: UTF8.self))
        if writer == nil {
            writer = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.writer = nil }
                do {
                    while self.socket === socket, !self.pending.isEmpty, !Task.isCancelled {
                        try await socket.send(.string(self.pending.removeFirst()))
                    }
                } catch {
                    self.reportFailure(socket, reason: "could not send to voice WebSocket")
                }
            }
        }
        return true
    }

    @MainActor
    private var controls: VoiceSocketControls {
        VoiceSocketControls(
            playPCM16LE: { [weak self] data in self?.play(data) },
            clearPlayback: { [weak self] in self?.clearPlayback() },
            emitEvent: { [weak self] event in self?.onEvent(event) }
        )
    }

    @MainActor
    private func handleServerMessage(_ message: [String: Any]) {
        guard !closed else { return }
        adapter.translateServerMessage(message, controls: controls)
    }

    @MainActor
    private func reportFailure(_ socket: URLSessionWebSocketTask, reason: String) {
        guard !closed, self.socket === socket else { return }
        closeOnMain()
        onClosed(reason)
    }

    // TODO: no observer for AVAudioEngineConfigurationChange or audio session interruptions yet; a route
    // change (headphones, a call) stops the engine and the talk goes silent until it ends.
    @MainActor
    private func startAudio(microphone: Bool) throws {
        let audio = AVAudioSession.sharedInstance()
        if microphone {
            try? audio.setActive(false)
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audio.setActive(true)
            let input = engine.inputNode
            // Enable hardware acoustic echo cancellation before wiring nodes, because voice processing
            // reconfigures the audio engine's I/O unit graph.
            #if targetEnvironment(simulator)
            try? input.setVoiceProcessingEnabled(true)
            #else
            try input.setVoiceProcessingEnabled(true)
            #endif
        } else {
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
        }
        audioStarted = true

        if !playerAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            playerAttached = true
        }
        player.volume = remoteVolume

        if microphone {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: adapter.inputSampleRate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: format, to: pcm) else {
                #if targetEnvironment(simulator)
                engine.prepare()
                try engine.start()
                player.play()
                return
                #else
                throw VoiceSocketFailure.microphone
                #endif
            }
            Self.installTap(input, format: format, pcm: pcm, converter: converter) { [weak self] data in
                guard let self, !self.closed else { return }
                self.capturedBytes += data.count
                self.capturedChunks += 1
                if let frame = self.adapter.encodeMicrophonePCM(data) {
                    _ = self.enqueueWireObject(frame)
                }
            }
            tapInstalled = true
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    private static func installTap(_ input: AVAudioInputNode, format: AVAudioFormat,
                                   pcm: AVAudioFormat, converter: AVAudioConverter,
                                   deliver: @escaping @MainActor (Data) -> Void) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            let count = AVAudioFrameCount(ceil(Double(buffer.frameLength) * pcm.sampleRate / format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: count) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in
                if supplied {
                    state.pointee = .noDataNow
                    return nil
                }
                supplied = true
                state.pointee = .haveData
                return buffer
            }
            guard status != .error, let samples = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
            let data = Data(bytes: samples, count: Int(converted.frameLength) * 2)
            Task { @MainActor in deliver(data) }
        }
    }

    @MainActor
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
        playedBytes += data.count
        let enqueued = playback.enqueue()
        let generation = enqueued.generation
        if audioStarted, engine.isRunning {
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.audioPlayed(generation: generation) }
            }
        } else {
            Task { @MainActor [weak self] in self?.audioPlayed(generation: generation) }
        }
        if enqueued.transition == .started {
            onEvent(["type": "output_audio_buffer.started"])
        }
    }

    @MainActor
    private func audioPlayed(generation: Int) {
        if playback.complete(generation: generation) == .stopped {
            onEvent(["type": "output_audio_buffer.stopped"])
        }
    }

    @MainActor
    private func clearPlayback() {
        _ = playback.clear()
        if audioStarted {
            player.stop()
            if engine.isRunning { player.play() }
        }
        onEvent(["type": "output_audio_buffer.cleared"])
    }

    func setRemoteVolume(_ value: Double) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                remoteVolume = Float(value)
                player.volume = Float(value)
            }
        } else {
            Task { @MainActor [weak self] in
                self?.remoteVolume = Float(value)
                self?.player.volume = Float(value)
            }
        }
    }

    func diagnose(_ write: @escaping @MainActor (String) -> Void) {
        let now = VoiceLink.audioSession()
        Task { @MainActor in write(now) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                write("microphone after 3 s: sent \(self.capturedBytes) bytes in \(self.capturedChunks) chunks; received \(self.playedBytes) audio bytes")
            }
        }
    }

    func close() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { closeOnMain() }
        } else {
            Task { @MainActor [weak self] in self?.closeOnMain() }
        }
    }

    @MainActor
    private func closeOnMain() {
        guard !closed else { return }
        closed = true
        let closing = socket
        socket = nil
        reader?.cancel()
        writer?.cancel()
        reader = nil
        writer = nil
        pending.removeAll()
        closing?.cancel(with: .normalClosure, reason: nil)
        network.finishTasksAndInvalidate()
        playback.invalidate()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioStarted {
            player.stop()
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioStarted = false
        }
    }
}
