// Talk to Poki from outside the app: the Action Button, Control Center, the Lock Screen, Shortcuts,
// Siri and Spotlight. In both the app and the widget extension, because a control's action has to be
// in both; it always runs in the app (`openAppWhenRun`).
import AppIntents
import Foundation
import Observation
import os

@MainActor
@Observable
final class PokiEntry {
    enum Destination: Equatable { case talk, voice, chat }
    enum Source: String { case appShortcut, control, link, anytime, sendTask }

    struct Request: Equatable {
        let id: UUID
        let destination: Destination
        let issuedAt: Date
        let receivedUptimeMS: UInt64 = DispatchTime.now().uptimeNanoseconds / 1_000_000
        let source: Source
        let epoch: Int

        func isExpired(at now: Date = PokiEntry.now()) -> Bool {
            now.timeIntervalSince(issuedAt) > 15
        }
    }

    static let shared = PokiEntry()
    private(set) var pending: [Request] = []
    @ObservationIgnored private var accepted = Set<UUID>()
    private nonisolated static let epochState = OSAllocatedUnfairLock(initialState: 0)
    private nonisolated static let clockState = OSAllocatedUnfairLock<@Sendable () -> Date>(initialState: { Date.now })
    nonisolated static var currentEpoch: Int { epochState.withLock { $0 } }
    nonisolated static var now: @Sendable () -> Date {
        get { clockState.withLock { $0 } }
        set { clockState.withLock { $0 = newValue } }
    }
    nonisolated var epoch: Int { Self.currentEpoch }

    func ask(_ destination: Destination, from source: Source, id: UUID = UUID(), issuedAt: Date? = nil, epoch: Int? = nil) {
        ask(Request(id: id, destination: destination, issuedAt: issuedAt ?? Self.now(), source: source, epoch: epoch ?? self.epoch))
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

    func advanceEpoch() { Self.epochState.withLock { $0 += 1 } }
}

/// Opens Poki's chat to start or return to a talk.
/// A tool for Siri AI in the app only (POKI_SIRI_TOOLS is never set for the widget extension, which
/// carries this intent for its control): see SendTaskToPokiIntent.
struct TalkToPokiIntent: AppIntent {
    static let title = LocalizedStringResource("Talk to Poki", table: "Entry")
    static let description = IntentDescription(LocalizedStringResource("Opens Poki to start or return to a talk. If Poki is doing a task, it shows the task and leaves it running.", table: "Entry"))
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    private let requestID = UUID()
    private let issuedAt = PokiEntry.now()
    private let issuedEpoch = PokiEntry.currentEpoch

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
        PokiEntry.shared.ask(.talk, from: fromControl == true ? .control : .appShortcut,
                             id: requestID, issuedAt: issuedAt, epoch: issuedEpoch)
        return .result()
    }
}

#if POKI_SIRI_TOOLS
// A tool for Siri AI. This is what @AppIntent(.tool) adds, written out: the macro needs iOS 27.3,
// and Poki runs from iOS 18, so only the conformance is limited to 27.3 and the intent stays
// available (with its App Shortcut and control) on earlier versions.
@available(iOS 27.3, *)
extension TalkToPokiIntent: ToolIntent {}
#endif
