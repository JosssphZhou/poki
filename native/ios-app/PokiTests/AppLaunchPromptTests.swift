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

    func testTheDebugFileKeepsLaunchesAndFailuresButNoTypedText() {
        let calls = [
            CallRecord(name: "report_plan", arguments: "{}", answer: "Plan published. Continue.", ms: 2, ok: true),
            CallRecord(name: "do", arguments: #"{"actions":[{"launch":"com.taobao.taobao"}]}"#,
                       answer: "app: Poki\nerror: launch com.taobao.taobao: no app with that bundle id is installed on this device\nelements (3):",
                       ms: 120, ok: false),
            CallRecord(name: "do", arguments: #"{"actions":[{"type":"my secret","ref":3},{"key":"return"}]}"#,
                       answer: "error: the field holds my secret", ms: 80, ok: false),
        ]
        let entry = ChatDebugLog.entry(model: "pi, openai/x", named: ["com.taobao.taobao4iphone"], calls: calls, finished: false, seconds: 4.26)
        XCTAssertEqual(entry.seconds, 4.3)
        XCTAssertEqual(entry.calls[1].actions, ["launch com.taobao.taobao"])
        XCTAssertEqual(entry.calls[1].error, "error: launch com.taobao.taobao: no app with that bundle id is installed on this device")
        XCTAssertEqual(entry.calls[2].actions, ["type", "key return"])
        XCTAssertFalse(entry.calls[2].error?.contains("secret") ?? true)

        ChatDebugLog.clear()
        defer { ChatDebugLog.clear() }
        for _ in 0..<(ChatDebugLog.limit + 3) { ChatDebugLog.add(entry) }
        XCTAssertEqual(ChatDebugLog.entries().count, ChatDebugLog.limit)
        guard case .array(let tasks) = ChatDebugLog.json(), case .object(let first)? = tasks.first else { return XCTFail("chat_tasks is a list") }
        XCTAssertEqual(first["named"], .array([.string("com.taobao.taobao4iphone")]))
    }

    // MARK: find_app

    private let phoneList: [InstalledApps.App] = [
        .init(id: "com.taobao.taobao4iphone", name: "淘宝", bundleName: "Taobao4iPhone"),
        .init(id: "com.meituan.itakeaway", name: "美团外卖", bundleName: "iTakeaway"),
        .init(id: "com.meituan.imeituan", name: "美团", bundleName: "imeituan"),
        .init(id: "com.apple.mobilenotes", name: nil, bundleName: "MobileNotes"),
    ]

    private func finder(store: [InstalledApps.StoreApp] = []) -> InstalledApps {
        let apps = InstalledApps()
        apps.phone = { nil }
        apps.hasIcon = { _ in nil }
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
        let apps = finder()
        apps.use(phoneList)
        let answer = await apps.find(name: "淘宝", purpose: nil)
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("com.taobao.taobao4iphone (installed)"), answer.text)
    }

    func testAMissingAppComesWithItsAppStoreLink() async {
        let apps = finder(store: [.init(id: "com.taobao.fleamarket", name: "闲鱼", url: "https://apps.apple.com/cn/app/id510909506")])
        apps.use(phoneList)
        let answer = await apps.find(name: "闲鱼", purpose: nil)
        XCTAssertTrue(answer.text.contains("NOT installed"), answer.text)
        XCTAssertTrue(answer.text.contains("com.taobao.fleamarket (not installed) https://apps.apple.com/cn/app/id510909506"), answer.text)
    }

    func testTheStoresNameFindsAnInstalledAppThePhoneNamesOtherwise() async {
        let apps = finder(store: [.init(id: "com.meituan.imeituan", name: "美团-问美团，都安排", url: nil)])
        apps.use([.init(id: "com.meituan.imeituan", name: "Meituan", bundleName: nil)])
        let answer = await apps.find(name: "问美团", purpose: nil)
        XCTAssertTrue(answer.text.contains("com.meituan.imeituan (installed)"), answer.text)
    }

    func testAPurposeListsInstalledAppsFirst() async {
        let apps = finder(store: [.init(id: "com.example.park", name: "ParkMe", url: "https://apps.apple.com/us/app/id1"),
                                  .init(id: "com.meituan.imeituan", name: "美团", url: "https://apps.apple.com/cn/app/id2")])
        apps.use(phoneList)
        let answer = await apps.find(name: nil, purpose: "parking")
        let lines = answer.text.split(separator: "\n").dropFirst()
        XCTAssertEqual(lines.first.map(String.init), "- 美团: com.meituan.imeituan (installed)")
        XCTAssertEqual(lines.last.map(String.init), "- ParkMe: com.example.park (not installed) https://apps.apple.com/us/app/id1")
    }

    func testWithoutThePhonesListTheIconsDecide() async {
        let apps = finder()
        apps.hasIcon = { $0 == "com.taobao.taobao4iphone" }
        let answer = await apps.find(name: "淘宝", purpose: nil)
        XCTAssertTrue(answer.text.contains("com.taobao.taobao4iphone (installed)"), answer.text)
        XCTAssertTrue(answer.text.contains("could not be read"), answer.text)
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
