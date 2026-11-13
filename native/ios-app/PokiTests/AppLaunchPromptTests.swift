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
}
