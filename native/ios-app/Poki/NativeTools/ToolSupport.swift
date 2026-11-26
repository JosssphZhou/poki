import Foundation
import PokiCore

/// Parsed tool arguments and the small pieces of validation every native tool shares.
struct ToolArgs {
    let values: [String: Any]

    init(_ text: String) {
        values = (text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
    }

    func string(_ key: String) -> String? {
        (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func double(_ key: String) -> Double? {
        if let value = values[key] as? Double { return value }
        if let value = values[key] as? Int { return Double(value) }
        if let value = values[key] as? String { return Double(value) }
        return nil
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension ToolSpec {
    /// A spec whose schema is an object with the given properties and required names.
    static func make(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String]) -> ToolSpec {
        ToolSpec(name: name, description: description, schema: [
            "type": "object", "properties": properties, "required": required, "additionalProperties": false,
        ])
    }
}

/// The answer vocabulary shared by the native tools, so a refused or failed call reads the same in
/// chat and over MCP.
enum NativeToolAnswer {
    static func ok(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: text, jpeg: nil, isError: false)
    }

    static func empty(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "empty: \(text)", jpeg: nil, isError: false)
    }

    static func ambiguous(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "ambiguous: \(text)", jpeg: nil, isError: false)
    }

    static func unavailable(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "unavailable: \(text)", jpeg: nil, isError: true)
    }

    static func failed(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "failed: \(text)", jpeg: nil, isError: true)
    }

    static func invalid(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "invalid: \(text)", jpeg: nil, isError: true)
    }
}
