import Foundation
import os

private let voiceLaunchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nz.zheha.poki", category: "voice")

enum VoiceLaunchTiming {
    static let logArea = "voice-timing"
    static let inputReadySource = "webrtc_outbound_rtp_bytes"

    static func nowUptimeMS() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    static func line(session: Int?, at uptimeMS: UInt64, event: String, fields: [(String, String)]) -> String {
        let sessionText = session.map(String.init) ?? "none"
        let base = "session=\(sessionText) flow=voice turn=0 t_ms=\(uptimeMS) event=\(event)"
        guard !fields.isEmpty else { return base }
        return base + " " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }

    static func reasonValue(_ raw: String) -> String {
        switch raw {
        case "newTalk": return "new_talk"
        case "activeTalk": return "active_talk"
        case "firstRun": return "first_run"
        case "pairing": return "pairing"
        case "expired": return "expired"
        case "link": return "link"
        case "taskRunning": return "task_running"
        case "voiceNotConfigured": return "voice_not_configured"
        case "voiceEpochChanged": return "voice_epoch_changed"
        case "sceneInactive": return "scene_inactive"
        default:
            var out = ""
            out.reserveCapacity(raw.count + 4)
            var previousWasLowerOrDigit = false
            for scalar in raw.unicodeScalars {
                if CharacterSet.uppercaseLetters.contains(scalar) {
                    if previousWasLowerOrDigit { out.append("_") }
                    out.append(String(scalar).lowercased())
                    previousWasLowerOrDigit = false
                } else {
                    out.append(String(scalar))
                    previousWasLowerOrDigit = CharacterSet.lowercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
                }
            }
            return out
        }
    }
}

extension PokiEntry.Source {
    var timingValue: String {
        switch self {
        case .appShortcut: "app_shortcut"
        case .control: "control"
        case .link: "link"
        case .anytime: "anytime"
        case .sendTask: "send_task"
        }
    }
}

extension PokiEntry.Request {
    enum Outcome: String { case started, returned, shown, blocked, invalidated }
    enum Stage: String {
        case receipt
        case pageShown
        case transportConnected
        case inputReady
        case firstUtterance

        var timingEvent: String {
            switch self {
            case .receipt: "launch_receipt"
            case .pageShown: "launch_page_shown"
            case .transportConnected: "launch_transport_connected"
            case .inputReady: "launch_input_ready"
            case .firstUtterance: "launch_first_utterance"
            }
        }
    }

    @MainActor
    func record(_ outcome: Outcome, reason: String, session: Int? = nil) {
        let talk = session.map { " session=\($0)" } ?? ""
        let message = "launch request=\(id.uuidString) source=\(source.rawValue) result=\(outcome.rawValue) reason=\(reason)\(talk)"
        AppLog.shared.add("voice", message)
        voiceLaunchLogger.notice("\(message, privacy: .public)")

        let now = max(VoiceLaunchTiming.nowUptimeMS(), receivedUptimeMS)
        let timing = VoiceLaunchTiming.line(
            session: session,
            at: now,
            event: "launch_outcome",
            fields: [
                ("request_id", id.uuidString),
                ("source", source.timingValue),
                ("result", outcome.rawValue),
                ("reason", VoiceLaunchTiming.reasonValue(reason)),
                ("since_receipt_ms", "\(now - receivedUptimeMS)"),
            ]
        )
        AppLog.shared.add(VoiceLaunchTiming.logArea, timing)
        voiceLaunchLogger.notice("\(timing, privacy: .public)")
    }

    @MainActor
    func recordStage(_ stage: Stage, session: Int? = nil) {
        let now = stage == .receipt ? receivedUptimeMS : max(VoiceLaunchTiming.nowUptimeMS(), receivedUptimeMS)
        let milliseconds = stage == .receipt ? 0 : Int(now - receivedUptimeMS)
        var fields: [(String, String)] = [
            ("request_id", id.uuidString),
            ("source", source.timingValue),
            ("since_receipt_ms", "\(milliseconds)"),
        ]
        if stage == .inputReady {
            fields.append(("input_ready_source", VoiceLaunchTiming.inputReadySource))
        }
        let timing = VoiceLaunchTiming.line(session: session, at: now, event: stage.timingEvent, fields: fields)
        AppLog.shared.add(VoiceLaunchTiming.logArea, timing)
        voiceLaunchLogger.notice("\(timing, privacy: .public)")
    }
}
