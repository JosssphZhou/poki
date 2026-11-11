import Foundation

public struct InstalledApp: Codable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var aliases: [String]

    public init(bundleID: String, displayName: String, aliases: [String] = []) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.aliases = aliases
    }
}

public struct AppDirectoryUnavailable: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? { "The installed app directory is unavailable. Use an explicit bundle id or try again when the phone is connected." }
}

extension Computer {
    func resolveLaunches(_ actions: [JSON]) async throws -> [JSON] {
        var directory: Result<[InstalledApp], Error>?
        func normalized(_ name: String) -> String {
            name.lowercased().filter { !$0.isWhitespace }
        }
        var resolved = actions
        for index in actions.indices {
            guard let spec = actions[index]["launch"] else { continue }
            if spec["bundle"]?.string != nil { continue }
            guard let query = spec.string ?? spec["name"]?.string, !normalized(query).isEmpty else {
                throw ActionFailure(message: "launch takes an app name or bundle id", delivery: .notSent)
            }
            if directory == nil {
                do { directory = .success(try await host.installedApps()) }
                catch { directory = .failure(error) }
            }
            let apps: [InstalledApp]
            do { apps = try directory!.get() }
            catch {
                if spec.string != nil, query.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil { continue }
                throw error
            }
            if spec.string != nil, apps.contains(where: { $0.bundleID == query }) { continue }
            let key = normalized(query)
            let exact = apps.filter { app in
                ([app.displayName] + app.aliases).contains { normalized($0) == key }
            }
            let matches = exact.isEmpty ? apps.filter { app in
                ([app.displayName] + app.aliases).contains { normalized($0).contains(key) }
            } : exact
            guard matches.count == 1 else {
                let message = matches.isEmpty ? "No installed app matches \(query)." : "Multiple installed apps match \(query): \(matches.map { "\($0.displayName) (\($0.bundleID))" }.sorted().joined(separator: ", ")). Give an explicit bundle id."
                throw ActionFailure(message: message, delivery: .notSent)
            }
            var action = actions[index].object ?? [:]
            action["launch"] = ["bundle": .string(matches[0].bundleID), "fresh": .bool(spec["fresh"]?.bool ?? false)]
            resolved[index] = .object(action)
        }
        return resolved
    }
}
