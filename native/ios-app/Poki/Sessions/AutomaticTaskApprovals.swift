import Foundation
import PokiCore

/// A transient floor for the lifetime of automatically started tasks. The saved owner preference
/// is untouched. The core reads from its own executor, so this small piece of state is locked.
final class AutomaticTaskApprovals: @unchecked Sendable {
    static let shared = AutomaticTaskApprovals()
    private let lock = NSLock()
    private var runs: Set<UUID> = []

    func begin() -> UUID {
        lock.withLock { let id = UUID(); runs.insert(id); return id }
    }

    func end(_ id: UUID) { lock.withLock { _ = runs.remove(id) } }

    func effective(_ saved: (mode: ApprovalMode, level: ApprovalLevel)) -> (mode: ApprovalMode, level: ApprovalLevel) {
        lock.withLock {
            guard !runs.isEmpty else { return saved }
            // Unattended tasks must check sensitive steps at Balanced or stricter.
            return (saved.mode == .off ? .confirm : saved.mode,
                    saved.level == .permissive ? .balanced : saved.level)
        }
    }
}
