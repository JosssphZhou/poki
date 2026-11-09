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
        var directory: [InstalledApp]?
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
            if spec.string != nil, query.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil { continue }
            if directory == nil { directory = try await host.installedApps() }
            let key = normalized(query)
            let exact = directory!.filter { app in
                app.bundleID == query || ([app.displayName] + app.aliases).contains { normalized($0) == key }
            }
            let matches = exact.isEmpty ? directory!.filter { app in
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
