#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import WebRTC

/// A recorded microphone and captured speaker for real WebRTC checks in a simulator.
/// Input is 48 kHz mono PCM16. Neither audio nor credentials are sent to a test server.
final class VoiceReplay: NSObject, RTCAudioDevice {
    static func fromEnvironment() -> VoiceReplay? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["POKI_VOICE_INPUT"], let input = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let directory = environment["POKI_VOICE_CAPTURE"] else { return nil }
        return VoiceReplay(input: input, directory: directory)
    }

    let deviceInputSampleRate = 48000.0
    let inputIOBufferDuration = 0.01
    let inputNumberOfChannels = 1
    let inputLatency = 0.0
    let deviceOutputSampleRate = 48000.0
    let outputIOBufferDuration = 0.01
    let outputNumberOfChannels = 1
    let outputLatency = 0.0
    private(set) var isInitialized = false
    private(set) var isPlayoutInitialized = false
    private(set) var isPlaying = false
    private(set) var isRecordingInitialized = false
    private(set) var isRecording = false
    private var delegate: RTCAudioDeviceDelegate?
    private var timer: DispatchSourceTimer?
    private let input: Data
    private var position = 0
    private var ready = false
    private var captured = Data()
    private var started: TimeInterval?
    private var inputStarted: TimeInterval?
    private let output: URL

    private init(input: Data, directory: String) {
        self.input = input
        output = URL(fileURLWithPath: directory).appendingPathComponent("voice-\(UUID().uuidString.prefix(8))")
    }

    func beginInput() {
        delegate?.dispatchAsync { [weak self] in self?.ready = true }
    }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate
        isInitialized = true
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "poki.voice.replay"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.delegate?.dispatchAsync { [weak self] in self?.tick() }
        }
        self.timer = timer
        timer.resume()
        return true
    }

    private func tick() {
        guard let delegate else { return }
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mFlags = .sampleTimeValid
        timestamp.mSampleTime = Double(captured.count / 2)
        if isPlaying {
            if started == nil { started = Date().timeIntervalSince1970 }
            var samples = [Int16](repeating: 0, count: 480)
            samples.withUnsafeMutableBytes { bytes in
                var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 960, mData: bytes.baseAddress))
                _ = delegate.getPlayoutData(&flags, &timestamp, 0, 480, &buffer)
                captured.append(contentsOf: bytes.bindMemory(to: UInt8.self))
            }
        }
        if isRecording {
            var bytes = Data(repeating: 0, count: 960)
            if ready, position < input.count {
                if inputStarted == nil { inputStarted = Date().timeIntervalSince1970 }
                let end = min(position + 960, input.count)
                bytes.replaceSubrange(0..<(end - position), with: input[position..<end])
                position = end
            }
            bytes.withUnsafeBytes { bytes in
                var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 960, mData: UnsafeMutableRawPointer(mutating: bytes.baseAddress)))
                _ = delegate.deliverRecordedData(&flags, &timestamp, 0, 480, &buffer, nil, nil)
            }
        }
    }

    private func save() {
        guard let started else { return }
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? captured.write(to: output.appendingPathExtension("pcm"), options: .atomic)
        let metadata: [String: Any] = ["startUnix": started, "inputUnix": inputStarted ?? 0, "sampleRate": 48000, "frames": captured.count / 2]
        if let data = try? JSONSerialization.data(withJSONObject: metadata) { try? data.write(to: output.appendingPathExtension("json"), options: .atomic) }
    }

    func terminateDevice() -> Bool {
        timer?.cancel()
        timer = nil
        save()
        delegate = nil
        isInitialized = false
        isPlaying = false
        isRecording = false
        return true
    }
    func initializePlayout() -> Bool { isPlayoutInitialized = true; return true }
    func startPlayout() -> Bool { isPlaying = true; return true }
    func stopPlayout() -> Bool { isPlaying = false; save(); return true }
    func initializeRecording() -> Bool { isRecordingInitialized = true; return true }
    func startRecording() -> Bool { isRecording = true; return true }
    func stopRecording() -> Bool { isRecording = false; return true }
}
#endif
