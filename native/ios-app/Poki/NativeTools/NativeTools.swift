import Foundation
import PokiCore

/// The iPhone's own abilities, exposed to the chat and to MCP clients as ordinary tools: the battery,
/// the clipboard, and reading a page aloud.
///
/// The specs are the single source for both catalogs: `Harness.toolSpecs` declares them to the chat's
/// model, and `hostTools()` projects the same spec into PokiCore's `tools/list`, so an outside MCP
/// client and Poki's own agent call one implementation. They do not touch the phone's screen and
/// therefore never wait for Automation Mode.
@MainActor
enum NativeTools {
    nonisolated static let specs: [ToolSpec] =
        BatteryTools.specs + ClipboardTools.specs + SpeechTools.specs

    nonisolated static var names: Set<String> { Set(specs.map(\.name)) }

    /// How the model should reach for these tools, appended to the task instructions. Native calls do
    /// not need Automation Mode and never act on the screen.
    nonisolated static let instructions = """
    The iPhone's own abilities are tools too: battery_status, clipboard_read and read_aloud. Use them directly for the owner's requests about these things; they do not need Automation Mode and never touch the screen. A read-only request should answer with the values the tool returned, not with values from memory.
    """

    static func install(app: AppModel) {
        app.refreshHostTools()
    }

    /// The MCP projection of the same specs. PokiCore drops names it owns (look, do and so on); every
    /// native name is distinct from those.
    nonisolated static func hostTools() -> [HostTool] {
        specs.compactMap { spec in
            guard let data = try? JSONSerialization.data(withJSONObject: spec.schema),
                  let schema = String(data: data, encoding: .utf8) else { return nil }
            let name = spec.name
            return HostTool(name: name, description: spec.description, schemaJSON: schema) { arguments, _, _ in
                await NativeTools.perform(name, arguments: arguments)
            }
        }
    }

    static func perform(_ name: String, arguments: String) async -> PokiCore.ToolAnswer {
        await dispatch(name, arguments: arguments)
    }

    private static func dispatch(_ name: String, arguments: String) async -> PokiCore.ToolAnswer {
        switch name {
        case "battery_status": return await BatteryTools.perform(arguments)
        case "clipboard_read": return await ClipboardTools.perform(arguments)
        case "read_aloud": return await SpeechTools.perform(arguments)
        default:
            return NativeToolAnswer.invalid("unknown native tool \(name); nothing was done")
        }
    }
}
