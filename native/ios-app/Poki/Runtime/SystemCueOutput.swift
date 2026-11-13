import AudioToolbox
import Foundation

@MainActor
final class SystemCueOutput: CueSoundOutput {
    private let queue = DispatchQueue(label: "poki.cue-sounds", qos: .userInitiated)
    private let bank = CueSoundBank()

    init() {
        let bank = bank
        queue.async { bank.prepare() }
    }

    func play(_ cue: TaskCue) {
        let bank = bank
        queue.async {
            guard UserDefaults.standard.object(forKey: CueSounds.enabledKey) as? Bool ?? true else { return }
            bank.play(cue)
        }
    }
}

// Only the serial cue queue accesses the IDs. System sounds respect the silent switch without
// changing the audio session used by voice and background keep-alive.
private final class CueSoundBank: @unchecked Sendable {
    private var sounds: [TaskCue: SystemSoundID] = [:]

    func prepare() {
        for cue in TaskCue.allCases {
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "caf") else {
                NSLog("Poki: missing cue sound %@", cue.rawValue)
                continue
            }
            var id: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
            if status == kAudioServicesNoError { sounds[cue] = id }
            else { NSLog("Poki: could not prepare cue %@ (%d)", cue.rawValue, status) }
        }
    }

    func play(_ cue: TaskCue) {
        if let id = sounds[cue] { AudioServicesPlaySystemSound(id) }
    }

    deinit {
        for id in sounds.values { AudioServicesDisposeSystemSoundID(id) }
    }
}
