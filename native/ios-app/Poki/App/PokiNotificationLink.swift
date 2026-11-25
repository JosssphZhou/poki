import Foundation

/// A `poki://` link from a notification's default tap. The notification delegate may run before the
/// scene is active, so the link waits here and the root view takes it once, on activation or on the
/// delegate's post. Approval responses keep their own path and never come here.
@MainActor
enum PokiNotificationLink {
    static let posted = Notification.Name("PokiNotificationLinkPosted")
    private static var pending: URL?

    static func post(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: posted, object: nil)
    }

    static func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}
