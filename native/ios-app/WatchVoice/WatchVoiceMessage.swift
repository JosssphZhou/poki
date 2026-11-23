import Foundation

enum WatchVoiceRequest: Codable {
    case submit(id: UUID, audio: Data)
    case status(id: UUID)
    case result(id: UUID, offset: Int)

    // A 15-second mono AAC recording at 16 kbps stays below this limit.
    static let maxAudioBytes = 43_000
    static let contextKey = "poki.watchVoice.update"
    static let maxMessageBytes = 60_000
    static let resultChunkBytes = 16_384
}

struct WatchVoiceUpdate: Codable, Equatable, Identifiable {
    enum Phase: Int, Codable {
        case received = 0
        case running = 1
        case finished = 2
        case blocked = 3
        case waitingForUnlock = 4

        var isTerminal: Bool { self == .finished || self == .blocked }

        var progressionOrder: Int {
            switch self {
            case .received: 0
            case .waitingForUnlock: 1
            case .running: 2
            case .finished, .blocked: 3
            }
        }

        func canAdvance(to next: Phase) -> Bool {
            guard !isTerminal else { return false }
            return next.progressionOrder > progressionOrder
        }
    }

    let id: UUID
    let phase: Phase
    let text: String?
    var fullTextBytes: Int? = nil

    func forDelivery() -> Self {
        guard let text, text.utf8.count > 4_096 else { return self }
        return Self(id: id, phase: phase, text: String(decoding: text.utf8.prefix(512), as: UTF8.self),
                    fullTextBytes: text.utf8.count)
    }

    func resultChunk(at offset: Int) -> Data {
        guard phase.isTerminal, let text, offset >= 0, offset < text.utf8.count else { return Data() }
        return Data(text.utf8.dropFirst(offset).prefix(WatchVoiceRequest.resultChunkBytes))
    }
}

enum WatchVoiceDeliveryFailure: Equatable {
    case needsUnlockAfterReboot
    case phoneUnavailable
    case timedOut
    case companionNotInstalled
    case sessionInactive
    case deliveryFailed

    static func from(wcErrorCode code: Int) -> Self {
        switch code {
        case 7004, 7016: .sessionInactive
        case 7007, 7011, 7014: .phoneUnavailable
        case 7012, 7017: .timedOut
        case 7018: .companionNotInstalled
        default: .deliveryFailed
        }
    }
}

enum WatchVoicePendingStatus: Equatable {
    case idle
    case sending
    case deliveryFailed(WatchVoiceDeliveryFailure)
    case tracking(WatchVoiceUpdate)

    static func resolve(
        hasPending: Bool,
        sending: Bool,
        update: WatchVoiceUpdate?,
        failure: WatchVoiceDeliveryFailure?
    ) -> Self {
        if let update { return .tracking(update) }
        if sending { return .sending }
        if let failure { return .deliveryFailed(failure) }
        if hasPending { return .deliveryFailed(.deliveryFailed) }
        return .idle
    }
}
