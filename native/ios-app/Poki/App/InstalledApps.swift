import Foundation

/// The apps on this iPhone and their bundle ids, for the chat's agent (`find_app`). A model that
/// recalls a bundle id guesses: a tester's 淘宝 and 美团 tasks (Nov 13 2026) were refused as "no app
/// with that bundle id is installed" and the agent told the owner to install apps they had.
///
/// Sources, most reliable first: the phone's own list from installation_proxy (the signer's `apps`
/// request over the loopback, the lookup Poki Runner used), the names Poki knows (KnownApps), and
/// the App Store's public search as the backup, which also gives the link of an app that is not
/// installed. Without the phone's list, an id counts as installed when iOS has its icon.
@MainActor
final class InstalledApps {
    static let shared = InstalledApps()

    struct App: Equatable, Decodable {
        var id: String
        var name: String?
        var bundleName: String?
        enum CodingKeys: String, CodingKey { case id, name, bundleName = "bundle_name" }
    }

    /// The signer's way to the phone (AppModel sets it with the signer's): nil while the loopback is down.
    var phone: () -> [String: Any]? = { nil }
    /// Reads the list over that way: the signer's `apps` request.
    var fetch: ([String: Any]) async throws -> [App] = { phone in
        var request = phone
        request["op"] = "apps"
        struct Answer: Decodable { let apps: [App] }
        return try await SignerBridge.decode(Answer.self, request).apps
    }
    /// Whether iOS has an icon for an id: the check when the phone's list cannot be read.
    var hasIcon: @MainActor (String) -> Bool? = { AppIconStore.installedOnPhone($0) }
    /// The App Store's search (tests answer it themselves).
    var search: (String) async -> [StoreApp] = { await AppStoreSearch.apps($0) }

    private(set) var apps: [App]?
    private var fetchedAt: Date?
    private(set) var lastProblem: String?
    private static let maxAge: TimeInterval = 300

    /// The phone's list, read again after five minutes; nil when it cannot be read.
    func list() async -> [App]? {
        if let apps, let at = fetchedAt, Date().timeIntervalSince(at) < Self.maxAge { return apps }
        guard let request = phone() else { lastProblem = "the loopback to the phone is not on"; return apps }
        do {
            apps = try await fetch(request); fetchedAt = Date(); lastProblem = nil
        } catch {
            lastProblem = error.localizedDescription
        }
        return apps
    }

    /// Whether `id` is on this phone: from its list, else from iOS's icons; nil when neither can say.
    func installed(_ id: String, in list: [App]?) -> Bool? {
        if let list { return list.contains { $0.id.caseInsensitiveCompare(id) == .orderedSame } }
        return hasIcon(id)
    }

    // MARK: find_app

    struct StoreApp: Equatable {
        var id: String
        var name: String
        var url: String?
    }

    struct Match: Equatable {
        var id: String
        var name: String
        var installed: Bool?
        var url: String?
    }

    /// The installed apps called `name`, best first: an exact name, then one that starts with it or
    /// holds it. KnownApps' names count too, so 淘宝 finds com.taobao.taobao4iphone whatever the phone
    /// calls it.
    static func matches(_ name: String, in list: [App]) -> [App] {
        let key = normalized(name)
        guard !key.isEmpty else { return [] }
        let known = KnownApps.find(name).map { Set($0.ids.map { $0.lowercased() }) } ?? []
        func score(_ app: App) -> Int? {
            if known.contains(app.id.lowercased()) { return 0 }
            let names = [app.name, app.bundleName].compactMap { $0 }.map(normalized).filter { !$0.isEmpty }
            if names.contains(key) { return 1 }
            if names.contains(where: { $0.hasPrefix(key) }) { return 2 }
            if key.count >= 2, names.contains(where: { $0.contains(key) || ($0.count >= 2 && key.contains($0)) }) { return 3 }
            return nil
        }
        return list.compactMap { app in score(app).map { (app, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : ($0.0.name ?? $0.0.id).count < ($1.0.name ?? $1.0.id).count }
            .map(\.0)
    }

    /// Lower-cased, without spaces and punctuation: "WeChat" and "We Chat", "淘宝-万能的淘宝！" and "淘宝万能的淘宝".
    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The answer to find_app: the installed apps by `name`, or for `purpose` the App Store's apps
    /// marked installed or not, with the store's link for the ones that are not.
    func find(name: String?, purpose: String?) async -> (text: String, isError: Bool) {
        let list = await list()
        let source = list != nil ? "this iPhone's app list (\(list!.count) apps)" : "the app icons on this iPhone (its app list could not be read: \(lastProblem ?? "no answer"))"
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            var found: [Match] = []
            // Ids whose installation neither the list nor the icons could settle: a lookup that failed
            // is no evidence that an app is missing.
            var unsure: [String] = []
            if let list {
                found = Self.matches(name, in: list).prefix(5).map { Match(id: $0.id, name: $0.name ?? $0.bundleName ?? $0.id, installed: true) }
            } else if let known = KnownApps.find(name) {
                let states = known.ids.map { ($0, hasIcon($0)) }
                if let id = states.first(where: { $0.1 == true })?.0 {
                    found = [Match(id: id, name: known.name(in: .current), installed: true)]
                } else {
                    unsure += states.filter { $0.1 == nil }.map(\.0)
                }
            }
            if found.isEmpty {
                // The App Store's names, kept to the ones on this phone: its own list may name an app
                // in another language than the owner did.
                let store = await search(name)
                let marked = store.prefix(3).map { Match(id: $0.id, name: $0.name, installed: installed($0.id, in: list), url: $0.url) }
                found = store.filter { installed($0.id, in: list) == true }.prefix(3).map { Match(id: $0.id, name: $0.name, installed: true) }
                unsure += marked.filter { $0.installed == nil }.map(\.id)
                if found.isEmpty {
                    // Missing only on the phone's own list, or when the icons said no for every candidate.
                    let settled = list != nil || (!marked.isEmpty && unsure.isEmpty)
                    if !settled { return (Self.answer(unknown: name, offers: marked, source: source), false) }
                    return (Self.answer(missing: name, offers: marked, source: source), false)
                }
            }
            return ("installed apps named \"\(name)\", from \(source); launch the first unless another fits better:\n" + found.map(Self.line).joined(separator: "\n"), false)
        }
        if let purpose = purpose?.trimmingCharacters(in: .whitespacesAndNewlines), !purpose.isEmpty {
            let store = await search(purpose)
            guard !store.isEmpty else { return ("the App Store found no app for \"\(purpose)\".", false) }
            let marked = store.prefix(5).map { Match(id: $0.id, name: $0.name, installed: installed($0.id, in: list), url: $0.url) }
            let sorted = marked.filter { $0.installed == true } + marked.filter { $0.installed != true }
            return ("App Store apps for \"\(purpose)\", installed ones first (installed checked with \(source)):\n" + sorted.map(Self.line).joined(separator: "\n"), false)
        }
        return ("find_app takes name (an app's name) or purpose (what the app is for).", true)
    }

    /// Neither the phone's list nor its icons could say whether the app is there.
    private static func answer(unknown name: String, offers: [Match], source: String) -> String {
        var text = "could not tell whether \"\(name)\" is installed: the phone's app list could not be read and the icons could not settle it (checked \(source)). Do not tell the owner it is missing: go home ({button: \"home\"}), swipe down on the Home Screen to search, type its name and tap it."
        if !offers.isEmpty { text += " The App Store's matches, for their ids:\n" + offers.map(line).joined(separator: "\n") }
        return text
    }

    private static func answer(missing name: String, offers: [Match], source: String) -> String {
        var text = "no app named \"\(name)\" is installed (checked \(source))."
        if offers.isEmpty { return text + " The App Store found none either; try the Home Screen search before telling the owner." }
        text += " The App Store's matches, NOT installed (launch cannot open them; tell the owner and give the link when the task needs the app):\n"
        return text + offers.map(line).joined(separator: "\n")
    }

    private static func line(_ m: Match) -> String {
        let state = m.installed == true ? "installed" : m.installed == false ? "not installed" : "installed: unknown"
        return "- \(m.name): \(m.id) (\(state))" + (m.installed == true ? "" : m.url.map { " \($0)" } ?? "")
    }
}

/// The App Store's public search (iTunes Search API) in the store of the phone's region: names to
/// bundle ids and store links. A Chinese name is looked up in the China store too.
enum AppStoreSearch {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        return URLSession(configuration: configuration)
    }()

    static func apps(_ term: String, limit: Int = 5) async -> [InstalledApps.StoreApp] {
        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        let han = term.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        var stores = [region]
        for extra in han ? ["cn"] : ["us"] where !stores.contains(extra) { stores.append(extra) }
        for store in stores {
            var url = URLComponents(string: "https://itunes.apple.com/search")!
            url.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "country", value: store),
                              URLQueryItem(name: "entity", value: "software"), URLQueryItem(name: "limit", value: String(limit))]
            guard let address = url.url, let (data, _) = try? await session.data(from: address) else { continue }
            let found = parse(data)
            if !found.isEmpty { return found }
        }
        return []
    }

    /// The search's results. Its descriptions carry raw control characters, which JSONSerialization
    /// refuses, so they become spaces first.
    static func parse(_ data: Data) -> [InstalledApps.StoreApp] {
        let text = String(decoding: data, as: UTF8.self).unicodeScalars.map { $0.value < 0x20 ? " " : String($0) }.joined()
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let id = r["bundleId"] as? String, !id.isEmpty else { return nil }
            let link = (r["trackViewUrl"] as? String).map { $0.components(separatedBy: "?").first ?? $0 }
            return InstalledApps.StoreApp(id: id, name: (r["trackName"] as? String) ?? id, url: link)
        }
    }
}
