import Foundation
import PokiCore

/// The iPhone's own abilities, exposed to the chat and to MCP clients as ordinary tools: steps and
/// health, calendar and reminders, HomeKit, contacts, Bluetooth, the clipboard, reading a page aloud,
/// alarms, the battery, the photo library, and location, maps and weather.
///
/// The specs are the single source for both catalogs: `Harness.toolSpecs` declares them to the chat's
/// model, and `hostTools()` projects the same spec into PokiCore's `tools/list`, so an outside MCP
/// client and Poki's own agent call one implementation. They do not touch the phone's screen and
/// therefore never wait for Automation Mode.
@MainActor
enum NativeTools {
    nonisolated static let specs: [ToolSpec] =
        HealthTools.specs + CalendarTools.specs + ReminderTools.specs + HomeTools.specs +
        ContactTools.specs + BluetoothTools.specs + ClipboardTools.specs + SpeechTools.specs +
        AlarmTools.specs + BatteryTools.specs + PhotoTools.specs + PlaceTools.specs

    nonisolated static var names: Set<String> { Set(specs.map(\.name)) }

    /// How the model should reach for these tools, appended to the task instructions. Native calls do
    /// not need Automation Mode and never act on the screen.
    nonisolated static let instructions = """
    The iPhone's own abilities are tools too: health_steps, calendar_events and calendar_create_event, reminder_create and reminder_lists, home_set_light, contacts_find, bluetooth_scan, clipboard_read, read_aloud, alarm_set, battery_status, photos_find/export/save/add_to_album/albums, location_current, maps_geocode/maps_search/maps_route, and weather_forecast. Use them directly for the owner's requests about these things; they do not need Automation Mode and never touch the screen. Ask the owner before acting when a tool reports ambiguous; do not guess between matches. A read-only request should answer with the values the tool returned, not with values from memory. Weather answers include Apple Weather attribution; keep it in the reply.
    """

    private(set) static weak var app: AppModel?
    private(set) static weak var chat: ChatModel?

    static func install(app: AppModel, chat: ChatModel) {
        self.app = app
        self.chat = chat
        app.refreshHostTools()
    }

    /// The MCP projection of the same specs. PokiCore drops names it owns (look, do and so on); every
    /// native name is distinct from those.
    nonisolated static func hostTools() -> [HostTool] {
        specs.compactMap { spec in
            guard let data = try? JSONSerialization.data(withJSONObject: spec.schema),
                  let schema = String(data: data, encoding: .utf8) else { return nil }
            return HostTool(name: spec.name, description: spec.description, schemaJSON: schema) { arguments, session, _ in
                await NativeTools.perform(spec.name, arguments: arguments, session: session)
            }
        }
    }

    static func perform(_ name: String, arguments: String, session: String? = nil) async -> PokiCore.ToolAnswer {
        let answer = await dispatch(name, arguments: arguments, session: session)
        // A native call runs inside the same ordinary task as a phone step: the Live Activity counts it
        // and says what it is doing, including a task that never opened Automation Mode.
        app?.nativeToolStep(summary: stepSummary(name, arguments: arguments), ok: !answer.isError, session: session)
        return answer
    }

    private static func dispatch(_ name: String, arguments: String, session: String?) async -> PokiCore.ToolAnswer {
        switch name {
        case "health_steps": return await HealthTools.perform(arguments)
        case "calendar_events": return await CalendarTools.events(arguments)
        case "calendar_create_event": return await CalendarTools.createEvent(arguments)
        case "reminder_create": return await ReminderTools.perform(arguments)
        case "reminder_lists": return await ReminderTools.lists(arguments)
        case "home_set_light": return await HomeTools.perform(arguments)
        case "contacts_find": return await ContactTools.perform(arguments)
        case "bluetooth_scan": return await BluetoothTools.perform(arguments)
        case "clipboard_read": return await ClipboardTools.perform(arguments)
        case "read_aloud": return await SpeechTools.perform(arguments)
        case "alarm_set": return await AlarmTools.perform(arguments)
        case "battery_status": return await BatteryTools.perform(arguments)
        case "photos_find": return await PhotoTools.find(arguments)
        case "photos_export": return await PhotoTools.export(arguments)
        case "photos_save": return await PhotoTools.save(arguments)
        case "photos_add_to_album": return await PhotoTools.addToAlbum(arguments)
        case "photos_albums": return await PhotoTools.albums(arguments)
        case "location_current": return await PlaceTools.current(arguments)
        case "maps_geocode": return await PlaceTools.geocode(arguments)
        case "maps_search": return await PlaceTools.search(arguments)
        case "maps_route": return await PlaceTools.route(arguments)
        case "weather_forecast": return await PlaceTools.weather(arguments)
        default:
            return NativeToolAnswer.invalid("unknown native tool \(name); nothing was done")
        }
    }

    /// The Live Activity's one-line description of a native call, in the app's UI language.
    static func stepSummary(_ name: String, arguments: String) -> String {
        let args = ToolArgs(arguments)
        switch name {
        case "health_steps":
            let range = args.string("range") ?? (args.date("start") == nil ? "week" : "range")
            switch range {
            case "today": return AppLocalization.text(LocalizedStringResource("Reading today's steps"))
            case "week": return AppLocalization.text(LocalizedStringResource("Reading this week's steps"))
            default: return AppLocalization.text(LocalizedStringResource("Reading steps"))
            }
        case "calendar_events": return AppLocalization.text(LocalizedStringResource("Reading the calendar"))
        case "calendar_create_event": return AppLocalization.text(LocalizedStringResource("Adding a calendar event"))
        case "reminder_create": return AppLocalization.text(LocalizedStringResource("Adding a reminder"))
        case "home_set_light": return AppLocalization.text(LocalizedStringResource("Setting a light"))
        case "contacts_find": return AppLocalization.text(LocalizedStringResource("Looking up a contact"))
        case "bluetooth_scan": return AppLocalization.text(LocalizedStringResource("Scanning for Bluetooth devices"))
        case "clipboard_read": return AppLocalization.text(LocalizedStringResource("Reading the clipboard"))
        case "read_aloud": return AppLocalization.text(LocalizedStringResource("Reading it aloud"))
        case "alarm_set": return AppLocalization.text(LocalizedStringResource("Setting an alarm"))
        case "battery_status": return AppLocalization.text(LocalizedStringResource("Reading the battery"))
        case "photos_find": return AppLocalization.text(LocalizedStringResource("Looking through the photo library"))
        case "photos_export": return AppLocalization.text(LocalizedStringResource("Exporting photos"))
        case "photos_save": return AppLocalization.text(LocalizedStringResource("Saving to the photo library"))
        case "photos_add_to_album": return AppLocalization.text(LocalizedStringResource("Adding photos to an album"))
        case "photos_albums": return AppLocalization.text(LocalizedStringResource("Listing photo albums"))
        case "location_current": return AppLocalization.text(LocalizedStringResource("Finding this iPhone"))
        case "maps_geocode": return AppLocalization.text(LocalizedStringResource("Looking up an address"))
        case "maps_search": return AppLocalization.text(LocalizedStringResource("Searching nearby places"))
        case "maps_route": return AppLocalization.text(LocalizedStringResource("Planning a route"))
        case "weather_forecast": return AppLocalization.text(LocalizedStringResource("Reading the forecast"))
        default: return AppLocalization.text(LocalizedStringResource("Using this iPhone"))
        }
    }
}
