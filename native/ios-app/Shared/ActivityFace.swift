import Foundation

typealias PokiState = PokiActivityAttributes.ContentState

/// What the Live Activity shows for a state, worked out once per phase. The Lock Screen, the expanded
/// island, the compact island and the minimal view all draw this, so the four presentations always say
/// the same thing in the same order.
///
/// The one fact to read at a glance is what Poki is doing on the phone right now, or what it needs
/// from you. Every presentation is built around it: Poki in the state's pose (the same in all four), a
/// short status word, and in the larger presentations the content line (the action, the question, the
/// result) in the large size. Below it there is at most one action: Stop while working, the Allow/Deny
/// decision while an approval waits, or Done for a step handed to you. Progress is a bar only where
/// there is a real total (setup's steps). An agent's run has no known length and its actions are not
/// numbered: the island shows the action in hand, and the chat keeps the record once the run has ended.
struct ActivityFace: Hashable {
    enum Meta: Hashable {
        case none
        /// A short count ("Step 7", "2/6") or a duration.
        case text(String)
        /// The time left on an approval, counted down by the system.
        case countdown(Date)
        /// A time of day ("9:41 AM").
        case clock(Date)
        /// How long the agent has waited for the person, counted up by the system.
        case elapsed(Date)
    }
    enum Compact: Hashable {
        /// Working: a dot, which beats once as each action comes in.
        case dot
        /// An SF Symbol ("checkmark" when done).
        case glyph(String)
        /// A short word or count ("2/6", "Done"); `quiet` for a state that needs nothing.
        case text(String, quiet: Bool)
        /// The pairing code, tabular digits.
        case code(String)
        case countdown(Date)
        case elapsed(Date)
    }
    enum Bottom: Hashable {
        case none
        /// Stop, beside the content line, while the agent is working.
        case stop
        case approval(id: String)
        /// "I'm Done" for a screen the agent handed to the person.
        case handoff(id: String)
        /// A real fraction (setup: steps done of all steps).
        case progress(Double)
        /// "Open Poki", for a problem the app explains.
        case open
    }

    /// Poki's pose for the state (a picture in Poki/BearPoses), drawn in every presentation.
    var pose: String
    /// The SF Symbol for the state, for lists of states (the in-app preview).
    var symbol: String
    /// The status word ("Approval").
    var status: String
    /// The same, short enough for the expanded island's leading region and the compact island.
    var shortStatus: String
    /// The value at the status word's right, on the Lock Screen and beside the camera.
    var meta: Meta
    /// The content line, the one thing in the large size.
    var content: String
    /// Set for the states that need the owner or stopped (an approval, a hand-off, a problem): the status
    /// word becomes a heading, and this is the quiet line under it. Nil: one line, the content.
    var detail: String?
    /// The content is the pairing code.
    var contentIsCode = false
    var bottom: Bottom
    var compact: Compact
    /// Outline the island while the person is needed.
    var outlined = false
    /// The screen a tap opens.
    var link: URL = ActivityLink.chat
    /// The app has not updated the activity for longer than it should have: what it shows may be old.
    var stale = false
    /// Who is calling: the outside agent whose badge sits beside the meta value.
    var caller: String?
    /// Time left on an approval, run down by the system in a ring around Poki in the minimal island.
    var timer: ClosedRange<Date>?
    /// A talk with Poki is on and the microphone is open: the island shows the microphone, and a tap on it
    /// ends the talk.
    var talking = false

    var hasAction: Bool {
        switch bottom {
        case .stop, .approval, .handoff, .open: true
        default: false
        }
    }
}

/// Where a tap on the Live Activity goes, handled by RootView's onOpenURL.
enum ActivityLink {
    /// The chat that runs the agent (also approvals and handoffs, which the chat shows).
    static let chat = URL(string: "poki://chat")!
    /// The Activity Log, where a problem's details are.
    static let log = URL(string: "poki://log")!
    static func setup(_ step: String? = nil) -> URL {
        URL(string: step.map { "poki://setup?step=\($0)" } ?? "poki://setup")!
    }
}

extension PokiState {
    var hasThumbnail: Bool { thumbnailVersion > 0 }

    /// "12 steps in 1:24".
    var runLine: String {
        let steps = stepCount == 1 ? String(activity: "1 step") : String(activity: "\(stepCount) steps")
        guard let since, let endedAt else { return steps }
        let time = Duration.seconds(max(0, endedAt.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond))
        return String(activity: "\(steps) in \(time)")
    }

    /// The finished run for the alert: "12 steps in 1:24, 1 missed".
    var runSummary: String {
        failedCount > 0 ? String(activity: "\(runLine), \(failedCount) missed") : runLine
    }

    var face: ActivityFace { face(stale: false) }

    /// The face for the widget: `stale` when ActivityKit says the content is past its stale date.
    func face(stale: Bool) -> ActivityFace {
        var face = baseFace
        face.caller = caller
        if talking == true {
            face.talking = true
            // Nothing in hand: Poki is listening.
            if phase == .idle {
                face.pose = "listen"
                face.content = String(activity: "Listening")
                face.compact = .glyph("mic.fill")
            }
        }
        // A fresh event ("Started", "Allowed") takes the status word's place for a few seconds, in
        // its own colour. An app switch keeps the app's name as the word and only lights it up.
        if let event, !phase.holdsApproval, face.detail == nil {
            let word = event.kind == .app ? (app ?? event.text) : ActivityWords.local(event.text)
            face.status = word
            face.shortStatus = word
        }
        if stale, phase == .working || phase == .handoff {
            // The app stopped updating (closed, or iOS suspended it): say so, and drop the action,
            // which needs the app.
            let word = String(activity: "Not updating")
            face.pose = "sleep"
            face.symbol = "clock.badge.exclamationmark"
            face.status = word
            face.shortStatus = String(activity: "Paused")
            face.meta = .none
            face.bottom = .none
            face.compact = .text(String(activity: "Paused"), quiet: true)
            face.outlined = false
            face.stale = true
        }
        return face
    }

    private var baseFace: ActivityFace {
        switch phase {
        case .working:
            let name = app ?? String(activity: "Working")
            return ActivityFace(
                pose: ActionKind(label: headline).pose, symbol: "hand.tap.fill", status: name, shortStatus: name, meta: .none,
                content: ActivityWords.step(headline), bottom: .stop,
                compact: .dot)
        case .approval, .deciding:
            guard let approval else { return quietFace }
            let question = ActivityWords.brief(approval.question)
            if phase == .deciding {
                let allowed = decision == true
                let word = allowed ? String(activity: "Allowed") : String(activity: "Denied")
                return ActivityFace(
                    pose: allowed ? "happy" : "rest", symbol: allowed ? "checkmark.circle.fill" : "xmark.circle.fill",
                    status: word, shortStatus: word, meta: .none,
                    content: question, bottom: .none,
                    compact: .text(word, quiet: !allowed))
            }
            let word = String(activity: "Approval")
            // The question is the heading; under it, the step that is waiting ("Tap “Send”").
            return ActivityFace(
                pose: "ask", symbol: "hand.raised.fill", status: question, shortStatus: word,
                meta: .countdown(approval.expires),
                content: question, detail: ActivityWords.step(approval.summary), bottom: .approval(id: approval.id),
                compact: .countdown(approval.expires),
                outlined: true,
                timer: Countdown.range(approval.expires))
        case .done:
            let word = String(activity: "Done")
            return ActivityFace(
                pose: "happy", symbol: "checkmark.circle.fill", status: word, shortStatus: word,
                meta: .none,
                content: word, bottom: .none,
                compact: .glyph("checkmark"))
        case .problem:
            let short = label == "Pairing Failed" ? String(activity: "Failed") : String(activity: "Stopped")
            return ActivityFace(
                pose: "worry", symbol: "exclamationmark.triangle.fill",
                status: ActivityWords.local(label ?? "Problem"), shortStatus: short,
                meta: .none,
                content: ActivityWords.brief(ActivityWords.local(headline)), detail: ActivityWords.local(headline), bottom: .open,
                compact: .text(short, quiet: false),
                link: label == "Pairing Failed" ? ActivityLink.setup("pairing") : ActivityLink.log)
        case .pairing:
            if let pin {
                return ActivityFace(
                    pose: "search", symbol: "link", status: pin.count == 6 ? "\(pin.prefix(3)) \(pin.suffix(3))" : pin, shortStatus: String(activity: "Pairing"),
                    meta: .none,
                    content: pin, detail: String(activity: "Pairing Code"), contentIsCode: true,
                    bottom: .none,
                    compact: .code(pin),
                    link: ActivityLink.setup("pairing"))
            }
            let word = String(activity: "Pairing")
            return ActivityFace(
                pose: "search", symbol: "link", status: word, shortStatus: word, meta: .none,
                content: String(activity: "Pair in Settings"), bottom: .none,
                compact: .text(word, quiet: false),
                link: ActivityLink.setup("pairing"))
        case .setup:
            guard let guide else { return quietFace }
            let word = String(activity: "Setup")
            let count = "\(guide.number)/\(guide.count)"
            return ActivityFace(
                pose: "search", symbol: "checklist", status: word, shortStatus: word, meta: .text(count),
                content: ActivityWords.brief(ActivityWords.local(guide.title)),
                bottom: .progress(Double(max(0, guide.number - 1)) / Double(max(1, guide.count))),
                compact: .text(count, quiet: false),
                link: ActivityLink.setup())
        case .handoff:
            guard let handoff else { return quietFace }
            let word = String(activity: "Your turn")
            return ActivityFace(
                pose: "hide", symbol: handoff.symbol, status: word, shortStatus: word, meta: .elapsed(handoff.since),
                content: ActivityWords.brief(handoff.line), detail: handoff.line,
                bottom: .handoff(id: handoff.id),
                compact: .elapsed(handoff.since),
                outlined: true)
        case .idle:
            return quietFace
        }
    }

    /// Ready (the runner is up) and Idle (it sleeps until an agent asks).
    private var quietFace: ActivityFace {
        let word = runnerPaused ? String(activity: "Idle") : String(activity: "Ready")
        return ActivityFace(
            pose: runnerPaused ? "sleep" : "rest", symbol: runnerPaused ? "moon.fill" : "checkmark.circle",
            status: word, shortStatus: word, meta: .none,
            content: ActivityWords.brief(ActivityWords.local(headline)), bottom: .none,
            compact: .text(word, quiet: runnerPaused))
    }
}

/// The kind of action a step label from PokiCore names ("Tap “Send”", "Scroll to “Checkout”"), read from
/// its first word, for Poki's pose: it looks at the screen for the actions that read it, and is on the
/// phone for the rest. PokiCore's labels are English (ActivityWords).
struct ActionKind {
    var pose: String
    init(label: String) {
        let word = label.prefix { $0.isLetter }.lowercased()
        pose = ["scroll", "swipe", "look", "read", "wait"].contains(word) ? "search" : "phone"
    }
}

extension PokiActivityAttributes.Handoff {
    /// What the person has to do, in the agent's place.
    var title: String {
        switch kind {
        case .runnerPasscode: String(activity: "Enter your passcode to start the runner")
        case .automationPasscode: String(activity: "Enter your passcode to allow automation")
        case .passcode: String(activity: "Enter your passcode")
        case .password: String(activity: "Fill in your password")
        case .verification: String(activity: "Pass the verification yourself")
        case .payment: String(activity: "Finish the payment yourself")
        case .other: String(activity: "Do this step yourself")
        }
    }
    /// The content line: a fixed short line per kind, so it fits the Live Activity's four words (eight
    /// characters in Chinese) whole. The agent's own note is the alert's second line (`detail`) and
    /// the app's issue row, where it has room.
    var line: String {
        switch kind {
        case .runnerPasscode: String(activity: "Passcode for the runner")
        case .automationPasscode: String(activity: "Passcode for automation")
        default: title
        }
    }
    /// The agent's own note, or what happens next (the alert's second line).
    var detail: String {
        if let text, !text.isEmpty { return text }
        switch kind {
        case .runnerPasscode: return String(activity: "iOS asks for it once after a restart. The agent waits.")
        case .automationPasscode: return String(activity: "iOS asks after Poki restarts or 8 hours later. The agent waits.")
        case .payment: return String(activity: "The agent does not pay for you. It waits, then carries on.")
        default: return String(activity: "The agent can't act on this screen. It waits for you.")
        }
    }
    var symbol: String {
        switch kind {
        case .runnerPasscode, .automationPasscode, .passcode: "lock.fill"
        case .password: "key.fill"
        case .verification: "checkmark.shield.fill"
        case .payment: "creditcard.fill"
        case .other: "person.fill"
        }
    }
}
