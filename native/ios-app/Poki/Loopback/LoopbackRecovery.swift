import Foundation

@MainActor
final class LoopbackRecovery {
    enum Demand: String, Hashable {
        case screenHistory, automation, pairing, automaticSigning, signing
    }

    static var retryHelp: String {
        AppLocalization.text(LocalizedStringResource("Run the Poki Loopback shortcut or reconnect your VPN, then try again."))
    }

    private(set) var failurePending = false
    private var attempt: Task<Bool, Never>?
    private var demands: Set<Demand> = []
    private var failedDemands: Set<Demand> = []
    private var shortcutReturnedAt: Date?
    private var lastLaunch: ContinuousClock.Instant?
    private(set) var attemptedDuringOutage = false
    private let clock = ContinuousClock()
    private let confirmation: Duration
    private let timeout: Duration
    private let cooldown: Duration
    private let interval: Duration
    private let active: () -> Bool
    private let canRun: () -> Bool
    private let canInterrupt: (Demand) -> Bool
    private let stillNeeded: (Demand) -> Bool
    private let status: () -> (working: Bool, startedAt: Date?)
    private let check: () -> Void
    private let launch: @MainActor () -> (@MainActor () -> Void)
    private let onFailure: () -> Void

    init(confirmation: Duration = .seconds(8), timeout: Duration = .seconds(25),
         cooldown: Duration = .seconds(60), interval: Duration = .milliseconds(350),
         active: @escaping () -> Bool, canRun: @escaping () -> Bool,
         canInterrupt: @escaping (Demand) -> Bool, stillNeeded: @escaping (Demand) -> Bool,
         status: @escaping () -> (working: Bool, startedAt: Date?),
         check: @escaping () -> Void, launch: @escaping @MainActor () -> (@MainActor () -> Void),
         onFailure: @escaping () -> Void) {
        self.confirmation = confirmation
        self.timeout = timeout
        self.cooldown = cooldown
        self.interval = interval
        self.active = active
        self.canRun = canRun
        self.canInterrupt = canInterrupt
        self.stillNeeded = stillNeeded
        self.status = status
        self.check = check
        self.launch = launch
        self.onFailure = onFailure
    }

    @discardableResult
    func restore(for demand: Demand) async -> Bool {
        guard !Task.isCancelled else { return false }
        let task: Task<Bool, Never>
        if let attempt {
            task = attempt
        } else {
            let signing = demand == .signing || demand == .automaticSigning
            if (!signing || !active()), available(since: Date().addingTimeInterval(-5)) { return true }
            guard active(), stillNeeded(demand), canInterrupt(demand) || status().working,
                  status().working || (canRun() && !attemptedDuringOutage) else { return false }
            task = Task { await recover() }
            attempt = task
        }
        demands.insert(demand)
        let restored = await task.value
        return restored && !Task.isCancelled && active() && available(since: Date().addingTimeInterval(-5))
    }

    func connectionRestored(for demand: Demand? = nil) {
        if let demand {
            guard failedDemands.remove(demand) != nil, failedDemands.isEmpty else { return }
        } else {
            failedDemands.removeAll()
        }
        if attempt == nil { attemptedDuringOutage = false }
        failurePending = false
    }

    func returnedFromShortcut() {
        shortcutReturnedAt = Date()
        check()
    }

    func dismissFailure() { failurePending = false }

    var shortcutNeedsFreshConnection: Bool {
        attempt != nil && demands.contains { $0 != .screenHistory && stillNeeded($0) }
    }

    func checkFreshConnection(within duration: Duration) async -> Bool {
        let requested = Date()
        let deadline = clock.now + duration
        check()
        while status().startedAt.map({ $0 < requested }) ?? true {
            guard !Task.isCancelled, clock.now < deadline else { return false }
            try? await clock.sleep(until: min(deadline, clock.now + interval))
        }
        return available(since: requested)
    }

    private func available(since: Date) -> Bool {
        let result = status()
        return result.working && result.startedAt.map { $0 >= since } == true
    }

    private func recover() async -> Bool {
        defer { demands.removeAll(); attempt = nil }
        let checkedSince = Date()
        let confirmBy = clock.now + confirmation
        check()
        while status().startedAt.map({ $0 < checkedSince }) ?? true {
            guard clock.now < confirmBy, active(), demands.contains(where: stillNeeded) else { return false }
            try? await clock.sleep(until: min(confirmBy, clock.now + interval))
        }
        if available(since: checkedSince) {
            attemptedDuringOutage = false
            connectionRestored()
            return true
        }
        guard active(), canRun(), !attemptedDuringOutage,
              lastLaunch.map({ $0.duration(to: clock.now) >= cooldown }) ?? true,
              let demand = demands.first(where: { stillNeeded($0) && canInterrupt($0) }) else { return false }

        attemptedDuringOutage = true
        lastLaunch = clock.now
        shortcutReturnedAt = nil
        let deadline = clock.now + timeout
        AppLog.shared.add("loopback", "running the Poki Loopback Shortcut for \(demand.rawValue)")
        let endHandoff = launch()
        defer { endHandoff() }
        var nextCheck = clock.now
        repeat {
            let restored = active() && shortcutReturnedAt.map { available(since: $0) } == true
            if restored || !demands.contains(where: stillNeeded) {
                attemptedDuringOutage = false
                if restored { connectionRestored() }
                AppLog.shared.add("loopback", "recovery finished with no work waiting for loopback")
                return restored
            }
            guard clock.now < deadline else { break }
            if clock.now >= nextCheck {
                check()
                nextCheck = clock.now + .seconds(1)
            }
            try? await clock.sleep(until: min(deadline, clock.now + interval))
        } while true

        failedDemands = demands.filter(stillNeeded)
        failurePending = true
        AppLog.shared.add("loopback", "the Poki Loopback Shortcut did not restore the connection in time")
        onFailure()
        return false
    }
}
