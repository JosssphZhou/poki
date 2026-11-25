import EventKit
import Foundation
import PokiCore

/// Reading the owner's calendars and adding an event with EventKit. Dates keep their time zone when
/// they have one; an all-day event uses local day boundaries. A created event is read back before it
/// is reported, and an optional request_id makes a retried write return the first event instead of a
/// second one.
enum CalendarTools {
    static let specs: [ToolSpec] = [
        .make("calendar_events",
              "Read the owner's calendar events. Omit date for today; date accepts today, tomorrow or yyyy-MM-dd. start/end accept ISO 8601 or yyyy-MM-dd HH:mm. All-day events, start and end times, titles and calendar names are kept.",
              [
                "date": ["type": "string", "description": "today, tomorrow, or yyyy-MM-dd."],
                "start": ["type": "string"],
                "end": ["type": "string"],
                "days": ["type": "integer", "minimum": 1, "maximum": 31],
              ], []),
        .make("calendar_create_event",
              "Add an event to the owner's calendar. title, start and end (or duration_minutes) are required. all_day uses local day boundaries. location, notes and calendar are optional; calendar is a name from calendar_events. The event is saved and read back.",
              [
                "title": ["type": "string"],
                "start": ["type": "string", "description": "ISO 8601 or yyyy-MM-dd HH:mm in local time."],
                "end": ["type": "string"],
                "duration_minutes": ["type": "integer", "minimum": 1, "maximum": 1440],
                "all_day": ["type": "boolean"],
                "location": ["type": "string"],
                "notes": ["type": "string"],
                "calendar": ["type": "string"],
                "request_id": ["type": "string", "description": "A stable id for this requested write; a retry with the same id does not create a second event."],
              ], ["title", "start"]),
    ]

    @MainActor private static let store = EKEventStore()

    @MainActor static func events(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let start: Date
        let end: Date
        if let explicitStart = args.date("start") {
            start = explicitStart
            end = args.date("end") ?? NativeDate.day(containing: explicitStart).1
        } else {
            let day: Date
            switch (args.string("date") ?? "today").lowercased() {
            case "tomorrow": day = NativeDate.day(containing: Date()).1
            case "today": day = Date()
            default: day = args.date("date") ?? Date()
            }
            let first = NativeDate.day(containing: day).0
            start = first
            let days = max(1, args.int("days") ?? 1)
            end = NativeDate.local.date(byAdding: .day, value: days, to: first) ?? first.addingTimeInterval(Double(days) * 86_400)
        }
        guard end > start else { return NativeToolAnswer.invalid("end must be after start; nothing was read") }
        guard let granted = await access(readOnly: true) else {
            return NativeToolAnswer.permission("Calendar access is not allowed. Open Settings › Privacy & Security › Calendars and allow Poki full access. Nothing was read.")
        }
        guard granted else { return NativeToolAnswer.permission("Calendar access was not granted. Nothing was read.") }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !found.isEmpty else {
            return NativeToolAnswer.empty("no events between \(NativeDate.display(start)) and \(NativeDate.display(end)).")
        }
        let lines = found.prefix(100).map { event -> String in
            let title = event.title?.nilIfEmpty ?? "(untitled event)"
            let calendar = event.calendar?.title ?? "unknown calendar"
            let when: String
            if event.isAllDay {
                when = "all day \(NativeDate.display(event.startDate).prefix(10))"
            } else {
                let zone = event.timeZone?.identifier ?? NativeDate.local.timeZone.identifier
                when = "\(NativeDate.display(event.startDate)) – \(NativeDate.display(event.endDate)) (\(zone))"
            }
            let place = event.location?.nilIfEmpty.map { " @ \($0)" } ?? ""
            return "- \(title) — \(when) — \(calendar)\(place)"
        }
        var text = "events: \(found.count)\n" + lines.joined(separator: "\n")
        if found.count > 100 { text += "\n(only the first 100 are listed)" }
        return NativeToolAnswer.ok(text)
    }

    @MainActor static func createEvent(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let title = args.string("title") else {
            return NativeToolAnswer.invalid("title is required; nothing was created")
        }
        guard let start = args.date("start") else {
            return NativeToolAnswer.invalid("start must be an ISO 8601 date or yyyy-MM-dd HH:mm; nothing was created")
        }
        let allDay = args.bool("all_day") == true
        let end: Date
        if allDay {
            end = NativeDate.day(containing: start).1
        } else if let explicit = args.date("end") {
            end = explicit
        } else if let minutes = args.int("duration_minutes") {
            end = start.addingTimeInterval(Double(minutes) * 60)
        } else {
            end = start.addingTimeInterval(3_600)
        }
        guard end > start else {
            return NativeToolAnswer.invalid("the end must be later than the start; nothing was created")
        }
        if let requestID = args.string("request_id"), let previous = WriteLedger.completed(requestID) {
            return NativeToolAnswer.ok("already created: \(previous) (request_id \(requestID)); no second event was added.")
        }
        guard await access(readOnly: false) == true else {
            return NativeToolAnswer.permission("Calendar write access is not allowed. Open Settings › Privacy & Security › Calendars and allow Poki. Nothing was created.")
        }
        let calendar: EKCalendar
        if let name = args.string("calendar") {
            let matches = store.calendars(for: .event).filter {
                $0.allowsContentModifications && $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if matches.count > 1 {
                return NativeToolAnswer.ambiguous("more than one writable calendar is named “\(name)”: \(matches.map(\.title).joined(separator: ", ")). Ask the owner which one to use; nothing was created.")
            }
            guard let only = matches.first else {
                let available = store.calendars(for: .event).filter(\.allowsContentModifications).map(\.title)
                return NativeToolAnswer.empty("no writable calendar named “\(name)”. Writable calendars: \(available.joined(separator: ", ")); nothing was created.")
            }
            calendar = only
        } else {
            guard let fallback = store.defaultCalendarForNewEvents, fallback.allowsContentModifications else {
                return NativeToolAnswer.empty("there is no default calendar to add to; name one with calendar. Nothing was created.")
            }
            calendar = fallback
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.location = args.string("location")
        event.notes = args.string("notes")
        if !allDay { event.timeZone = NativeDate.local.timeZone }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return NativeToolAnswer.failed("EventKit could not save the event: \(error.localizedDescription). Nothing was created.")
        }
        guard let identifier = event.eventIdentifier, let saved = store.event(withIdentifier: identifier) else {
            return NativeToolAnswer.failed("the event was saved but could not be read back; check the Calendar app before trying again.")
        }
        let when = saved.isAllDay
            ? "all day \(NativeDate.display(saved.startDate).prefix(10))"
            : "\(NativeDate.display(saved.startDate)) – \(NativeDate.display(saved.endDate)) (\(saved.timeZone?.identifier ?? NativeDate.local.timeZone.identifier))"
        let place = saved.location?.nilIfEmpty.map { " @ \($0)" } ?? ""
        let text = "created: \(saved.title ?? title)\nwhen: \(when)\ncalendar: \(saved.calendar.title)\(place)\nid: \(identifier)"
        if let requestID = args.string("request_id") {
            WriteLedger.record(requestID, value: text)
        }
        return NativeToolAnswer.ok(text)
    }

    /// True when full event access is allowed; nil when it could not be requested (for example from
    /// the background), false when it is denied.
    @MainActor private static func access(readOnly: Bool) async -> Bool? {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .writeOnly: return readOnly ? false : true
        case .denied, .restricted: return false
        case .notDetermined:
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return nil
            }
        @unknown default:
            return nil
        }
    }
}
