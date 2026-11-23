#if POKI_WATCH
import Foundation
import UIKit
import UserNotifications
import WatchConnectivity

@MainActor
protocol WatchBackgroundExecution: AnyObject {
    func begin(name: String, expirationHandler: @escaping @MainActor @Sendable () -> Void) -> AnyObject?
    func end(_ token: AnyObject?)
}

@MainActor
final class LiveWatchBackgroundExecution: WatchBackgroundExecution {
    private final class Token {
        let id: UIBackgroundTaskIdentifier
        init(_ id: UIBackgroundTaskIdentifier) { self.id = id }
    }

    func begin(name: String, expirationHandler: @escaping @MainActor @Sendable () -> Void) -> AnyObject? {
        let id = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in expirationHandler() }
        }
        return id == .invalid ? nil : Token(id)
    }

    func end(_ token: AnyObject?) {
        guard let boxed = token as? Token, boxed.id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(boxed.id)
    }
}

final class PokiWatchAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            WatchVoicePhone.shared?.ensureSessionActivated()
        }
        return true
    }
}

enum WatchVoiceNotice {
    static func identifier(for id: UUID) -> String { "poki-watch-unlock-\(id.uuidString)" }

    @MainActor
    static func postUnlockPrompt(for id: UUID) {
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text(LocalizedStringResource("Unlock iPhone for Watch Task"))
        content.body = AppLocalization.text(LocalizedStringResource("Poki received your Apple Watch request. If it doesn’t continue after unlocking, tap this notification or tap Check iPhone on Apple Watch."))
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "watch-voice"
        content.userInfo = ["poki_link": "poki://chat", "watch_voice_unlock": id.uuidString]
        let request = UNNotificationRequest(identifier: identifier(for: id), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    static func clearUnlockPrompt(for id: UUID) {
        let noticeID = identifier(for: id)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [noticeID])
        center.removePendingNotificationRequests(withIdentifiers: [noticeID])
    }
}

@MainActor
private final class WCSessionTransport: WatchVoiceTransport {
    private let session: WCSession

    init(_ session: WCSession) {
        self.session = session
    }

    var isActivated: Bool { session.activationState == .activated }
    var isPaired: Bool { session.isPaired }
    var isWatchAppInstalled: Bool { session.isWatchAppInstalled }
    var isReachable: Bool { session.isReachable }
    var applicationContext: [String: Any] { session.applicationContext }

    func updateApplicationContext(_ context: [String: Any]) throws {
        try session.updateApplicationContext(context)
    }

    func sendMessage(_ message: [String: Any]) {
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendMessageData(_ data: Data) {
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        session.transferUserInfo(userInfo)
    }
}

@MainActor
final class WatchVoicePhone: NSObject, WCSessionDelegate {
    static weak var shared: WatchVoicePhone?

    private let app: AppModel
    private let chat: ChatModel
    private let session = WCSession.default
    private let usesLiveSession: Bool
    private let transport: any WatchVoiceTransport
    private let backgroundExecution: any WatchBackgroundExecution
    private let resultJournal: WatchVoiceResultJournal
    private let pendingAudioDirectory: URL
    private let isProtectedDataAvailable: @MainActor () -> Bool
    private let isScreenLocked: @MainActor () -> Bool
    private var activeID: UUID?
    private var waitingUnlockID: UUID?
    private var postedUnlockNotices: Set<UUID> = []
    private var work: Task<Void, Never>?
    private var backgroundToken: AnyObject?
    private var remoteBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var unlockObservers: [NSObjectProtocol] = []
    private var lockStateMailbox: LockStateMailbox?
    private lazy var channel: WatchVoiceRemoteChannel = {
        let host = WatchVoiceRemoteHost(app: app, chat: chat, isWatchTaskBusy: { [weak self] in self?.activeID != nil })
        let channel = WatchVoiceRemoteChannel(
            remoteHost: host,
            resultJournal: resultJournal,
            transport: transport
        )
        channel.onTaskRequest = { [weak self] request in self?.reply(to: request) ?? Data() }
        channel.onBackgroundTaskNeeded = { [weak self] needed in
            if needed { self?.beginRemoteBackgroundTask() } else { self?.endRemoteBackgroundTask() }
        }
        channel.onLog = { message in AppLog.shared.add("watch", message) }
        return channel
    }()

    #if DEBUG && targetEnvironment(simulator)
    private var simulatedLockActive = ProcessInfo.processInfo.arguments.contains("-pokiWatchVoiceSimulateLocked")
        || UserDefaults.standard.bool(forKey: "pokiWatchVoiceSimulateLocked")
    #endif

    private var phoneLocked: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if simulatedLockActive { return true }
        #endif
        return !isProtectedDataAvailable() || isScreenLocked()
    }

    init(
        app: AppModel,
        chat: ChatModel,
        transport: (any WatchVoiceTransport)? = nil,
        backgroundExecution: (any WatchBackgroundExecution)? = nil,
        journal: URL = URL.applicationSupportDirectory.appending(path: "WatchVoice.json"),
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        isScreenLocked: @escaping @MainActor () -> Bool = { PKInProcess.shared().screenLocked() }
    ) {
        self.app = app
        self.chat = chat
        self.usesLiveSession = transport == nil
        self.transport = transport ?? WCSessionTransport(session)
        self.backgroundExecution = backgroundExecution ?? LiveWatchBackgroundExecution()
        self.resultJournal = WatchVoiceResultJournal(url: journal)
        self.pendingAudioDirectory = journal.deletingLastPathComponent().appending(path: "WatchVoicePending", directoryHint: .isDirectory)
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.isScreenLocked = isScreenLocked
        super.init()
        channel.remoteHost.startObserving()
        restoreWaitingUnlockTask()
        installUnlockObservers()
        ensureSessionActivated()
    }

    deinit {
        for observer in unlockObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func ensureSessionActivated() {
        guard usesLiveSession, WCSession.isSupported() else { return }
        if session.delegate !== self { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    func handleUnlockSignal() {
        resumeWaitingTaskIfUnlocked()
    }

    #if DEBUG && targetEnvironment(simulator)
    fileprivate func handleSimulatedUnlock() {
        simulatedLockActive = false
        UserDefaults.standard.set(false, forKey: "pokiWatchVoiceSimulateLocked")
        AppLog.shared.add("watch", "Simulated unlock signal received")
        resumeWaitingTaskIfUnlocked()
    }
    #endif

    private func installUnlockObservers() {
        let center = NotificationCenter.default
        unlockObservers.append(center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlockSignal() }
        })
        unlockObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlockSignal() }
        })
        let mailbox = LockStateMailbox(owner: self)
        mailbox.listen()
        lockStateMailbox = mailbox
    }

    private func pendingAudioURL(for id: UUID) -> URL {
        pendingAudioDirectory.appending(path: "\(id.uuidString).m4a")
    }

    private func savePendingAudio(_ audio: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: pendingAudioDirectory, withIntermediateDirectories: true)
        try audio.write(to: pendingAudioURL(for: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func loadPendingAudio(for id: UUID) -> Data? {
        try? Data(contentsOf: pendingAudioURL(for: id))
    }

    private func removePendingAudio(for id: UUID) {
        try? FileManager.default.removeItem(at: pendingAudioURL(for: id))
    }

    private func restoreWaitingUnlockTask() {
        guard let candidate = resultJournal.updates.values.first(where: { $0.phase == .waitingForUnlock }) else { return }
        guard FileManager.default.fileExists(atPath: pendingAudioURL(for: candidate.id).path) else { return }
        waitingUnlockID = candidate.id
        postedUnlockNotices.insert(candidate.id)
    }

    private func store(_ update: WatchVoiceUpdate) throws {
        try resultJournal.store(update)
    }

    private func reply(to request: WatchVoiceRequest) -> Data {
        switch request {
        case .status(let id):
            return channel.encodeUpdate(status(for: id))
        case .submit(let id, let audio):
            return channel.encodeUpdate(accept(id, audio: audio))
        case .result(let id, let offset):
            return resultJournal.resultChunk(id: id, offset: offset)
        }
    }

    private func accept(_ id: UUID, audio: Data) -> WatchVoiceUpdate {
        if let existing = status(for: id) { return existing }
        guard !audio.isEmpty, audio.count <= WatchVoiceRequest.maxAudioBytes else {
            return blocked(id, "The recording is empty or too long. Record a shorter request.")
        }
        if activeID != nil {
            return complete(blocked(id, "Poki is handling another Watch task. Wait for it to finish and try again."))
        }
        if let waiting = waitingUnlockID, waiting != id {
            if !phoneLocked {
                resumeWaitingTaskIfUnlocked()
                return complete(blocked(id, "Poki is handling another Watch task. Wait for it to finish and try again."))
            }
            return complete(blocked(id, "Poki is waiting for you to unlock iPhone for another Watch task."))
        }
        if phoneLocked {
            return parkForUnlock(id, audio: audio, publishToWatch: false)
        }
        let receipt = WatchVoiceUpdate(id: id, phase: .received, text: nil)
        do {
            try store(receipt)
        } catch {
            return blocked(id, "Poki couldn’t save this request on iPhone. Check available storage and try again.")
        }
        AppLog.shared.add("watch", "Received Watch task \(id)")
        startTask(id, audio: audio)
        return receipt
    }

    private func status(for id: UUID) -> WatchVoiceUpdate? {
        guard let update = resultJournal.update(for: id) else { return nil }
        if update.phase.isTerminal { return update }
        if activeID == id { return update }
        if update.phase == .waitingForUnlock {
            if FileManager.default.fileExists(atPath: pendingAudioURL(for: id).path) {
                waitingUnlockID = id
                if !phoneLocked {
                    resumeWaitingTaskIfUnlocked()
                    return resultJournal.update(for: id)
                }
                return update
            }
            WatchVoiceNotice.clearUnlockPrompt(for: id)
            return complete(blocked(id, "Poki couldn’t find the saved Watch recording after unlock. Record the request again."))
        }
        return complete(blocked(id, "Poki was interrupted on iPhone. Check what happened there before sending the task again."))
    }

    @discardableResult
    private func parkForUnlock(_ id: UUID, audio: Data, publishToWatch: Bool) -> WatchVoiceUpdate {
        let waiting = WatchVoiceUpdate(
            id: id,
            phase: .waitingForUnlock,
            text: AppLocalization.text(LocalizedStringResource("Received. Unlock your iPhone."))
        )
        do {
            try savePendingAudio(audio, for: id)
            try store(waiting)
        } catch {
            removePendingAudio(for: id)
            let failed = blocked(id, "Poki couldn’t save this request on iPhone. Check available storage and try again.")
            if publishToWatch { return complete(failed) }
            return failed
        }
        waitingUnlockID = id
        if postedUnlockNotices.insert(id).inserted {
            WatchVoiceNotice.postUnlockPrompt(for: id)
        }
        AppLog.shared.add("watch", "Parked Watch task \(id) until iPhone is unlocked")
        beginBackgroundTask()
        if publishToWatch {
            publish(waiting)
        } else {
            publishContext(waiting)
        }
        return waiting
    }

    private func clearNoticeIfNeeded(for id: UUID) {
        if postedUnlockNotices.remove(id) != nil || waitingUnlockID == id {
            WatchVoiceNotice.clearUnlockPrompt(for: id)
        }
    }

    private func resumeWaitingTaskIfUnlocked() {
        guard let id = waitingUnlockID, activeID == nil, !phoneLocked else { return }
        clearNoticeIfNeeded(for: id)
        waitingUnlockID = nil
        guard let audio = loadPendingAudio(for: id) else {
            complete(blocked(id, "Poki couldn’t find the saved Watch recording after unlock. Record the request again."))
            return
        }
        AppLog.shared.add("watch", "Resuming Watch task \(id) after iPhone unlocked")
        startTask(id, audio: audio)
    }

    private func startTask(_ id: UUID, audio: Data) {
        activeID = id
        work = Task { await run(id, audio: audio) }
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundToken = backgroundExecution.begin(name: "Poki Watch task") { [weak self] in
            guard let self else { return }
            if self.waitingUnlockID == nil { self.work?.cancel() }
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard let token = backgroundToken else { return }
        backgroundToken = nil
        backgroundExecution.end(token)
    }

    private func run(_ id: UUID, audio: Data) async {
        beginBackgroundTask()
        var watchLease: AppModel.BackgroundWatchLease?
        defer {
            app.endBackgroundWatchSession(watchLease)
            if waitingUnlockID != id { endBackgroundTask() }
            work = nil
            activeID = nil
        }
        if phoneLocked {
            parkForUnlock(id, audio: audio, publishToWatch: true)
            return
        }
        do {
            try checkPreconditionsBeforeSession()
            watchLease = await app.beginBackgroundWatchSession()
            try Task.checkCancellation()
            if phoneLocked {
                parkForUnlock(id, audio: audio, publishToWatch: true)
                return
            }
            try checkSessionReady()
            let transcript = try await Dictation.transcribe(recording: audio)
            try Task.checkCancellation()
            if phoneLocked {
                parkForUnlock(id, audio: audio, publishToWatch: true)
                return
            }
            try checkPreconditionsBeforeSession()
            try checkSessionReady()
            removePendingAudio(for: id)
            let running = WatchVoiceUpdate(id: id, phase: .running, text: nil)
            try store(running)
            publish(running)
            let task = ChatModel(app: app, kind: .handoff, requester: "Apple Watch", sessionID: id.uuidString)
            let result = await task.runDelegated(transcript)
            try Task.checkCancellation()
            let update = WatchVoiceUpdate(id: id, phase: result.success == true ? .finished : .blocked,
                                          text: result.text)
            complete(update)
        } catch is CancellationError {
            guard waitingUnlockID != id else { return }
            removePendingAudio(for: id)
            complete(blocked(id, "iPhone stopped the background task. Check Poki on iPhone before trying again."))
        } catch let error as WatchVoiceStartError {
            removePendingAudio(for: id)
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch let error as WatchVoiceSpeechError {
            removePendingAudio(for: id)
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch {
            removePendingAudio(for: id)
            complete(blocked(id, "Poki couldn’t save the task on iPhone. Check available storage and try again."))
        }
    }

    private func checkPreconditionsBeforeSession() throws {
        if let message = app.signer.installMessage { throw WatchVoiceStartError(text: message) }
        guard ModelKeys.hasUsableKey else {
            throw WatchVoiceStartError(message: "Choose a model in Poki’s settings on iPhone, then try again.")
        }
        guard !chat.running, !app.voice.isOn, ChatModel.delegatedBusy == nil else {
            throw WatchVoiceStartError(message: "Poki is busy on iPhone. Wait for the current task and try again.")
        }
        guard app.automationPath == .inProcess, !app.ownerPaused else {
            throw WatchVoiceStartError(message: "Turn on Poki with on-device automation on iPhone, then try again.")
        }
    }

    private func checkSessionReady() throws {
        guard app.automationPath == .inProcess, app.sessionOn, !app.ownerPaused else {
            throw WatchVoiceStartError(message: "Turn on Poki with on-device automation on iPhone, then try again.")
        }
    }

    private func blocked(_ id: UUID, _ message: LocalizedStringResource) -> WatchVoiceUpdate {
        WatchVoiceUpdate(id: id, phase: .blocked, text: AppLocalization.text(message))
    }

    @discardableResult
    private func complete(_ update: WatchVoiceUpdate) -> WatchVoiceUpdate {
        clearNoticeIfNeeded(for: update.id)
        removePendingAudio(for: update.id)
        if waitingUnlockID == update.id { waitingUnlockID = nil }
        if work == nil { endBackgroundTask() }
        let terminal: WatchVoiceUpdate
        do {
            try store(update)
            terminal = update
        } catch {
            terminal = blocked(update.id, "Poki couldn’t save the result on iPhone. Check the task there before trying again.")
            resultJournal.storeInMemoryFallback(terminal)
        }
        AppLog.shared.add("watch", "Watch task \(update.id) ended as \(terminal.phase)")
        publish(terminal)
        return terminal
    }

    private func publish(_ update: WatchVoiceUpdate) {
        channel.publishTaskUpdate(update)
    }

    private func publishContext(_ update: WatchVoiceUpdate) {
        channel.publishTaskContext(update)
    }

    private func beginRemoteBackgroundTask() {
        guard remoteBackgroundTask == .invalid else { return }
        remoteBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Poki Watch voice remote") { [weak self] in
            Task { @MainActor in
                self?.endRemoteBackgroundTask()
            }
        }
    }

    private func endRemoteBackgroundTask() {
        guard remoteBackgroundTask != .invalid else { return }
        let id = remoteBackgroundTask
        remoteBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
        Task { @MainActor in replyHandler(self.channel.handleMessageData(data)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.channel.handleRemoteMessage(message)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            _ = self.channel.handleRemoteMessage(userInfo, pushSnapshot: true)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            channel.remoteHost.setMeterStreaming(session.isReachable)
            channel.publishRemoteSnapshot(channel.remoteHost.currentSnapshot())
            self.resumeWaitingTaskIfUnlocked()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            channel.remoteHost.setMeterStreaming(session.isReachable)
            if session.isReachable {
                channel.publishRemoteSnapshot(channel.remoteHost.currentSnapshot())
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            channel.remoteHost.setMeterStreaming(session.isReachable)
            if session.isPaired, session.isWatchAppInstalled {
                channel.syncRemoteContext(channel.remoteHost.currentSnapshot())
            }
            if session.isReachable {
                channel.publishRemoteSnapshot(channel.remoteHost.currentSnapshot())
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

private final class LockStateMailbox {
    private static let lockStateName = "com.apple.springboard.lockstate" as CFString
    #if DEBUG && targetEnvironment(simulator)
    private static let simUnlockName = "nz.zheha.poki.watchVoice.simUnlock" as CFString
    #endif

    weak var owner: WatchVoicePhone?

    init(owner: WatchVoicePhone) {
        self.owner = owner
    }

    func listen() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let mailbox = Unmanaged<LockStateMailbox>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in mailbox.owner?.handleUnlockSignal() }
        }, Self.lockStateName, nil, .deliverImmediately)
        #if DEBUG && targetEnvironment(simulator)
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let mailbox = Unmanaged<LockStateMailbox>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in mailbox.owner?.handleSimulatedUnlock() }
        }, Self.simUnlockName, nil, .deliverImmediately)
        #endif
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(Self.lockStateName), nil)
        #if DEBUG && targetEnvironment(simulator)
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(Self.simUnlockName), nil)
        #endif
    }
}

private struct WatchVoiceStartError: LocalizedError {
    let errorDescription: String?

    init(message: LocalizedStringResource) { errorDescription = AppLocalization.text(message) }
    init(text: String) { errorDescription = text }
}
#endif
