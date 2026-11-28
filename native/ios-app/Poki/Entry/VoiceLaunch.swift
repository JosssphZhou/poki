import Foundation
import os

private let voiceLaunchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nz.zheha.poki", category: "voice")

extension PokiEntry.Request {
    enum Outcome: String { case started, returned, shown, blocked, invalidated }
    enum Stage: String { case receipt, pageShown, transportConnected, inputReady, firstUtterance }

    @MainActor
    func record(_ outcome: Outcome, reason: String, session: Int? = nil) {
        let talk = session.map { " session=\($0)" } ?? ""
        let message = "launch request=\(id.uuidString) source=\(source.rawValue) result=\(outcome.rawValue) reason=\(reason)\(talk)"
        AppLog.shared.add("voice", message)
        voiceLaunchLogger.notice("\(message, privacy: .public)")
    }

    @MainActor
    func recordStage(_ stage: Stage, session: Int? = nil) {
        let elapsed = receivedAt.duration(to: .now).components
        let milliseconds = stage == .receipt ? 0 : elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        let talk = session.map { " session=\($0)" } ?? ""
        let message = "launch request=\(id.uuidString) stage=\(stage.rawValue) elapsedMS=\(milliseconds)\(talk)"
        AppLog.shared.add("voice", message)
        voiceLaunchLogger.notice("\(message, privacy: .public)")
    }
}
