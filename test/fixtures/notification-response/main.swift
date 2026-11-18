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
    var stopAsking = false
}
enum ApprovalIntentBridge {
    @MainActor static func submit(_ decision: ApprovalDecision) {
        precondition(Thread.isMainThread)
        precondition(decision.approvalID == "test-approval")
        print("DECISION approved=\(decision.approved) stopAsking=\(decision.stopAsking)")
    }
}
checkNotificationResponses(ApprovalNoticeDelegate.shared)
RunLoop.main.run()
