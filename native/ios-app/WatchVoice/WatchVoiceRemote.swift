import Foundation

enum WatchVoiceRemote {
    static let commandKey = "poki.watchVoice.remote.command"
    static let replyKey = "poki.watchVoice.remote.reply"
    static let snapshotKey = "poki.watchVoice.remote.snapshot"
    static let meterKey = "poki.watchVoice.remote.meter"
    static let contextKey = "poki.watchVoice.remote.context"
    static let resultKey = "poki.watchVoice.remote.result"
    static let maxRecentResults = 16

    static let defaultCommandWindow = WatchVoiceCommandWindow(
        maxAge: 10,
        maxFutureSkew: 2,
        meterMaxPastSkew: 1.2,
        meterMaxFutureSkew: 0.5
    )

    /// Preserves existing keys (such as an undelivered #591 one-shot task update after iPhone restarts)
    /// while updating whichever context entries the current process has produced.
    static func mergeApplicationContext(
        existing: [String: Any],
        taskContext: Data?,
        remoteContext: Data?
    ) -> [String: Any] {
        var merged = existing
        if let taskContext {
            merged[WatchVoiceRequest.contextKey] = taskContext
        }
        if let remoteContext {
            merged[WatchVoiceRemote.contextKey] = remoteContext
        }
        return merged
    }

    /// Inserts newest-first incoming terminal results into an existing newest-first history list
    /// without losing intermediate offline turns or duplicating already-recorded result IDs.
    static func mergeResults(
        _ incoming: [WatchVoiceUpdate],
        into existing: [WatchVoiceUpdate]
    ) -> (merged: [WatchVoiceUpdate], added: [WatchVoiceUpdate]) {
        var merged = existing
        var seen = Set(existing.map(\.id))
        var addedOldestFirst: [WatchVoiceUpdate] = []
        for item in incoming.reversed() where item.phase.isTerminal && !seen.contains(item.id) {
            seen.insert(item.id)
            merged.insert(item, at: 0)
            addedOldestFirst.append(item)
        }
        return (merged, addedOldestFirst.reversed())
    }
}

extension WatchVoiceUpdate {
    func forCompactDelivery(maxBytes: Int = 512) -> Self {
        guard let text, text.utf8.count > maxBytes else { return self }
        return Self(
            id: id,
            phase: phase,
            text: String(decoding: text.utf8.prefix(maxBytes), as: UTF8.self),
            fullTextBytes: text.utf8.count
        )
    }
}

final class WatchVoiceResultJournal {
    let url: URL
    private(set) var updates: [UUID: WatchVoiceUpdate] = [:]
    private(set) var isAvailable = true

    init(url: URL) {
        self.url = url
        do {
            let saved = try Data(contentsOf: url)
            updates = try JSONDecoder().decode([UUID: WatchVoiceUpdate].self, from: saved)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // The first persisted result creates the journal.
        } catch {
            // An unreadable journal cannot safely distinguish a new request from a retry.
            isAvailable = false
        }
    }

    func update(for id: UUID) -> WatchVoiceUpdate? {
        updates[id]
    }

    func store(_ update: WatchVoiceUpdate) throws {
        guard isAvailable else { throw CocoaError(.fileReadCorruptFile) }
        var next = updates
        next[update.id] = update
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        updates = next
    }

    func storeInMemoryFallback(_ update: WatchVoiceUpdate) {
        updates[update.id] = update
    }

    func resultChunk(id: UUID, offset: Int) -> Data {
        updates[id]?.resultChunk(at: offset) ?? Data()
    }
}

enum WatchVoiceCallState: String, Codable, Equatable, Hashable, Sendable {
    case unavailable
    case needsSetup
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case muted
    case ending
    case failed

    var isActiveCall: Bool {
        switch self {
        case .connecting, .listening, .thinking, .speaking, .muted:
            true
        case .unavailable, .needsSetup, .idle, .ending, .failed:
            false
        }
    }
}

struct WatchVoiceCommandWindow: Equatable, Sendable {
    let maxAge: TimeInterval
    let maxFutureSkew: TimeInterval
    let meterMaxPastSkew: TimeInterval
    let meterMaxFutureSkew: TimeInterval

    func acceptsCommand(issuedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(issuedAt)
        return age >= -maxFutureSkew && age <= maxAge
    }

    func acceptsMeter(timestamp: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= -meterMaxFutureSkew && age <= meterMaxPastSkew
    }
}

struct WatchVoiceRemoteCommand: Codable, Equatable, Sendable {
    enum Action: Codable, Equatable, Sendable {
        case state
        case start
        case setMuted(Bool)
        case end
    }

    let requestID: UUID
    let issuedAt: Date
    let action: Action
    let targetCallID: String?

    init(requestID: UUID = UUID(), issuedAt: Date = Date(), action: Action, targetCallID: String? = nil) {
        self.requestID = requestID
        self.issuedAt = issuedAt
        self.action = action
        self.targetCallID = targetCallID
    }
}

struct WatchVoicePendingEnd: Codable, Equatable, Sendable {
    let requestID: UUID
    let callID: String
    let issuedAt: Date

    func makeCommand() -> WatchVoiceRemoteCommand {
        WatchVoiceRemoteCommand(
            requestID: requestID,
            issuedAt: issuedAt,
            action: .end,
            targetCallID: callID
        )
    }
}

enum WatchVoiceRemoteOutcome: String, Codable, Equatable, Sendable {
    case accepted
    case noChange
    case requiresForeground
    case needsSetup
    case busy
    case expired
    case callChanged
    case unavailable
    case failed

    var isSuccess: Bool {
        self == .accepted || self == .noChange
    }
}

struct WatchVoiceRemoteSnapshot: Codable, Equatable, Sendable {
    let epoch: UInt64
    let sequence: UInt64
    let state: WatchVoiceCallState
    let callID: String?
    let isMuted: Bool
    let transportConnected: Bool
    let inputReady: Bool
    let requiresForeground: Bool
    let updatedAt: Date
    let detail: String?
    var currentStep: String? = nil
    var latestResult: WatchVoiceUpdate? = nil
    var recentResults: [WatchVoiceUpdate] = []

    enum CodingKeys: String, CodingKey {
        case epoch
        case sequence
        case state
        case callID
        case isMuted
        case transportConnected
        case inputReady
        case requiresForeground
        case updatedAt
        case detail
        case currentStep
        case latestResult
        case recentResults
    }

    init(
        epoch: UInt64,
        sequence: UInt64,
        state: WatchVoiceCallState,
        callID: String?,
        isMuted: Bool,
        transportConnected: Bool,
        inputReady: Bool,
        requiresForeground: Bool,
        updatedAt: Date,
        detail: String?,
        currentStep: String? = nil,
        latestResult: WatchVoiceUpdate? = nil,
        recentResults: [WatchVoiceUpdate] = []
    ) {
        self.epoch = epoch
        self.sequence = sequence
        self.state = state
        self.callID = callID
        self.isMuted = isMuted
        self.transportConnected = transportConnected
        self.inputReady = inputReady
        self.requiresForeground = requiresForeground
        self.updatedAt = updatedAt
        self.detail = detail
        self.currentStep = currentStep
        self.latestResult = latestResult
        self.recentResults = recentResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        epoch = try container.decode(UInt64.self, forKey: .epoch)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        state = try container.decode(WatchVoiceCallState.self, forKey: .state)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        transportConnected = try container.decode(Bool.self, forKey: .transportConnected)
        inputReady = try container.decode(Bool.self, forKey: .inputReady)
        requiresForeground = try container.decode(Bool.self, forKey: .requiresForeground)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        currentStep = try container.decodeIfPresent(String.self, forKey: .currentStep)
        latestResult = try container.decodeIfPresent(WatchVoiceUpdate.self, forKey: .latestResult)
        recentResults = try container.decodeIfPresent([WatchVoiceUpdate].self, forKey: .recentResults) ?? []
    }

    var deliveredResults: [WatchVoiceUpdate] {
        if !recentResults.isEmpty { return recentResults }
        return latestResult.map { [$0] } ?? []
    }

    func isNewer(than other: WatchVoiceRemoteSnapshot) -> Bool {
        if epoch != other.epoch { return epoch > other.epoch }
        return sequence > other.sequence
    }
}

struct WatchVoiceRemoteMeter: Codable, Equatable, Sendable {
    let epoch: UInt64
    let callID: String
    let level: UInt8
    let timestamp: Date
}

struct WatchVoiceRemoteReply: Codable, Equatable, Sendable {
    let requestID: UUID
    let outcome: WatchVoiceRemoteOutcome
    let snapshot: WatchVoiceRemoteSnapshot
    let detail: String?
}

struct WatchVoiceRemoteStateReducer: Equatable, Sendable {
    private(set) var latestSnapshot: WatchVoiceRemoteSnapshot?
    private(set) var pendingEnd: WatchVoicePendingEnd?
    private(set) var meterLevel: UInt8 = 0
    private(set) var meterUpdatedAt: Date?
    private(set) var pendingContinueOnPhone = false
    private(set) var lastProblem: String?

    init(latestSnapshot: WatchVoiceRemoteSnapshot? = nil, pendingEnd: WatchVoicePendingEnd? = nil) {
        self.latestSnapshot = latestSnapshot
        self.pendingEnd = pendingEnd
        self.pendingContinueOnPhone = latestSnapshot?.requiresForeground ?? false
        self.lastProblem = latestSnapshot?.detail
        if let latestSnapshot {
            reconcilePendingEnd(with: latestSnapshot)
        }
    }

    var canShowEndButton: Bool {
        if pendingEnd != nil { return true }
        guard let snapshot = latestSnapshot else { return false }
        return snapshot.state.isActiveCall || snapshot.state == .ending
    }

    @discardableResult
    mutating func queueEnd(requestID: UUID = UUID(), now: Date) -> WatchVoiceRemoteCommand? {
        if let existing = pendingEnd {
            return existing.makeCommand()
        }
        guard let snapshot = latestSnapshot,
              snapshot.state.isActiveCall,
              let callID = snapshot.callID else {
            return nil
        }
        let queued = WatchVoicePendingEnd(requestID: requestID, callID: callID, issuedAt: now)
        pendingEnd = queued
        return queued.makeCommand()
    }

    @discardableResult
    mutating func apply(snapshot: WatchVoiceRemoteSnapshot) -> Bool {
        if let current = latestSnapshot, !snapshot.isNewer(than: current) {
            return false
        }
        let callChanged = latestSnapshot?.callID != snapshot.callID
        latestSnapshot = snapshot
        if !snapshot.state.isActiveCall || callChanged {
            meterLevel = 0
            meterUpdatedAt = nil
        }
        pendingContinueOnPhone = snapshot.requiresForeground
        lastProblem = snapshot.detail
        reconcilePendingEnd(with: snapshot)
        return true
    }

    @discardableResult
    mutating func apply(reply: WatchVoiceRemoteReply, targetCallID: String? = nil) -> Bool {
        if let current = latestSnapshot, current.isNewer(than: reply.snapshot) {
            return false
        }
        let isStrictlyNewer = latestSnapshot.map { reply.snapshot.isNewer(than: $0) } ?? true
        if !isStrictlyNewer,
           let targetCallID,
           let current = latestSnapshot,
           current.callID != targetCallID,
           reply.requestID != pendingEnd?.requestID {
            return false
        }
        if isStrictlyNewer {
            _ = apply(snapshot: reply.snapshot)
        }
        if pendingEnd?.requestID == reply.requestID,
           reply.outcome == .accepted || reply.outcome == .noChange || reply.outcome == .callChanged {
            pendingEnd = nil
        }
        switch reply.outcome {
        case .requiresForeground:
            if isStrictlyNewer || !(latestSnapshot?.state.isActiveCall ?? false) {
                pendingContinueOnPhone = true
                lastProblem = reply.detail ?? reply.snapshot.detail
            }
        case .accepted, .noChange:
            if isStrictlyNewer {
                if !reply.snapshot.requiresForeground {
                    pendingContinueOnPhone = false
                }
                if reply.snapshot.state != .failed {
                    lastProblem = reply.detail ?? reply.snapshot.detail
                }
            }
        case .needsSetup, .busy, .expired, .callChanged, .unavailable, .failed:
            if isStrictlyNewer && !reply.snapshot.requiresForeground {
                pendingContinueOnPhone = false
            }
            if let detail = reply.detail ?? reply.snapshot.detail {
                lastProblem = detail
            } else if isStrictlyNewer {
                lastProblem = nil
            }
        }
        return true
    }

    @discardableResult
    mutating func apply(
        meter: WatchVoiceRemoteMeter,
        now: Date,
        window: WatchVoiceCommandWindow = WatchVoiceRemote.defaultCommandWindow
    ) -> Bool {
        guard let snapshot = latestSnapshot,
              snapshot.state.isActiveCall,
              snapshot.epoch == meter.epoch,
              snapshot.callID == meter.callID,
              window.acceptsMeter(timestamp: meter.timestamp, now: now) else {
            return false
        }
        if let previous = meterUpdatedAt, meter.timestamp < previous {
            return false
        }
        meterLevel = meter.level
        meterUpdatedAt = meter.timestamp
        return true
    }

    mutating func clearMeterIfStale(now: Date, maxAge: TimeInterval = 1.5) {
        guard let meterUpdatedAt, now.timeIntervalSince(meterUpdatedAt) > maxAge else { return }
        meterLevel = 0
    }

    private mutating func reconcilePendingEnd(with snapshot: WatchVoiceRemoteSnapshot) {
        guard let pending = pendingEnd else { return }
        if !snapshot.state.isActiveCall || snapshot.callID != pending.callID {
            pendingEnd = nil
        }
    }
}

enum WatchVoiceCue: String, Equatable, Hashable, Sendable {
    case start
    case mute
    case unmute
    case end
}

enum WatchVoiceTone {
    static let sampleRate = 24_000

    private struct Segment {
        let frequency: Double
        let duration: Double
        let amplitude: Double
    }

    static func wavData(for cue: WatchVoiceCue) -> Data {
        let segments: [Segment] = switch cue {
        case .start:
            [
                Segment(frequency: 523.25, duration: 0.065, amplitude: 0.28),
                Segment(frequency: 783.99, duration: 0.085, amplitude: 0.30),
            ]
        case .mute:
            [
                Segment(frequency: 659.25, duration: 0.055, amplitude: 0.26),
                Segment(frequency: 440.00, duration: 0.075, amplitude: 0.24),
            ]
        case .unmute:
            [
                Segment(frequency: 440.00, duration: 0.050, amplitude: 0.24),
                Segment(frequency: 659.25, duration: 0.070, amplitude: 0.28),
            ]
        case .end:
            [
                Segment(frequency: 587.33, duration: 0.065, amplitude: 0.26),
                Segment(frequency: 392.00, duration: 0.095, amplitude: 0.24),
            ]
        }
        return encodePCM16MonoWAV(samples: synthesize(segments: segments), sampleRate: sampleRate)
    }

    private static func synthesize(segments: [Segment]) -> [Int16] {
        var samples: [Int16] = []
        let fadeSamples = max(1, Int(Double(sampleRate) * 0.008))
        for segment in segments {
            let count = max(1, Int((segment.duration * Double(sampleRate)).rounded()))
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                let wave = sin(2.0 * Double.pi * segment.frequency * time)
                let fadeIn = index < fadeSamples ? Double(index) / Double(fadeSamples) : 1.0
                let remaining = count - 1 - index
                let fadeOut = remaining < fadeSamples ? Double(remaining) / Double(fadeSamples) : 1.0
                let envelope = min(fadeIn, fadeOut)
                let scaled = max(-1.0, min(1.0, wave * segment.amplitude * envelope))
                samples.append(Int16((scaled * Double(Int16.max)).rounded()))
            }
        }
        return samples
    }

    private static func encodePCM16MonoWAV(samples: [Int16], sampleRate: Int) -> Data {
        let dataBytes = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffBytes = UInt32(36) + dataBytes
        let byteRate = UInt32(sampleRate * MemoryLayout<Int16>.size)
        let blockAlign = UInt16(MemoryLayout<Int16>.size)

        var data = Data(capacity: 44 + Int(dataBytes))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        appendLE(&data, riffBytes)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        appendLE(&data, UInt32(16))
        appendLE(&data, UInt16(1))
        appendLE(&data, UInt16(1))
        appendLE(&data, UInt32(sampleRate))
        appendLE(&data, byteRate)
        appendLE(&data, blockAlign)
        appendLE(&data, UInt16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        appendLE(&data, dataBytes)
        for sample in samples {
            appendLE(&data, sample)
        }
        return data
    }

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
