import Foundation
import PiSwiftAI

struct ChatGPTProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let number: Int
    let clientID: String
    var subject: String?
    var email: String?
    var label: String?
    var idToken: String?
    var credentials: OAuthCredentials?
    var models: [ChatModelChoice]?

    var title: String { label ?? String(localized: "ChatGPT Account \(number)") }
    var isSignedIn: Bool {
        guard let credentials, credentials.clientId == clientID else { return false }
        return ChatGPTOAuth.canUsePlan(credentials)
    }
}

/// One protected, atomically updated Keychain item containing independent registrations.
@MainActor
final class ChatGPTProfiles {
    static let shared = ChatGPTProfiles(
        read: { try Keychain.read("chatgpt.profiles") },
        write: { try Keychain.upsert($0, account: "chatgpt.profiles") },
        readLegacy: { try Keychain.read("model-key.chatgpt") },
        eraseLegacy: { Keychain.delete("model-key.chatgpt") }
    )

    private struct Records: Codable {
        var profiles: [ChatGPTProfile] = []
        var nextNumber = 1
    }

    private let read: () throws -> Data?
    private let write: (Data) throws -> Void
    private let readLegacy: () throws -> Data?
    private let eraseLegacy: () -> Void
    private let didChange: () -> Void
    private var refreshes: [UUID: Task<String?, Never>] = [:]
    private var mutations: Set<UUID> = []
    private var activeRuns: [UUID: Int] = [:]

    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void,
         readLegacy: @escaping () throws -> Data?, eraseLegacy: @escaping () -> Void,
         didChange: @escaping () -> Void = { ModelKeys.saved += 1 }) {
        self.read = read
        self.write = write
        self.readLegacy = readLegacy
        self.eraseLegacy = eraseLegacy
        self.didChange = didChange
    }

    private func load() throws -> Records {
        if let data = try read() {
            return try JSONDecoder().decode(Records.self, from: data)
        }
        guard let legacy = try readLegacy(),
              let tokens = try? JSONDecoder().decode(OAuthCredentials.self, from: legacy),
              let client = tokens.clientId, ChatGPTOAuth.isIssuedClient(client),
              ChatGPTOAuth.canUsePlan(tokens) else { return Records() }
        // Earlier Poki versions retained the issued client and grant, but did not retain verified identity.
        let profile = ChatGPTProfile(id: UUID(), number: 1, clientID: client, credentials: tokens)
        let migrated = Records(profiles: [profile], nextNumber: 2)
        try save(migrated)
        eraseLegacy()
        return migrated
    }

    private func save(_ records: Records) throws {
        try write(JSONEncoder().encode(records))
    }

    var all: [ChatGPTProfile] { (try? load())?.profiles ?? [] }
    func profile(_ id: UUID) -> ChatGPTProfile? { all.first { $0.id == id } }

    func beginRun(_ id: UUID) -> Bool {
        guard !mutations.contains(id), profile(id)?.isSignedIn == true else { return false }
        activeRuns[id, default: 0] += 1
        return true
    }

    func endRun(_ id: UUID) {
        guard let count = activeRuns[id] else { return }
        activeRuns[id] = count > 1 ? count - 1 : nil
    }

    func authorize(_ id: UUID?, using signIn: (ChatGPTProfile?) async throws -> ChatGPTOAuth.Authorization) async throws -> ChatGPTProfile {
        if let id {
            guard activeRuns[id] == nil, mutations.insert(id).inserted else { throw ChatGPTOAuth.Failure.accountBusy }
        }
        defer { if let id { mutations.remove(id) } }
        if let id { _ = await refreshes[id]?.value }
        let previous = try id.map { id in
            guard let profile = try load().profiles.first(where: { $0.id == id }) else { throw ChatGPTOAuth.Failure.missingAccount }
            return profile
        }
        let grant = try await signIn(previous)
        try Task.checkCancellation()
        var records = try load()
        guard let client = grant.credentials.clientId, ChatGPTOAuth.isIssuedClient(client),
              ChatGPTOAuth.canUsePlan(grant.credentials) else { throw ChatGPTOAuth.Failure.invalidGrant }
        var profile: ChatGPTProfile
        if let previous {
            guard previous.clientID == client,
                  previous.subject == nil || previous.subject == grant.subject,
                  let index = records.profiles.firstIndex(where: { $0.id == previous.id }) else {
                throw ChatGPTOAuth.Failure.invalidIdentity
            }
            profile = records.profiles[index]
            profile.subject = grant.subject
            profile.email = grant.email
            profile.idToken = grant.idToken
            profile.credentials = grant.credentials
            profile.models = grant.models ?? profile.models
            records.profiles[index] = profile
        } else {
            guard !records.profiles.contains(where: { $0.clientID == client }) else {
                throw ChatGPTOAuth.Failure.duplicateRegistration
            }
            profile = ChatGPTProfile(id: UUID(), number: records.nextNumber, clientID: client,
                                     subject: grant.subject, email: grant.email, idToken: grant.idToken,
                                     credentials: grant.credentials, models: grant.models)
            records.nextNumber += 1
            records.profiles.append(profile)
        }
        try save(records)
        didChange()
        return profile
    }

    func rename(_ id: UUID, to label: String) throws {
        var records = try load()
        guard let index = records.profiles.firstIndex(where: { $0.id == id }) else { throw ChatGPTOAuth.Failure.missingAccount }
        let name = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let label = name.isEmpty ? nil : name
        if let label, records.profiles.contains(where: { $0.id != id && $0.title.localizedCaseInsensitiveCompare(label) == .orderedSame }) {
            throw ChatGPTOAuth.Failure.duplicateLabel
        }
        records.profiles[index].label = label
        try save(records)
        didChange()
    }

    /// Prevent new requests while ending this session and wait for any rotating refresh token.
    func signOut(_ id: UUID, remove: Bool, revoke: (OAuthCredentials) async -> Bool = ChatGPTOAuth.revoke) async throws -> Bool {
        guard activeRuns[id] == nil, mutations.insert(id).inserted else { throw ChatGPTOAuth.Failure.accountBusy }
        defer { mutations.remove(id); didChange() }
        _ = await refreshes[id]?.value
        guard let profile = profile(id) else { throw ChatGPTOAuth.Failure.missingAccount }
        var revoked = true
        if let tokens = profile.credentials { revoked = await revoke(tokens) }
        var records = try load()
        guard let index = records.profiles.firstIndex(where: { $0.id == id }) else { throw ChatGPTOAuth.Failure.missingAccount }
        if remove {
            records.profiles.remove(at: index)
        } else {
            records.profiles[index].credentials = nil
            records.profiles[index].idToken = nil
            records.profiles[index].models = nil
        }
        try save(records)
        return revoked
    }

    func accessToken(_ id: UUID, now: Date = Date(),
                     refresh: @escaping @Sendable (OAuthCredentials) async throws -> OAuthCredentials = { try await ChatGPTOAuth.refresh($0) }) async -> String? {
        guard !mutations.contains(id), let profile = profile(id), profile.isSignedIn, let original = profile.credentials else { return nil }
        guard original.expires < now.timeIntervalSince1970 * 1000 + 60_000 else { return original.access }
        if let pending = refreshes[id] {
            let token = await pending.value
            return mutations.contains(id) ? nil : token
        }
        let pending = Task { @MainActor () -> String? in
            defer { refreshes[id] = nil }
            do {
                let updated = try await refresh(original)
                var records = try load()
                guard updated.clientId == original.clientId, ChatGPTOAuth.canUsePlan(updated),
                      let index = records.profiles.firstIndex(where: { $0.id == id }),
                      records.profiles[index].credentials?.refresh == original.refresh else { return nil }
                records.profiles[index].credentials = updated
                try save(records)
                return updated.access
            } catch {
                return nil
            }
        }
        refreshes[id] = pending
        let token = await pending.value
        return mutations.contains(id) ? nil : token
    }

    @discardableResult
    func reloadModels(_ id: UUID) async -> Bool {
        guard let token = await accessToken(id), let models = try? await ChatGPTOAuth.models(token),
              !mutations.contains(id), var records = try? load(),
              let index = records.profiles.firstIndex(where: { $0.id == id && $0.credentials?.access == token }) else { return false }
        if records.profiles[index].models == models { return true }
        records.profiles[index].models = models
        guard (try? save(records)) != nil else { return false }
        didChange()
        return true
    }
}
