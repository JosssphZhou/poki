import Foundation

/// The Poki Loopback shortcut's listener lives in `HistoryReconnect`, which Screen History, Setup and
/// the loopback prompt share. One listener only: both answered on 127.0.0.1:47684, so two would fight
/// over the port. This name stays for the views that came with the guided Setup port.
typealias LoopbackShortcut = HistoryReconnect

extension HistoryReconnect {
    static let recoveryReturn = URL(string: "poki://loopback-recovery")!

    static var recoveryRun: URL {
        var components = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "Poki Loopback"),
            URLQueryItem(name: "x-success", value: recoveryReturn.absoluteString),
            URLQueryItem(name: "x-cancel", value: recoveryReturn.absoluteString),
            URLQueryItem(name: "x-error", value: recoveryReturn.absoluteString),
        ]
        return components.url!
    }

    /// The link to open for the shortcut, noted as shown and as the owner's.
    func take(model: AppModel) -> URL {
        let link = take()
        listen(true, model: model)
        return link
    }

    /// Listens at launch once the owner has the shortcut that can be run at any time.
    func start(model: AppModel) {
        guard canRun else { return }
        listen(true, model: model)
    }
}
