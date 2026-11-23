import AVFAudio
import Foundation
import Observation
import UIKit

struct WatchVoiceRemoteEnvironment {
    var isProtectedDataAvailable: @MainActor () -> Bool
    var isSetupReady: @MainActor () -> Bool
    var isBusy: @MainActor () -> Bool
    var hasMicrophonePermission: @MainActor () -> Bool
    var currentStep: @MainActor () -> String?
    var prepareForVoice: @MainActor () -> Void
    var stopVoice: @MainActor () -> Void
    var requestForegroundContinuation: @MainActor () -> Void
    var now: @MainActor () -> Date
}

@MainActor
final class WatchVoiceRemoteHost {
    private struct SnapshotSignature: Equatable {
        let state: WatchVoiceCallState
        let callID: String?
        let isMuted: Bool
        let transportConnected: Bool
        let inputReady: Bool
        let requiresForeground: Bool
        let detail: String?
        let currentStep: String?
        let latestResult: WatchVoiceUpdate?
        let recentResults: [WatchVoiceUpdate]
    }

    private static let epochDefaultsKey = "poki.watchVoice.remote.epoch"
    private static let maxCachedReplies = 256

    let epoch: UInt64
    let window: WatchVoiceCommandWindow
    private let voice: VoiceModel
    private let environment: WatchVoiceRemoteEnvironment
    private var sequence: UInt64 = 0
    private var lastSignature: SnapshotSignature?
    private var lastSnapshot: WatchVoiceRemoteSnapshot?
    private var pendingRequiresForeground = false
    private var pendingDetail: String?
    private var recentFullResults: [WatchVoiceUpdate] = []
    private var deliveredSpokenResultID: UUID?
    private var deliveredFailureCallID: String?
    private var lastActiveCallID: String?
    private var handledReplies: [UUID: WatchVoiceRemoteReply] = [:]
    private var handledOrder: [UUID] = []
    private var observing = false
    private var meterTask: Task<Void, Never>?
    private var meterEnabled = false

    var onSnapshot: ((WatchVoiceRemoteSnapshot) -> Void)?
    var onMeter: ((WatchVoiceRemoteMeter) -> Void)?
    var onResult: ((WatchVoiceUpdate) -> Void)?

    init(
        voice: VoiceModel,
        environment: WatchVoiceRemoteEnvironment,
        epoch: UInt64? = nil,
        window: WatchVoiceCommandWindow = WatchVoiceRemote.defaultCommandWindow
    ) {
        self.voice = voice
        self.environment = environment
        self.epoch = epoch ?? Self.nextPersistedEpoch(now: environment.now())
        self.window = window
    }

    convenience init(
        app: AppModel,
        chat: ChatModel,
        isWatchTaskBusy: @escaping @MainActor () -> Bool,
        epoch: UInt64? = nil
    ) {
        self.init(
            voice: app.voice,
            environment: WatchVoiceRemoteEnvironment(
                isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable },
                isSetupReady: { !FirstRun.isDue() && !app.pairingUnderWay && app.voice.canTalkLive },
                isBusy: { chat.running || ChatModel.delegatedBusy != nil || isWatchTaskBusy() },
                hasMicrophonePermission: { AVAudioApplication.shared.recordPermission == .granted },
                currentStep: {
                    guard app.voice.isOn else { return nil }
                    if let plan = app.activityPlan, plan.total > 0 {
                        let current = min(max(plan.current, 1), plan.total)
                        let stepTitle = (plan.steps.indices.contains(current - 1) ? plan.steps[current - 1] : nil)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let planTitle = plan.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = (stepTitle?.isEmpty == false ? stepTitle : nil)
                            ?? (planTitle?.isEmpty == false ? planTitle : nil)
                        if let name {
                            return "\(current)/\(plan.total) \(name)"
                        }
                    }
                    #if DEBUG && targetEnvironment(simulator)
                    if TalkRehearsal.asked,
                       let rehearsalStep = TalkRehearsal.rehearsalStep,
                       app.voice.activeStepDescription != nil {
                        return rehearsalStep
                    }
                    #endif
                    let activityStep = app.activityText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !activityStep.isEmpty, activityStep != "Idle" {
                        return ActivityWords.label(activityStep)
                    }
                    return app.voice.activeStepDescription
                },
                prepareForVoice: { app.prepareForTask() },
                stopVoice: { app.stopFromOutside("Apple Watch ended the talk") },
                requestForegroundContinuation: { PokiEntry.shared.ask(.talk) },
                now: { Date() }
            ),
            epoch: epoch
        )
    }

    deinit {
        meterTask?.cancel()
    }

    static func nextPersistedEpoch(defaults: UserDefaults = .standard, now: Date = Date()) -> UInt64 {
        let saved = (defaults.object(forKey: epochDefaultsKey) as? NSNumber)?.uint64Value ?? 0
        let clockFloor = UInt64(max(1, Int64(now.timeIntervalSince1970 * 1000)))
        let next = max(saved &+ 1, clockFloor)
        defaults.set(NSNumber(value: next), forKey: epochDefaultsKey)
        return next
    }

    /// Reuses Dynamic Island's `PokiState.Voice` states (`.listening`, `.thinking`, `.speaking`)
    /// alongside `.connecting`, `.muted`, `.ending`, `.idle`, `.needsSetup`, and `.failed`.
    static func callState(of voice: VoiceModel, isSetupReady: Bool) -> WatchVoiceCallState {
        if voice.isEnding { return .ending }
        if case .connecting = voice.phase { return .connecting }
        if voice.isOn {
            if voice.microphoneMuted { return .muted }
            if let islandState = TalkActivity.state(of: voice) {
                switch islandState {
                case .listening: return .listening
                case .thinking: return .thinking
                case .speaking: return .speaking
                }
            }
            return .listening
        }
        if case .lost = voice.phase { return .failed }
        return isSetupReady ? .idle : .needsSetup
    }

    func startObserving() {
        guard !observing else { return }
        observing = true
        followVoice()
    }

    func setMeterStreaming(_ enabled: Bool) {
        meterEnabled = enabled
        updateMeterPolling()
    }

    func currentSnapshot() -> WatchVoiceRemoteSnapshot {
        refreshSnapshot(notify: false)
    }

    func handle(_ command: WatchVoiceRemoteCommand) -> WatchVoiceRemoteReply {
        if let cached = handledReplies[command.requestID] {
            return cached
        }
        if case .state = command.action {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .accepted,
                snapshot: snapshot,
                detail: snapshot.detail
            ))
        }
        // A targeted End stays valid across reconnect delays so a disconnected/muted call is never
        // left un-endable on iPhone, while `handleEnd` still rejects any mismatched newer call ID.
        if case .end = command.action, command.targetCallID != nil {
            return handleEnd(command)
        }
        let now = environment.now()
        guard window.acceptsCommand(issuedAt: command.issuedAt, now: now) else {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .expired,
                snapshot: snapshot,
                detail: AppLocalization.text(LocalizedStringResource("That Watch command expired. Try again."))
            ))
        }

        switch command.action {
        case .state:
            preconditionFailure("Handled above")

        case .start:
            return handleStart(command)

        case .setMuted(let muted):
            return handleSetMuted(command, muted: muted)

        case .end:
            return handleEnd(command)
        }
    }

    private func handleStart(_ command: WatchVoiceRemoteCommand) -> WatchVoiceRemoteReply {
        if voice.isOn {
            pendingRequiresForeground = false
            pendingDetail = nil
            let snapshot = refreshSnapshot(notify: true)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .noChange,
                snapshot: snapshot,
                detail: nil
            ))
        }
        if voice.isEnding {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .busy,
                snapshot: snapshot,
                detail: AppLocalization.text(LocalizedStringResource("Poki is ending the previous call. Try again in a moment."))
            ))
        }
        guard environment.isProtectedDataAvailable() else {
            return requiresForegroundReply(
                for: command,
                detail: AppLocalization.text(LocalizedStringResource("Unlock iPhone and open Poki to start voice."))
            )
        }
        guard environment.isSetupReady() else {
            pendingRequiresForeground = false
            let detail = AppLocalization.text(LocalizedStringResource("Set up Poki’s voice on iPhone first."))
            pendingDetail = detail
            let snapshot = refreshSnapshot(notify: true)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .needsSetup,
                snapshot: snapshot,
                detail: detail
            ))
        }
        guard !environment.isBusy() else {
            pendingRequiresForeground = false
            let detail = AppLocalization.text(LocalizedStringResource("Poki is busy with another task on iPhone."))
            pendingDetail = detail
            let snapshot = refreshSnapshot(notify: true)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .busy,
                snapshot: snapshot,
                detail: detail
            ))
        }
        guard environment.hasMicrophonePermission() else {
            return requiresForegroundReply(
                for: command,
                detail: AppLocalization.text(LocalizedStringResource("Allow microphone access in Poki on iPhone."))
            )
        }

        pendingRequiresForeground = false
        pendingDetail = nil
        environment.prepareForVoice()
        guard voice.beginLiveStart(microphone: true) != nil else {
            let detail = AppLocalization.text(LocalizedStringResource("Poki couldn’t start live voice on iPhone."))
            pendingDetail = detail
            let snapshot = refreshSnapshot(notify: true)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .failed,
                snapshot: snapshot,
                detail: detail
            ))
        }
        lastActiveCallID = voice.callID

        let snapshot = refreshSnapshot(notify: true)
        updateMeterPolling()
        return record(WatchVoiceRemoteReply(
            requestID: command.requestID,
            outcome: .accepted,
            snapshot: snapshot,
            detail: nil
        ))
    }

    private func handleSetMuted(_ command: WatchVoiceRemoteCommand, muted: Bool) -> WatchVoiceRemoteReply {
        guard voice.isOn, let activeCallID = voice.callID, command.targetCallID == activeCallID else {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .callChanged,
                snapshot: snapshot,
                detail: AppLocalization.text(LocalizedStringResource("The call on iPhone has changed."))
            ))
        }
        if voice.microphoneMuted == muted {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .noChange,
                snapshot: snapshot,
                detail: nil
            ))
        }
        voice.setMicrophoneMuted(muted)
        let snapshot = refreshSnapshot(notify: true)
        return record(WatchVoiceRemoteReply(
            requestID: command.requestID,
            outcome: .accepted,
            snapshot: snapshot,
            detail: nil
        ))
    }

    private func handleEnd(_ command: WatchVoiceRemoteCommand) -> WatchVoiceRemoteReply {
        if !voice.isOn && !voice.isEnding {
            let outcome: WatchVoiceRemoteOutcome = command.targetCallID == nil ? .noChange : .callChanged
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: outcome,
                snapshot: snapshot,
                detail: nil
            ))
        }
        if voice.isEnding {
            let outcome: WatchVoiceRemoteOutcome = (command.targetCallID == nil || command.targetCallID == voice.callID) ? .noChange : .callChanged
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: outcome,
                snapshot: snapshot,
                detail: nil
            ))
        }
        guard let activeCallID = voice.callID, command.targetCallID == activeCallID else {
            let snapshot = refreshSnapshot(notify: false)
            return record(WatchVoiceRemoteReply(
                requestID: command.requestID,
                outcome: .callChanged,
                snapshot: snapshot,
                detail: AppLocalization.text(LocalizedStringResource("The call on iPhone has changed."))
            ))
        }
        pendingRequiresForeground = false
        pendingDetail = nil
        environment.stopVoice()
        captureCompletedResultIfReady()
        let snapshot = refreshSnapshot(notify: true)
        updateMeterPolling()
        return record(WatchVoiceRemoteReply(
            requestID: command.requestID,
            outcome: .accepted,
            snapshot: snapshot,
            detail: nil
        ))
    }

    private func requiresForegroundReply(for command: WatchVoiceRemoteCommand, detail: String) -> WatchVoiceRemoteReply {
        pendingRequiresForeground = true
        pendingDetail = detail
        environment.requestForegroundContinuation()
        let snapshot = refreshSnapshot(notify: true)
        return record(WatchVoiceRemoteReply(
            requestID: command.requestID,
            outcome: .requiresForeground,
            snapshot: snapshot,
            detail: detail
        ))
    }

    private func followVoice() {
        withObservationTracking {
            _ = voice.phase
            _ = voice.isOn
            _ = voice.isEnding
            _ = voice.microphoneMuted
            _ = voice.callID
            _ = voice.isTransportConnected
            _ = voice.isInputReady
            _ = voice.lastStartFailedInBackground
            _ = voice.calls
            _ = voice.midTurn
            _ = voice.latestSpokenResult
            _ = environment.currentStep()
            handleObservedChange()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.followVoice()
            }
        }
    }

    private func handleObservedChange() {
        if let activeID = voice.callID {
            lastActiveCallID = activeID
        }
        if voice.isOn {
            pendingRequiresForeground = false
            pendingDetail = nil
        } else if voice.lastStartFailedInBackground, case .lost = voice.phase {
            if !pendingRequiresForeground {
                pendingRequiresForeground = true
                pendingDetail = AppLocalization.text(LocalizedStringResource("Continue on iPhone to start voice."))
                environment.requestForegroundContinuation()
            }
        }
        captureCompletedResultIfReady()
        _ = refreshSnapshot(notify: true)
        updateMeterPolling()
    }

    private func captureCompletedResultIfReady() {
        if let spoken = voice.latestSpokenResult,
           spoken.id != deliveredSpokenResultID,
           (!voice.midTurn || !voice.isOn || voice.isEnding) {
            deliveredSpokenResultID = spoken.id
            let full = WatchVoiceUpdate(id: spoken.id, phase: .finished, text: spoken.text)
            recordCompletedResult(full)
            return
        }
        if !voice.isOn,
           !voice.lastStartFailedInBackground,
           case .lost(let why) = voice.phase,
           let failedCall = lastActiveCallID,
           failedCall != deliveredFailureCallID {
            deliveredFailureCallID = failedCall
            let failed = WatchVoiceUpdate(id: UUID(), phase: .blocked, text: why)
            recordCompletedResult(failed)
        }
    }

    private func recordCompletedResult(_ result: WatchVoiceUpdate) {
        recentFullResults.removeAll { $0.id == result.id }
        recentFullResults.insert(result, at: 0)
        if recentFullResults.count > WatchVoiceRemote.maxRecentResults {
            recentFullResults.removeLast(recentFullResults.count - WatchVoiceRemote.maxRecentResults)
        }
        onResult?(result)
    }

    @discardableResult
    private func refreshSnapshot(notify: Bool) -> WatchVoiceRemoteSnapshot {
        let state = Self.callState(of: voice, isSetupReady: environment.isSetupReady())
        let detail: String? = switch state {
        case .failed:
            if case .lost(let why) = voice.phase { pendingDetail ?? why } else { pendingDetail }
        case .idle, .needsSetup:
            pendingDetail
        default:
            nil
        }
        let stepText: String? = state.isActiveCall ? Self.oneLine(environment.currentStep()) : nil
        let deliveredRecent = recentFullResults.enumerated().map { index, item in
            index == 0 ? item.forDelivery() : item.forCompactDelivery()
        }
        let deliveryResult = deliveredRecent.first
        let signature = SnapshotSignature(
            state: state,
            callID: voice.callID,
            isMuted: voice.isOn && voice.microphoneMuted,
            transportConnected: voice.isTransportConnected,
            inputReady: voice.isInputReady,
            requiresForeground: pendingRequiresForeground,
            detail: detail,
            currentStep: stepText,
            latestResult: deliveryResult,
            recentResults: deliveredRecent
        )
        if signature == lastSignature, let lastSnapshot {
            return lastSnapshot
        }
        sequence += 1
        let snapshot = WatchVoiceRemoteSnapshot(
            epoch: epoch,
            sequence: sequence,
            state: signature.state,
            callID: signature.callID,
            isMuted: signature.isMuted,
            transportConnected: signature.transportConnected,
            inputReady: signature.inputReady,
            requiresForeground: signature.requiresForeground,
            updatedAt: environment.now(),
            detail: signature.detail,
            currentStep: signature.currentStep,
            latestResult: signature.latestResult,
            recentResults: signature.recentResults
        )
        lastSignature = signature
        lastSnapshot = snapshot
        if notify {
            onSnapshot?(snapshot)
        }
        return snapshot
    }

    private static func oneLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }

    private func updateMeterPolling() {
        guard meterEnabled, voice.isOn, !voice.isEnding, !voice.microphoneMuted else {
            meterTask?.cancel()
            meterTask = nil
            return
        }
        guard meterTask == nil else { return }
        meterTask = Task { [weak self] in
            var lastSent: UInt8 = 0
            var lastSentAt = Date.distantPast
            while !Task.isCancelled {
                guard let self, self.meterEnabled, self.voice.isOn, !self.voice.isEnding, !self.voice.microphoneMuted else { break }
                if let callID = self.voice.callID {
                    let raw = await self.voice.remoteAudioLevel() ?? 0
                    let level = UInt8(min(255, max(0, Int((raw * 255.0).rounded()))))
                    let now = self.environment.now()
                    if level != lastSent || (level > 0 && now.timeIntervalSince(lastSentAt) >= 0.6) {
                        lastSent = level
                        lastSentAt = now
                        self.onMeter?(WatchVoiceRemoteMeter(
                            epoch: self.epoch,
                            callID: callID,
                            level: level,
                            timestamp: now
                        ))
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.meterTask = nil
        }
    }

    private func record(_ reply: WatchVoiceRemoteReply) -> WatchVoiceRemoteReply {
        if handledReplies[reply.requestID] == nil {
            handledOrder.append(reply.requestID)
            if handledOrder.count > Self.maxCachedReplies {
                let oldest = handledOrder.removeFirst()
                handledReplies.removeValue(forKey: oldest)
            }
        }
        handledReplies[reply.requestID] = reply
        return reply
    }
}

@MainActor
protocol WatchVoiceTransport: AnyObject {
    var isActivated: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }
    var applicationContext: [String: Any] { get }
    func updateApplicationContext(_ context: [String: Any]) throws
    func sendMessage(_ message: [String: Any])
    func sendMessageData(_ data: Data)
    func transferUserInfo(_ userInfo: [String: Any])
}

@MainActor
final class WatchVoiceRemoteChannel {
    let remoteHost: WatchVoiceRemoteHost
    let resultJournal: WatchVoiceResultJournal
    private let transport: WatchVoiceTransport
    private var latestTaskContext: Data?
    private var latestRemoteContext: Data?
    private var lastSyncedSnapshot: WatchVoiceRemoteSnapshot?
    private var handlingRemoteCommand = false

    var onTaskRequest: ((WatchVoiceRequest) -> Data)?
    var onBackgroundTaskNeeded: ((Bool) -> Void)?
    var onLog: ((String) -> Void)?

    init(
        remoteHost: WatchVoiceRemoteHost,
        resultJournal: WatchVoiceResultJournal,
        transport: WatchVoiceTransport
    ) {
        self.remoteHost = remoteHost
        self.resultJournal = resultJournal
        self.transport = transport
        remoteHost.onSnapshot = { [weak self] snapshot in self?.publishRemoteSnapshot(snapshot) }
        remoteHost.onMeter = { [weak self] meter in self?.publishRemoteMeter(meter) }
        remoteHost.onResult = { [weak self] result in self?.storeRemoteResult(result) }
    }

    func handleMessageData(_ data: Data) -> Data {
        guard data.count <= WatchVoiceRequest.maxMessageBytes,
              let request = try? JSONDecoder().decode(WatchVoiceRequest.self, from: data) else {
            return Data()
        }
        if case .result(let id, let offset) = request {
            return resultJournal.resultChunk(id: id, offset: offset)
        }
        return onTaskRequest?(request) ?? Data()
    }

    func handleRemoteMessage(_ message: [String: Any], pushSnapshot: Bool = false) -> [String: Any] {
        guard let data = message[WatchVoiceRemote.commandKey] as? Data,
              data.count <= WatchVoiceRequest.maxMessageBytes,
              let command = try? JSONDecoder().decode(WatchVoiceRemoteCommand.self, from: data) else {
            return [:]
        }
        handlingRemoteCommand = true
        let reply = remoteHost.handle(command)
        handlingRemoteCommand = false
        let currentSnapshot = remoteHost.currentSnapshot()
        onBackgroundTaskNeeded?(currentSnapshot.state.isActiveCall || currentSnapshot.state == .ending)
        if pushSnapshot {
            publishRemoteSnapshot(currentSnapshot)
        } else {
            syncRemoteContext(currentSnapshot)
        }
        onLog?("Watch remote \(command.action) (\(command.requestID)) -> \(reply.outcome.rawValue), state \(currentSnapshot.state.rawValue) [\(currentSnapshot.epoch):\(currentSnapshot.sequence)]")
        guard let encoded = try? JSONEncoder().encode(reply) else { return [:] }
        return [WatchVoiceRemote.replyKey: encoded]
    }

    func publishTaskUpdate(_ update: WatchVoiceUpdate) {
        guard transport.isActivated, transport.isWatchAppInstalled else { return }
        let data = encodeUpdate(update)
        guard !data.isEmpty else { return }
        if transport.isReachable { transport.sendMessageData(data) }
        if update.phase != .received {
            latestTaskContext = data
            syncApplicationContext()
        }
    }

    func publishTaskContext(_ update: WatchVoiceUpdate) {
        guard transport.isActivated, transport.isWatchAppInstalled else { return }
        let data = encodeUpdate(update)
        guard !data.isEmpty else { return }
        latestTaskContext = data
        syncApplicationContext()
    }

    func storeRemoteResult(_ update: WatchVoiceUpdate) {
        do {
            try resultJournal.store(update)
        } catch {
            resultJournal.storeInMemoryFallback(update)
        }
        let delivery = encodeUpdate(update)
        if !delivery.isEmpty,
           transport.isActivated,
           transport.isPaired,
           transport.isWatchAppInstalled {
            transport.transferUserInfo([WatchVoiceRemote.resultKey: delivery])
        }
    }

    func publishRemoteSnapshot(_ snapshot: WatchVoiceRemoteSnapshot) {
        if !snapshot.state.isActiveCall && snapshot.state != .ending {
            onBackgroundTaskNeeded?(false)
        }
        guard !handlingRemoteCommand else { return }
        if let lastSyncedSnapshot, lastSyncedSnapshot.isNewer(than: snapshot) { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lastSyncedSnapshot = snapshot
        latestRemoteContext = data
        guard transport.isActivated else { return }
        if transport.isReachable {
            transport.sendMessage([WatchVoiceRemote.snapshotKey: data])
        }
        syncApplicationContext()
    }

    func syncRemoteContext(_ snapshot: WatchVoiceRemoteSnapshot) {
        if let lastSyncedSnapshot, lastSyncedSnapshot.isNewer(than: snapshot) { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lastSyncedSnapshot = snapshot
        latestRemoteContext = data
        syncApplicationContext()
    }

    func publishRemoteMeter(_ meter: WatchVoiceRemoteMeter) {
        guard transport.isActivated, transport.isReachable,
              let data = try? JSONEncoder().encode(meter) else { return }
        transport.sendMessage([WatchVoiceRemote.meterKey: data])
    }

    func syncApplicationContext() {
        guard transport.isActivated, transport.isPaired, transport.isWatchAppInstalled else { return }
        let context = WatchVoiceRemote.mergeApplicationContext(
            existing: transport.applicationContext,
            taskContext: latestTaskContext,
            remoteContext: latestRemoteContext
        )
        guard !context.isEmpty else { return }
        do {
            try transport.updateApplicationContext(context)
        } catch {
            onLog?("Watch application context sync deferred")
        }
    }

    func encodeUpdate(_ update: WatchVoiceUpdate?) -> Data {
        guard let update else { return Data() }
        return (try? JSONEncoder().encode(update.forDelivery())) ?? Data()
    }
}
