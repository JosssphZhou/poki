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

    func int(_ key: String) -> Int? {
        if let value = values[key] as? Int { return value }
        if let value = values[key] as? Double { return Int(value) }
        if let value = values[key] as? String { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = values[key] as? Double { return value }
        if let value = values[key] as? Int { return Double(value) }
        if let value = values[key] as? String { return Double(value) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = values[key] as? Bool { return value }
        if let value = values[key] as? String {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    func date(_ key: String) -> Date? { NativeDate.parse(string(key)) }

    func array(_ key: String) -> [[String: Any]]? { values[key] as? [[String: Any]] }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum NativeDate {
    static let local: Calendar = {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static func parse(_ text: String?) -> Date? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasSuffix("Z") || text.contains("+") || text.range(of: #"T\d{2}:\d{2}.*[-]\d{2}:\d{2}"#, options: .regularExpression) != nil {
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: text) { return date }
            precise.formatOptions = [.withInternetDateTime]
            if let date = precise.date(from: text) { return date }
        }
        let patterns = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "HH:mm"]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = local
            formatter.timeZone = local.timeZone
            formatter.dateFormat = pattern
            if pattern == "HH:mm" {
                if let time = formatter.date(from: text) {
                    let parts = local.dateComponents([.hour, .minute], from: time)
                    guard let hour = parts.hour, let minute = parts.minute else { continue }
                    var day = local.dateComponents([.year, .month, .day], from: Date())
                    day.hour = hour
                    day.minute = minute
                    day.second = 0
                    return local.date(from: day)
                }
            } else if let date = formatter.date(from: text) {
                return date
            }
            if text.hasSuffix("Z") {
                text.removeLast()
            }
        }
        return nil
    }

    /// A local day's start and the start of the next day, from a date or today.
    static func day(containing date: Date) -> (Date, Date) {
        let start = local.startOfDay(for: date)
        return (start, local.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    /// This week's start (the calendar's own first weekday and time zone) and now.
    static func week(containing date: Date = Date()) -> (Date, Date) {
        if let interval = local.dateInterval(of: .weekOfYear, for: date) { return (interval.start, interval.end) }
        let start = local.startOfDay(for: date)
        return (start, start.addingTimeInterval(86_400 * 7))
    }

    static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = local
        formatter.timeZone = local.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = local
        formatter.timeZone = local.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "HH:mm" in the local time zone, parsed as the next occurrence (or a date when given).
    static func next(hour: Int, minute: Int, after now: Date = Date()) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var parts = local.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        guard let candidate = local.date(from: parts) else { return nil }
        if candidate > now { return candidate }
        return local.date(byAdding: .day, value: 1, to: candidate)
    }

    static func next(hhmm: String, after now: Date = Date()) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return next(hour: parts[0], minute: parts[1], after: now)
    }
}

extension ToolSpec {
    static func object(_ properties: [String: Any], _ required: [String]) -> ToolSpec {
        ToolSpec(name: "", description: "", schema: [
            "type": "object", "properties": properties, "required": required, "additionalProperties": false,
        ])
    }

    /// A spec whose schema is `object(properties, required)`; callers set the name and description.
    static func make(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String]) -> ToolSpec {
        ToolSpec(name: name, description: description, schema: [
            "type": "object", "properties": properties, "required": required, "additionalProperties": false,
        ])
    }
}

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

    static func permission(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "permission: \(text)", jpeg: nil, isError: true)
    }

    static func unavailable(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "unavailable: \(text)", jpeg: nil, isError: true)
    }

    static func timeout(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "timeout: \(text)", jpeg: nil, isError: true)
    }

    static func failed(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "failed: \(text)", jpeg: nil, isError: true)
    }

    static func invalid(_ text: String) -> PokiCore.ToolAnswer {
        PokiCore.ToolAnswer(text: "invalid: \(text)", jpeg: nil, isError: true)
    }
}

/// Request ids make a retried write a no-op instead of a second event, reminder, alarm or photo.
enum WriteLedger {
    private static let key = "nativeWriteLedger"
    private static let cap = 200

    static func completed(_ requestID: String) -> String? {
        guard !requestID.isEmpty else { return nil }
        return UserDefaults.standard.dictionary(forKey: key)?[requestID] as? String
    }

    static func record(_ requestID: String, value: String) {
        guard !requestID.isEmpty else { return }
        var ledger = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        ledger[requestID] = value
        if ledger.count > cap {
            let survivors = ledger.sorted { $0.value < $1.value }.suffix(cap)
            ledger = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(ledger, forKey: key)
    }
}

/// Matches the owner's words against a list of names, keeping the candidates when more than one fits.
enum NameChoice {
    static func matches(_ names: [String], query: String) -> [Int] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        let exact = names.indices.filter { names[$0].lowercased() == query }
        if !exact.isEmpty { return exact }
        return names.indices.filter { names[$0].lowercased().contains(query) }
    }
}

/// The app-private files the native tools produce and accept. Every model-supplied path is resolved
/// against these roots; a path outside them, or one that reaches outside through a symlink, is refused.
enum NativeWorkspace {
    static var base: URL { AppFiles.support }
    static var photoExports: URL { base.appendingPathComponent("PhotoExports", isDirectory: true) }
    static var sharedImports: URL { base.appendingPathComponent("SharedImports", isDirectory: true) }

    static func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    static func safeName(_ original: String, fallback: String) -> String {
        let name = (original as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-()[]"))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = cleaned.isEmpty ? fallback : cleaned
        return candidate.count > 180 ? String(candidate.suffix(180)) : candidate
    }

    static func newDirectory(in root: URL, prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "\(prefix)-\(UUID().uuidString.lowercased())"
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
