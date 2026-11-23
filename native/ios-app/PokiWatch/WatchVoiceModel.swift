import AVFoundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

@MainActor
private final class LiveWatchVoiceDeliveryLink: WatchVoiceDeliveryLink {
    private let session: WCSession

    init(session: WCSession) {
        self.session = session
    }

    var isActivated: Bool { session.activationState == .activated }
    var isCompanionInstalled: Bool { session.isCompanionAppInstalled }
    var isReachable: Bool { session.isReachable }
    var needsUnlockAfterReboot: Bool { session.iOSDeviceNeedsUnlockAfterRebootForReachability }

    func activate() {
        session.activate()
    }

    func sendMessageData(
        _ data: Data,
        replyHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) {
        session.sendMessageData(data, replyHandler: replyHandler, errorHandler: errorHandler)
    }
}

@MainActor
@Observable
final class WatchVoiceModel: NSObject, WCSessionDelegate {
    static let shared = WatchVoiceModel()

    private let session = WCSession.default
    private let delivery: WatchVoiceDeliveryController
    private let recordingURL = FileManager.default.temporaryDirectory.appending(path: "PokiWatchVoice.m4a")
    private var remoteReducer = WatchVoiceRemoteStateReducer()
    @ObservationIgnored private let cuePlayer = WatchVoiceCuePlayer()
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var meterDecayTask: Task<Void, Never>?
    @ObservationIgnored private var transientSyncTask: Task<Void, Never>?
    @ObservationIgnored private var endedScreenTask: Task<Void, Never>?
    @ObservationIgnored private var lastStateQueryAt: Date?
    @ObservationIgnored private var pendingDeepLinkStartAt: Date?
    @ObservationIgnored private var pendingContent: NSKeyValueObservation?
    @ObservationIgnored private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    private(set) var microphone = AVAudioApplication.shared.recordPermission
    private(set) var recording = false

    private(set) var remoteReachable = false
    private(set) var remoteCommandInFlight = false
    private(set) var isStartingCall = false
    private(set) var showingEndedScreen = false
    private(set) var remoteTransportError: LocalizedStringResource?
    var selectedResultID: UUID?

    var sending: Bool { delivery.sending }
    var deliveryFailure: WatchVoiceDeliveryFailure? { delivery.deliveryFailure }
    var problem: LocalizedStringResource? { delivery.problem }
    var hasPending: Bool { delivery.hasPending }
    var update: WatchVoiceUpdate? { delivery.update }
    var results: [WatchVoiceUpdate] { delivery.results }
    var pendingStatus: WatchVoicePendingStatus { delivery.pendingStatus }

    var remoteSnapshot: WatchVoiceRemoteSnapshot? { remoteReducer.latestSnapshot }
    var remoteIsMuted: Bool { remoteReducer.latestSnapshot?.isMuted ?? false }
    var canEndRemoteCall: Bool { remoteReducer.canShowEndButton }
    var hasPendingRemoteEnd: Bool { remoteReducer.pendingEnd != nil }
    var remoteRequiresForeground: Bool { remoteReachable && remoteReducer.pendingContinueOnPhone }
    var remoteDetail: String? { remoteReducer.lastProblem }
    var remoteCurrentStep: String? {
        guard remoteReachable, remoteState.isActiveCall else { return nil }
        return remoteReducer.latestSnapshot?.currentStep
    }

    var remoteState: WatchVoiceCallState {
        guard remoteReachable else { return .unavailable }
        return remoteReducer.latestSnapshot?.state ?? .idle
    }

    var remoteMeterLevel: UInt8 {
        guard remoteReachable, remoteState.isActiveCall else { return 0 }
        return remoteReducer.meterLevel
    }

    private override init() {
        delivery = WatchVoiceDeliveryController(link: LiveWatchVoiceDeliveryLink(session: session))
        super.init()
        remoteReducer = WatchVoiceRemoteStateReducer(
            latestSnapshot: delivery.remoteSnapshot,
            pendingEnd: delivery.pendingEnd
        )
        delivery.onTerminalUpdate = { [weak self] update in self?.notify(update) }
        delivery.onWaitingForUnlock = {
            if WKApplication.shared().applicationState == .active {
                WKInterfaceDevice.current().play(.notification)
            }
        }
        delivery.onDeliveryFailure = {
            if WKApplication.shared().applicationState == .active {
                WKInterfaceDevice.current().play(.failure)
            }
        }
        session.delegate = self
        pendingContent = session.observe(\.hasContentPending) { [weak self] _, _ in
            Task { @MainActor in self?.finishBackgroundTasks() }
        }
        session.activate()
    }

    func setActive(_ active: Bool) {
        delivery.setActive(active)
    }

    func opened() {
        microphone = AVAudioApplication.shared.recordPermission
        updateReachability()
        receiveContext(session.receivedApplicationContext)
        flushPendingEnd()
        consumePendingDeepLinkStart()
        refreshRemoteState()
        updateActiveSync()
        if delivery.hasPending { delivery.sync() }
    }

    func handleStartDeepLink() {
        dismissEndedScreen()
        guard !remoteState.isActiveCall, remoteState != .ending else { return }
        if remoteReachable, !remoteCommandInFlight {
            pendingDeepLinkStartAt = nil
            remotePrimaryAction()
        } else {
            pendingDeepLinkStartAt = Date()
            updateReachability()
            consumePendingDeepLinkStart()
        }
    }

    func openResult(_ id: UUID) {
        selectedResultID = id
    }

    func clearSelectedResult() {
        selectedResultID = nil
    }

    func dismissEndedScreen() {
        endedScreenTask?.cancel()
        endedScreenTask = nil
        showingEndedScreen = false
    }

    private func consumePendingDeepLinkStart() {
        guard let requestedAt = pendingDeepLinkStartAt else { return }
        if Date().timeIntervalSince(requestedAt) > 6.0 {
            pendingDeepLinkStartAt = nil
            return
        }
        guard remoteReachable, !remoteCommandInFlight else { return }
        pendingDeepLinkStartAt = nil
        guard !remoteState.isActiveCall, remoteState != .ending else { return }
        remotePrimaryAction()
    }

    private func triggerEndedScreen() {
        endedScreenTask?.cancel()
        showingEndedScreen = true
        endedScreenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.showingEndedScreen = false
            self?.endedScreenTask = nil
        }
    }

    func refreshRemoteState() {
        guard remoteReachable else { return }
        let now = Date()
        if let last = lastStateQueryAt, now.timeIntervalSince(last) < 1.5 { return }
        lastStateQueryAt = now
        sendRemoteCommand(WatchVoiceRemoteCommand(action: .state), cueOnAccept: nil)
    }

    func remotePrimaryAction() {
        guard !remoteCommandInFlight else { return }
        guard remoteReachable else {
            remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
            cuePlayer.playFailureHaptic()
            return
        }
        if remoteState.isActiveCall {
            let nextMuted = !remoteIsMuted
            let command = WatchVoiceRemoteCommand(
                action: .setMuted(nextMuted),
                targetCallID: remoteSnapshot?.callID
            )
            sendRemoteCommand(command, cueOnAccept: nextMuted ? .mute : .unmute)
        } else {
            let command = WatchVoiceRemoteCommand(action: .start, targetCallID: nil)
            sendRemoteCommand(command, cueOnAccept: .start)
        }
    }

    func remoteEndAction() {
        guard !remoteCommandInFlight else { return }
        if let command = remoteReducer.queueEnd(now: Date()) {
            persistRemoteState(ingesting: [])
            if remoteReachable {
                sendRemoteCommand(command, cueOnAccept: .end)
            } else {
                enqueuePendingEndTransfer(command)
                remoteTransportError = nil
                cuePlayer.play(.end)
            }
            return
        }
        guard remoteReachable else {
            remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
            cuePlayer.playFailureHaptic()
            return
        }
        let command = WatchVoiceRemoteCommand(action: .end, targetCallID: remoteSnapshot?.callID)
        sendRemoteCommand(command, cueOnAccept: .end)
    }

    private func enqueuePendingEndTransfer(_ command: WatchVoiceRemoteCommand) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(command) else { return }
        session.transferUserInfo([WatchVoiceRemote.commandKey: data])
    }

    private func flushPendingEnd() {
        guard remoteReachable, !remoteCommandInFlight,
              let pending = remoteReducer.pendingEnd else { return }
        sendRemoteCommand(pending.makeCommand(), cueOnAccept: nil)
    }

    private func sendRemoteCommand(_ command: WatchVoiceRemoteCommand, cueOnAccept: WatchVoiceCue?) {
        guard session.activationState == .activated, session.isReachable else {
            remoteReachable = false
            if command.action == .end, command.targetCallID != nil {
                if remoteReducer.pendingEnd == nil {
                    _ = remoteReducer.queueEnd(requestID: command.requestID, now: command.issuedAt)
                    persistRemoteState(ingesting: [])
                }
                enqueuePendingEndTransfer(command)
                remoteTransportError = nil
                if let cue = cueOnAccept { cuePlayer.play(cue) }
                return
            }
            if command.action != .state {
                remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
                cuePlayer.playFailureHaptic()
            }
            return
        }
        guard let data = try? JSONEncoder().encode(command) else { return }
        let isUserCommand = command.action != .state
        let isStartCommand = command.action == .start
        if isUserCommand {
            remoteCommandInFlight = true
            remoteTransportError = nil
            if isStartCommand {
                dismissEndedScreen()
                isStartingCall = true
            }
        }
        session.sendMessage([WatchVoiceRemote.commandKey: data]) { [weak self] replyMessage in
            Task { @MainActor in
                guard let self else { return }
                if isUserCommand { self.remoteCommandInFlight = false }
                if isStartCommand { self.isStartingCall = false }
                guard let replyData = replyMessage[WatchVoiceRemote.replyKey] as? Data,
                      let reply = try? JSONDecoder().decode(WatchVoiceRemoteReply.self, from: replyData),
                      reply.requestID == command.requestID else {
                    if isUserCommand {
                        if command.action == .end, command.targetCallID != nil {
                            self.enqueuePendingEndTransfer(command)
                            self.remoteTransportError = nil
                        } else {
                            self.remoteTransportError = "iPhone didn’t confirm the command."
                            self.cuePlayer.playFailureHaptic()
                        }
                    }
                    return
                }
                self.applyRemoteReply(
                    reply,
                    targetCallID: command.targetCallID,
                    cueOnAccept: cueOnAccept,
                    isUserCommand: isUserCommand
                )
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if isUserCommand { self.remoteCommandInFlight = false }
                if isStartCommand { self.isStartingCall = false }
                self.updateReachability()
                if command.action == .end, command.targetCallID != nil {
                    if self.remoteReducer.pendingEnd == nil {
                        _ = self.remoteReducer.queueEnd(requestID: command.requestID, now: command.issuedAt)
                        self.persistRemoteState(ingesting: [])
                    }
                    self.enqueuePendingEndTransfer(command)
                    self.remoteTransportError = nil
                    if let cue = cueOnAccept { self.cuePlayer.play(cue) }
                } else if isUserCommand {
                    self.remoteTransportError = "iPhone hasn’t replied. Open Poki on your iPhone and try again."
                    self.cuePlayer.playFailureHaptic()
                }
            }
        }
    }

    private func applyRemoteReply(
        _ reply: WatchVoiceRemoteReply,
        targetCallID: String?,
        cueOnAccept: WatchVoiceCue?,
        isUserCommand: Bool
    ) {
        let previousState = remoteReducer.latestSnapshot?.state
        guard remoteReducer.apply(reply: reply, targetCallID: targetCallID) else {
            return
        }
        handleEndedTransition(from: previousState, to: remoteReducer.latestSnapshot?.state)
        remoteTransportError = nil
        persistRemoteState(ingesting: reply.snapshot.deliveredResults)
        updateActiveSync()
        if remoteReducer.pendingEnd != nil {
            flushPendingEnd()
        }
        guard isUserCommand else { return }
        if reply.outcome.isSuccess {
            if let cue = cueOnAccept {
                cuePlayer.play(cue)
            }
        } else {
            cuePlayer.playFailureHaptic()
        }
    }

    private func applyRemoteSnapshot(_ snapshot: WatchVoiceRemoteSnapshot) {
        let previousState = remoteReducer.latestSnapshot?.state
        guard remoteReducer.apply(snapshot: snapshot) else { return }
        handleEndedTransition(from: previousState, to: remoteReducer.latestSnapshot?.state)
        persistRemoteState(ingesting: snapshot.deliveredResults)
        updateActiveSync()
        if remoteReducer.pendingEnd != nil {
            flushPendingEnd()
        }
    }

    private func handleEndedTransition(from previous: WatchVoiceCallState?, to next: WatchVoiceCallState?) {
        guard let next else { return }
        if next.isActiveCall || next == .ending {
            dismissEndedScreen()
        } else if next == .idle, let previous, previous.isActiveCall || previous == .ending {
            triggerEndedScreen()
        }
    }

    private func updateActiveSync() {
        transientSyncTask?.cancel()
        transientSyncTask = nil
        let state = remoteState
        let needsInitialSync = remoteSnapshot == nil
        guard remoteReachable, needsInitialSync || state.isActiveCall || state == .ending || hasPendingRemoteEnd else { return }
        let intervalMs = (state == .connecting || state == .ending || hasPendingRemoteEnd) ? 1500 : 5000
        transientSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(intervalMs))
                guard !Task.isCancelled, let self else { return }
                guard WKApplication.shared().applicationState == .active else { return }
                let current = self.remoteState
                guard self.remoteReachable,
                      self.remoteSnapshot == nil || current.isActiveCall || current == .ending || self.hasPendingRemoteEnd else { return }
                self.flushPendingEnd()
                self.refreshRemoteState()
            }
        }
    }

    private func persistRemoteState(ingesting incoming: [WatchVoiceUpdate]) {
        let added = delivery.updateRemoteState(
            snapshot: remoteReducer.latestSnapshot,
            pendingEnd: remoteReducer.pendingEnd,
            ingesting: incoming
        )
        if !added.isEmpty {
            notify(added)
        }
    }

    private func applyRemoteMeter(_ meter: WatchVoiceRemoteMeter) {
        let now = Date()
        guard remoteReducer.apply(meter: meter, now: now) else { return }
        meterDecayTask?.cancel()
        meterDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.remoteReducer.clearMeterIfStale(now: Date())
        }
    }

    private func updateReachability() {
        remoteReachable = session.activationState == .activated && session.isReachable
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        microphone = AVAudioApplication.shared.recordPermission
        if microphone == .granted { await requestNotifications() }
    }

    func requestNotifications() async {
        let notifications = UNUserNotificationCenter.current()
        if await notifications.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
        }
    }

    func startRecording() {
        guard microphone == .granted, !hasPending, !recording else { return }
        delivery.clearProblem()
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default)
            try audio.setActive(true)
            let recorder = try AVAudioRecorder(url: recordingURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 16_000
            ])
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            recording = true
            recordingLimit = Task {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { stopRecording() }
            }
        } catch {
            releaseMicrophone()
            delivery.setProblem("Poki couldn’t start recording. Try holding the microphone again.")
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        let seconds = recorder.currentTime
        releaseMicrophone()
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        guard seconds >= 0.3 else {
            delivery.setProblem("Hold the microphone while you speak.")
            return
        }
        guard let audio = try? Data(contentsOf: recordingURL), !audio.isEmpty, audio.count <= WatchVoiceRequest.maxAudioBytes else {
            delivery.setProblem("The recording couldn’t be saved. Try a shorter request.")
            return
        }
        _ = delivery.enqueue(audio: audio)
    }

    func cancelRecording() {
        guard recording else { return }
        releaseMicrophone()
        try? FileManager.default.removeItem(at: recordingURL)
    }

    func discardPending() {
        delivery.discardPending()
    }

    func sync() {
        delivery.sync()
    }

    func loadFullResult(_ id: UUID) async -> Bool {
        await delivery.loadFullResult(id)
    }

    private func releaseMicrophone() {
        recordingLimit?.cancel()
        recordingLimit = nil
        recorder?.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func notify(_ updates: [WatchVoiceUpdate]) {
        guard let newest = updates.first else { return }
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(newest.phase == .finished ? .success : .failure)
        } else {
            for update in updates {
                let content = UNMutableNotificationContent()
                content.title = String(localized: update.phase == .finished ? "Poki task finished" : "Poki task needs attention")
                let preview = update.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                content.body = preview.isEmpty ? String(localized: "Open Poki to see the result.") : String(preview.prefix(120))
                content.sound = .default
                let request = UNNotificationRequest(identifier: update.id.uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func notify(_ update: WatchVoiceUpdate) {
        notify([update])
    }

    private func receiveContext(_ context: [String: Any]) {
        delivery.receiveContext(context)
        if let remoteData = context[WatchVoiceRemote.contextKey] as? Data,
           let snapshot = try? JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: remoteData) {
            applyRemoteSnapshot(snapshot)
        }
    }

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        finishBackgroundTasks()
    }

    private func finishBackgroundTasks() {
        guard session.activationState == .activated, !session.hasContentPending else { return }
        receiveContext(session.receivedApplicationContext)
        for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
        backgroundTasks.removeAll()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated {
                delivery.activationDidComplete(activated: true)
                opened()
                finishBackgroundTasks()
            } else {
                remoteReachable = false
                delivery.activationDidComplete(activated: false)
                for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
                backgroundTasks.removeAll()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            updateReachability()
            if remoteReachable {
                remoteTransportError = nil
                flushPendingEnd()
                consumePendingDeepLinkStart()
                refreshRemoteState()
            }
            updateActiveSync()
            delivery.reachabilityDidChange()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: messageData) else { return }
        Task { @MainActor in delivery.receive(update) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let snapshotData = message[WatchVoiceRemote.snapshotKey] as? Data,
           let snapshot = try? JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: snapshotData) {
            Task { @MainActor in applyRemoteSnapshot(snapshot) }
        }
        if let meterData = message[WatchVoiceRemote.meterKey] as? Data,
           let meter = try? JSONDecoder().decode(WatchVoiceRemoteMeter.self, from: meterData) {
            Task { @MainActor in applyRemoteMeter(meter) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let resultData = userInfo[WatchVoiceRemote.resultKey] as? Data,
           let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: resultData) {
            Task { @MainActor in
                self.persistRemoteState(ingesting: [update])
                self.finishBackgroundTasks()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            receiveContext(applicationContext)
            finishBackgroundTasks()
        }
    }
}
