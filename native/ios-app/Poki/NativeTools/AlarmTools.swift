import AlarmKit
import Foundation
import SwiftUI
import PokiCore

/// Schedules a system alarm with AlarmKit (iOS 26+). "HH:mm" is the next local occurrence; a repeating
/// alarm is only made when the owner asks for one. The answer names the actual scheduled time and id.
enum AlarmTools {
    static let specs: [ToolSpec] = [
        .make("alarm_set",
              "Set a system alarm with AlarmKit (iOS 26 or later). time is HH:mm in local time and means the next occurrence; label is shown on the alarm. repeat creates a daily alarm, or a weekly one for the given days. Returns the scheduled time. Permission is requested on the first alarm.",
              [
                "time": ["type": "string", "description": "HH:mm in local time."],
                "label": ["type": "string"],
                "repeat": ["type": "boolean"],
                "days": ["type": "array", "items": ["type": "string", "enum": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]]],
                "request_id": ["type": "string"],
              ], ["time"]),
    ]

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        guard #available(iOS 26.0, *) else {
            return NativeToolAnswer.unavailable("system alarms need iOS 26 or later; this iPhone is on an earlier version. Nothing was scheduled.")
        }
        let args = ToolArgs(arguments)
        let raw = args.string("time") ?? ""
        guard let next = NativeDate.next(hhmm: raw) else {
            return NativeToolAnswer.invalid("time must be HH:mm in local time; nothing was scheduled")
        }
        if let requestID = args.string("request_id"), let previous = WriteLedger.completed(requestID) {
            return NativeToolAnswer.ok("already scheduled: \(previous) (request_id \(requestID)); no second alarm was set.")
        }
        let label = args.string("label") ?? "Alarm"
        let repeats = args.bool("repeat") == true
        let days = Self.weekdays(args.values["days"] as? [String])
        do {
            let manager = AlarmManager.shared
            var state = manager.authorizationState
            if state == .notDetermined {
                state = try await manager.requestAuthorization()
            }
            guard state == .authorized else {
                return NativeToolAnswer.permission("alarm access is not allowed. Allow alarms for Poki in Settings › Privacy & Security › Alarms, then try again. Nothing was scheduled.")
            }
            let time = Alarm.Schedule.Relative.Time(hour: NativeDate.local.component(.hour, from: next), minute: NativeDate.local.component(.minute, from: next))
            let schedule: Alarm.Schedule
            if repeats {
                let recurrence: Alarm.Schedule.Relative.Recurrence = days.isEmpty ? .weekly(Self.allWeekdays) : .weekly(days)
                schedule = .relative(.init(time: time, repeats: recurrence))
            } else {
                schedule = .fixed(next)
            }
            let presentation = AlarmPresentation(alert: .init(
                title: LocalizedStringResource("\(label)"),
                stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
            ))
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: NativeAlarmMetadata(label: label),
                tintColor: .orange
            )
            let alarm = try await manager.schedule(
                id: UUID(),
                configuration: .alarm(schedule: schedule, attributes: attributes)
            )
            let repeatText: String
            if repeats {
                repeatText = days.isEmpty ? "every day" : days.map(Self.weekdayName).joined(separator: ", ")
            } else {
                repeatText = "once"
            }
            let text = "scheduled alarm: \(label)\nat: \(NativeDate.display(next)) (\(NativeDate.local.timeZone.identifier))\nrepeat: \(repeatText)\nid: \(alarm.id.uuidString)"
            if let requestID = args.string("request_id") {
                WriteLedger.record(requestID, value: text)
            }
            return NativeToolAnswer.ok(text)
        } catch {
            return NativeToolAnswer.failed("AlarmKit could not schedule the alarm: \(error.localizedDescription). Nothing was scheduled.")
        }
    }

    private static var allWeekdays: [Locale.Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    private static func weekdays(_ names: [String]?) -> [Locale.Weekday] {
        guard let names else { return [] }
        let map: [String: Locale.Weekday] = [
            "monday": .monday, "tuesday": .tuesday, "wednesday": .wednesday,
            "thursday": .thursday, "friday": .friday, "saturday": .saturday, "sunday": .sunday,
        ]
        return names.compactMap { map[$0.lowercased()] }
    }

    private static func weekdayName(_ day: Locale.Weekday) -> String {
        switch day {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        @unknown default: return "a day"
        }
    }
}

@available(iOS 26.0, *)
struct NativeAlarmMetadata: AlarmMetadata {
    var label: String
}
