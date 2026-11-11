import AVFoundation
import CoreLocation
import Foundation
import UIKit

/// Keeps Poki running in the background while it is on, so the relay connection and the launcher stay
/// up. Silent audio does it; location is the backup only when it is needed: while a pairing waits in
/// Settings, and when the silent audio cannot play (it failed to start, or another app's audio
/// interrupted it), when iOS would otherwise suspend Poki mid-session. Then it is the coarsest
/// accuracy, with no indicator under Always Allow, and it stops again as soon as the audio is back.
/// The location is never read or sent anywhere.
@MainActor
@Observable
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var activity: CLBackgroundActivitySession?
    private let audio = KeepAlive()
    private(set) var authorization: CLAuthorizationStatus
    private(set) var isOn = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
    }

    var allowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var denied: Bool { authorization == .denied || authorization == .restricted }

    /// Always Allow lets Poki stay up without the location pill. iOS asks for While Using first and
    /// offers the upgrade on the second request.
    var always: Bool { authorization == .authorizedAlways }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestAlwaysAuthorization() }
    }

    /// Called while Poki is in front (iOS only starts background location from the foreground).
    func start() {
        guard !isOn else { return }
        isOn = true
        startHeartbeat()
        // iOS 26 and later: the system's continued processing task keeps Poki up, with no audio and
        // no location. Silent audio only when iOS refuses it or ends it early.
        if #available(iOS 26.0, *) {
            let run = ContinuedRun.shared
            continued = run
            run.onExpired = { [weak self] in
                guard let self, self.isOn else { return }
                self.continuedRunEnded = true
                self.startAudio(); self.watchInterruptions()
            }
            if run.begin(subtitle: String(localized: "Agents can reach this iPhone")) { return }
        }
        startAudio()
        watchInterruptions()
    }

    /// The iOS 26 continued run (typed loosely so this class builds for iOS 18).
    private var continued: AnyObject?
    /// iOS ended the continued run while Poki was on: it is asked for again when Poki comes to the front.
    private var continuedRunEnded = false

    /// Poki came to the front, the only time iOS grants a continued run. One iOS ended during this
    /// session is asked for again; once granted, the silent audio and location stop.
    func cameToFront() {
        if #available(iOS 26.0, *), isOn, continuedRunEnded, !continuedRunIsOn,
           ContinuedRun.shared.begin(subtitle: String(localized: "Agents can reach this iPhone")) {
            continuedRunEnded = false
            AppLog.shared.add("background", "continued run asked for again after iOS ended it: silent audio off")
            audio.stop()
            setAudioLost(false)
        }
        check("Poki came to the front")
    }

    /// iOS's continued processing task is holding Poki up, with its own "Poki is on" on the Lock
    /// Screen and in the island: Poki's Live Activity is not needed while nothing is happening.
    var continuedRunIsOn: Bool {
        if #available(iOS 26.0, *) { return (continued as? ContinuedRun)?.isRunning == true }
        return false
    }

    /// The line under "Poki is on" in iOS's own background-task UI: what Poki is doing now.
    func showStatus(_ text: String) {
        if #available(iOS 26.0, *) { (continued as? ContinuedRun)?.update(subtitle: text) }
    }

    /// Silent audio could not hold Poki up (it would be suspended): location stands in until it can.
    private(set) var audioLost = false
    private var observers: [NSObjectProtocol] = []

    private var state: KeepAliveState {
        KeepAliveState(on: isOn, continuedRun: continuedRunIsOn, voice: audioPaused, audio: audio.state)
    }

    private func startAudio() {
        do { try audio.start() } catch { AppLog.shared.add("background", "silent audio did not start: \(error.localizedDescription)") }
        setAudioLost(!audio.isPlaying)
    }

    /// Makes sure something holds Poki up. When nothing does, the silent audio starts again from
    /// scratch (only a fresh start is known to play), and location stands in if that fails. Called
    /// when the audio may have stopped, and as Poki comes to the front or leaves it, while a remedy
    /// can still start.
    func check(_ why: String) {
        guard let holder = state.holder else { return }
        guard holder == .nothing else { setAudioLost(false); return }
        AppLog.shared.add("background", "nothing keeps Poki running (\(why), silent audio \(audio.state), \(UIApplication.shared.applicationState == .active ? "in front" : "in the background")): starting the silent audio again")
        audio.stop()
        startAudio()
    }

    private func setAudioLost(_ lost: Bool) {
        guard lost != audioLost else { return }
        audioLost = lost
        if lost {
            AppLog.shared.add("background", allowed
                ? "silent audio not playing (\(audio.state)): location keeps Poki running until it is back (location \(always ? "Always" : "While Using"))"
                : "silent audio not playing (\(audio.state)) and location is not allowed: iOS may suspend Poki in the background")
            startLocation()
        } else {
            AppLog.shared.add("background", "\(state.holder.map { "\($0)" } ?? "off") holds Poki up: location off")
            if !pairingHold { stopLocation() }
        }
    }

    private func watchInterruptions() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self, self.isOn, !self.audioPaused else { return }
                switch type {
                case .began: self.setAudioLost(true)
                case .ended:
                    // KeepAlive restarts its engine on its own; check a moment later.
                    try? await Task.sleep(for: .seconds(1))
                    self.check("an audio interruption ended")
                @unknown default: break
                }
            }
        })
        // These stop the engine with no interruption: a route or format change (headphones,
        // Bluetooth), and a reset of the media services.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.check("the audio configuration changed") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.check("the media services were reset") }
        })
    }

    /// A beat every second while Poki is on. A longer gap is time iOS kept Poki suspended (its timers,
    /// a step's deadline among them, wait for it to resume), logged with what holds Poki up now.
    private var heartbeat: Timer?
    private var lastBeat = Date()

    private func startHeartbeat() {
        lastBeat = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func beat() {
        let now = Date(), gap = now.timeIntervalSince(lastBeat)
        defer { lastBeat = now }
        guard gap > 2.5 else { return }
        AppLog.shared.add("background", "iOS paused Poki for \(Int(gap.rounded())) s, from \(lastBeat.formatted(date: .omitted, time: .standard)); now \(state.holder.map { "\($0)" } ?? "off") holds Poki up, \(UIApplication.shared.applicationState == .active ? "in front" : "in the background")")
    }

    /// A voice conversation needs the audio session for the microphone; the voice-chat session keeps
    /// Poki running meanwhile. The silent audio comes back when it ends, if Poki is still on.
    /// While a voice conversation holds the audio session (it keeps Poki running itself).
    private var audioPaused = false
    func pauseAudio() { audioPaused = true; audio.stop() }
    func resumeAudio() {
        audioPaused = false
        guard isOn else { return }
        if #available(iOS 26.0, *), (continued as? ContinuedRun)?.isRunning == true { return }
        startAudio()
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        continuedRunEnded = false
        heartbeat?.invalidate(); heartbeat = nil
        if #available(iOS 26.0, *) { (continued as? ContinuedRun)?.end() }
        audioLost = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if !pairingHold { stopLocation() }
        audio.stop()
    }

    /// While a pairing waits in Settings, location keeps Poki running (with the silent audio), so the
    /// pairing listener answers when Settings connects. While Using is enough here: the updates start
    /// in front, and a CLBackgroundActivitySession carries them into the background (iOS shows its
    /// location indicator meanwhile). Ended when the pairing ends.
    private(set) var pairingHold = false
    func holdForPairing() {
        guard !pairingHold else { return }
        pairingHold = true
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        startPairingLocation()
    }

    func releasePairing() {
        guard pairingHold else { return }
        pairingHold = false
        activity?.invalidate(); activity = nil
        if isOn && audioLost { startLocation() } else { stopLocation() }
    }

    private func startPairingLocation() {
        guard pairingHold, allowed else { return }
        if activity == nil { activity = CLBackgroundActivitySession() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = !always
        manager.startUpdatingLocation()
    }

    private func startLocation() {
        if pairingHold { startPairingLocation(); return }
        guard audioLost, allowed else { stopLocation(); return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = !always
        if !always, activity == nil { activity = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
    }

    private func stopLocation() {
        manager.stopUpdatingLocation()
        activity?.invalidate(); activity = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.pairingHold || (self.isOn && self.audioLost) { self.startLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
