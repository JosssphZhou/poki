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

    static func install(app: AppModel, chat: ChatModel) {
        _ = chat
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
        await dispatch(name, arguments: arguments, session: session)
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
}
