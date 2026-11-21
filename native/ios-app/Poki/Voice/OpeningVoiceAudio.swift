import AudioToolbox
import AVFoundation
import Foundation
import WebRTC

@MainActor
struct OpeningVoiceCapture {
    let audio: OpeningVoiceAudio
    let factory: RTCPeerConnectionFactory

    init(audio: OpeningVoiceAudio) {
        self.audio = audio
        factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil, audioDevice: audio)
    }
}

/// Captures the Action Button's opening words before WebRTC is ready. The same voice-processed
/// audio engine supplies WebRTC after connect, so there is no second microphone or audio upload.
final class OpeningVoiceAudio: NSObject, RTCAudioDevice, @unchecked Sendable {
    private static let sampleRate = 48_000.0
    // Enough speech for both bridge attempts, including token, offer and ICE timeouts.
    private static let maxOpeningFrames = Int(sampleRate) * 210
    private static let maxReplayBurst = Int(sampleRate / 10)
    private static let channelFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true
    )!

    private let engine = AVAudioEngine()
    @MainActor private var engineRunning = false
    private let lock = NSLock()
    // Revocation waits only for an audio delivery already in progress. The SDK is never
    // called with the device state lock held.
    private let sendLock = NSLock()
    private let session: Int
    private enum State {
        case buffering, sending, waitingForOwner(AsyncStream<Void>.Continuation), readyForDictation, stopped
    }
    private var delegate: RTCAudioDeviceDelegate?
    private var recording = false
    private var playing = false
    private var recordingInitialized = false
    private var playoutInitialized = false
    private var state = State.buffering
    private var deliveredToMedia = false
    private var openingFramesAwaitingMedia = 0
    private var remoteUsedInput = false
    private var overflow = false
    private var queued = [Int16]()
    private var readIndex = 0
    // The sending queue can advance before anything reaches the server. Keep an exact
    // recording so a transport failure can hand it to local dictation without gaps.
    private var recovery: [Int16] = []
    private var recoveryOverflow = false

    let deviceInputSampleRate = OpeningVoiceAudio.sampleRate
    let deviceOutputSampleRate = OpeningVoiceAudio.sampleRate
    let inputNumberOfChannels = 1
    let outputNumberOfChannels = 1
    let inputIOBufferDuration = 0.01
    let outputIOBufferDuration = 0.01
    let inputLatency: TimeInterval = 0
    let outputLatency: TimeInterval = 0
    var isInitialized: Bool { lock.withLock { delegate != nil } }
    var isRecordingInitialized: Bool { lock.withLock { recordingInitialized } }
    var isPlayoutInitialized: Bool { lock.withLock { playoutInitialized } }
    var isRecording: Bool { lock.withLock { recording } }
    var isPlaying: Bool { lock.withLock { playing } }
    var bufferedDuration: Duration {
        lock.withLock { .seconds(Double(queued.count - readIndex) / Self.sampleRate) }
    }
    var submittedOpeningToMedia: Bool {
        lock.withLock { deliveredToMedia && openingFramesAwaitingMedia == 0 }
    }

    init(session: Int) {
        self.session = session
        super.init()
    }

    @MainActor func startCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        var tapInstalled = false
        do {
            let microphone = engine.inputNode
            try microphone.setVoiceProcessingEnabled(true)
            let inputFormat = microphone.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let converter = AVAudioConverter(from: inputFormat, to: Self.channelFormat) else {
                throw VoiceError.noWebRTC
            }
            let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
            let player = makePlayer(format: playbackFormat)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            installTap(on: microphone, format: inputFormat, converter: converter)
            tapInstalled = true
            engine.prepare()
            try engine.start()
            engineRunning = true
        } catch {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    /// The media track drains the opening audio after session readiness, in front of any live input.
    func allowSending(session: Int) -> Bool {
        lock.withLock {
            guard session == self.session, !overflow else { return false }
            switch state {
            case .buffering:
                recovery = queued
                openingFramesAwaitingMedia = queued.count
                state = .sending
                return true
            case .sending:
                return true
            case .waitingForOwner, .readyForDictation, .stopped:
                return false
            }
        }
    }

    /// A model commit or a tool call can rule out repeating the request. Neither an RTP
    /// handoff nor a partial transcript confirms the whole recording.
    func markRemoteInputUsed(session: Int, phoneAction: Bool = false) {
        lock.withLock {
            guard session == self.session, case .sending = state, deliveredToMedia,
                  phoneAction || openingFramesAwaitingMedia == 0 else { return }
            remoteUsedInput = true
        }
    }

    func waitForOwnerToFinish(session: Int) -> AsyncStream<Void>? {
        sendLock.withLock {
            lock.withLock {
                guard session == self.session, !remoteUsedInput else { return nil }
                switch state {
                case .buffering: break
                case .sending:
                    queued = recovery
                    recovery.removeAll()
                    readIndex = 0
                    overflow = overflow || recoveryOverflow
                case .waitingForOwner, .readyForDictation, .stopped:
                    return nil
                }
                let (finished, continuation) = AsyncStream<Void>.makeStream()
                state = .waitingForOwner(continuation)
                return finished
            }
        }
    }

    @discardableResult
    func finishForDictation(session: Int, discard: Bool = false) -> Bool {
        lock.withLock {
            guard session == self.session, case .waitingForOwner(let completion) = state else { return false }
            if discard { overflow = true }
            state = .readyForDictation
            completion.finish()
            return true
        }
    }

    /// Revokes the media callback before stopping the engine or waiting for the peer to close.
    /// Only the local fallback may take the recording, once the utterance has finished.
    @MainActor func stopCapture(session: Int, forDictation: Bool = false) -> AVAudioPCMBuffer? {
        guard session == self.session else { return nil }
        let stopped: (wasRunning: Bool, completeRecording: [Int16]?) = sendLock.withLock {
            lock.withLock {
                if case .stopped = state { return (false, nil) }
                let samples: [Int16]?
                if forDictation, case .readyForDictation = state, !overflow { samples = queued }
                else { samples = nil }
                let previous = state
                state = .stopped
                delegate = nil
                queued.removeAll()
                recovery.removeAll()
                readIndex = 0
                if case .waitingForOwner(let completion) = previous { completion.finish() }
                return (true, samples)
            }
        }
        guard stopped.wasRunning else { return nil }
        if engineRunning {
            engineRunning = false
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard let samples = stopped.completeRecording, !samples.isEmpty,
              let audio = AVAudioPCMBuffer(pcmFormat: Self.channelFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = audio.int16ChannelData?[0] else { return nil }
        audio.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: $0.count) }
        return audio
    }

    private func installTap(on microphone: AVAudioInputNode, format: AVAudioFormat, converter: AVAudioConverter) {
        microphone.installTap(onBus: 0, bufferSize: 480, format: format) { [weak self] buffer, time in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * Self.sampleRate / format.sampleRate)) + 64
            guard let self, let pcm = AVAudioPCMBuffer(pcmFormat: Self.channelFormat, frameCapacity: capacity) else { return }
            var supplied = false
            let status = converter.convert(to: pcm, error: nil) { _, inputStatus in
                inputStatus.pointee = supplied ? .noDataNow : .haveData
                defer { supplied = true }
                return supplied ? nil : buffer
            }
            guard status != .error, pcm.frameLength > 0 else { return }
            self.input(pcm, at: time)
        }
    }

    func input(_ pcm: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let source = pcm.int16ChannelData?[0] else { return }
        let count = Int(pcm.frameLength)
        let sourceFrames = UnsafeBufferPointer(start: source, count: count)
        sendLock.withLock {
            let (delegate, audio): (RTCAudioDeviceDelegate?, [Int16]?) = lock.withLock {
                switch state {
                case .buffering, .waitingForOwner:
                    buffer(sourceFrames)
                    return (nil, nil)
                case .sending:
                    rememberForRecovery(sourceFrames)
                    guard recording, let delegate else {
                        buffer(sourceFrames)
                        return (nil, nil)
                    }
                    guard !overflow else { return (nil, nil) }
                    let packet = readIndex < queued.count ? drain(with: sourceFrames) : nil
                    openingFramesAwaitingMedia = max(0, openingFramesAwaitingMedia - (packet?.count ?? count))
                    deliveredToMedia = true
                    return (delegate, packet)
                case .readyForDictation, .stopped:
                    return (nil, nil)
                }
            }
            guard let delegate else { return }
            if let audio {
                audio.withUnsafeBufferPointer { deliver($0, to: delegate, at: time) }
            } else {
                deliver(sourceFrames, to: delegate, at: time)
            }
        }
    }

    private func rememberForRecovery(_ frames: UnsafeBufferPointer<Int16>) {
        guard !remoteUsedInput, !recoveryOverflow else { return }
        guard frames.count <= Self.maxOpeningFrames - recovery.count else {
            recoveryOverflow = true
            return
        }
        recovery.append(contentsOf: frames)
    }

    private func buffer(_ frames: UnsafeBufferPointer<Int16>) {
        let available = Self.maxOpeningFrames - (queued.count - readIndex)
        guard frames.count <= available else {
            overflow = true
            return
        }
        queued.append(contentsOf: frames)
    }

    private func drain(with frames: UnsafeBufferPointer<Int16>) -> [Int16] {
        // The same microphone stays on. Append new input behind the opening before draining
        // the next packet, so speech that crosses the handoff cannot overlap or disappear.
        queued.append(contentsOf: frames)
        // WebRTC divides this input into its normal audio frames. Hand off a bounded
        // extra block each time so the queue can catch up without removing samples.
        let burst = min(frames.count, Self.maxReplayBurst)
        let end = min(readIndex + frames.count + burst, queued.count)
        let packet = Array(queued[readIndex..<end])
        readIndex = end
        if readIndex == queued.count {
            queued.removeAll(keepingCapacity: true)
            readIndex = 0
        } else if readIndex >= Int(Self.sampleRate), readIndex >= queued.count / 2 {
            queued.removeFirst(readIndex)
            readIndex = 0
        }
        return packet
    }

    private func deliver(_ samples: UnsafeBufferPointer<Int16>, to delegate: RTCAudioDeviceDelegate, at time: AVAudioTime) {
        var flags: AudioUnitRenderActionFlags = []
        var timestamp = time.audioTimeStamp
        var audio = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: UInt32(samples.count * MemoryLayout<Int16>.stride),
            mData: UnsafeMutableRawPointer(mutating: samples.baseAddress)
        ))
        _ = delegate.deliverRecordedData(&flags, &timestamp, 0, UInt32(samples.count), &audio, nil, nil)
    }

    private func makePlayer(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [weak self] silent, timestamp, count, output in
            guard let self, let destination = output.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            let delegate = self.lock.withLock {
                if case .stopped = self.state { return nil as RTCAudioDeviceDelegate? }
                return self.playing ? self.delegate : nil
            }
            guard let delegate else {
                silent.pointee = true
                destination.update(repeating: 0, count: Int(count))
                return noErr
            }
            return withUnsafeTemporaryAllocation(of: Int16.self, capacity: Int(count)) { samples in
                var flags: AudioUnitRenderActionFlags = []
                var audio = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: count * UInt32(MemoryLayout<Int16>.stride), mData: samples.baseAddress
                ))
                let status = delegate.getPlayoutData(&flags, timestamp, 0, count, &audio)
                guard status == noErr else { return status }
                if flags.contains(.unitRenderAction_OutputIsSilence) {
                    silent.pointee = true
                    destination.update(repeating: 0, count: Int(count))
                } else {
                    for index in samples.indices { destination[index] = Float(samples[index]) / 32_768 }
                }
                return noErr
            }
        }
    }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        lock.withLock { self.delegate = delegate }
        return true
    }
    func terminateDevice() -> Bool {
        lock.withLock {
            delegate = nil
            recording = false
            playing = false
            recordingInitialized = false
            playoutInitialized = false
        }
        return true
    }
    func initializeRecording() -> Bool { lock.withLock { recordingInitialized = true }; return true }
    func initializePlayout() -> Bool { lock.withLock { playoutInitialized = true }; return true }
    func startRecording() -> Bool { lock.withLock { recording = true }; return true }
    func stopRecording() -> Bool { lock.withLock { recording = false }; return true }
    func startPlayout() -> Bool { lock.withLock { playing = true }; return true }
    func stopPlayout() -> Bool { lock.withLock { playing = false }; return true }
}
