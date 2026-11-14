import Foundation

enum VoiceAPI: Sendable {
    case realtime, live

    init(model: String) { self = model == "gpt-live-1" ? .live : .realtime }

    func offer(_ sdp: String, secret: String) throws -> URLRequest {
        let path = self == .live ? "live/sessions" : "realtime/calls"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if self == .live {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "session": VoiceDirect.liveSession,
                "transport": ["type": "webrtc", "sdp": sdp],
            ])
        } else {
            request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(sdp.utf8)
        }
        return request
    }

    func answer(_ data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            // The response can echo the owner's key. Only the status leaves the authentication boundary.
            throw VoiceError.realtime(status, "Voice session request failed (HTTP \(status)).")
        }
        if self == .realtime { return String(decoding: data, as: UTF8.self) }
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let transport = body?["transport"] as? [String: Any], let sdp = transport["sdp"] as? String, !sdp.isEmpty else {
            throw VoiceError.noOffer
        }
        return sdp
    }

    func note(_ text: String) -> [String: Any] {
        if self == .live { return ["type": "session.thinking.append", "delegation_id": NSNull(), "content": Self.content(text)] }
        return ["type": "conversation.item.create", "item": ["type": "message", "role": "system", "content": [["type": "input_text", "text": text]]]]
    }

    // At most 500 tokens per Live append; a UTF-8 byte bound also covers non-Latin text.
    static func content(_ text: String) -> String {
        guard text.utf8.count > 450 else { return text }
        return String(decoding: text.utf8.prefix(400), as: UTF8.self) + "… (shortened)"
    }
}

struct LiveConversation {
    struct Fragment {
        let text: String
        let start: Int
    }
    var input: [Fragment] = []
    var delegated: Set<String> = []
    var pending: [(id: String, offset: Int)] = []
    var hearing = false
    var speaking = false

    mutating func task(through offset: Int) -> String {
        let text = input.filter { $0.start <= offset }.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { input.removeAll { $0.start <= offset } }
        return text
    }
}
