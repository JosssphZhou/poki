import SwiftUI
import XCTest
@testable import Poki

@MainActor
final class InterfaceSizeLocalizationTests: XCTestCase {
    /// Read the production views while changing only Poki's preference. The same hosting controller
    /// must update in place even when iOS's app language is different.
    func testPreviewAndEmptyBrowserHeaderFollowPokiLanguage() async throws {
        try XCTSkipUnless(Bundle.main.preferredLocalizations.first == "en", "Requires iOS app language English (-AppleLanguages (en))")
        let language = AppLocalization.shared.preference
        let size = UserDefaults.standard.object(forKey: AppInterfaceSize.defaultsKey)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let covered = scene.windows.filter { !$0.accessibilityElementsHidden }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let chat = ChatModel(app: app, kind: .handoff, requester: "Localization test")
        let browser = PokiBrowser.shared
        browser.close()
        _ = browser.begin("Localization test")
        XCTAssertTrue(browser.host.isEmpty)
        covered.forEach { $0.accessibilityElementsHidden = true }
        defer {
            window.isHidden = true
            covered.forEach { $0.accessibilityElementsHidden = false }
            browser.close()
            AppLocalization.shared.preference = language
            UserDefaults.standard.set(size, forKey: AppInterfaceSize.defaultsKey)
        }
        UserDefaults.standard.set(AppInterfaceSize.system, forKey: AppInterfaceSize.defaultsKey)
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterfaceSizeLanguageEvidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let cases = [
            ("en", "Help me plan tomorrow.", "Reminder created", "Poki’s Browser"),
            ("zh-Hans", "帮我安排一下明天的计划。", "已创建提醒", "浏览器"),
            ("zh-Hant", "幫我安排一下明天的計劃。", "已建立提醒", "瀏覽器"),
            ("system", "Help me plan tomorrow.", "Reminder created", "Poki’s Browser"),
        ]
        for preview in [true, false] {
            let controller = UIHostingController(rootView:
                LocalizationReviewView(preview: preview).environment(app).environment(chat))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            for (preference, message, reminder, browserTitle) in cases {
                AppLocalization.shared.preference = preference
                window.layoutIfNeeded()
                CATransaction.flush()
                let expected = preview ? [message, reminder] : [browserTitle]
                var source = ""
                let deadline = CACurrentMediaTime() + 10
                repeat {
                    source = await Task.detached {
                        var code: NSString?
                        return PKInProcess.shared().sourceXML(nil, code: &code) ?? ""
                    }.value
                    if expected.allSatisfy(source.contains) { break }
                    try await Task.sleep(for: .milliseconds(50))
                } while CACurrentMediaTime() < deadline
                for text in expected { XCTAssertTrue(source.contains(text), "\(preference): missing \(text)") }
                XCTAssertTrue(window.rootViewController === controller)
                let name = "\(preview ? "preview" : "browser")-\(preference)"
                try source.write(to: output.appendingPathComponent("\(name).xml"), atomically: true, encoding: .utf8)
                let image = await Task.detached {
                    var code: NSString?
                    return PKInProcess.shared().screenshot(&code)
                }.value
                try XCTUnwrap(image).write(to: output.appendingPathComponent("\(name).png"))
            }
        }
    }
}

private struct LocalizationReviewView: View {
    let preview: Bool

    var body: some View {
        Group {
            if preview { InterfaceSizeSettingsView() }
            else { BrowserPanel().padding() }
        }
        .environment(\.locale, AppLocalization.locale)
    }
}
