// Talk to Poki from outside the app: the Action Button, Control Center, the Lock Screen, Shortcuts,
// Siri and Spotlight. In both the app and the widget extension, because a control's action has to be
// in both; it always runs in the app (`openAppWhenRun`).
import AppIntents
import Foundation
import Observation

@MainActor
@Observable
final class PokiEntry {
    enum Destination: Equatable { case talk, voice, chat }
    enum Source: String { case appShortcut, control, link, anytime, sendTask }

    struct Request: Equatable {
        let id: UUID
        let destination: Destination
        let issuedAt: Date
        let receivedAt = ContinuousClock.now
        let source: Source
        let epoch: Int

        func isExpired(at now: Date = .now) -> Bool {
            now.timeIntervalSince(issuedAt) > 15
        }
    }

    static let shared = PokiEntry()
    private(set) var pending: [Request] = []
    @ObservationIgnored private var accepted = Set<UUID>()
    @ObservationIgnored private(set) var epoch = 0

    func ask(_ destination: Destination, from source: Source, id: UUID = UUID()) {
        ask(Request(id: id, destination: destination, issuedAt: .now, source: source, epoch: epoch))
    }

    func ask(_ request: Request) {
        guard accepted.insert(request.id).inserted else { return }
        #if POKI_APP
        if request.destination != .chat { request.recordStage(.receipt) }
        #endif
        pending.append(request)
    }

    func take() -> [Request] {
        defer { pending.removeAll() }
        return pending
    }

    func advanceEpoch() { epoch += 1 }
}

/// Opens Poki's chat to start or return to a talk.
struct TalkToPokiIntent: AppIntent {
    static let title = LocalizedStringResource("Talk to Poki", table: "Entry")
    static let description = IntentDescription(LocalizedStringResource("Opens Poki to start or return to a talk. If Poki is doing a task, it shows the task and leaves it running.", table: "Entry"))
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    private let requestID = UUID()

    // WidgetKit serializes intent parameters between its extension and the app.
    @Parameter(title: "Control")
    var fromControl: Bool?

    static var parameterSummary: some ParameterSummary {
        Summary("Talk to Poki", table: "Entry")
    }

    init() {}
    init(fromControl: Bool) { self.fromControl = fromControl }

    @MainActor
    func perform() async throws -> some IntentResult {
        PokiEntry.shared.ask(.talk, from: fromControl == true ? .control : .appShortcut, id: requestID)
        return .result()
    }
}
