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
}
enum ApprovalIntentBridge {
    @MainActor static func submit(_ decision: ApprovalDecision) {
        precondition(Thread.isMainThread)
        precondition(decision.approvalID == "test-approval")
    }
}
// Queue adapter for this delegate/threading test. Persistent claims and task eligibility are
// covered by the app's DailyTaskTests; this fixture must not touch the owner's app-support files.
enum DailyTask {
    struct Delivery {
        let id: UUID
        let date: Date
    }
    @MainActor final class Queue {
        private(set) var requests: [Delivery] = []
        func request(_ delivery: Delivery) {
            precondition(Thread.isMainThread)
            requests.append(delivery)
        }
        func shouldRemind(_ delivery: Delivery) -> Bool {
            precondition(Thread.isMainThread)
            return true
        }
    }
    @MainActor static let shared = Queue()
}
atexit {
    MainActor.assumeIsolated {
        precondition(DailyTask.shared.requests.map { $0.date.timeIntervalSince1970 } == [4, 5],
                     "Default tap and Run Task queue once each, preserving delivery dates; dismiss must not queue")
        print("PASS: only the two explicit daily-task actions queue a task")
    }
}
checkNotificationResponses(ApprovalNoticeDelegate.shared)
RunLoop.main.run()
