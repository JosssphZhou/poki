import AppIntents

struct ToggleMicrophoneMuteIntent: AppIntent {
    static let title = LocalizedStringResource("Toggle Microphone Mute", table: "Entry")
    static let description = IntentDescription(LocalizedStringResource("Mutes or unmutes your microphone in the current Poki call.", table: "Entry"))
    static let openAppWhenRun = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let words: LocalizedStringResource
        switch AskPoki.app?.voice.toggleMicrophoneMute() {
        case .some(true):
            words = LocalizedStringResource("Microphone muted.", table: "Entry")
        case .some(false):
            words = LocalizedStringResource("Microphone unmuted.", table: "Entry")
        case nil:
            words = LocalizedStringResource("There is no active call.", table: "Entry")
        }
        return .result(dialog: IntentDialog(words))
    }
}
