import Foundation

/// The live voice backend protocol that determines which official voices are accepted at handshake.
enum LiveVoiceRoute: String, CaseIterable, Hashable, Sendable {
    /// OpenAI Realtime API and GPT-Live (`/v1/live/sessions`, `/v1/realtime/client_secrets`),
    /// used by an OpenAI API key or an OpenAI-compatible custom endpoint.
    case realtimeAPI
    /// ChatGPT account direct live voice via `CodexVoice` (`codex-rs` realtime v3).
    case chatgpt

    var defaultVoice: LiveVoiceOption {
        switch self {
        case .realtimeAPI: .marin
        case .chatgpt: .cove
        }
    }

    var options: [LiveVoiceOption] {
        LiveVoiceOption.allCases.filter { $0.route == self }
    }

    /// Stored under the `voice.` prefix so `SettingsVault` automatically backs it up in Keychain.
    var storageKey: String {
        switch self {
        case .realtimeAPI: "voice.speaker"
        case .chatgpt: "voice.speaker.chatgpt"
        }
    }
}

/// Official GPT live voice options, partitioned by the backend route that supports each voice.
enum LiveVoiceOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    // OpenAI Realtime API / GPT-Live (10 official voices; marin and cedar recommended).
    case marin
    case cedar
    case alloy
    case ash
    case ballad
    case coral
    case echo
    case sage
    case shimmer
    case verse

    // ChatGPT account direct live voice (`codex-rs` v3 core catalog: 9 official ChatGPT voices).
    case cove
    case juniper
    case maple
    case spruce
    case ember
    case vale
    case breeze
    case arbor
    case sol

    private struct Spec {
        let route: LiveVoiceRoute
        let name: LocalizedStringResource
        let personality: LocalizedStringResource
    }

    private var spec: Spec {
        switch self {
        case .marin: Spec(route: .realtimeAPI, name: "Marin", personality: "Natural and clear")
        case .cedar: Spec(route: .realtimeAPI, name: "Cedar", personality: "Warm and steady")
        case .alloy: Spec(route: .realtimeAPI, name: "Alloy", personality: "Neutral and balanced")
        case .ash: Spec(route: .realtimeAPI, name: "Ash", personality: "Calm and measured")
        case .ballad: Spec(route: .realtimeAPI, name: "Ballad", personality: "Melodic and expressive")
        case .coral: Spec(route: .realtimeAPI, name: "Coral", personality: "Bright and energetic")
        case .echo: Spec(route: .realtimeAPI, name: "Echo", personality: "Smooth and conversational")
        case .sage: Spec(route: .realtimeAPI, name: "Sage", personality: "Thoughtful and composed")
        case .shimmer: Spec(route: .realtimeAPI, name: "Shimmer", personality: "Clear and gentle")
        case .verse: Spec(route: .realtimeAPI, name: "Verse", personality: "Articulate and rhythmic")
        case .cove: Spec(route: .chatgpt, name: "Cove", personality: "Composed and direct")
        case .juniper: Spec(route: .chatgpt, name: "Juniper", personality: "Open and upbeat")
        case .maple: Spec(route: .chatgpt, name: "Maple", personality: "Cheerful and candid")
        case .spruce: Spec(route: .chatgpt, name: "Spruce", personality: "Calm and affirming")
        case .ember: Spec(route: .chatgpt, name: "Ember", personality: "Confident and optimistic")
        case .vale: Spec(route: .chatgpt, name: "Vale", personality: "Bright and inquisitive")
        case .breeze: Spec(route: .chatgpt, name: "Breeze", personality: "Animated and earnest")
        case .arbor: Spec(route: .chatgpt, name: "Arbor", personality: "Easygoing and versatile")
        case .sol: Spec(route: .chatgpt, name: "Sol", personality: "Savvy and relaxed")
        }
    }

    var id: String { rawValue }
    var route: LiveVoiceRoute { spec.route }
    var displayName: String { AppLocalization.text(spec.name) }
    var personality: String { AppLocalization.text(spec.personality) }
}

/// Persists and resolves live voice selections per route, guaranteeing every handshake receives a
/// voice supported by its backend even after switching authentication methods or reading stale data.
enum VoiceCatalog {
    /// Parses a stored or caller-provided voice identifier for `route`, falling back to the route's
    /// default voice whenever the value is missing, unknown, or belongs to a different route.
    static func resolve(_ rawValue: String?, for route: LiveVoiceRoute) -> LiveVoiceOption {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let option = LiveVoiceOption(rawValue: trimmed),
              option.route == route else {
            return route.defaultVoice
        }
        return option
    }

    static func voice(for route: LiveVoiceRoute, in storage: PokiStorage = .live) -> LiveVoiceOption {
        resolve(storage.defaults.string(forKey: route.storageKey), for: route)
    }

    static func setVoice(_ option: LiveVoiceOption, for route: LiveVoiceRoute, in storage: PokiStorage = .live) {
        let resolved = resolve(option.rawValue, for: route)
        storage.defaults.set(resolved.rawValue, forKey: route.storageKey)
        ModelKeys.saved += 1
    }
}
