import Foundation

// A talk that shows on the Live Activity and can be ended there is the interaction of pull request #250;
// the code is written here. The talk goes into the state's existing `voice` field, follows the talk's
// phase, and takes the Live Activity with it when it ends only if nothing else is on it.

/// The Live Activity during a talk with Poki, in front and while a step of the talk has Poki in another
/// app: it says whether Poki is listening, working or speaking, and its End ends the talk.
@MainActor
final class TalkActivity {
    private let voice: VoiceModel
    private let activity: ActivityController
    private let deviceName: @MainActor () -> String
    /// Poki is on: its Live Activity stays when the talk ends.
    private let keepsActivity: @MainActor () -> Bool
    /// The talk went off.
    private let ended: @MainActor () -> Void
    /// End on the Live Activity: what stops with the talk.
    private let endFromLiveActivityAction: (@MainActor () -> Void)?
    /// How long terminal voice states (`.ended`, `.failed`) stay visible before dismissing.
    var dismissAfter: Duration = .seconds(3)
    /// How often microphone loudness is sampled during `.hearing` to update waveform bar heights.
    var levelPollInterval: Duration = .seconds(1)
    private var shown: PokiState.Voice?
    private var shownStep: String?
    private var dismissTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var wasMidTurn = false
    /// What EndTalkIntent's notification reaches; it holds this weakly, so an ended TalkActivity hears nothing.
    private let mailbox: Mailbox

    init(voice: VoiceModel, activity: ActivityController, deviceName: @escaping @MainActor () -> String,
         keepsActivity: @escaping @MainActor () -> Bool, ended: @escaping @MainActor () -> Void = {},
         endFromLiveActivity: (@MainActor () -> Void)? = nil) {
        self.voice = voice
        self.activity = activity
        self.deviceName = deviceName
        self.keepsActivity = keepsActivity
        self.ended = ended
        endFromLiveActivityAction = endFromLiveActivity
        mailbox = Mailbox()
        mailbox.owner = self
        mailbox.listen()
        follow()
    }

    /// The talk's state as the Live Activity says it: nil while no talk is on.
    static func state(of voice: VoiceModel) -> PokiState.Voice? {
        switch voice.phase {
        case .off: return nil
        case .lost: return .failed
        case .connecting: return .connecting
        case .listening: return .listening
        case .hearing: return .hearing
        case .thinking: return voice.calls.contains { $0.state == .running } ? .working : .thinking
        case .speaking: return .speaking
        }
    }

    /// Maps WebRTC microphone `audioLevel` (0...1) to the three waveform tiers (0 = quiet, 1 = normal, 2 = loud).
    static func loudnessTier(for level: Double) -> Int {
        if level < 0.04 { return 0 }
        if level < 0.16 { return 1 }
        return 2
    }

    private func follow() {
        withObservationTracking {
            let next = Self.state(of: voice)
            let step = next == .working ? voice.activeTurnStep : nil
            show(next, step: step)
            turn(voice.midTurn)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func show(_ next: PokiState.Voice?, step: String? = nil, fromIntent: Bool = false) {
        let wasActive = shown != nil && shown != .ended && shown != .failed
        switch next {
        case nil:
            guard let current = shown else { return }
            if current == .ended { return }
            if current == .failed {
                clearVoice()
                return
            }
            levelTask?.cancel(); levelTask = nil
            ended()
            if activity.state.phase == .idle || activity.state.phase == .working {
                holdTerminal(.ended)
            } else {
                clearVoice()
            }
        case .failed?:
            guard wasActive else { return }
            levelTask?.cancel(); levelTask = nil
            ended()
            if activity.state.phase == .idle || activity.state.phase == .working {
                holdTerminal(.failed)
            } else {
                clearVoice()
            }
        case .ended?:
            guard wasActive else { return }
            levelTask?.cancel(); levelTask = nil
            ended()
            holdTerminal(.ended)
        case let active?:
            dismissTask?.cancel(); dismissTask = nil
            let nextStep = active == .working ? step : nil
            guard active != shown || nextStep != shownStep else { return }
            let started = shown == nil
            shown = active
            shownStep = nextStep
            activity.update { state in
                state.voice = active
                if active != .hearing && active != .speaking { state.voiceLevel = nil }
                state.voiceStep = nextStep
            }
            // Started from a tap in Poki, or from Talk Here's intent: the times iOS lets a Live Activity start.
            if started { activity.start(deviceName: deviceName(), fromIntent: fromIntent) }
            if active == .hearing { startLevelPolling() } else { levelTask?.cancel(); levelTask = nil }
        }
    }

    private func holdTerminal(_ terminal: PokiState.Voice) {
        shown = terminal
        shownStep = nil
        activity.update { state in
            state.voice = terminal
            state.voiceLevel = nil
            state.voiceStep = nil
        }
        dismissTask?.cancel()
        let wait = dismissAfter
        dismissTask = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled, let self, self.shown == terminal else { return }
            self.clearVoice()
        }
    }

    private func clearVoice() {
        dismissTask?.cancel(); dismissTask = nil
        levelTask?.cancel(); levelTask = nil
        shown = nil
        shownStep = nil
        activity.update { state in
            state.voice = nil
            state.voiceLevel = nil
            state.voiceStep = nil
        }
        // Only a Live Activity that shows nothing else goes with the talk: an approval, a hand-off, a
        // problem, pairing or setup stays.
        if !keepsActivity(), activity.state.phase == .idle { activity.end() }
    }

    private func startLevelPolling() {
        levelTask?.cancel()
        let interval = levelPollInterval
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, self.shown == .hearing else { return }
                guard let level = await self.voice.inputAudioLevel() else { continue }
                guard !Task.isCancelled, self.shown == .hearing else { return }
                let tier = Self.loudnessTier(for: level)
                if self.activity.state.voiceLevel != tier {
                    self.activity.update { $0.voiceLevel = tier }
                }
            }
        }
    }

    /// The talk's turn is over: Poki has answered and has nothing left to do for the request. A run of
    /// steps the turn took finishes now, with what Poki said, as the chat finishes its task's run. A talk
    /// that ends mid-turn leaves its run to the Live Activity's quiet wait.
    private func turn(_ mid: Bool) {
        defer { wasMidTurn = mid }
        guard wasMidTurn, !mid, voice.isOn, activity.state.stepCount > 0 else { return }
        let asked = voice.lines.lastIndex { $0.role == .you }
        let said = voice.lines[(asked.map { $0 + 1 } ?? 0)...].last { $0.role == .poki }?.text
        activity.finishNow(alert: true, result: said, task: asked.map { voice.lines[$0].text })
    }

    /// Talk Here (TalkHereIntent), with Poki in the background: the Live Activity starts first, while
    /// the intent runs, and the microphone only once it is up, because iOS ends an app that records in
    /// the background without one. false: the Live Activity did not start, and nothing else did.
    func startHere() async -> Bool {
        show(.connecting, fromIntent: true)
        guard activity.isRunning else {
            clearVoice()
            return false
        }
        await voice.start()
        // Not connected: the talk's phase is `.lost`, which shows Connection failed for 3 s before dismissing.
        let next = Self.state(of: voice)
        show(next, step: next == .working ? voice.activeTurnStep : nil)
        return true
    }

    fileprivate func endFromLiveActivity() {
        guard voice.isOn else { return }
        AppLog.shared.add("voice", "the talk was ended from the Live Activity")
        if let endFromLiveActivityAction { endFromLiveActivityAction() } else { voice.stop() }
    }

    private final class Mailbox {
        weak var owner: TalkActivity?

        func listen() {
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
                guard let observer else { return }
                let mailbox = Unmanaged<Mailbox>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in mailbox.owner?.endFromLiveActivity() }
            }, TalkSignal.end as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                               CFNotificationName(TalkSignal.end as CFString), nil)
        }
    }
}
