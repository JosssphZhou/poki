import Foundation

enum TaskCue: String, CaseIterable, Sendable {
    case started = "start"
    case approval = "notification"
    case completed = "complete"
    case failed = "blocked"
}

@MainActor
protocol CueSoundOutput {
    func play(_ cue: TaskCue)
}

@MainActor
final class CueSounds {
    nonisolated static let enabledKey = "sounds.cuesEnabled"
    private let output: any CueSoundOutput
    private let defaults: UserDefaults
    private var startedTasks: Set<UUID> = []
    private var endedTasks: Set<UUID> = []
    private var presentedApprovals: Set<String> = []

    init(output: any CueSoundOutput, defaults: UserDefaults = .standard) {
        self.output = output
        self.defaults = defaults
    }

    var enabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func taskStarted(_ id: UUID) {
        guard startedTasks.insert(id).inserted, enabled else { return }
        output.play(.started)
    }

    func taskEnded(_ id: UUID, succeeded: Bool) {
        guard endedTasks.insert(id).inserted, enabled else { return }
        output.play(succeeded ? .completed : .failed)
    }

    func approvalPresented(_ id: String) {
        guard presentedApprovals.insert(id).inserted, enabled else { return }
        output.play(.approval)
    }
}
