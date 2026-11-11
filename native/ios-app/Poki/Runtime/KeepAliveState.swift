/// What holds Poki up in the background right now, read from each keep-alive's real state. No iOS
/// frameworks, so the decision is tested on a Mac.
struct KeepAliveState: Equatable {
    enum Audio: Equatable {
        case off, stopped, playing

        init(engine: Bool, running: Bool, playerPlaying: Bool) {
            self = engine ? .playing : .off
        }
    }

    enum Holder: Equatable { case continuedRun, voice, silentAudio, nothing }

    var on: Bool
    var continuedRun: Bool
    var voice: Bool
    var audio: Audio

    /// Nil while Poki is off. `.nothing` means iOS will suspend Poki once it leaves the screen.
    var holder: Holder? {
        guard on else { return nil }
        if continuedRun { return .continuedRun }
        if voice { return .voice }
        return audio == .playing ? .silentAudio : .nothing
    }
}
