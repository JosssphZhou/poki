import XCTest
@testable import Poki

/// open_app, the live voice's way into an app (the owner, 2026-11-18: "open WeChat" went to the Home
/// Screen's search instead of straight to the app).
@MainActor
final class VoiceAppsTests: XCTestCase {
    /// What open_app sends to PokiCore for what the user said, and whether it answers a failure.
    func testOpenAppGoesStraightToTheAppTheUserNamed() async {
        let installed: Set<String> = ["com.tencent.xin", "com.bilibili.inter", "com.apple.Preferences"]
        let cases: [(arguments: String, linkOpens: Bool, sent: [String], failed: Bool)] = [
            (#"{"app":"微信"}"#, true, [#"{"actions":[{"launch":"com.tencent.xin"}]}"#], false),
            (#"{"app":"WeChat"}"#, true, [#"{"actions":[{"launch":"com.tencent.xin"}]}"#], false),
            // Bilibili's own edition is not installed here; its international one is.
            (#"{"app":"B站"}"#, true, [#"{"actions":[{"launch":"tv.danmaku.bilianime"}]}"#, #"{"actions":[{"launch":"com.bilibili.inter"}]}"#], false),
            (#"{"app":"设置","page":"bluetooth"}"#, true, [#"{"actions":[{"wait_until":{"settled":true,"ms":2500}}]}"#], false),
            // Poki in the background cannot open the link: Settings opens, and the model taps the page.
            (#"{"app":"设置","page":"bluetooth"}"#, false, [#"{"actions":[{"launch":"com.apple.Preferences"}]}"#], false),
            // A name Poki does not know, and one that names two apps: nothing is sent.
            (#"{"app":"Zorblax"}"#, true, [], true),
            (#"{"app":"微信和支付宝"}"#, true, [], true),
            // An app this iPhone does not have: the launch is tried, and the answer says to search for it.
            (#"{"app":"美团"}"#, true, [#"{"actions":[{"launch":"com.meituan.imeituan"}]}"#], true),
        ]
        for c in cases {
            var sent: [String] = []
            var links: [URL] = []
            let answer = await VoiceApps.open(c.arguments, tool: { name, arguments in
                sent.append(arguments)
                return arguments.contains("launch") && !installed.contains(where: { arguments.contains("\"\($0)\"") })
                    ? ("not_sent: launch: no app with that bundle id is installed on this device", true, nil)
                    : ("app: in front", false, Data([1]))
            }, openLink: { links.append($0); return c.linkOpens })
            XCTAssertEqual(sent, c.sent, c.arguments)
            XCTAssertEqual(answer.failed, c.failed, c.arguments)
            if c.arguments.contains("bluetooth") { XCTAssertEqual(links, [URL(string: "App-prefs:Bluetooth")!], c.arguments) }
        }
    }

    /// phone_step, the fast path for 往下翻, 返回 and 回到桌面: one PokiCore do, not Poki's agent (30 to
    /// 50 s on a physical iPhone, 2026-11-19).
    func testPhoneStepScrollsGoesBackOrHomeInOneDo() async {
        let cases: [(arguments: String, sent: [String], failed: Bool)] = [
            (#"{"step":"scroll_down"}"#, [#"{"actions":[{"swipe":{"direction":"up","distance":"scroll"}}]}"#], false),
            (#"{"step":"scroll_up"}"#, [#"{"actions":[{"swipe":{"direction":"down","distance":"scroll"}}]}"#], false),
            (#"{"step":"back"}"#, [#"{"actions":[{"back":true}]}"#], false),
            (#"{"step":"home"}"#, [#"{"actions":[{"button":"home"}]}"#], false),
            (#"{"step":"tap"}"#, [], true),
        ]
        for c in cases {
            var sent: [String] = []
            let answer = await VoiceApps.step(c.arguments, tool: { name, arguments in
                XCTAssertEqual(name, "do")
                sent.append(arguments)
                return ("app: in front", false, nil)
            })
            XCTAssertEqual(sent, c.sent, c.arguments)
            XCTAssertEqual(answer.failed, c.failed, c.arguments)
        }
    }
}
