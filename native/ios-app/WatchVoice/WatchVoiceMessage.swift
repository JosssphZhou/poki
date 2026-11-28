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
        case received
        case running
        case finished
        case blocked

        var isTerminal: Bool { self == .finished || self == .blocked }
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
