#if POKI_WATCH
import Foundation
import UIKit
import WatchConnectivity

@MainActor
final class WatchVoicePhone: NSObject, WCSessionDelegate {
    private let app: AppModel
    private let chat: ChatModel
    private let session = WCSession.default
    private let journal = URL.applicationSupportDirectory.appending(path: "WatchVoice.json")
    private var updates: [UUID: WatchVoiceUpdate] = [:]
    private var journalAvailable = true
    private var activeID: UUID?
    private var work: Task<Void, Never>?

    init(app: AppModel, chat: ChatModel) {
        self.app = app
        self.chat = chat
        super.init()
        do {
            let saved = try Data(contentsOf: journal)
            updates = try JSONDecoder().decode([UUID: WatchVoiceUpdate].self, from: saved)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // The first accepted request creates the journal.
        } catch {
            // An unreadable journal cannot safely distinguish a new request from a retry.
            journalAvailable = false
        }
        session.delegate = self
        session.activate()
    }

    private func store(_ update: WatchVoiceUpdate) throws {
        guard journalAvailable else { throw CocoaError(.fileReadCorruptFile) }
        var next = updates
        next[update.id] = update
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: journal, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        updates = next
    }

    private func reply(to request: WatchVoiceRequest) -> Data {
        switch request {
        case .status(let id):
            return encodeUpdate(status(for: id))
        case .submit(let id, let audio):
            return encodeUpdate(accept(id, audio: audio))
        case .result(let id, let offset):
            return updates[id]?.resultChunk(at: offset) ?? Data()
        }
    }

    private func accept(_ id: UUID, audio: Data) -> WatchVoiceUpdate {
        if let existing = status(for: id) { return existing }
        guard !audio.isEmpty, audio.count <= WatchVoiceRequest.maxAudioBytes else {
            return blocked(id, "The recording is empty or too long. Record a shorter request.")
        }
        let receipt = WatchVoiceUpdate(id: id, phase: .received, text: nil)
        do {
            try store(receipt)
        } catch {
            return blocked(id, "Poki couldn’t save this request on iPhone. Check available storage and try again.")
        }
        AppLog.shared.add("watch", "Received Watch task \(id)")
        guard activeID == nil else {
            return complete(blocked(id, "Poki is handling another Watch task. Wait for it to finish and try again."))
        }
        activeID = id
        work = Task { await run(id, audio: audio) }
        return receipt
    }

    private func status(for id: UUID) -> WatchVoiceUpdate? {
        guard let update = updates[id], !update.phase.isTerminal, activeID != id else { return updates[id] }
        return complete(blocked(id, "Poki was interrupted on iPhone. Check what happened there before sending the task again."))
    }

    private func run(_ id: UUID, audio: Data) async {
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Poki Watch task") { [weak self] in
            self?.work?.cancel()
            if background != .invalid {
                UIApplication.shared.endBackgroundTask(background)
                background = .invalid
            }
        }
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            work = nil
            activeID = nil
        }
        do {
            try checkReady()
            let transcript = try await Dictation.transcribe(recording: audio)
            try Task.checkCancellation()
            try checkReady()
            let running = WatchVoiceUpdate(id: id, phase: .running, text: nil)
            try store(running)
            publish(running)
            let task = ChatModel(app: app, kind: .handoff, requester: "Apple Watch", sessionID: id.uuidString)
            let result = await task.runDelegated(transcript)
            let update = WatchVoiceUpdate(id: id, phase: result.success == true ? .finished : .blocked,
                                          text: result.text)
            complete(update)
        } catch is CancellationError {
            complete(blocked(id, "iPhone stopped the background task. Check Poki on iPhone before trying again."))
        } catch let error as WatchVoiceStartError {
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch let error as WatchVoiceSpeechError {
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch {
            complete(blocked(id, "Poki couldn’t save the task on iPhone. Check available storage and try again."))
        }
    }

    private func checkReady() throws {
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw WatchVoiceStartError(message: "Unlock your iPhone and open Poki, then try again.")
        }
        if let message = app.signer.installMessage { throw WatchVoiceStartError(text: message) }
        guard ModelKeys.hasUsableKey else {
            throw WatchVoiceStartError(message: "Choose a model in Poki’s settings on iPhone, then try again.")
        }
        guard !chat.running, !app.voice.isOn, ChatModel.delegatedBusy == nil else {
            throw WatchVoiceStartError(message: "Poki is busy on iPhone. Wait for the current task and try again.")
        }
        guard app.automationPath == .inProcess, app.sessionOn, !app.ownerPaused else {
            throw WatchVoiceStartError(message: "Turn on Poki with on-device automation on iPhone, then try again.")
        }
    }

    private func blocked(_ id: UUID, _ message: LocalizedStringResource) -> WatchVoiceUpdate {
        WatchVoiceUpdate(id: id, phase: .blocked, text: AppLocalization.text(message))
    }

    @discardableResult
    private func complete(_ update: WatchVoiceUpdate) -> WatchVoiceUpdate {
        let terminal: WatchVoiceUpdate
        do {
            try store(update)
            terminal = update
        } catch {
            terminal = blocked(update.id, "Poki couldn’t save the result on iPhone. Check the task there before trying again.")
            updates[update.id] = terminal
        }
        AppLog.shared.add("watch", "Watch task \(update.id) ended as \(terminal.phase)")
        publish(terminal)
        return terminal
    }

    private func publish(_ update: WatchVoiceUpdate) {
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        let data = encodeUpdate(update)
        guard !data.isEmpty else { return }
        if session.isReachable { session.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
        if update.phase.isTerminal {
            do {
                try session.updateApplicationContext([WatchVoiceRequest.contextKey: data])
            } catch {
                AppLog.shared.add("watch", "Watch task result saved for the next status request")
            }
        }
    }

    private func encodeUpdate(_ update: WatchVoiceUpdate?) -> Data {
        guard let update else { return Data() }
        return (try? JSONEncoder().encode(update.forDelivery())) ?? Data()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
        guard data.count <= WatchVoiceRequest.maxMessageBytes,
              let request = try? JSONDecoder().decode(WatchVoiceRequest.self, from: data) else {
            replyHandler(Data())
            return
        }
        Task { @MainActor in replyHandler(self.reply(to: request)) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

private struct WatchVoiceStartError: LocalizedError {
    let errorDescription: String?

    init(message: LocalizedStringResource) { errorDescription = AppLocalization.text(message) }
    init(text: String) { errorDescription = text }
}
#endif
