import Foundation
import PokiCore

/// The chat's latest tasks for the maintainers' debug file (Advanced, the run log's share button).
/// That file held only routines and their runs, so a tester's failed chat tasks left it empty (Nov 13
/// 2026: "没能打开淘宝" with `"runs": []`). Each task keeps the model, which tools ran, the actions
/// of each do with launch and run targets, how long each took, and the error lines of a failed call.
/// No request text, no typed text, no screenshots, as the routines' part.
enum ChatDebugLog {
    static let limit = 20

    struct Entry: Codable, Equatable {
        var at: Date
        var model: String
        var seconds: Double
        /// The bundle ids of the apps the request named (KnownApps), what the model was told to launch.
        var named: [String]
        var calls: [Call]
        /// finish_task's success; nil when the model never called it.
        var finished: Bool?
    }

    struct Call: Codable, Equatable {
        var tool: String
        var actions: [String]
        var ok: Bool
        var ms: Int
        var error: String?
    }

    private static let lock = NSLock()
    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("chat-debug.json")
    }

    /// Saves a finished task, keeping the newest `limit`.
    static func add(_ entry: Entry) {
        lock.withLock {
            var all = readLocked()
            all.append(entry)
            if all.count > limit { all.removeFirst(all.count - limit) }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? encoder.encode(all) { try? data.write(to: file, options: .atomic) }
        }
    }

    static func entries() -> [Entry] { lock.withLock { readLocked() } }

    static func clear() { lock.withLock { try? FileManager.default.removeItem(at: file) } }

    private static func readLocked() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    /// A task's entry from its tool calls.
    static func entry(model: String, named: [String], calls: [CallRecord], finished: Bool?, seconds: Double, at: Date = Date()) -> Entry {
        Entry(at: at, model: model, seconds: (seconds * 10).rounded() / 10, named: named, calls: calls.map(call), finished: finished)
    }

    static func call(_ record: CallRecord) -> Call {
        let actions = record.name == "do" ? Self.actions(record.arguments) : []
        var error: String?
        if !record.ok {
            if actions.contains("type") {
                error = "(a type action failed; its text is left out)"
            } else {
                let lines = record.answer.split(separator: "\n").map(String.init)
                let picked = lines.filter { $0.hasPrefix("error:") || $0.hasPrefix("not_sent") || $0.hasPrefix("runner:") }
                error = String((picked.isEmpty ? Array(lines.prefix(1)) : picked).joined(separator: " | ").prefix(400))
            }
        }
        return Call(tool: record.name, actions: actions, ok: record.ok, ms: record.ms, error: error)
    }

    /// Each action's kind, with the target of the ones that name no owner text: launch and run name an
    /// app or a routine, button, key and swipe a direction. A type keeps only its kind.
    static func actions(_ arguments: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let actions = object["actions"] as? [[String: Any]] else { return [] }
        return actions.compactMap { action in
            guard let pair = action.first(where: { $0.key != "finish" }) else { return nil }
            let kind = pair.key, value = pair.value
            switch kind {
            case "launch":
                let bundle = (value as? String) ?? ((value as? [String: Any])?["bundle"] as? String) ?? "?"
                let fresh = ((value as? [String: Any])?["fresh"] as? Bool) == true
                return "launch \(bundle)\(fresh ? " (fresh)" : "")"
            case "run":
                return "run \((value as? String) ?? ((value as? [String: Any])?["name"] as? String) ?? "?")"
            case "button", "key", "swipe":
                return (value as? String).map { "\(kind) \($0)" } ?? kind
            default:
                return kind
            }
        }
    }

    /// The tasks as the debug file's `chat_tasks`.
    static func json() -> JSON {
        let iso = ISO8601DateFormatter()
        return .array(entries().map { e -> JSON in
            JSON.object([
                "at": .string(iso.string(from: e.at)),
                "model": .string(e.model),
                "seconds": .number(e.seconds),
                "named": .array(e.named.map(JSON.string)),
                "finished": e.finished.map(JSON.bool) ?? .null,
                "calls": .array(e.calls.map { c -> JSON in
                    JSON.object([
                        "tool": .string(c.tool),
                        "actions": .array(c.actions.map(JSON.string)),
                        "ok": .bool(c.ok),
                        "ms": .number(Double(c.ms)),
                        "error": c.error.map(JSON.string) ?? .null,
                    ])
                }),
            ])
        })
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
