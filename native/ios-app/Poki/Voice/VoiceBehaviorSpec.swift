import Foundation

enum VoicePromptRole: String, Codable, Sendable {
    case realtime
    case liveVoice = "live_voice"
    case liveExecutor = "live_executor"
    case codexVoice = "codex_voice"
    case codexExecutor = "codex_executor"

    var mode: String {
        switch self {
        case .realtime: return "realtime"
        case .liveVoice, .liveExecutor: return "live"
        case .codexVoice, .codexExecutor: return "codex"
        }
    }
}

enum VoicePromptHost: String, Codable, Sendable {
    case phone
    case mac
}

enum VoiceStartupMode: String, Sendable {
    case realtimeDirect = "realtime_direct"
    case liveDirect = "live_direct"
    case realtimeBridge = "realtime_bridge"
    case liveBridge = "live_bridge"
    case codexLive = "codex_live"
    case rehearsal
    case dictation
}

enum VoiceStartupCommitState: String, Sendable {
    case queued
    case submitted
    case confirmed
    case failed
}

struct VoicePromptSectionOutput: Equatable, Sendable {
    struct ClauseOutput: Equatable, Sendable {
        let id: String
        let text: String
    }

    let id: String
    let title: String
    let clauses: [ClauseOutput]
}

struct VoicePromptBuild: Equatable, Sendable {
    let templateVersion: String
    let role: VoicePromptRole
    let mode: String
    let host: VoicePromptHost
    let language: String
    let languageName: String
    let tools: [String]
    let sectionIds: [String]
    let clauseIds: [String]
    let sections: [VoicePromptSectionOutput]
    let text: String
}

struct VoiceBehaviorSpec: Decodable, Sendable {
    struct Section: Decodable, Sendable {
        let id: String
        let title: String
    }

    struct Clause: Decodable, Sendable {
        let id: String
        let section: String
        let roles: [String]
        let hosts: [String]?
        let requires_work_tools: Bool?
        let forbids_work_tools: Bool?
        let requires_all_tools: [String]?
        let requires_any_tools: [String]?
        let forbids_tools: [String]?
        let text: String
    }

    let version: String
    let language_names: [String: String]
    let lock_check: String
    let sections: [Section]
    let clauses: [Clause]

    static let shared: VoiceBehaviorSpec = load()
    static var version: String { shared.version }

    static func startupLogLine(templateVersion: String, mode: VoiceStartupMode, commitState: VoiceStartupCommitState, errorCode: String? = nil) -> String {
        let base = "voice startup: template=\(templateVersion) mode=\(mode.rawValue) commit_state=\(commitState.rawValue)"
        guard let errorCode, !errorCode.isEmpty else { return base }
        return "\(base) error_code=\(errorCode)"
    }

    private static let screenImageTools = ["look", "do", "open_app"]
    private static let numberedTools = ["look", "do"]
    private static let controlOnlyTools: Set<String> = ["cancel_current_task"]

    private static func load() -> VoiceBehaviorSpec {
        if let url = Bundle.main.url(forResource: "voice-behavior-spec", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(VoiceBehaviorSpec.self, from: data) {
            return decoded
        }
        #if DEBUG
        let sourceSpec = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/data/voice-behavior-spec.json")
        if let data = try? Data(contentsOf: sourceSpec),
           let decoded = try? JSONDecoder().decode(VoiceBehaviorSpec.self, from: data) {
            return decoded
        }
        #endif
        preconditionFailure("Missing voice-behavior-spec.json resource")
    }

    func resolveLanguageName(_ code: String) -> String {
        if let mapped = language_names[code] { return mapped }
        return Locale(identifier: "en").localizedString(forIdentifier: code) ?? "English"
    }

    func build(role: VoicePromptRole, language: String, tools: [String], host: VoicePromptHost = .phone) -> VoicePromptBuild {
        var orderedTools: [String] = []
        var toolSet: Set<String> = []
        for name in tools where !name.isEmpty && toolSet.insert(name).inserted {
            orderedTools.append(name)
        }
        let hasWorkTools = orderedTools.contains { !Self.controlOnlyTools.contains($0) }
        let languageName = resolveLanguageName(language)
        let screenTools = Self.formatList(Self.screenImageTools.filter(toolSet.contains), conjunction: "or")
        let numberedTools = Self.formatList(Self.numberedTools.filter(toolSet.contains), conjunction: "or")
        let values: [String: String] = [
            "language": languageName,
            "lock_check": lock_check,
            "screen_tools": screenTools,
            "numbered_tools": numberedTools,
            "cancel_tool": "cancel_current_task",
        ]

        var builtSections: [VoicePromptSectionOutput] = []
        var clauseIds: [String] = []
        for section in sections {
            var selected: [VoicePromptSectionOutput.ClauseOutput] = []
            for clause in clauses where clause.section == section.id {
                guard matches(clause, role: role, host: host, toolSet: toolSet, hasWorkTools: hasWorkTools) else { continue }
                let rendered = Self.substitute(clause.text, values: values)
                selected.append(.init(id: clause.id, text: rendered))
                clauseIds.append(clause.id)
            }
            if !selected.isEmpty {
                builtSections.append(.init(id: section.id, title: section.title, clauses: selected))
            }
        }

        let text = builtSections
            .map { "# \($0.title)\n" + $0.clauses.map(\.text).joined(separator: "\n") }
            .joined(separator: "\n\n")

        return VoicePromptBuild(
            templateVersion: version,
            role: role,
            mode: role.mode,
            host: host,
            language: language,
            languageName: languageName,
            tools: orderedTools,
            sectionIds: builtSections.map(\.id),
            clauseIds: clauseIds,
            sections: builtSections,
            text: text
        )
    }

    private func matches(_ clause: Clause, role: VoicePromptRole, host: VoicePromptHost, toolSet: Set<String>, hasWorkTools: Bool) -> Bool {
        guard clause.roles.contains(role.rawValue) else { return false }
        if let hosts = clause.hosts, !hosts.contains(host.rawValue) { return false }
        if clause.requires_work_tools == true, !hasWorkTools { return false }
        if clause.forbids_work_tools == true, hasWorkTools { return false }
        if let requiredAll = clause.requires_all_tools, !requiredAll.allSatisfy(toolSet.contains) { return false }
        if let requiredAny = clause.requires_any_tools, !requiredAny.contains(where: toolSet.contains) { return false }
        if let forbidden = clause.forbids_tools, forbidden.contains(where: toolSet.contains) { return false }
        return true
    }

    private static func formatList(_ items: [String], conjunction: String) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(conjunction) \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", \(conjunction) " + items.last!
        }
    }

    private static func substitute(_ template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
