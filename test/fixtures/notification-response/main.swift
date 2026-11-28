import Foundation
import UserNotifications

enum ApprovalNotice {
    static let allow = "approval.allow"
    static let deny = "approval.deny"
    static let stopAsking = "approval.stop"
}
struct ApprovalDecision {
    let approvalID: String
    let approved: Bool
    let stopAsking: Bool
    var waitForIslandCollapse = true
}
enum ApprovalIntentBridge {
    @MainActor static func submit(_ decision: ApprovalDecision) {
        precondition(Thread.isMainThread)
        precondition(decision.approvalID == "test-approval")
        precondition(!decision.waitForIslandCollapse, "Notification actions must not wait for the island to collapse")
    }
}
checkNotificationResponses(ApprovalNoticeDelegate.shared)
RunLoop.main.run()
