/// What holds Poki up in the background right now, read from each keep-alive's real state. No iOS
/// frameworks, so the decision is tested on a Mac.
struct KeepAliveState: Equatable {
    /// The silent audio. An interruption, a route or configuration change, or a media services reset
    /// stops the engine without releasing it: `.stopped`, which holds nothing up. `interrupted`: another
    /// app's audio (a call, an alarm) interrupted it, and it has not started again from scratch since.
    enum Audio: Equatable {
        case off, stopped, playing

        init(engine: Bool, running: Bool, playerPlaying: Bool, interrupted: Bool) {
            self = !engine ? .off : running && playerPlaying && !interrupted ? .playing : .stopped
        }
    }

    enum Holder: Equatable { case continuedRun, voice, silentAudio, nothing }

    var on: Bool
    var continuedRun: Bool
    var voice: Bool
    var audio: Audio
    /// How long iOS kept Poki suspended before now, as the heartbeat measures it (0 outside a beat).
    var suspendedFor: Double = 0

    /// Longer than a busy main thread holds up the heartbeat: iOS suspended Poki. A continued run that
    /// is really running never lets that happen, so one Poki still takes for running is gone (seen when
    /// the person stopped it in iOS's own UI and Poki heard no end).
    static let suspendedPastAStall: Double = 10

    /// Nil while Poki is off. `.nothing` means iOS will suspend Poki once it leaves the screen.
    var holder: Holder? {
        guard on else { return nil }
        if continuedRun, suspendedFor < Self.suspendedPastAStall { return .continuedRun }
        if voice { return .voice }
        return audio == .playing ? .silentAudio : .nothing
    }
}
