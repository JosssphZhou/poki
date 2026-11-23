import AVFoundation
import WatchKit

@MainActor
final class WatchVoiceCuePlayer {
    private var player: AVAudioPlayer?
    private var toneCache: [WatchVoiceCue: Data] = [:]

    func play(_ cue: WatchVoiceCue) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let data = toneData(for: cue)
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.prepareToPlay()
            guard audioPlayer.play() else {
                playFallbackHaptic(for: cue)
                return
            }
            player = audioPlayer
        } catch {
            playFallbackHaptic(for: cue)
        }
    }

    func playFailureHaptic() {
        WKInterfaceDevice.current().play(.failure)
    }

    private func toneData(for cue: WatchVoiceCue) -> Data {
        if let cached = toneCache[cue] { return cached }
        let generated = WatchVoiceTone.wavData(for: cue)
        toneCache[cue] = generated
        return generated
    }

    private func playFallbackHaptic(for cue: WatchVoiceCue) {
        switch cue {
        case .start:
            WKInterfaceDevice.current().play(.start)
        case .mute, .unmute:
            WKInterfaceDevice.current().play(.click)
        case .end:
            WKInterfaceDevice.current().play(.stop)
        }
    }
}
