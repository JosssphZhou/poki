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
        guard let app = Self.named(app), let at = failed[app] else { return false }
        return now.timeIntervalSince(at) < Self.holdBack
    }

    /// `why` is nil when the switch worked. No keyboard on screen is a field without the focus yet,
    /// not a switch that failed.
    mutating func note(in app: String?, why: String?, at now: Date) {
        guard let app = Self.named(app), why != Self.noKeyboardOnScreen else { return }
        failed[app] = why == nil ? nil : now
    }

    private static func named(_ app: String?) -> String? {
        guard let app = app?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else { return nil }
        return app
    }

    /// Why the globe key's list gave no row for `name`, told apart by what the last read held. The
    /// list counts as open when a new row in it is ticked (the keyboard in use); only then are its
    /// rows quoted, and only then is a list without Poki taken to mean Poki's keyboard is not turned
    /// on, with the place the owner turns it on.
    static func listMissed(_ name: String, rows: [String], open: Bool, skipped: String?, after ms: Int, poki: Bool) -> String {
        if let skipped {
            return "the globe key's list did not show \(name) where it was looked for: a row \"\(skipped.prefix(40))\" was in the list, but the same label was on screen before the globe key was held"
        }
        guard open else {
            return rows.isEmpty
                ? "the globe key's list did not show \(name): nothing new came up within \(ms) ms of holding the globe key (the list opened late, or not at all)"
                : "the globe key's list did not show \(name): \(rows.count) new items came up within \(ms) ms of holding the globe key, but none was ticked, so they were not taken for the list"
        }
        let quoted = rows.prefix(8).map { "\"\($0.prefix(40))\"" }.joined(separator: ", ")
        guard poki else { return "the globe key's list shows \(quoted) and not \(name)" }
        return "the globe key's list shows \(quoted) and not \(name), so the Poki keyboard is not turned on. The owner turns it on under Settings › General › Keyboard › Keyboards › Add New Keyboard › Poki, then taps Poki there and turns on Allow Full Access"
    }
}
