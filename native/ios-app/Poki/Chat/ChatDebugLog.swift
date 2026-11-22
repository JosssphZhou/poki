import Foundation
import PokiCore

/// The chat's latest tasks for the maintainers' debug file (Advanced, the run log's share button).
/// That file held only routines and their runs, so a tester's failed chat tasks left it empty (Nov 13
/// 2026: "没能打开淘宝" with `"runs": []`). Each task keeps the model, the tools that ran, the kind of
/// each do action (with a launch's bundle id and a button, key or swipe direction), how long each took,
/// and what kind of failure a failed call had. Only these structured fields are kept: never a tool's
/// answer text, a typed or entered value, a routine's name, the request or a screenshot.
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
        /// A failed call's kind of failure (`Failure`), never its text.
        var error: String?
    }

    /// What went wrong in a failed or refused call, kept as a category only.
    enum Failure: String, Codable, Equatable {
        case notInstalled = "launch_not_installed"
        case approval = "approval_required"
        case busy = "runner_busy"
        case sessionOff = "session_off"
        case stopped
        case timeout
        case invalidArguments = "invalid_arguments"
        case notSentTunnelDisconnected = "not_sent_tunnel_disconnected"
        case notSentPairingRequired = "not_sent_pairing_required"
        case notSentAppPreflight = "not_sent_app_preflight"
        case notSentScreenEvidence = "not_sent_screen_evidence"
        case notSentSessionNotReady = "not_sent_session_not_ready"
        case notSentLocked = "not_sent_locked"
        case notSentHandoff = "not_sent_handoff"
        case notSentOwnApp = "not_sent_own_app"
        case notSentApprovalDeclined = "not_sent_approval_declined"
        case notSentSplitView = "not_sent_split_view"
        case notSentTargetRefused = "not_sent_target_refused"
        case notSent = "not_sent"
        case failed

        init(answer: String) {
            self = Self.classify(answer: answer, allowNonError: false) ?? .failed
        }

        /// Extracts a structured refusal category from a non-error phone tool answer
        /// (such as `waitingForOwner == true` while waiting for the loopback).
        static func nonErrorRefusal(answer: String) -> Failure? {
            classify(answer: answer, allowNonError: true)
        }

        private static func classify(answer: String, allowNonError: Bool) -> Failure? {
            let lines = answer.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let first = lines.first ?? ""
            let runnerLine = lines.first { $0.hasPrefix("runner: ") }
            let errorLine = lines.first { $0.hasPrefix("error: ") }
            let notSentFromLine = lines.first { $0.hasPrefix("not_sent from action ") }
            let hasNothingSent = lines.contains {
                $0 == "nothing was sent."
                    || $0.hasPrefix("nothing was sent.")
                    || $0.contains("; nothing was sent")
                    || $0.contains(". nothing was sent.")
                    || $0.contains(". no requested action was sent.")
            }

            if let runnerLine, hasNothingSent {
                return classifyRunnerLine(String(runnerLine.dropFirst("runner: ".count)))
            }
            if first.hasPrefix("not_sent: poki could not turn on: ") {
                return classifyStartupReason(String(first.dropFirst("not_sent: poki could not turn on: ".count)))
            }
            if isAppPreflightHeader(first: first, errorLine: errorLine) {
                return .notSentAppPreflight
            }
            if errorLine?.contains("no app with that bundle id is installed") == true
                || (first.hasPrefix("not_sent: launch:") && first.contains("no app with that bundle id is installed")) {
                return .notInstalled
            }
            if let notSentFromLine {
                return classifyNotSentFromAction(notSentFromLine)
            }
            if let header = classifySingleHeader(first: first, errorLine: errorLine) {
                return header
            }
            guard !allowNonError else { return nil }
            let a = answer.lowercased()
            if a.contains("approval_required") { return .approval }
            if a.contains("busy") { return .busy }
            if a.contains("could not turn on") { return .sessionOff }
            if a.contains("task stopped") { return .stopped }
            if a.contains("timed out") || a.contains("timeout") || a.contains("did not answer in time") { return .timeout }
            if a.contains("not json") || a.contains("must be an array") || a.contains("needs a ") || a.contains("takes ") { return .invalidArguments }
            if first.hasPrefix("not_sent") || hasNothingSent { return .notSent }
            return .failed
        }

        private static func classifyRunnerLine(_ detail: String) -> Failure {
            if detail.hasPrefix("failed: cannot read the pairing file")
                || detail.hasPrefix("failed: the pairing file is neither")
                || detail.contains("fix on the phone: pair again in poki's setup.") {
                return .notSentPairingRequired
            }
            if detail.hasPrefix("starting (waiting for the loopback")
                || detail.hasPrefix("starting (waiting for the local developer connection")
                || detail == "starting (needs loopback)"
                || detail.hasPrefix("failed: remote pairing connect failed:")
                || detail.hasPrefix("failed: remote pairing handshake failed:")
                || detail.contains("fix on the phone: turn on the loopback")
                || detail.contains("fix on the phone: open setup › loopback")
                || detail.contains("fix on the phone: poki can't reach this iphone. check in this order: setup › loopback")
                || detail.contains("fix on the phone: the loopback is on. ios moved its pairing service") {
                return .notSentTunnelDisconnected
            }
            return .notSentSessionNotReady
        }

        private static func classifyStartupReason(_ reason: String) -> Failure {
            if reason.hasPrefix("the local connection is off")
                || reason.hasPrefix("choose and enable a local connection") {
                return .notSentTunnelDisconnected
            }
            if reason.hasPrefix("the phone refused the pairing")
                || reason.hasPrefix("pair this iphone first") {
                return .notSentPairingRequired
            }
            return .sessionOff
        }

        private static func isAppPreflightHeader(first: String, errorLine: String?) -> Bool {
            if first.hasPrefix("do: no app named ") || first.hasPrefix("do: app is turned off") { return true }
            if first.hasPrefix("launch ") && first.contains(": no app named ") { return true }
            if let errorLine, errorLine.hasPrefix("error: launch ") && errorLine.contains(": no app named ") { return true }
            if first.hasPrefix("not_sent: poki does not know an app called ") { return true }
            if first.hasPrefix("not_sent: ") && (first.contains(" could be any of ") || first.contains(" is not installed on this iphone.")) { return true }
            return false
        }

        private static func classifyNotSentFromAction(_ line: String) -> Failure {
            guard let colon = line.range(of: ": ") else { return .notSent }
            let reason = line[colon.upperBound...]
            if reason.hasPrefix("approval_required") { return .approval }
            if reason.hasPrefix("a coordinate action needs a fresh read") { return .notSentScreenEvidence }
            if reason.hasPrefix("the owner declined on the phone") || reason.hasPrefix("the approval request ended unanswered") {
                return .notSentApprovalDeclined
            }
            return .notSent
        }

        private static func classifySingleHeader(first: String, errorLine: String?) -> Failure? {
            if first.hasPrefix("not_sent: the runner is still finishing") || first.hasPrefix("busy: ") { return .busy }
            if first.hasPrefix("task stopped.") || first.hasPrefix("not_sent: task stopped") { return .stopped }
            if first.hasPrefix("automation is ready. nothing was sent.")
                || first.hasPrefix("the iphone unlocked. no requested action was sent.")
                || first.hasPrefix("split view: look at the selected pane")
                || (first.hasPrefix("element ") && first.contains(" is not in the latest read; nothing was sent"))
                || (errorLine?.hasPrefix("error: element ") == true && errorLine?.contains(" is not in the latest read; nothing was sent") == true) {
                return .notSentScreenEvidence
            }
            if first.hasPrefix("poki stopped waiting for automation to be ready.")
                || first.hasPrefix("poki is waiting for automation to be ready.")
                || isPasscodeConfirmationHeader(first) {
                return .notSentSessionNotReady
            }
            if first.hasPrefix("screen: locked.")
                || first.hasPrefix("automatic unlock could not be confirmed.")
                || errorLine?.hasPrefix("error: automatic unlock could not be confirmed.") == true {
                return .notSentLocked
            }
            if first.hasPrefix("not_sent: a step is handed to the owner") { return .notSentHandoff }
            if first.hasPrefix("not_sent: ") && first.contains("leave poki first") { return .notSentOwnApp }
            if first.hasPrefix("not_sent: the user declined on the phone")
                || first.hasPrefix("not_sent: the user did not allow it on the phone in time") {
                return .notSentApprovalDeclined
            }
            if first.hasPrefix("not_sent: the two visible apps")
                || first.hasPrefix("not_sent: split view")
                || first.hasPrefix("not_sent: keep both apps in place")
                || first.hasPrefix("not_sent: use look with pane")
                || first.hasPrefix("not_sent: choose left or right")
                || first.hasPrefix("not_sent: use the two visible apps")
                || first.hasPrefix("not_sent: that drag was already dropped") {
                return .notSentSplitView
            }
            if first.hasPrefix("not_hittable:")
                || errorLine?.hasPrefix("error: not_hittable:") == true
                || (first.hasPrefix("path:") && first.contains("nothing was sent")) {
                return .notSentTargetRefused
            }
            return nil
        }

        private static func isPasscodeConfirmationHeader(_ first: String) -> Bool {
            let passcode = AppLocalization.text(AppModel.passcodeConfirmationMessage).lowercased()
            return first.hasPrefix("not_sent: \(passcode)")
                || first.hasPrefix("not_sent: to turn on automation, open settings › connection")
                || first.hasPrefix("not_sent: 要开启自动化，请前往设置 › 连接")
                || first.hasPrefix("not_sent: 若要開啟自動化，請前往設定 › 連線")
        }
    }

    private static let lock = NSLock()
    /// Where the tasks are kept (Application Support/chat-debug.json).
    static var file: URL {
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

    private static func readLocked() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    /// A task's entry from its tool calls.
    static func entry(model: String, named: [String], calls: [CallRecord], finished: Bool?, seconds: Double, at: Date = Date()) -> Entry {
        Entry(at: at, model: model, seconds: (seconds * 10).rounded() / 10, named: named, calls: calls.map(call), finished: finished)
    }

    static func call(_ record: CallRecord) -> Call {
        let resolvedFailure = record.failure
            ?? (!record.ok ? Failure(answer: record.answer)
                : (record.name == "do" || record.name == "look" ? Failure.nonErrorRefusal(answer: record.answer) : nil))
        return Call(tool: record.name, actions: record.name == "do" ? actions(record.arguments) : [],
                    ok: record.ok && resolvedFailure == nil, ms: record.ms,
                    error: resolvedFailure?.rawValue)
    }

    /// Each do action's kind. Only values that cannot hold the owner's text are added: a launch's bundle
    /// id when it is an app Poki knows or one installed on this iPhone, and the direction of a button,
    /// key or swipe from their fixed lists. A launch that names anything else (a made-up id, a sentence
    /// with dots) is kept as "launch" alone; a run keeps no routine name and a type no text.
    static func actions(_ arguments: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let actions = object["actions"] as? [[String: Any]] else { return [] }
        return actions.compactMap { action in
            // An action is named by its verb, whatever else it carries: {type, ref} is a type. A
            // dictionary has no order, so the verb is looked for, not taken as the first key.
            guard let kind = verbs.first(where: { action[$0] != nil }) else { return action.keys.contains { $0 != "finish" } ? "other" : nil }
            let value = action[kind]
            let word = (value as? String) ?? ((value as? [String: Any])?["direction"] as? String)
            switch kind {
            case "launch":
                if let given = value as? String {
                    return isKnownApp(given) ? "launch \(given)" : "launch"
                }
                if let spec = value as? [String: Any] {
                    if let bundle = spec["bundle"] as? String {
                        return isKnownApp(bundle) ? "launch bundle \(bundle)" : "launch bundle"
                    }
                    if spec["name"] as? String != nil {
                        return "launch name"
                    }
                    if let app = spec["app"] as? String {
                        return isKnownApp(app) ? "launch \(app)" : "launch"
                    }
                }
                return "launch"
            case "button", "key", "swipe":
                return word.flatMap { directions[kind]?.contains($0) == true ? "\(kind) \($0)" : nil } ?? kind
            default:
                return kind
            }
        }
    }

    private static let directions: [String: Set<String>] = [
        "button": ["home", "lock", "volume_up", "volume_down"],
        "key": ["return", "delete", "tab", "space", "escape"],
        "swipe": ["up", "down", "left", "right"],
    ]
    /// The verbs of a do action, the ones that say most first.
    private static let verbs = ["launch", "run", "type", "tap", "long_press", "drag", "pinch", "swipe", "scroll_to", "key", "button", "back", "handoff", "wait_until", "wait"]

    /// A bundle id Poki lists (KnownApps) or the phone's own app list holds: nothing the model or the
    /// owner could have made up.
    static func isKnownApp(_ id: String) -> Bool {
        KnownApps.byID[id.lowercased()] != nil || DynamicApps.name(forID: id) != nil
    }

    /// The maintainers' debug file: PokiCore's routines and runs, then these tasks as `chat_tasks`.
    static func exportBundle() -> Data {
        RoutineStore.shared.debugBundle(extra: ["chat_tasks": json()])
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
