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
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var pendingContent: NSKeyValueObservation?
    @ObservationIgnored private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private(set) var microphone = AVAudioApplication.shared.recordPermission
    private(set) var recording = false

    var sending: Bool { delivery.sending }
    var deliveryFailure: WatchVoiceDeliveryFailure? { delivery.deliveryFailure }
    var problem: LocalizedStringResource? { delivery.problem }
    var hasPending: Bool { delivery.hasPending }
    var update: WatchVoiceUpdate? { delivery.update }
    var results: [WatchVoiceUpdate] { delivery.results }
    var pendingStatus: WatchVoicePendingStatus { delivery.pendingStatus }

    private override init() {
        delivery = WatchVoiceDeliveryController(link: LiveWatchVoiceDeliveryLink(session: session))
        super.init()
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
        delivery.receiveContext(session.receivedApplicationContext)
        if delivery.hasPending { delivery.sync() }
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

    private func notify(_ update: WatchVoiceUpdate) {
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(update.phase == .finished ? .success : .failure)
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: update.phase == .finished ? "Poki task finished" : "Poki task needs attention")
            content.body = String(localized: "Open Poki to see the result.")
            content.sound = .default
            let request = UNNotificationRequest(identifier: update.id.uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        finishBackgroundTasks()
    }

    private func finishBackgroundTasks() {
        guard session.activationState == .activated, !session.hasContentPending else { return }
        delivery.receiveContext(session.receivedApplicationContext)
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
                delivery.activationDidComplete(activated: false)
                for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
                backgroundTasks.removeAll()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            delivery.reachabilityDidChange()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: messageData) else { return }
        Task { @MainActor in delivery.receive(update) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            delivery.receiveContext(applicationContext)
            finishBackgroundTasks()
        }
    }
}
