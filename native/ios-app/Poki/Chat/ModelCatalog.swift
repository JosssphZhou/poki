import Foundation

/// The models each account offers the text chat: a few fast defaults per type (no-thinking models such
/// as GPT-6.1 Terra and Claude Haiku first), plus whatever the provider's own model list returns for
/// the owner's key, which start switched off. The owner switches models on and off in Accounts ›
/// the account › Text Chat; the chat's model menu offers only the ones switched on.
@MainActor
enum ModelCatalog {
    /// The defaults, switched on until the owner turns them off.
    static func defaults(_ provider: ModelProvider) -> Set<String> {
        switch provider {
        case .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5"]
        case .openai, .chatgpt: ["gpt-6.1-terra"]
        case .deepseek: ["deepseek-flash"]
        case .gemini: ["gemini-3.8-flash"]
        case .openrouter: ["anthropic/claude-sonnet-5.5", "google/gemini-3.8-flash"]
        case .custom: []
        }
    }

    /// No-thinking, fast models first: Terra, Haiku, Flash.
    static func fast(_ id: String) -> Bool {
        ["terra", "haiku", "flash", "mini"].contains { id.lowercased().contains($0) }
    }

    static func decodeModels(_ data: Data, provider: ModelProvider) throws -> [ChatModelChoice] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = (json?["data"] as? [[String: Any]]) ?? (json?["models"] as? [[String: Any]]) else { throw URLError(.cannotParseResponse) }
        let ids = items.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
            .filter { usable($0, provider) }
        return Set(ids).sorted().map { ChatModelChoice(id: $0, name: $0) }
    }

    /// Chat models only: no embeddings, speech, images or moderation.
    private static func usable(_ id: String, _ provider: ModelProvider) -> Bool {
        let lower = id.lowercased()
        let skip = ["embed", "audio", "realtime", "transcribe", "tts", "whisper", "image", "dall-e", "moderation", "search", "aqa", "imagen", "veo"]
        if skip.contains(where: lower.contains) { return false }
        switch provider {
        case .openai: return lower.hasPrefix("gpt-") || lower.hasPrefix("o")
        case .anthropic: return lower.hasPrefix("claude")
        case .gemini: return lower.hasPrefix("gemini")
        default: return true
        }
    }

    static func request(_ provider: ModelProvider, key: String?, endpoint: String? = nil) -> URLRequest? {
        var request: URLRequest
        switch provider {
        case .openai:
            guard let key else { return nil }
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            guard let key else { return nil }
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .deepseek:
            guard let key else { return nil }
            request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .gemini:
            guard let key, var parts = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return nil }
            parts.queryItems = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "pageSize", value: "200")]
            request = URLRequest(url: parts.url!)
        case .openrouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .custom:
            let base = (endpoint ?? ModelKeys.customURL).trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: base)?.appending(path: "models") else { return nil }
            request = URLRequest(url: url)
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .chatgpt:
            // A ChatGPT sign-in has no model list; its plan's models are the built-in ones.
            return nil
        }
        request.timeoutInterval = 15
        return request
    }

    // MARK: Voice

    /// Live voice models (OpenAI Realtime): the built-in one and any the key's list adds, off at first.
    static let voiceDefault = "gpt-realtime-2.1"

    static var voiceAll: [ChatModelChoice] {
        let listed = (VoiceDirect.profileID.flatMap { ModelProfiles.shared.profile($0)?.voiceModels } ?? []).filter { $0 != voiceDefault }
        return [ChatModelChoice(id: voiceDefault, name: "GPT Realtime 2.1")] + listed.map { ChatModelChoice(id: $0, name: $0) }
    }

    private static func voiceSetting(_ key: String) -> String {
        guard let id = VoiceDirect.profileID else { return key }
        return "\(key).\(id.uuidString)"
    }

    static var voiceEnabled: Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: voiceSetting("models.enabled.voice")) { return Set(saved) }
        if let id = VoiceDirect.profileID, ModelProfiles.shared.profile(id)?.legacy == true,
           let legacy = UserDefaults.standard.stringArray(forKey: "models.enabled.voice") { return Set(legacy) }
        return [voiceDefault]
    }

    static func setVoice(_ id: String, on: Bool) {
        var ids = voiceEnabled
        if on { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: voiceSetting("models.enabled.voice"))
        if !ids.contains(voiceModel) { voiceModel = voiceAll.first { ids.contains($0.id) }?.id ?? voiceDefault }
        ModelKeys.saved += 1
    }

    static var voiceAvailable: [ChatModelChoice] { voiceAll.filter { voiceEnabled.contains($0.id) } }

    /// The live voice model.
    static var voiceModel: String {
        get {
            let legacy = VoiceDirect.profileID.flatMap { ModelProfiles.shared.profile($0) }?.legacy == true
                ? UserDefaults.standard.string(forKey: "voice.model") : nil
            let saved = UserDefaults.standard.string(forKey: voiceSetting("voice.model")) ?? legacy ?? voiceDefault
            return voiceEnabled.contains(saved) ? saved : voiceAvailable.first?.id ?? voiceDefault
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceSetting("voice.model")); ModelKeys.saved += 1 }
    }
}
