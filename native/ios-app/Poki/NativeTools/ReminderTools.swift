import EventKit
import Foundation
import PokiCore

/// Adds a reminder with EventKit and, when it should alert at the due time, an EKAlarm. The reminder
/// is read back with its due components before it is reported; request_id keeps a retry idempotent.
enum ReminderTools {
    static let specs: [ToolSpec] = [
        .make("reminder_create",
              "Add a reminder to the owner's Reminders. title and due (ISO 8601 or yyyy-MM-dd HH:mm) are required; a date without a time is due at 09:00. list and notes are optional. alarm adds an alert at the due time (default true).",
              [
                "title": ["type": "string"],
                "due": ["type": "string", "description": "ISO 8601 or yyyy-MM-dd HH:mm in local time."],
                "list": ["type": "string", "description": "A Reminders list name from reminder lists."],
                "notes": ["type": "string"],
                "alarm": ["type": "boolean"],
                "request_id": ["type": "string"],
              ], ["title", "due"]),
        .make("reminder_lists",
              "List the owner's writable Reminders lists, with their names.",
              [:], []),
    ]

    static let listSpecs = specs

    @MainActor private static let store = EKEventStore()

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let title = args.string("title") else {
            return NativeToolAnswer.invalid("title is required; nothing was created")
        }
        guard var due = args.date("due") else {
            return NativeToolAnswer.invalid("due must be an ISO 8601 date or yyyy-MM-dd HH:mm; nothing was created")
        }
        let dueText = args.string("due") ?? ""
        if !dueText.contains(":") {
            // A date alone: due at 09:00 local, not the current time.
            let day = NativeDate.day(containing: due).0
            due = NativeDate.local.date(byAdding: .hour, value: 9, to: day) ?? due
        }
        if let requestID = args.string("request_id"), let previous = WriteLedger.completed(requestID) {
            return NativeToolAnswer.ok("already created: \(previous) (request_id \(requestID)); no second reminder was added.")
        }
        guard await access(readOnly: false) == true else {
            return NativeToolAnswer.permission("Reminders access is not allowed. Open Settings › Privacy & Security › Reminders and allow Poki. Nothing was created.")
        }
        let calendar: EKCalendar
        if let name = args.string("list") {
            let matches = store.calendars(for: .reminder).filter {
                $0.allowsContentModifications && $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if matches.count > 1 {
                return NativeToolAnswer.ambiguous("more than one Reminders list is named “\(name)”: \(matches.map(\.title).joined(separator: ", ")). Ask the owner which one; nothing was created.")
            }
            guard let only = matches.first else {
                let available = store.calendars(for: .reminder).filter(\.allowsContentModifications).map(\.title)
                return NativeToolAnswer.empty("no writable Reminders list named “\(name)”. Lists: \(available.joined(separator: ", ")); nothing was created.")
            }
            calendar = only
        } else {
            guard let fallback = store.defaultCalendarForNewReminders(), fallback.allowsContentModifications else {
                return NativeToolAnswer.empty("there is no default Reminders list; name one with list. Nothing was created.")
            }
            calendar = fallback
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = args.string("notes")
        var components = NativeDate.local.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        components.timeZone = NativeDate.local.timeZone
        reminder.dueDateComponents = components
        if args.bool("alarm") ?? true {
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return NativeToolAnswer.failed("EventKit could not save the reminder: \(error.localizedDescription). Nothing was created.")
        }
        guard let identifier = reminder.calendarItemIdentifier as String?,
              let saved = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return NativeToolAnswer.failed("the reminder was saved but could not be read back; check Reminders before trying again.")
        }
        let text = "created reminder: \(saved.title ?? title)\ndue: \(NativeDate.display(due)) (\(NativeDate.local.timeZone.identifier))\nlist: \(saved.calendar.title)\nalarm: \((args.bool("alarm") ?? true) ? "at the due time" : "none")\nid: \(identifier)"
        if let requestID = args.string("request_id") {
            WriteLedger.record(requestID, value: text)
        }
        return NativeToolAnswer.ok(text)
    }

    @MainActor static func lists(_ arguments: String) async -> PokiCore.ToolAnswer {
        guard await access(readOnly: true) == true else {
            return NativeToolAnswer.permission("Reminders read access is not allowed. Open Settings › Privacy & Security › Reminders and allow Poki full access. Nothing was read.")
        }
        let names = store.calendars(for: .reminder).filter(\.allowsContentModifications).map(\.title).sorted()
        guard !names.isEmpty else { return NativeToolAnswer.empty("there are no writable Reminders lists.") }
        return NativeToolAnswer.ok("reminder lists: " + names.joined(separator: ", "))
    }

    @MainActor private static func access(readOnly: Bool) async -> Bool? {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .writeOnly: return readOnly ? false : true
        case .denied, .restricted: return false
        case .notDetermined:
            do { return try await store.requestFullAccessToReminders() } catch { return nil }
        @unknown default:
            return nil
        }
    }
}
