import Foundation

/// Keeps complete log snapshots in submission order, including an empty snapshot after Clear.
final class AppLogSnapshots: Sendable {
    private let queue = DispatchQueue(label: "poki.app-log.snapshots", qos: .utility)
    private let write: @Sendable (String, URL) -> Void

    init(write: @escaping @Sendable (String, URL) -> Void = { text, file in
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }) {
        self.write = write
    }

    func save(_ text: String, to file: URL, completion: @escaping @Sendable () -> Void = {}) {
        queue.async { [write] in
            write(text, file)
            completion()
        }
    }
}
