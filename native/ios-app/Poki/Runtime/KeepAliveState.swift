/// What holds Poki up in the background right now, read from each keep-alive's real state. No iOS
/// frameworks, so the decision is tested on a Mac.
struct KeepAliveState: Equatable {
    /// The silent audio. An interruption, a route or configuration change, or a media services reset
    /// stops the engine without releasing it: `.stopped`, which holds nothing up. `interrupted`: another
    /// app's audio (a call, an alarm) interrupted it, and it has not started again from scratch since.
    enum Audio: Equatable {
        case off, stopped, playing

        init(engine: Bool, running: Bool, playerPlaying: Bool, interrupted: Bool) {
            self = !engine ? .off : running && playerPlaying ? .playing : .stopped
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
