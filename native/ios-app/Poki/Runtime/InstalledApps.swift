import Foundation
import PokiCore

enum InstalledApps {
    private struct Reply: Decodable {
        let apps: [InstalledApp]?
        let error: String?
    }
    private final class Pending {
        let continuation: CheckedContinuation<[InstalledApp], Error>
        init(_ continuation: CheckedContinuation<[InstalledApp], Error>) { self.continuation = continuation }
    }

    static func read(config: String) async throws -> [InstalledApp] {
        try await withCheckedThrowingContinuation { continuation in
            let pending = Unmanaged.passRetained(Pending(continuation))
            let accepted = config.withCString { poki_installed_apps($0, { context, text in
                guard let context else { return }
                let pending = Unmanaged<Pending>.fromOpaque(context).takeRetainedValue()
                do {
                    guard let text else { throw AppDirectoryUnavailable() }
                    let reply = try JSONDecoder().decode(Reply.self, from: Data(String(cString: text).utf8))
                    if let error = reply.error { throw NSError(domain: "Poki", code: 13, userInfo: [NSLocalizedDescriptionKey: error]) }
                    guard let apps = reply.apps else { throw AppDirectoryUnavailable() }
                    pending.continuation.resume(returning: apps)
                } catch { pending.continuation.resume(throwing: error) }
            }, pending.toOpaque()) }
            if accepted != 0 {
                pending.release()
                continuation.resume(throwing: AppDirectoryUnavailable())
            }
        }
    }
}
