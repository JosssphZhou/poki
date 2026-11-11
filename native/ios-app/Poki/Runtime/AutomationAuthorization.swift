import Foundation

/// Recognize the explicit XCTest refusal; an absent tree or a timeout is not proof of revocation.
enum AutomationAuthorization {
    static let lost = Notification.Name("poki.automationAuthorizationLost")
    static func isDenied(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("not authorized for performing UI testing actions")
    }
}
