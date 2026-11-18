import Foundation

/// The models each account offers the text chat: a few fast defaults per type (no-thinking models such
/// as GPT-6.1 Terra and Claude Haiku first), plus whatever the provider's own model list returns for
/// the owner's key, which start switched off. The owner switches models on and off in Accounts ›
/// the account › Text Chat; the chat's model menu offers only the ones switched on.
enum ModelCatalog {
    /// The defaults, switched on until the owner turns them off.
    static func defaults(_ provider: ModelProvider) -> Set<String> {
        switch provider {
        case .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5"]
        case .openai, .chatgpt: ["gpt-6.1-terra"]
        case .deepseek: ["deepseek-flash"]
        case .gemini: ["gemini-3.8-flash"]
        case .openrouter: ["anthropic/claude-sonnet-5.5", "google/gemini-3.8-flash"]
        case .custom: Set(provider.models.map(\.id))
        }
    }

    /// The account's models: the built-in ones, fast first, then the listed ones.
    static func all(_ provider: ModelProvider) -> [ChatModelChoice] {
        let builtIn = provider.models.sorted { fast($0.id) && !fast($1.id) }
        let known = Set(builtIn.map(\.id))
        return builtIn + listed(provider).filter { !known.contains($0.id) }
    }

    static func available(_ provider: ModelProvider) -> [ChatModelChoice] {
        let on = enabled(provider)
        return all(provider).filter { on.contains($0.id) }
    }

    static func enabled(_ provider: ModelProvider) -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: "models.enabled.\(provider.rawValue)") { return Set(saved) }
        return defaults(provider)
    }

    static func set(_ id: String, on: Bool, for provider: ModelProvider) {
        var ids = enabled(provider)
        if on { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: "models.enabled.\(provider.rawValue)")
        // The chat's model is always one that is switched on.
        if ModelKeys.selectedProvider == provider, !ids.contains(ModelKeys.selectedModel), let first = available(provider).first {
            ModelKeys.selectedModel = first.id
        }
        ModelKeys.saved += 1
    }

    static func listed(_ provider: ModelProvider) -> [ChatModelChoice] {
        (UserDefaults.standard.stringArray(forKey: "models.listed.\(provider.rawValue)") ?? []).map { ChatModelChoice(id: $0, name: $0) }
    }

    static func supportsReasoning(_ id: String, for provider: ModelProvider) -> Bool {
        guard provider == .openrouter else { return false }
        return (UserDefaults.standard.stringArray(forKey: "models.reasoning.openrouter") ?? []).contains(id)
    }

    /// No-thinking, fast models first: Terra, Haiku, Flash.
    static func fast(_ id: String) -> Bool {
        ["terra", "haiku", "flash", "mini"].contains { id.lowercased().contains($0) }
    }

    /// Reads the provider's model list with the owner's key (sent only to that provider).
    static func refresh(_ provider: ModelProvider) async throws -> Int {
        guard let request = request(provider) else { return 0 }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let items = (json?["data"] as? [[String: Any]]) ?? (json?["models"] as? [[String: Any]]) ?? []
        var ids = items.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
            .filter { usable($0, provider) }
        if provider == .openai {
            let voice = items.compactMap { $0["id"] as? String }.filter { $0.contains("realtime") && !$0.contains("transcribe") }.sorted()
            UserDefaults.standard.set(voice, forKey: voiceListedKey(.openai))
        }
        if provider == .gemini {
            let voice = items.compactMap { item -> String? in
                guard let methods = item["supportedGenerationMethods"] as? [String],
                      methods.contains("bidiGenerateContent"),
                      let raw = (item["name"] as? String) ?? (item["id"] as? String) else { return nil }
                return raw.hasPrefix("models/") ? String(raw.dropFirst(7)) : raw
            }
            UserDefaults.standard.set(Array(Set(voice)).sorted(), forKey: voiceListedKey(.gemini))
        }
        if provider == .openrouter {
            let reasoning = items.compactMap { item -> String? in
                guard let id = item["id"] as? String, usable(id, provider),
                      let parameters = item["supported_parameters"] as? [String],
                      parameters.contains("reasoning") || parameters.contains("reasoning_effort") else { return nil }
                return id
            }
            UserDefaults.standard.set(Array(Set(reasoning)).sorted(), forKey: "models.reasoning.openrouter")
        }
        ids = Array(Set(ids)).sorted { fast($0) == fast($1) ? $0 < $1 : fast($0) }
        UserDefaults.standard.set(ids, forKey: "models.listed.\(provider.rawValue)")
        ModelKeys.saved += 1
        return ids.count
    }

    /// Chat models only: no embeddings, speech, images or moderation.
    private static func usable(_ id: String, _ provider: ModelProvider) -> Bool {
        let lower = id.lowercased()
        let skip = ["embed", "audio", "realtime", "transcribe", "tts", "whisper", "image", "dall-e", "moderation", "search", "aqa", "imagen", "veo"]
        if skip.contains(where: lower.contains) { return false }
        // Gemini Live models only take a live conversation, not a chat request.
        if provider == .gemini, lower.contains("-live") { return false }
        switch provider {
        case .openai: return lower.hasPrefix("gpt-") || lower.hasPrefix("o")
        case .anthropic: return lower.hasPrefix("claude")
        case .gemini: return lower.hasPrefix("gemini")
        default: return true
        }
    }

    private static func request(_ provider: ModelProvider) -> URLRequest? {
        let key = ModelKeys.key(provider)
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
            let base = ModelKeys.customURL.trimmingCharacters(in: .whitespaces)
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

    static let voiceDefault = "gpt-realtime-2.1"

    static func voiceDefault(for provider: ModelProvider) -> String {
        provider == .gemini ? GeminiVoiceAdapter.defaultModel : voiceDefault
    }

    private static func voiceDefaultName(for provider: ModelProvider) -> String {
        provider == .gemini ? "Gemini 3.8 Live" : "GPT Realtime 2.1"
    }

    private static func voiceListedKey(_ provider: ModelProvider) -> String {
        provider == .openai ? "models.listed.voice" : "models.listed.voice.\(provider.rawValue)"
    }

    private static func voiceEnabledKey(_ provider: ModelProvider) -> String {
        provider == .openai ? "models.enabled.voice" : "models.enabled.voice.\(provider.rawValue)"
    }

    private static func voiceModelKey(_ provider: ModelProvider) -> String {
        provider == .openai ? "voice.model" : "voice.model.\(provider.rawValue)"
    }

    static func voiceAll(for provider: ModelProvider) -> [ChatModelChoice] {
        let base = voiceDefault(for: provider)
        let listed = (UserDefaults.standard.stringArray(forKey: voiceListedKey(provider)) ?? []).filter { $0 != base }
        return [ChatModelChoice(id: base, name: voiceDefaultName(for: provider))] + listed.map { ChatModelChoice(id: $0, name: $0) }
    }

    static func voiceEnabled(for provider: ModelProvider) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: voiceEnabledKey(provider)) ?? [voiceDefault(for: provider)])
    }

    static func setVoice(_ id: String, on: Bool, for provider: ModelProvider) {
        var ids = voiceEnabled(for: provider)
        if on { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: voiceEnabledKey(provider))
        let current = voiceModel(for: provider)
        if !ids.contains(current) {
            setVoiceModel(voiceAll(for: provider).first { ids.contains($0.id) }?.id ?? voiceDefault(for: provider), for: provider)
        } else {
            ModelKeys.saved += 1
        }
    }

    static func voiceAvailable(for provider: ModelProvider) -> [ChatModelChoice] {
        let on = voiceEnabled(for: provider)
        return voiceAll(for: provider).filter { on.contains($0.id) }
    }

    static func voiceModel(for provider: ModelProvider) -> String {
        let base = voiceDefault(for: provider)
        let saved = UserDefaults.standard.string(forKey: voiceModelKey(provider)) ?? base
        return voiceEnabled(for: provider).contains(saved) ? saved : voiceAvailable(for: provider).first?.id ?? base
    }

    static func setVoiceModel(_ id: String, for provider: ModelProvider) {
        UserDefaults.standard.set(id, forKey: voiceModelKey(provider))
        ModelKeys.saved += 1
    }
}
