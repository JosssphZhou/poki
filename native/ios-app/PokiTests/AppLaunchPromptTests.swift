import XCTest
@testable import Poki

/// The chat's model is told the bundle ids of the apps a request names, and the debug file keeps the
/// chat's tasks. A tester's 淘宝 and 美团 tasks (Nov 13 2026) failed with "no app with that bundle id is
/// installed": the model had guessed the ids, and the debug file showed no runs at all.
@MainActor
final class AppLaunchPromptTests: XCTestCase {
    func testTheRequestsAppsComeWithTheirBundleIDs() {
        let taobao = Harness.appIDs(for: "帮我每天自动上淘宝买纸巾") ?? ""
        XCTAssertTrue(taobao.contains("com.taobao.taobao4iphone"), taobao)
        let meituan = Harness.appIDs(for: "帮我在美团上买一杯霸王茶姬") ?? ""
        XCTAssertTrue(meituan.contains("com.meituan.imeituan"), meituan)
        XCTAssertFalse(meituan.contains("com.meituan.itakeaway"), "Meituan, not Meituan Waimai")
        XCTAssertNil(Harness.appIDs(for: "what time is it"))
    }

    func testTheInstructionsCarryThemAndTheSearchFallback() {
        let text = Harness.instructions(for: "帮我在美团上买一杯霸王茶姬")
        XCTAssertTrue(text.contains("com.meituan.imeituan"))
        XCTAssertTrue(text.contains("swipe down on the Home Screen to search"))
    }

    func testEachSpellingOf12306FindsIt() {
        for request in ["打开铁路12306查询", "打开12306查询", "打开 12306 查询"] {
            XCTAssertTrue(Harness.instructions(for: request).contains("cn.12306.rails12306"), request)
        }
        XCTAssertNil(Harness.appIDs(for: "order a123067 now"), "digits inside a longer Latin run are not the app")
        XCTAssertNil(Harness.appIDs(for: "call 9123067"), "nor inside a longer number")
        XCTAssertNil(Harness.appIDs(for: "open notesbook"), "a Latin name still needs a whole word")
    }

    // MARK: The debug file

    private func clearDebugFile() { try? FileManager.default.removeItem(at: ChatDebugLog.file) }
    override func setUp() async throws { clearDebugFile() }
    override func tearDown() async throws { clearDebugFile() }

    func testTheDebugFileKeepsKindsAndFailureCategoriesOnly() {
        let calls = [
            CallRecord(name: "report_plan", arguments: "{}", answer: "Plan published. Continue.", ms: 2, ok: true),
            CallRecord(name: "do", arguments: #"{"actions":[{"launch":"com.taobao.taobao"}]}"#,
                       answer: "app: Poki\nerror: launch com.taobao.taobao: no app with that bundle id is installed on this device\nelements (3):",
                       ms: 120, ok: false),
            CallRecord(name: "do", arguments: #"{"actions":[{"run":"Order my usual"},{"type":"hello","ref":3},{"key":"return"},{"swipe":"sideways please"}]}"#,
                       answer: "error: the field holds hello", ms: 80, ok: false),
        ]
        let entry = ChatDebugLog.entry(model: "pi, openai/x", named: ["com.taobao.taobao4iphone"], calls: calls, finished: false, seconds: 4.26)
        XCTAssertEqual(entry.seconds, 4.3)
        XCTAssertEqual(entry.calls[1].actions, ["launch com.taobao.taobao"])
        XCTAssertEqual(entry.calls[1].error, "launch_not_installed")
        XCTAssertEqual(entry.calls[2].actions, ["run", "type", "key return", "swipe"], "no routine name, no text, no free-form direction")
        XCTAssertEqual(entry.calls[2].error, "failed")

        for _ in 0..<(ChatDebugLog.limit + 3) { ChatDebugLog.add(entry) }
        XCTAssertEqual(ChatDebugLog.entries().count, ChatDebugLog.limit)
        guard case .array(let tasks) = ChatDebugLog.json(), case .object(let first)? = tasks.first else { return XCTFail("chat_tasks is a list") }
        XCTAssertEqual(first["named"], .array([.string("com.taobao.taobao4iphone")]))
    }

    /// web_type puts the entered value in its answer's first line (WebTools.after), and the call fails
    /// when the page read after it does. Neither the saved tasks nor the exported file may hold it.
    func testAnEnteredValueNeverReachesTheSavedLogOrTheExport() throws {
        let sentinel = "SENTINEL-\(UUID().uuidString)"
        let calls = [
            CallRecord(name: "web_type", arguments: #"{"ref":"e4","text":"\#(sentinel)"}"#,
                       answer: "Typed into “Search”: \(sentinel).\nThe page did not answer. Read it again with web_read.", ms: 900, ok: false),
            CallRecord(name: "do", arguments: #"{"actions":[{"run":"\#(sentinel)"},{"launch":"\#(sentinel) app"},{"type":"\#(sentinel)"}]}"#,
                       answer: "error: \(sentinel)", ms: 10, ok: false),
            CallRecord(name: "find_app", arguments: #"{"name":"\#(sentinel)"}"#, answer: "no app named \"\(sentinel)\" is installed", ms: 5, ok: true),
        ]
        ChatDebugLog.add(ChatDebugLog.entry(model: "pi, openai/x", named: [], calls: calls, finished: nil, seconds: 1))
        let saved = try String(contentsOf: ChatDebugLog.file, encoding: .utf8)
        XCTAssertFalse(saved.contains(sentinel), saved)
        let exported = String(decoding: ChatDebugLog.exportBundle(), as: UTF8.self)
        XCTAssertTrue(exported.contains("chat_tasks"), exported)
        XCTAssertFalse(exported.contains(sentinel), exported)
        XCTAssertEqual(ChatDebugLog.entries().first?.calls.map(\.actions), [[], ["run", "launch", "type"], []])
    }

    // MARK: find_app

    private let phoneList: [InstalledApps.App] = [
        .init(id: "com.taobao.taobao4iphone", name: "淘宝", bundleName: "Taobao4iPhone"),
        .init(id: "com.meituan.itakeaway", name: "美团外卖", bundleName: "iTakeaway"),
        .init(id: "com.meituan.imeituan", name: "美团", bundleName: "imeituan"),
        .init(id: "com.apple.mobilenotes", name: nil, bundleName: "MobileNotes"),
    ]

    /// A finder whose phone answers with `list` through the same read the signer's answer takes, or
    /// whose phone cannot be reached when `list` is nil.
    private func finder(list: [InstalledApps.App]?, store: [InstalledApps.StoreApp] = [], icons: @escaping (String) -> Bool? = { _ in nil }) -> InstalledApps {
        let apps = InstalledApps()
        apps.phone = { list == nil ? nil : [:] }
        apps.fetch = { _ in list ?? [] }
        apps.hasIcon = { icons($0) }
        apps.search = { _ in store }
        return apps
    }

    func testNamesFindTheInstalledAppExactNameFirst() {
        XCTAssertEqual(InstalledApps.matches("美团", in: phoneList).first?.id, "com.meituan.imeituan", "美团, ahead of 美团外卖 which holds it")
        XCTAssertEqual(InstalledApps.matches("Taobao", in: phoneList).first?.id, "com.taobao.taobao4iphone", "KnownApps' English name")
        XCTAssertEqual(InstalledApps.matches("Notes", in: phoneList).first?.id, "com.apple.mobilenotes")
        XCTAssertTrue(InstalledApps.matches("闲鱼", in: phoneList).isEmpty)
    }

    func testFindAppAnswersTheInstalledID() async {
        let answer = await finder(list: phoneList).find(name: "淘宝", purpose: nil)
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("com.taobao.taobao4iphone (installed)"), answer.text)
    }

    func testAMissingAppComesWithItsAppStoreLink() async {
        let apps = finder(list: phoneList, store: [.init(id: "com.taobao.fleamarket", name: "闲鱼", url: "https://apps.apple.com/cn/app/id510909506")])
        let answer = await apps.find(name: "闲鱼", purpose: nil)
        XCTAssertTrue(answer.text.contains("NOT installed"), answer.text)
        XCTAssertTrue(answer.text.contains("com.taobao.fleamarket (not installed) https://apps.apple.com/cn/app/id510909506"), answer.text)
    }

    func testTheStoresNameFindsAnInstalledAppThePhoneNamesOtherwise() async {
        let apps = finder(list: [.init(id: "com.meituan.imeituan", name: "Meituan", bundleName: nil)],
                          store: [.init(id: "com.meituan.imeituan", name: "美团-问美团，都安排", url: nil)])
        let answer = await apps.find(name: "问美团", purpose: nil)
        XCTAssertTrue(answer.text.contains("com.meituan.imeituan (installed)"), answer.text)
    }

    func testAPurposeListsInstalledAppsFirst() async {
        let apps = finder(list: phoneList, store: [.init(id: "com.example.park", name: "ParkMe", url: "https://apps.apple.com/us/app/id1"),
                                                   .init(id: "com.meituan.imeituan", name: "美团", url: "https://apps.apple.com/cn/app/id2")])
        let answer = await apps.find(name: nil, purpose: "parking")
        let lines = answer.text.split(separator: "\n").dropFirst()
        XCTAssertEqual(lines.first.map(String.init), "- 美团: com.meituan.imeituan (installed)")
        XCTAssertEqual(lines.last.map(String.init), "- ParkMe: com.example.park (not installed) https://apps.apple.com/us/app/id1")
    }

    func testWithoutThePhonesListTheIconsDecide() async {
        let answer = await finder(list: nil, icons: { $0 == "com.taobao.taobao4iphone" }).find(name: "淘宝", purpose: nil)
        XCTAssertTrue(answer.text.contains("com.taobao.taobao4iphone (installed)"), answer.text)
        XCTAssertTrue(answer.text.contains("could not be read"), answer.text)
    }

    /// A failed lookup is no evidence: with no list and no icons, an App Store match stays unknown and
    /// the agent is sent to the Home Screen search instead of telling the owner the app is missing.
    func testAnUnreadableListNeverMakesAnAppMissing() async {
        let store: [InstalledApps.StoreApp] = [.init(id: "com.taobao.fleamarket", name: "闲鱼", url: "https://apps.apple.com/cn/app/id510909506")]
        for apps in [finder(list: nil, store: store), finder(list: nil)] {
            let answer = await apps.find(name: "闲鱼", purpose: nil)
            XCTAssertFalse(answer.text.contains("NOT installed"), answer.text)
            XCTAssertFalse(answer.text.contains("(not installed)"), answer.text)
            XCTAssertTrue(answer.text.contains("could not tell whether"), answer.text)
            XCTAssertTrue(answer.text.contains("swipe down on the Home Screen to search"), answer.text)
        }
        let noIcon = await finder(list: nil, store: store, icons: { _ in false }).find(name: "闲鱼", purpose: nil)
        XCTAssertTrue(noIcon.text.contains("NOT installed"), "the icons said no: that one is settled")
    }

    func testTheStoreSearchReadsPastControlCharacters() {
        let body = "{\"resultCount\":1,\"results\":[{\"bundleId\":\"com.taobao.taobao4iphone\",\"trackName\":\"淘宝\",\"trackViewUrl\":\"https://apps.apple.com/cn/app/id387682726?uo=4\",\"description\":\"line one\nline two\"}]}"
        XCTAssertEqual(AppStoreSearch.parse(Data(body.utf8)), [.init(id: "com.taobao.taobao4iphone", name: "淘宝", url: "https://apps.apple.com/cn/app/id387682726")])
    }

    func testTheModelIsOfferedFindApp() {
        XCTAssertTrue(Harness.tools.contains { $0.name == "find_app" })
        XCTAssertTrue(Harness.instructions(for: "打开闲鱼").contains("find_app"))
    }
}
