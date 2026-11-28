import Foundation

/// Single source of truth for classifying user barge-in transcripts during voice playback.
enum VoiceBargeInPolicy {
    enum Classification: Equatable {
        case empty
        case backchannel
        case stopCommand
        case substantive
    }

    static let stopPhrases: Set<String> = ["停", "停止", "停一下", "别动", "别做了", "stop", "cancel"]
    static let backchannels: Set<String> = ["嗯", "哦", "好的", "好", "uh-huh", "mm-hmm"]

    static func speechParts(_ text: String) -> [String] {
        text.lowercased().split { $0.isPunctuation && $0 != "-" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
    }

    static func requestsStop(_ parts: [String]) -> Bool {
        guard let first = parts.first, stopPhrases.contains(first) else { return false }
        return parts.dropFirst().allSatisfy { part in stopPhrases.contains { $0.hasPrefix(part) } }
    }

    static func classify(_ text: String) -> Classification {
        let parts = speechParts(text)
        guard !parts.isEmpty else { return .empty }
        if parts.allSatisfy(backchannels.contains) { return .backchannel }
        let substantive = parts.filter { !backchannels.contains($0) }
        if requestsStop(substantive) { return .stopCommand }
        return .substantive
    }
}

/// Tracks multi-step phone execution during a live voice turn and decides when a confirmed tool
/// milestone should trigger a brief factual spoken progress update after prolonged silence.
struct VoiceProgressSync {
    struct Tool: Hashable {
        fileprivate let id = UUID()
        fileprivate let turn: UUID
    }

    struct Update: Equatable {
        let app: String?
        let stepSummary: String
        let liveCommentary: String
        let realtimeNote: String
        let codexHeader: String
    }

    static let defaultSilenceThreshold: TimeInterval = 20
    static let defaultAppSwitchThreshold: TimeInterval = 12
    static let minCompletedSteps = 2

    private(set) var completedSteps = 0
    private var turn = UUID()
    private var tools: Set<Tool> = []
    var inFlightTools: Int { tools.count }
    private(set) var lastApp: String?
    private(set) var lastSpokenAt: Date?

    mutating func reset() {
        self = Self()
    }

    mutating func beginTurn(at now: Date) {
        turn = UUID()
        completedSteps = 0
        lastApp = nil
        lastSpokenAt = now
    }

    mutating func noteSpeech(at now: Date) {
        lastSpokenAt = now
    }

    mutating func toolStarted(at now: Date) -> Tool {
        let tool = Tool(turn: turn)
        tools.insert(tool)
        if lastSpokenAt == nil { lastSpokenAt = now }
        return tool
    }

    mutating func toolAborted(_ tool: Tool) {
        tools.remove(tool)
    }

    mutating func toolCompleted(_ tool: Tool, name: String, arguments: String, output: String, failed: Bool, at now: Date) -> Update? {
        guard tools.remove(tool) != nil, tool.turn == turn else { return nil }
        guard !failed, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        completedSteps += 1
        let currentApp = Self.extractApp(name: name, arguments: arguments, output: output)
        let switchedApp = currentApp != nil && lastApp != nil && currentApp != lastApp
        if let currentApp { lastApp = currentApp }
        guard inFlightTools == 0, completedSteps >= Self.minCompletedSteps else { return nil }
        let reference = lastSpokenAt ?? now
        let silentFor = now.timeIntervalSince(reference)
        let threshold = switchedApp ? Self.defaultAppSwitchThreshold : Self.defaultSilenceThreshold
        guard silentFor >= threshold else { return nil }
        lastSpokenAt = now

        let seconds = max(1, Int(silentFor))
        let stepSummary = Self.describeMilestone(name: name, app: currentApp)
        return Update(
            app: currentApp,
            stepSummary: stepSummary,
            liveCommentary: "Progress update (still in progress, do not claim the task is finished): \(stepSummary). Give one brief factual progress sentence in the user's language, then keep working.",
            realtimeNote: "Progress sync: over \(seconds)s have passed since your last spoken update. Confirmed step: \(stepSummary). Work is still in progress: say one brief factual progress sentence about this confirmed step in the user's language without claiming the overall task is finished, then continue the remaining steps.",
            codexHeader: "[Poki progress sync] Over \(seconds)s have passed since the last spoken update. Confirmed step: \(stepSummary). Work is still in progress: give one brief factual progress sentence in the user's language without claiming the overall task is finished, then continue the remaining steps."
        )
    }

    private static func describeMilestone(name: String, app: String?) -> String {
        if let app {
            switch name {
            case "open_app": return "opened \(app)"
            case "look": return "checked \(app)"
            default: return "completed a step in \(app)"
            }
        }
        switch name {
        case "open_app": return "opened the app"
        case "look": return "checked the screen"
        default: return "completed a phone step"
        }
    }

    private static func extractApp(name: String, arguments: String, output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("app: ") else { continue }
            let rawName = line.dropFirst(5).components(separatedBy: "   read:").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawName, !rawName.isEmpty, rawName.lowercased() != "unknown" {
                return rawName
            }
        }
        guard name == "open_app",
              let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = (json["app"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !app.isEmpty else { return nil }
        return app
    }
}
