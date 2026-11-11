import AVFoundation

/// Keeps the app running in the background while a session is on, so the launcher's connections
/// (and with them the runner) stay up: a silent audio session mixed with whatever else is playing.
/// The Live Activity shows that Poki is running. Background hold measurements in Debug decide whether
/// this is enough.
@MainActor
final class KeepAlive {
    /// Keep-alives playing now (the session's and the pairing's). They share the app's one audio
    /// session, so only the last one to stop deactivates it.
    private static var playing = 0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var interruption: NSObjectProtocol?
    private var interrupted = false

    var state: KeepAliveState.Audio {
        .init(engine: engine != nil, running: engine?.isRunning == true, playerPlaying: player?.isPlaying == true, interrupted: interrupted)
    }
    var isPlaying: Bool { state == .playing }

    func start() throws {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { Self.release(session); throw NoBuffer() }
        buffer.frameLength = buffer.frameCapacity // zero-filled: silence
        engine.mainMixerNode.outputVolume = 0
        do { try engine.start() } catch { Self.release(session); throw error }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine = engine
        self.player = player
        interrupted = false
        Self.playing += 1
        // Another app's audio can interrupt the session; start again when it ends.
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self, let engine = self.engine else { return }
                if type == .began { self.interrupted = true; return }
                try? AVAudioSession.sharedInstance().setActive(true)
                if !engine.isRunning { try? engine.start(); player.play() }
            }
        }
    }

    /// Only a keep-alive that is playing stops anything, so stopping one never silences another.
    func stop() {
        guard let engine else { return }
        engine.stop(); self.engine = nil; player = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        Self.playing -= 1
        Self.release(AVAudioSession.sharedInstance())
    }

    private struct NoBuffer: Error {}

    private static func release(_ session: AVAudioSession) {
        if playing == 0 { try? session.setActive(false, options: [.notifyOthersOnDeactivation]) }
    }
}
