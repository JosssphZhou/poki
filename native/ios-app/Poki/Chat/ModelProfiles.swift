import Foundation
import PiSwiftAI

/// API keys and connection configuration are protected together. OAuth registrations keep their
/// existing identity/refresh store and expose the same selection identity to the conversation.
struct ModelProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let provider: ModelProvider
    var label: String
    var key: String?
    var endpoint: String?
    var customModel: String?
    var listed: [ChatModelChoice]?
    var enabled: Set<String>
    var modelID: String
    var legacy: Bool? = nil
    var voiceModels: [String]? = nil

    var title: String { label }
}

@MainActor
final class ModelProfiles {
    static let shared = ModelProfiles(
        read: { try Keychain.read("model.profiles") },
        write: { try Keychain.upsert($0, account: "model.profiles") },
        legacyKey: { provider in
            guard let data = try Keychain.read("model-key.\(provider.rawValue)") else { return nil }
            return String(data: data, encoding: .utf8)
        }, defaults: .standard, eraseLegacy: { Keychain.delete("model-key.\($0.rawValue)") }
    )

    enum Failure: LocalizedError {
        case missing, invalid, duplicateLabel, changed
        var errorDescription: String? {
            switch self {
            case .missing: String(localized: "This account profile is unavailable. Choose another in Accounts.")
            case .invalid: String(localized: "Check the profile's key, address and model.")
            case .duplicateLabel: String(localized: "Choose a different profile name for this provider.")
            case .changed: String(localized: "The profile changed while loading its model list. Refresh it again.")
            }
        }
    }

    private let read: () throws -> Data?
    private let write: (Data) throws -> Void
    private let legacyKey: (ModelProvider) throws -> String?
    private let defaults: UserDefaults
    private let eraseLegacy: (ModelProvider) -> Void
    private let changed: () -> Void
    let chatGPT: ChatGPTProfiles

    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void,
         legacyKey: @escaping (ModelProvider) throws -> String?, defaults: UserDefaults,
         chatGPT: ChatGPTProfiles? = nil, eraseLegacy: @escaping (ModelProvider) -> Void = { _ in }, changed: @escaping () -> Void = { ModelKeys.saved += 1 }) {
        self.read = read; self.write = write; self.legacyKey = legacyKey
        self.eraseLegacy = eraseLegacy
        self.defaults = defaults; self.chatGPT = chatGPT ?? .shared; self.changed = changed
    }

    /// A single atomic write commits all legacy connections. Legacy entries remain available for
    /// rollback. Once the new item exists, removal cannot re-import an old key.
    func load() throws -> [ModelProfile] {
        if let data = try read() { return try JSONDecoder().decode([ModelProfile].self, from: data) }
        var profiles: [ModelProfile] = []
        for provider in ModelProvider.allCases where provider != .chatgpt {
            let key = try legacyKey(provider)
            let endpoint = provider == .custom ? defaults.string(forKey: "chat.customURL") : nil
            let model = provider == .custom ? defaults.string(forKey: "chat.customModel") : nil
            guard key?.isEmpty == false || (endpoint?.isEmpty == false && model?.isEmpty == false) else { continue }
            let listed = defaults.stringArray(forKey: "models.listed.\(provider.rawValue)")?.map { ChatModelChoice(id: $0, name: $0) }
            let enabled = Set(defaults.stringArray(forKey: "models.enabled.\(provider.rawValue)") ?? Array(ModelCatalog.defaults(provider)))
            profiles.append(ModelProfile(id: UUID(), provider: provider, label: String(localized: "Profile 1"),
                                         key: key, endpoint: endpoint, customModel: model, listed: listed,
                                         enabled: provider == .custom ? Set([model ?? ""]) : enabled,
                                         modelID: defaults.string(forKey: "chat.model.\(provider.rawValue)") ?? model ?? "", legacy: true))
        }
        try persist(profiles)
        return profiles
    }

    private func persist(_ profiles: [ModelProfile]) throws { try write(JSONEncoder().encode(profiles)) }
    var all: [ModelProfile] { (try? load()) ?? [] }
    func profile(_ id: UUID) -> ModelProfile? { all.first { $0.id == id } }

    func preferred(_ provider: ModelProvider) -> ModelProfile? {
        if let raw = defaults.string(forKey: "chat.profile.\(provider.rawValue)") {
            guard let id = UUID(uuidString: raw), let profile = profile(id), profile.provider == provider else { return nil }
            return profile
        }
        return all.first { $0.provider == provider }
    }

    func choose(_ id: UUID) {
        let provider: ModelProvider
        if let profile = profile(id) { provider = profile.provider }
        else if chatGPT.profile(id) != nil { provider = .chatgpt }
        else { return }
        defaults.set(id.uuidString, forKey: "chat.profile.\(provider.rawValue)")
        if provider == .chatgpt { defaults.set(id.uuidString, forKey: "chat.chatGPTProfile") }
        defaults.set(provider.rawValue, forKey: "chat.provider")
        changed()
    }

    var defaultSelection: ModelSelection {
        let provider = defaults.string(forKey: "chat.provider").flatMap(ModelProvider.init(rawValue:)) ?? .anthropic
        if provider == .chatgpt {
            let raw = defaults.string(forKey: "chat.chatGPTProfile")
            let id = raw == nil ? chatGPT.all.first?.id : raw.flatMap(UUID.init(uuidString:))
            let models = id.map { available($0) } ?? []
            let selected = defaults.string(forKey: "chat.model.chatgpt")
            return ModelSelection(provider: provider, modelID: models.first { $0.id == selected }?.id ?? models.first?.id ?? "", profileID: id)
        }
        guard let profile = preferred(provider) else {
            return .init(provider: provider, modelID: "", profileID: defaults.string(forKey: "chat.profile.\(provider.rawValue)").flatMap(UUID.init(uuidString:)))
        }
        let models = available(profile.id)
        let model = models.first { $0.id == profile.modelID } ?? models.first
        return .init(provider: provider, modelID: model?.id ?? "", profileID: profile.id)
    }

    @discardableResult
    func save(_ id: UUID?, provider: ModelProvider, label: String, key: String?, endpoint: String? = nil, model: String? = nil) throws -> ModelProfile {
        guard provider != .chatgpt else { throw Failure.invalid }
        let secret = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = provider == .custom ? endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let model = provider == .custom ? model?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        guard provider == .custom ? Self.validEndpoint(address) && model?.isEmpty == false : secret?.isEmpty == false else { throw Failure.invalid }
        var records = try load()
        let old = id.flatMap { id in records.first { $0.id == id } }
        guard id == nil || old?.provider == provider else { throw Failure.missing }
        let name = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let defaultName = (1...).lazy.map { String(localized: "Profile \($0)") }.first { name in
            !records.contains { $0.provider == provider && $0.label.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }!
        let title = name.isEmpty ? old?.label ?? defaultName : name
        guard !records.contains(where: { $0.id != id && $0.provider == provider && $0.label.localizedCaseInsensitiveCompare(title) == .orderedSame }) else { throw Failure.duplicateLabel }
        var profile = old ?? ModelProfile(id: UUID(), provider: provider, label: title, enabled: ModelCatalog.defaults(provider), modelID: "")
        let connectionChanged = old != nil && (old?.key != secret || old?.endpoint != address || old?.customModel != model)
        profile.label = title; profile.key = secret?.isEmpty == false ? secret : nil
        profile.endpoint = provider == .custom ? address : nil; profile.customModel = provider == .custom ? model : nil
        if connectionChanged {
            profile.listed = nil
            profile.voiceModels = nil
            profile.enabled = provider == .custom ? profile.enabled.intersection(Set([model].compactMap { $0 })) : ModelCatalog.defaults(provider)
        }
        if provider == .custom, old == nil || old?.customModel != model {
            profile.enabled.insert(model!); profile.modelID = model!
        }
        if let index = records.firstIndex(where: { $0.id == profile.id }) { records[index] = profile } else { records.append(profile) }
        try persist(records)
        if connectionChanged, old?.legacy == true { clearLegacy(provider) }
        changed()
        return profile
    }

    static func validEndpoint(_ address: String?) -> Bool {
        guard let address, let url = URLComponents(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        return true
    }

    func rename(_ id: UUID, to label: String) throws {
        guard let p = profile(id) else { throw Failure.missing }
        _ = try save(id, provider: p.provider, label: label, key: p.key, endpoint: p.endpoint, model: p.customModel)
    }

    func remove(_ id: UUID) throws {
        var records = try load()
        guard let profile = records.first(where: { $0.id == id }) else { throw Failure.missing }
        records.removeAll { $0.id == id }
        try persist(records)
        if profile.legacy == true { clearLegacy(profile.provider) }
        changed()
    }

    private func clearLegacy(_ provider: ModelProvider) {
        eraseLegacy(provider)
        if provider == .custom {
            defaults.removeObject(forKey: "chat.customURL")
            defaults.removeObject(forKey: "chat.customModel")
        }
    }

    func models(_ id: UUID) -> [ChatModelChoice] {
        if let p = chatGPT.profile(id) { return p.isSignedIn ? (p.models ?? []).filter { ModelProvider.chatgpt.piModel($0.id)?.api == .openAIResponses } : [] }
        guard let p = profile(id) else { return [] }
        if p.provider == .custom { return [ChatModelChoice(id: p.customModel ?? "", name: p.customModel ?? "")] + (p.listed ?? []).filter { $0.id != p.customModel } }
        return (p.listed ?? p.provider.models).filter { p.provider.piModel($0.id) != nil }
    }

    func available(_ id: UUID) -> [ChatModelChoice] {
        if chatGPT.profile(id) != nil { return models(id) }
        guard let p = profile(id), p.provider == .custom || p.key?.isEmpty == false else { return [] }
        if p.provider == .custom, !Self.validEndpoint(p.endpoint) || p.customModel?.isEmpty != false { return [] }
        return models(id).filter { p.enabled.contains($0.id) }
    }

    func setModel(_ model: String, enabled: Bool, profileID: UUID) throws {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == profileID }) else { throw Failure.missing }
        if enabled { records[index].enabled.insert(model) } else { records[index].enabled.remove(model) }
        try persist(records); changed()
    }

    func select(_ selection: ModelSelection) throws {
        guard let id = selection.profileID, selection.route(in: self) != nil else { throw Failure.missing }
        if selection.provider == .chatgpt { defaults.set(selection.modelID, forKey: "chat.model.chatgpt") }
        else {
            var records = try load()
            guard let index = records.firstIndex(where: { $0.id == id }) else { throw Failure.missing }
            records[index].modelID = selection.modelID
            try persist(records)
        }
        choose(id)
    }

    func refresh(_ id: UUID, send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws {
        guard let original = profile(id), let request = ModelCatalog.request(original.provider, key: original.key, endpoint: original.endpoint) else { throw Failure.missing }
        let (data, response) = try await send(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let choices = try ModelCatalog.decodeModels(data, provider: original.provider)
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }), records[index] == original else { throw Failure.changed }
        records[index].listed = choices
        if original.provider == .openai,
           let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = json["data"] as? [[String: Any]] {
            records[index].voiceModels = items.compactMap { $0["id"] as? String }.filter { $0.contains("realtime") && !$0.contains("transcribe") }.sorted()
        }
        try persist(records); changed()
    }
}

struct ModelSelection: Codable, Equatable, Sendable {
    let provider: ModelProvider
    let modelID: String
    var profileID: UUID?

    @MainActor var displayName: String { displayName(in: .shared) }
    @MainActor func displayName(in store: ModelProfiles) -> String {
        let label = profileID.flatMap { store.profile($0)?.title ?? store.chatGPT.profile($0)?.title } ?? String(localized: "Unavailable")
        return "\(provider.name) · \(label) — \(modelID)"
    }
    @MainActor var route: ModelRoute? { route(in: .shared) }
    @MainActor func route(in store: ModelProfiles) -> ModelRoute? {
        // Pre-profile API sessions resolve to their migrated connection, never to another provider.
        let id = profileID ?? (provider == .chatgpt ? nil : store.all.first { $0.provider == provider && $0.legacy == true }?.id)
        guard let id, store.available(id).contains(where: { $0.id == modelID }) else { return nil }
        if provider == .chatgpt {
            guard store.chatGPT.profile(id)?.isSignedIn == true, let model = provider.piModel(modelID),
                  model.api == .openAIResponses, model.baseUrl == ChatGPTOAuth.resource else { return nil }
            return ModelRoute(selection: .init(provider: provider, modelID: modelID, profileID: id), model: model, key: nil)
        }
        guard let p = store.profile(id), p.provider == provider,
              let model = provider.piModel(modelID, endpoint: p.endpoint) else { return nil }
        return ModelRoute(selection: .init(provider: provider, modelID: modelID, profileID: id), model: model, key: p.key)
    }
    func sameAccount(as other: Self) -> Bool { provider == other.provider && profileID == other.profileID }
}

struct ModelRoute: Sendable {
    let selection: ModelSelection
    let model: Model
    let key: String?

    /// A replacement affects future task routes. This route keeps its captured API credential.
    /// Local deletion prevents the next authentication lookup, including a tool continuation.
    /// It does not revoke the remote key or cancel a request already dispatched on the network.
    @MainActor func accessToken(profiles: ChatGPTProfiles, connections: ModelProfiles? = nil) async -> String? {
        if selection.provider == .chatgpt {
            guard let id = selection.profileID, model.api == .openAIResponses, model.baseUrl == ChatGPTOAuth.resource else { return nil }
            return await profiles.accessToken(id)
        }
        guard let id = selection.profileID, (connections ?? .shared).profile(id)?.provider == selection.provider,
              model.provider == selection.provider.piProvider else { return nil }
        return key ?? (selection.provider == .custom ? "none" : nil)
    }
    func sameAccount(as other: Self) -> Bool {
        selection.sameAccount(as: other.selection) && key == other.key && model.baseUrl == other.model.baseUrl
    }
}
