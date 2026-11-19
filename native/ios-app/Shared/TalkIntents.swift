import AppIntents
import Foundation

/// End on the Live Activity while you talk with Poki: ends the talk without opening Poki, and stops
/// what Poki is doing with it, as Stop does. The widget runs this in its own process, so it only rings
/// the app, as StopRunnerIntent does; TalkActivity hears the ring and ends the talk. No authentication: ending a
/// talk is always safe. Ending a talk from the island is the interaction of pull request #250; this code
/// is written here, on this file's neighbour StopRunnerIntent.
struct EndTalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End talk"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        TalkSignal.ring(TalkSignal.end)
        return .result()
    }
}

/// Try Again on the Live Activity after a talk could not connect. The island and the Lock Screen show
/// it while Poki is in the background, and iOS opens the microphone for a background app only from the
/// recording intent that started the talk (TalkHereIntent). So this brings the person back to Poki,
/// which starts the talk once it is in front (PokiEntry), like Talk to Poki.
struct RetryTalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Try Again"
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static let isDiscoverable = false
    init() {}
    @MainActor
    func perform() async throws -> some IntentResult {
        PokiEntry.shared.ask(.talk)
        return .result()
    }
}

/// The Darwin notifications between the Live Activity and the talk in the app. No payload: the name
/// is the message. Under the App Group's name, as ApprovalMailbox's are.
enum TalkSignal {
    static let end = SharedContainer.appGroup + ".talk.end"

    static func ring(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
}
