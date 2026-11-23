import Foundation
import Observation
#if !os(watchOS)
@testable import Poki
#endif

@MainActor
protocol WatchVoiceDeliveryLink: AnyObject {
    var isActivated: Bool { get }
    var isCompanionInstalled: Bool { get }
    var isReachable: Bool { get }
    var needsUnlockAfterReboot: Bool { get }
    func activate()
    func sendMessageData(
        _ data: Data,
        replyHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    )
}

struct WatchVoiceDeliveryTiming: Sendable {
    let reachabilityWait: Duration
    let sendTimeout: Duration
    let unlockPollInterval: Duration

    static let live = Self(
        reachabilityWait: .seconds(3),
        sendTimeout: .seconds(10),
        unlockPollInterval: .seconds(4)
    )
}

@MainActor
@Observable
final class WatchVoiceDeliveryController {
    struct Pending: Codable, Equatable {
        let id: UUID
        var audio: Data?
        var update: WatchVoiceUpdate?
    }

    struct Archive: Codable, Equatable {
        var pending: Pending?
        var results: [WatchVoiceUpdate] = []
        var remoteSnapshot: WatchVoiceRemoteSnapshot? = nil
        var pendingEnd: WatchVoicePendingEnd? = nil
    }

    private let link: any WatchVoiceDeliveryLink
    private let archiveURL: URL
    private let timing: WatchVoiceDeliveryTiming
    private var archive = Archive()
    @ObservationIgnored private var reachabilityWait: Task<Void, Never>?
    @ObservationIgnored private var sendTimeout: Task<Void, Never>?
    @ObservationIgnored private var waitingUnlockPoll: Task<Void, Never>?
    @ObservationIgnored private var sendToken = 0
    @ObservationIgnored private(set) var isActive = false
    @ObservationIgnored var onTerminalUpdate: (@MainActor (WatchVoiceUpdate) -> Void)?
    @ObservationIgnored var onWaitingForUnlock: (@MainActor () -> Void)?
    @ObservationIgnored var onDeliveryFailure: (@MainActor () -> Void)?

    private(set) var sending = false
    private(set) var deliveryFailure: WatchVoiceDeliveryFailure?
    private(set) var problem: LocalizedStringResource?

    var hasPending: Bool { archive.pending != nil }
    var update: WatchVoiceUpdate? { archive.pending?.update }
    var results: [WatchVoiceUpdate] { archive.results }
    var remoteSnapshot: WatchVoiceRemoteSnapshot? { archive.remoteSnapshot }
    var pendingEnd: WatchVoicePendingEnd? { archive.pendingEnd }
    var pendingStatus: WatchVoicePendingStatus {
        WatchVoicePendingStatus.resolve(hasPending: hasPending, sending: sending, update: update, failure: deliveryFailure)
    }

    init(
        link: any WatchVoiceDeliveryLink,
        archiveURL: URL = URL.applicationSupportDirectory.appending(path: "WatchVoice.json"),
        timing: WatchVoiceDeliveryTiming = .live
    ) {
        self.link = link
        self.archiveURL = archiveURL
        self.timing = timing
        if let saved = try? Data(contentsOf: archiveURL),
           let decoded = try? JSONDecoder().decode(Archive.self, from: saved) {
            archive = decoded
        }
    }

    deinit {
        waitingUnlockPoll?.cancel()
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateWaitingUnlockPoll()
    }

    func enqueue(id: UUID = UUID(), audio: Data) -> Bool {
        guard !hasPending else { return false }
        problem = nil
        deliveryFailure = nil
        var next = archive
        next.pending = Pending(id: id, audio: audio)
        guard save(next) else { return false }
        sync()
        return true
    }

    func discardPending() {
        guard archive.pending?.update == nil else { return }
        cancelInFlightDelivery()
        stopWaitingUnlockPoll()
        var next = archive
        next.pending = nil
        if save(next) {
            deliveryFailure = nil
            problem = nil
        }
    }

    func clearProblem() {
        problem = nil
        deliveryFailure = nil
    }

    func setProblem(_ message: LocalizedStringResource) {
        problem = message
    }

    @discardableResult
    func updateRemoteState(
        snapshot: WatchVoiceRemoteSnapshot?,
        pendingEnd: WatchVoicePendingEnd?,
        ingesting incoming: [WatchVoiceUpdate]
    ) -> [WatchVoiceUpdate] {
        var next = archive
        next.remoteSnapshot = snapshot
        next.pendingEnd = pendingEnd
        let (merged, added) = WatchVoiceRemote.mergeResults(incoming, into: next.results)
        next.results = merged
        guard next != archive else { return [] }
        guard save(next) else { return [] }
        return added
    }

    func sync() {
        guard let pending = archive.pending, !sending else { return }
        deliveryFailure = nil
        problem = nil
        if !link.isActivated {
            link.activate()
            waitForConnection(id: pending.id, onTimeout: .sessionInactive)
            return
        }
        if !link.isCompanionInstalled {
            failDelivery(.companionNotInstalled)
            return
        }
        if link.needsUnlockAfterReboot {
            failDelivery(.needsUnlockAfterReboot)
            return
        }
        if !link.isReachable {
            waitForConnection(id: pending.id, onTimeout: .phoneUnavailable)
            return
        }
        sendNow(pending)
    }

    func loadFullResult(_ id: UUID) async -> Bool {
        guard let result = results.first(where: { $0.id == id }),
              let total = result.fullTextBytes else { return true }
        var received = Data()
        while received.count < total {
            guard !Task.isCancelled, link.isActivated, link.isReachable,
                  let request = try? JSONEncoder().encode(WatchVoiceRequest.result(id: id, offset: received.count)),
                  let chunk = await resultReply(to: request),
                  chunk.count == min(total - received.count, WatchVoiceRequest.resultChunkBytes) else { return false }
            received.append(chunk)
        }
        guard !Task.isCancelled, let text = String(data: received, encoding: .utf8),
              let index = archive.results.firstIndex(where: { $0.id == id }) else { return false }
        var next = archive
        next.results[index] = WatchVoiceUpdate(id: id, phase: result.phase, text: text)
        return save(next)
    }

    func receive(_ update: WatchVoiceUpdate) {
        guard var pending = archive.pending, update.id == pending.id,
              pending.update.map({ $0.phase.canAdvance(to: update.phase) }) ?? true else { return }
        var next = archive
        if update.phase.isTerminal {
            next.pending = nil
            next.results = WatchVoiceRemote.mergeResults([update], into: next.results).merged
        } else {
            pending.update = update
            pending.audio = nil
            next.pending = pending
        }
        guard save(next) else { return }
        cancelInFlightDelivery()
        deliveryFailure = nil
        problem = nil
        if update.phase.isTerminal {
            stopWaitingUnlockPoll()
            onTerminalUpdate?(update)
        } else if update.phase == .waitingForUnlock {
            updateWaitingUnlockPoll()
            onWaitingForUnlock?()
        } else {
            stopWaitingUnlockPoll()
        }
    }

    func receiveContext(_ context: [String: Any]) {
        if let data = context[WatchVoiceRequest.contextKey] as? Data,
           let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: data) {
            receive(update)
        }
    }

    func activationDidComplete(activated: Bool) {
        if activated {
            if reachabilityWait != nil {
                reachabilityWait?.cancel()
                reachabilityWait = nil
                sending = false
            }
            if archive.pending != nil { sync() }
            updateWaitingUnlockPoll()
        } else {
            cancelInFlightDelivery()
            stopWaitingUnlockPoll()
            failDelivery(.sessionInactive)
        }
    }

    func reachabilityDidChange() {
        guard link.isReachable else { return }
        if reachabilityWait != nil {
            reachabilityWait?.cancel()
            reachabilityWait = nil
            sending = false
        }
        if archive.pending != nil { sync() }
        updateWaitingUnlockPoll()
    }

    private func stopWaitingUnlockPoll() {
        waitingUnlockPoll?.cancel()
        waitingUnlockPoll = nil
    }

    private func updateWaitingUnlockPoll() {
        stopWaitingUnlockPoll()
        guard isActive, let pending = archive.pending, pending.update?.phase == .waitingForUnlock else { return }
        let id = pending.id
        let interval = timing.unlockPollInterval
        waitingUnlockPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, self.isActive,
                      self.archive.pending?.id == id,
                      self.archive.pending?.update?.phase == .waitingForUnlock else { break }
                guard !self.sending, self.link.isActivated, self.link.isCompanionInstalled,
                      !self.link.needsUnlockAfterReboot, self.link.isReachable,
                      let data = try? JSONEncoder().encode(WatchVoiceRequest.status(id: id)) else { continue }
                self.link.sendMessageData(data) { [weak self] reply in
                    Task { @MainActor in
                        guard let self, self.archive.pending?.id == id,
                              let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: reply),
                              update.id == id else { return }
                        self.receive(update)
                    }
                } errorHandler: { _ in }
            }
        }
    }

    private func cancelInFlightDelivery() {
        sendToken &+= 1
        reachabilityWait?.cancel()
        reachabilityWait = nil
        sendTimeout?.cancel()
        sendTimeout = nil
        sending = false
    }

    private func waitForConnection(id: UUID, onTimeout failure: WatchVoiceDeliveryFailure) {
        reachabilityWait?.cancel()
        sending = true
        sendToken &+= 1
        let token = sendToken
        let duration = timing.reachabilityWait
        reachabilityWait = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.sendToken == token, self.archive.pending?.id == id else { return }
            self.reachabilityWait = nil
            self.sending = false
            if self.link.isActivated, self.link.isReachable {
                self.sync()
            } else if self.link.needsUnlockAfterReboot {
                self.failDelivery(.needsUnlockAfterReboot)
            } else {
                self.failDelivery(failure)
            }
        }
    }

    private func sendNow(_ pending: Pending) {
        reachabilityWait?.cancel()
        reachabilityWait = nil
        let request = pending.audio.map { WatchVoiceRequest.submit(id: pending.id, audio: $0) } ?? .status(id: pending.id)
        guard let data = try? JSONEncoder().encode(request) else {
            failDelivery(.deliveryFailed)
            return
        }
        sendToken &+= 1
        let token = sendToken
        sending = true
        sendTimeout?.cancel()
        let duration = timing.sendTimeout
        sendTimeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.sendToken == token, self.archive.pending?.id == pending.id else { return }
            self.sendTimeout = nil
            self.sending = false
            self.failDelivery(.timedOut)
        }
        link.sendMessageData(data) { [weak self] reply in
            Task { @MainActor in
                guard let self, self.archive.pending?.id == pending.id else { return }
                let matchesCurrent = self.sendToken == token
                if matchesCurrent {
                    self.sendTimeout?.cancel()
                    self.sendTimeout = nil
                    self.sending = false
                }
                if let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: reply), update.id == pending.id {
                    self.receive(update)
                } else if !matchesCurrent {
                    return
                } else if pending.update != nil {
                    self.receive(WatchVoiceUpdate(id: pending.id, phase: .blocked, text: String(localized:
                        "Poki couldn’t find the accepted task on iPhone. Check what happened there before recording it again.")))
                } else {
                    self.failDelivery(.phoneUnavailable)
                }
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                guard let self, self.sendToken == token, self.archive.pending?.id == pending.id else { return }
                self.sendTimeout?.cancel()
                self.sendTimeout = nil
                self.sending = false
                let nsError = error as NSError
                let failure = nsError.domain == "WCErrorDomain"
                    ? WatchVoiceDeliveryFailure.from(wcErrorCode: nsError.code)
                    : .deliveryFailed
                self.failDelivery(failure)
            }
        }
    }

    private func failDelivery(_ failure: WatchVoiceDeliveryFailure) {
        deliveryFailure = failure
        if archive.pending?.update != nil {
            problem = failure.detail
        } else {
            problem = nil
        }
        onDeliveryFailure?()
    }

    private func resultReply(to request: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            link.sendMessageData(request, replyHandler: { continuation.resume(returning: $0) },
                                 errorHandler: { _ in continuation.resume(returning: nil) })
        }
    }

    private func save(_ next: Archive) -> Bool {
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: archiveURL, options: .atomic)
            archive = next
            return true
        } catch {
            problem = "Poki couldn’t save this task on Watch. Check available storage and retry."
            return false
        }
    }
}

extension WatchVoiceDeliveryFailure {
    var title: LocalizedStringResource {
        switch self {
        case .needsUnlockAfterReboot: "Unlock iPhone first"
        case .phoneUnavailable: "Poki isn’t responding on iPhone"
        case .timedOut: "iPhone didn’t reply in time"
        case .companionNotInstalled: "Install Poki on iPhone"
        case .sessionInactive: "Couldn’t connect to iPhone"
        case .deliveryFailed: "Couldn’t send to iPhone"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .needsUnlockAfterReboot: "Your iPhone restarted. Unlock your iPhone, then try again."
        case .phoneUnavailable: "Open Poki on your iPhone if it was closed, then try again."
        case .timedOut: "iPhone took too long to reply. Open Poki on your iPhone and try again."
        case .companionNotInstalled: "Install Poki on your paired iPhone and try again."
        case .sessionInactive: "Move closer to your paired iPhone and try again."
        case .deliveryFailed: "Check your iPhone connection or open Poki, then try again."
        }
    }

    var symbol: String {
        switch self {
        case .needsUnlockAfterReboot: "lock.fill"
        case .phoneUnavailable, .timedOut, .companionNotInstalled, .sessionInactive, .deliveryFailed:
            "exclamationmark.triangle"
        }
    }
}
