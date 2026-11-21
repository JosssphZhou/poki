import AudioToolbox
import Foundation

@MainActor
enum VoiceOpeningFeedback {
    private static var sound: SystemSoundID = 0

    /// The ready chime belongs to the button press, before connection setup.
    static func play() {
        #if !targetEnvironment(simulator)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        if sound == 0 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("poki-voice-ready.wav")
            do {
                try chime().write(to: url, options: .atomic)
                var id: SystemSoundID = 0
                guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return }
                var isUISound: UInt32 = 1
                AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size),
                                         &id, UInt32(MemoryLayout<UInt32>.size), &isUISound)
                sound = id
            } catch {
                return
            }
        }
        AudioServicesPlaySystemSound(sound)
        #endif
    }

    private static func chime() -> Data {
        let rate = 44_100
        let frames = Int(Double(rate) * 0.18)
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + frames * 2))
        wav.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        wav.append(contentsOf: "data".utf8)
        append(UInt32(frames * 2))
        for frame in 0..<frames {
            let t = Double(frame) / Double(rate)
            let first = t < 0.075 ? tone(at: t, frequency: 587.33, gain: 0.18, decay: 28) : 0
            let second = t >= 0.065 ? tone(at: t - 0.065, frequency: 880, gain: 0.22, decay: 24) : 0
            append(Int16((first + second) * Double(Int16.max)))
        }
        return wav
    }

    private static func tone(at t: Double, frequency: Double, gain: Double, decay: Double) -> Double {
        gain * min(1, t / 0.008) * exp(-t * decay) * sin(2 * .pi * frequency * t)
    }
}
