import XCTest
@testable import PokiSetup

final class LocalizationTests: XCTestCase {
    func testProductionInstallProgressAndRecoveryLocalizeWithoutLosingData() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = SetupLocalization(defaults: defaults)
        localization.language = .simplifiedChinese
        let cases = [
            ("Installing the provisioning profiles", "正在安装描述文件"),
            ("Registering the iPhone with the team", "正在将 iPhone 注册到此团队"),
            ("No iPhone found. Plug it in with a cable and unlock it.", "用数据线连接并解锁"),
            ("More than one iPhone is plugged in. Choose one.", "请选择一部"),
            ("The iPhone said Don't Trust. Unplug it, plug it in again and tap Trust.", "选择了“不信任”"),
            ("The iPhone no longer trusts this computer. Plug it in with a cable, unlock it and tap Trust, then try again.", "不再信任这台电脑"),
            ("The developer disk image is already mounted.", "开发者磁盘映像已挂载"),
            ("R2 download was interrupted. Using GitHub.", "下载中断，改用 GitHub"),
            ("The iPhone did not accept the app's signature. Make sure this iPhone is registered on the Apple ID's team and Developer Mode is on, then try again.", "未接受 App 签名"),
            ("The installed Poki has a different application signing identity. Keep Poki installed to preserve its data, and update it using the original signing identity on the original computer.", "请在原来的电脑上使用原签名身份更新"),
            ("Signing Poki for Example Team", "正在为 Example Team 签名 Poki"),
            ("Poki 0.5.1 (456) signed for Example Team", "已为 Example Team 签名 Poki 0.5.1（456）"),
            ("Example Team (free, 7-day signing)", "Example Team（免费团队，签名有效期 7 天）"),
            ("App ID and profile for PokiWidgets", "为 PokiWidgets 设置 App ID 和描述文件"),
            ("Remote pairing did not finish (lockdown: InvalidHostID (0x42)). Poki can pair on the iPhone instead.", "远程配对未完成（lockdown: InvalidHostID (0x42)）"),
            ("The iPhone refused a provisioning profile: MobileInstallation (0xe8008001). On a free team the phone must be registered on the Apple ID; sign in again.", "iPhone 拒绝了描述文件：MobileInstallation (0xe8008001)"),
            ("The iPhone stopped answering while installing Poki (unlock the iPhone, check it for a prompt, then try again). Unplug it, plug it in again and unlock it, then try again.", "安装 Poki时，iPhone 停止响应")
        ]
        for (message, translation) in cases {
            XCTAssertTrue(progressLine(message, in: localization).contains(translation), message)
        }
        let diagnostic = "third-party reply: %s [0x42]"
        XCTAssertEqual(progressLine(diagnostic, in: localization), diagnostic)
        localization.language = .english
        for (message, _) in cases {
            XCTAssertEqual(progressLine(message, in: localization), message)
        }
    }

    func testCertificateWarningKeepsTheIdentityAndConsequenceInBothLanguages() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = SetupLocalization(defaults: defaults)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let error = try decoder.decode(CoreError.self, from: Data("""
        {"kind":"certificate_limit","message":"English fallback","certificate":
          {"name":"Example Certificate","serial":"5F00","machine":"Example Mac","days_left":3}}
        """.utf8))
        let certificate = try XCTUnwrap(error.certificate)
        localization.language = .english
        let en = certificate.warning(in: localization)
        XCTAssertTrue(en.contains("Every app signed with the old certificate will stop opening"))
        XCTAssertTrue(en.contains("It expires in 3 days."))
        localization.language = .simplifiedChinese
        let zh = certificate.warning(in: localization)
        XCTAssertTrue(zh.contains("使用旧证书签名的 App 都将无法打开，直到使用有效证书重新安装"))
        XCTAssertTrue(zh.contains("3 天后到期"))
        for warning in [en, zh] {
            XCTAssertTrue(warning.contains("Example Certificate"))
            XCTAssertTrue(warning.contains("5F00"))
            XCTAssertTrue(warning.contains("Example Mac"))
        }
    }

    func testSystemLanguageAndFallback() {
        XCTAssertEqual(SetupLanguage.system.resolve(preferred: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(SetupLanguage.system.resolve(preferred: ["de"]), "en")
        XCTAssertEqual(SetupLanguage.english.resolve(preferred: ["zh-Hans"]), "en")
    }

    func testSwitchingAndRestoringLanguage() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = SetupLocalization(defaults: defaults)
        XCTAssertEqual(localization.language, .system)
        localization.language = .simplifiedChinese
        XCTAssertEqual(localization.text("Apple Account"), "Apple 账户")
        let name = "Jane's iPad"
        let run = 42
        XCTAssertEqual(localization.text("Installed test build \(run) on \(name)."), "已在 Jane's iPad 上安装测试构建 42。")
        XCTAssertEqual(SetupLocalization(defaults: defaults).language, .simplifiedChinese)
        localization.language = .english
        XCTAssertEqual(localization.text("Apple Account"), "Apple Account")
        defaults.set("unknown", forKey: "uiLanguage")
        XCTAssertEqual(SetupLocalization(defaults: defaults).language, .system)
    }

    func testBundledTranslationsKeepEveryKeyAndArgument() throws {
        func entries(_ language: String, table: String) throws -> [String: String] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: table, withExtension: "strings",
                                                       subdirectory: nil, localization: language))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }

        // A translation may reorder arguments using e.g. %2$@, but their types must agree.
        let placeholder = try NSRegularExpression(pattern: #"%(?:(\d+)\$)?(lld|d|@)"#)
        func signature(_ text: String) -> [String] {
            let source = text as NSString
            let matches = placeholder.matches(in: text, range: NSRange(location: 0, length: source.length))
            return matches.enumerated().map { offset, match in
                let index = match.range(at: 1)
                let position = index.location == NSNotFound ? String(offset + 1) : source.substring(with: index)
                return position + source.substring(with: match.range(at: 2))
            }.sorted()
        }

        for table in ["Localizable", "Progress"] {
            let english = try entries("en", table: table)
            let chinese = try entries("zh-Hans", table: table)
            XCTAssertEqual(Set(english.keys), Set(chinese.keys))
            for (key, value) in chinese {
                XCTAssertFalse(value.isEmpty, key)
                XCTAssertEqual(signature(key), signature(value), key)
            }
        }
    }
}
