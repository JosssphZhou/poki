import Foundation

/// Switches to Poki's keyboard that failed, per app: for ten minutes after one failed, Poki does not
/// switch keyboards in that app again (each try holds the globe key and reads the screen twice).
struct KeyboardSwitchMemory {
    /// The answer of a switch when no keyboard is on screen at all: no text field has the focus yet.
    static let noKeyboardOnScreen = "no keyboard with a globe key is on screen (no text field has the focus, or the field takes only its own keyboard)"
    static let holdBack: TimeInterval = 600

    private var failed: [String: Date] = [:]

    /// Nothing is remembered for an app that is not named: under one empty name, a failure in one
    /// app would hold back every other.
    func failedLately(in app: String?, at now: Date) -> Bool {
        guard let app, let at = failed[app] else { return false }
        return now.timeIntervalSince(at) < Self.holdBack
    }

    /// `why` is nil when the switch worked. No keyboard on screen is a field without the focus yet,
    /// not a switch that failed.
    mutating func note(in app: String?, why: String?, at now: Date) {
        guard let app, why != Self.noKeyboardOnScreen else { return }
        failed[app] = why == nil ? nil : now
    }
}
