import PokiCore
import UIKit
import XCTest
@testable import Poki

/// Apps Poki does not list by name still show with their name and icon once the phone's app list has
/// them: the list's names give the bundle id, the id gives the iPhone's icon or the App Store's.
@MainActor
final class DynamicAppsTests: XCTestCase {
    private let strava = DynamicApps.Entry(id: "com.strava.stravaride", name: "Strava", user: true)
    private let chagee = DynamicApps.Entry(id: "com.chagee.application.cn", name: "霸王茶姬", user: true)

    private func reset() {
        DynamicApps.set([])
        try? FileManager.default.removeItem(at: InstalledApps.cacheFile)
    }
    override func setUp() async throws { reset() }
    override func tearDown() async throws { reset() }

    private func capsules(_ plain: String) -> [String] {
        CapsuleText.segments(plain).compactMap { if case .app(let app, _) = $0 { app.id } else { nil } }
    }

    func testAnInstalledAppsNameGivesItsBundleIDAndBack() {
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        DynamicApps.set([strava, chagee])
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride")
        XCTAssertEqual(AppIconStore.bundleID("strava"), "com.strava.stravaride")
        XCTAssertEqual(AppIconStore.bundleID("霸王茶姬"), "com.chagee.application.cn")
        XCTAssertEqual(AppIconStore.name("com.strava.stravaride"), "Strava")
        XCTAssertEqual(AppName.display("com.strava.stravaride"), "Strava", "an installed app's id reads as its name")
        XCTAssertEqual(AppIconStore.bundleID("淘宝"), "com.taobao.taobao4iphone", "KnownApps still first")
    }

    func testANameTwoAppsShareFindsNeither() {
        DynamicApps.set([strava, .init(id: "com.example.strava", name: "Strava", user: true)])
        XCTAssertNil(DynamicApps.id(forName: "Strava"))
        XCTAssertEqual(DynamicApps.name(forID: "com.example.strava"), "Strava")
    }

    private func square(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
    }

    /// The store follows the installed apps by itself: nothing here tells it they changed.
    func testTheIconComesOnceTheListArrivesAndGoesWithTheName() {
        let red = square(.red)
        let store = AppIconStore(installed: { id, _ in id == "com.strava.stravaride" ? red : nil })
        XCTAssertNil(store.icon("Strava"), "no id for the name yet")
        DynamicApps.set([strava])
        XCTAssertTrue(store.icon("Strava") === red)
        // The app is renamed: its old name finds no app, so it shows no icon either.
        DynamicApps.set([.init(id: "com.strava.stravaride", name: "Strava Run", user: true)])
        XCTAssertNil(store.icon("Strava"), "the kept icon went with the name")
        XCTAssertTrue(store.icon("Strava Run") === red)
    }

    func testALaunchByNameFallsBackToTheCachedAppList() {
        let noInstalledEditions: (String) -> Bool = { _ in false }
        XCTAssertEqual(KnownApps.launchID("Bilibili", isInstalled: noInstalledEditions), "tv.danmaku.bilianime", "no app list yet: the known app's own id")
        DynamicApps.set([.init(id: "com.bilibili.inter", name: "bilibili", user: true), strava])
        XCTAssertEqual(KnownApps.launchID("哔哩哔哩", isInstalled: noInstalledEditions), "com.bilibili.inter", "the cached edition is international")
        XCTAssertEqual(KnownApps.launchID("Strava"), "com.strava.stravaride")
        XCTAssertEqual(KnownApps.launchID("com.strava.stravaride"), "com.strava.stravaride")
        XCTAssertNil(KnownApps.launchID("Nonesuch"))
    }

    func testALaunchByNamePrefersTheInstalledEditionToTheCachedEdition() {
        let mainland = "tv.danmaku.bilianime"
        let international = "com.bilibili.inter"

        for (cached, installed) in [(international, mainland), (mainland, international)] {
            DynamicApps.set([.init(id: cached, name: "Bilibili", user: true)])
            XCTAssertEqual(KnownApps.launchID("Bilibili", isInstalled: { $0 == installed }), installed)
        }
    }

    func testAnExplicitBundleIDKeepsTheRequestedEdition() {
        let mainland = "tv.danmaku.bilianime"
        let international = "com.bilibili.inter"
        DynamicApps.set([.init(id: international, name: "Bilibili", user: true)])
        XCTAssertEqual(KnownApps.launchID(mainland), mainland)

        DynamicApps.set([.init(id: mainland, name: "哔哩哔哩", user: true)])
        XCTAssertEqual(KnownApps.launchID(international), international)
    }

    func testANameWithDotsIsAnAppBeforeItIsAnID() {
        XCTAssertNil(AppIconStore.bundleID("A.B.C"), "initials with dots are not a bundle id")
        XCTAssertNil(AppIconStore.bundleID("U.S.A"))
        XCTAssertEqual(AppIconStore.bundleID("com.tencent.xin"), "com.tencent.xin")
        XCTAssertEqual(AppIconStore.bundleID("com.example.new-app"), "com.example.new-app")
        DynamicApps.set([.init(id: "com.example.abc", name: "A.B.C", user: true)])
        XCTAssertEqual(AppIconStore.bundleID("A.B.C"), "com.example.abc", "an installed app's name comes first")
    }

    func testAnAccentedNameIsAWordOfItsOwn() {
        DynamicApps.set([.init(id: "com.example.cafe", name: "Café", user: true), strava])
        XCTAssertEqual(capsules("Open Café and order"), ["com.example.cafe"])
        XCTAssertEqual(capsules("Café"), ["com.example.cafe"])
        XCTAssertEqual(capsules("two Cafés nearby"), [], "not inside a longer word")
        XCTAssertEqual(capsules("open café"), [], "an unlisted name counts only as written")
        XCTAssertEqual(capsules("Stravaé"), [], "an accented letter ends no word")
    }

    func testInstalledUserAppsBecomeCapsulesCarefully() {
        DynamicApps.set([strava, chagee, .init(id: "com.apple.PrintCenter", name: "Print Center", user: false)])
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])
        XCTAssertEqual(capsules("open strava"), [], "an unlisted Latin name counts only as written")
        XCTAssertEqual(capsules("打开霸王茶姬点一杯"), ["com.chagee.application.cn"])
        XCTAssertEqual(capsules("我想喝霸王茶姬"), [], "an unlisted Chinese name only where an app goes")
        XCTAssertEqual(capsules("Print Center is slow"), [], "system apps are not capsules")
        XCTAssertEqual(capsules("打开淘宝"), ["com.taobao.taobao4iphone"], "KnownApps capsules stay")
        DynamicApps.set([])
        XCTAssertEqual(capsules("Open Strava and log my run"), [], "the table follows the list")
    }

    /// A name two installed apps share makes no capsule, whichever the phone lists first; the app
    /// beside them with a name of its own still does.
    func testANameTwoAppsShareMakesNoCapsuleInEitherOrder() {
        let other = DynamicApps.Entry(id: "com.example.strava", name: "Strava", user: true)
        for list in [[strava, other, chagee], [other, strava, chagee], [chagee, other, strava]] {
            DynamicApps.set(list)
            XCTAssertEqual(capsules("Open Strava and log my run"), [], "\(list.map(\.id))")
            XCTAssertEqual(capsules("打开霸王茶姬点一杯"), ["com.chagee.application.cn"], "\(list.map(\.id))")
        }
        // A system app with the same name takes the name away too.
        DynamicApps.set([strava, .init(id: "com.apple.strava", name: "Strava", user: false)])
        XCTAssertEqual(capsules("Open Strava and log my run"), [])
        DynamicApps.set([strava])
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])
    }

    /// The signer's answer, as it comes over the bridge, is decoded, reaches the names and capsules,
    /// tells the icons, and is kept in the file a later launch reads. A wrong key for the name or the
    /// type, a list that is never published, or icons that are never told, fails here.
    func testTheSignersAnswerReachesTheNamesTheCapsulesTheIconsAndTheFile() async throws {
        let answer = Data(#"{"v":{"apps":[{"id":"com.strava.stravaride","name":"Strava","bundle_name":"StravaRide","type":"User"},{"id":"com.apple.PrintCenter","bundle_name":"Print Center","type":"System"}]}}"#.utf8)
        var asked: [String: Any] = [:]
        let apps = InstalledApps()
        apps.phone = { ["device_address": "10.7.0.1"] }
        apps.call = { request in asked = request; return answer }
        let told = expectation(forNotification: AppIconStore.changed, object: AppIconStore.shared)
        let drawnBefore = AppIconStore.shared.arrivals
        let inventory = await apps.list()
        await fulfillment(of: [told], timeout: 1)
        XCTAssertGreaterThan(AppIconStore.shared.arrivals, drawnBefore, "the views that drew a placeholder draw again")
        XCTAssertEqual(asked["op"] as? String, "apps")
        XCTAssertEqual(asked["device_address"] as? String, "10.7.0.1")
        XCTAssertEqual(inventory?.apps, [.init(id: "com.strava.stravaride", name: "Strava", bundleName: "StravaRide", type: "User"),
                                         .init(id: "com.apple.PrintCenter", name: nil, bundleName: "Print Center", type: "System")])
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride")
        XCTAssertEqual(AppName.display("com.apple.PrintCenter"), "Print Center", "the bundle's name where there is no display name")
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"], "a User app is a capsule")
        XCTAssertEqual(capsules("Print Center is slow"), [], "a System app is not")

        // The file holds the same list, stays out of backups, and a later launch publishes from it.
        let file = InstalledApps.cacheFile
        let saved = try JSONDecoder().decode([InstalledApps.App].self, from: Data(contentsOf: file))
        XCTAssertEqual(saved, inventory?.apps)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        DynamicApps.set([])
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        _ = InstalledApps()
        XCTAssertEqual(capsules("Open Strava and log my run"), ["com.strava.stravaride"])

        // A second read fills the same file in place and it is still out of backups.
        apps.now = { Date().addingTimeInterval(600) }
        _ = await apps.list()
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        // Kept for 30 days: a file 29 days old is read, one 31 days old is removed unread.
        let day: TimeInterval = 86_400
        DynamicApps.set([])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-29 * day)], ofItemAtPath: file.path)
        _ = InstalledApps()
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride")
        DynamicApps.set([])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-31 * day)], ofItemAtPath: file.path)
        _ = InstalledApps()
        XCTAssertNil(AppIconStore.bundleID("Strava"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testLiveCoreLaunchRefusesUninstalledBundleIDsAndAllowsDynamicAppsAndExplicitBundleObjects() async {
        let savedAppNames = UserDefaults.standard.object(forKey: SpeedOptions.appNamesKey)
        UserDefaults.standard.set(true, forKey: SpeedOptions.appNamesKey)
        defer {
            if let savedAppNames { UserDefaults.standard.set(savedAppNames, forKey: SpeedOptions.appNamesKey) }
            else { UserDefaults.standard.removeObject(forKey: SpeedOptions.appNamesKey) }
        }

        let host = AppCoreHost()
        host.update(runner: .automationReady(revision: 1))
        let transport = LaunchProbeTransport()
        let core = LiveCore(host: host, transport: transport)

        for uninstalled in ["com.xingin.discover", "ctrip.com", "Nonesuch", "tutti.ch"] {
            let refused = await core.callTool("do", arguments: #"{"actions":[{"button":"home"},{"launch":"\#(uninstalled)"}]}"#, localTask: "esp-1274")
            XCTAssertTrue(refused.isError, "\(uninstalled): \(refused.text)")
            XCTAssertTrue(refused.text.contains("no app named \"\(uninstalled)\" is known"), "\(uninstalled): \(refused.text)")
        }
        let mutationsBeforeInstall = await transport.mutatingPaths
        XCTAssertEqual(mutationsBeforeInstall, [], "an uninstalled launch string refuses the whole batch before sending any action")

        let explicitBundleObject = await core.callTool("do", arguments: #"{"actions":[{"launch":{"bundle":"com.not.installed"}}]}"#, localTask: "esp-1274")
        XCTAssertFalse(explicitBundleObject.isError, explicitBundleObject.text)
        let afterBundleObject = await transport.activated
        XCTAssertEqual(afterBundleObject, ["com.not.installed"])

        DynamicApps.set([
            .init(id: "com.xingin.discover", name: "小红书", user: true),
            .init(id: "ctrip.com", name: "携程旅行", user: true),
            strava,
        ], current: true)
        for (input, expected) in [
            ("com.xingin.discover", "com.xingin.discover"),
            ("小红书", "com.xingin.discover"),
            ("ctrip.com", "ctrip.com"),
            ("Strava", "com.strava.stravaride"),
        ] {
            let result = await core.callTool("do", arguments: #"{"actions":[{"launch":"\#(input)"}]}"#, localTask: "esp-1274")
            XCTAssertFalse(result.isError, "\(input): \(result.text)")
            let latest = await transport.activated.last
            XCTAssertEqual(latest, expected, input)
        }

        let wrongCase = await core.callTool("do", arguments: #"{"actions":[{"launch":"COM.XINGIN.DISCOVER"}]}"#, localTask: "esp-1274")
        XCTAssertTrue(wrongCase.isError, wrongCase.text)
        XCTAssertTrue(wrongCase.text.contains("no app named \"COM.XINGIN.DISCOVER\" is known"), wrongCase.text)

        let finalActivated = await transport.activated
        XCTAssertEqual(finalActivated, ["com.not.installed", "com.xingin.discover", "com.xingin.discover", "ctrip.com", "com.strava.stravaride"])
    }

    func testStaleDiskCacheNeverPassesInstalledLaunchPreflight() async throws {
        let savedAppNames = UserDefaults.standard.object(forKey: SpeedOptions.appNamesKey)
        UserDefaults.standard.set(true, forKey: SpeedOptions.appNamesKey)
        defer {
            if let savedAppNames { UserDefaults.standard.set(savedAppNames, forKey: SpeedOptions.appNamesKey) }
            else { UserDefaults.standard.removeObject(forKey: SpeedOptions.appNamesKey) }
        }

        let cachedApps: [InstalledApps.App] = [
            .init(id: "ctrip.com", name: "携程旅行", bundleName: "CtripWireless", type: "User"),
            .init(id: "com.xingin.discover", name: "小红书", bundleName: "discover", type: "User"),
            .init(id: "com.strava.stravaride", name: "Strava", bundleName: "StravaRide", type: "User"),
        ]
        try FileManager.default.createDirectory(at: InstalledApps.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cachedApps).write(to: InstalledApps.cacheFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 86_400)],
            ofItemAtPath: InstalledApps.cacheFile.path
        )

        var clock = Date(timeIntervalSince1970: 2_000_000)
        let apps = InstalledApps()
        apps.now = { clock }
        XCTAssertEqual(AppIconStore.bundleID("Strava"), "com.strava.stravaride", "cached list still backs names and icons")
        XCTAssertEqual(AppName.display("com.strava.stravaride"), "Strava")
        XCTAssertEqual(DynamicApps.name(forID: "ctrip.com"), "携程旅行")

        let host = AppCoreHost()
        host.update(runner: .automationReady(revision: 1))
        let transport = LaunchProbeTransport()
        let core = LiveCore(host: host, transport: transport)

        for stale in ["ctrip.com", "携程旅行", "com.xingin.discover", "小红书", "Strava"] {
            let refused = await core.callTool("do", arguments: #"{"actions":[{"button":"home"},{"launch":"\#(stale)"}]}"#, localTask: "esp-1274")
            XCTAssertTrue(refused.isError, "\(stale): \(refused.text)")
            XCTAssertTrue(refused.text.contains("no app named \"\(stale)\" is known"), "\(stale): \(refused.text)")
        }
        let mutationsFromStaleCache = await transport.mutatingPaths
        XCTAssertEqual(mutationsFromStaleCache, [], "disk-cached apps must not pass launch preflight without current install evidence")

        var fetchCount = 0
        apps.phone = { ["device_address": "10.7.0.1"] }
        apps.call = { _ in
            fetchCount += 1
            if fetchCount > 1 { throw URLError(.timedOut) }
            return try AppLaunchPromptTests.signerAnswer(cachedApps)
        }
        let fresh = await apps.list()
        XCTAssertEqual(fresh?.fresh, true)

        let liveLaunch = await core.callTool("do", arguments: #"{"actions":[{"launch":"ctrip.com"}]}"#, localTask: "esp-1274")
        XCTAssertFalse(liveLaunch.isError, liveLaunch.text)
        let activatedAfterRefresh = await transport.activated
        XCTAssertEqual(activatedAfterRefresh, ["ctrip.com"])

        clock += 600
        let failedRefresh = await apps.list()
        XCTAssertEqual(failedRefresh?.fresh, false)
        XCTAssertEqual(AppName.display("com.strava.stravaride"), "Strava", "failed refresh still keeps display names")

        let mutationsBeforeStaleRetry = await transport.mutatingPaths.count
        let refusedAfterFailedRefresh = await core.callTool("do", arguments: #"{"actions":[{"button":"home"},{"launch":"ctrip.com"}]}"#, localTask: "esp-1274")
        XCTAssertTrue(refusedAfterFailedRefresh.isError, refusedAfterFailedRefresh.text)
        XCTAssertTrue(refusedAfterFailedRefresh.text.contains("no app named \"ctrip.com\" is known"), refusedAfterFailedRefresh.text)
        let mutationsAfterStaleRetry = await transport.mutatingPaths.count
        XCTAssertEqual(mutationsAfterStaleRetry, mutationsBeforeStaleRetry)
    }
}

private actor LaunchProbeTransport: HTTPTransport {
    private(set) var activated: [String] = []
    private(set) var mutatingPaths: [String] = []
    private var foreground = "nz.zheha.poki"

    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        let path = url.path.replacingOccurrences(of: #"^/session/[^/]+"#, with: "", options: .regularExpression)
        if method == "POST", path != "/session" {
            mutatingPaths.append(path)
        }
        let value: JSON
        switch (method, path) {
        case ("POST", "/session"):
            value = ["sessionId": "launch-probe"]
        case ("GET", "/status"):
            value = ["ready": true]
        case ("GET", "/wda/locked"):
            value = false
        case ("GET", "/wda/screen"):
            value = ["screenSize": ["width": 390, "height": 844]]
        case ("GET", "/wda/activeAppInfo"):
            value = ["bundleId": .string(foreground), "name": .string(foreground)]
        case ("GET", "/screenshot"):
            value = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAADklEQVR4nGP4DwYMEAoAU7oL9ZisIGcAAAAASUVORK5CYII="
        case ("GET", "/source"):
            value = .string(#"<AppiumAUT><XCUIElementTypeApplication name="\#(foreground)" label="\#(foreground)" x="0" y="0" width="390" height="844"><XCUIElementTypeButton name="Explore" label="Explore" x="16" y="100" width="358" height="44" /></XCUIElementTypeApplication></AppiumAUT>"#)
        case ("POST", "/wda/apps/activate"), ("POST", "/wda/apps/launch"):
            let bundle = body.flatMap { try? JSON.parse(String(decoding: $0, as: UTF8.self)) }?["bundleId"]?.string ?? ""
            activated.append(bundle)
            foreground = bundle
            value = .null
        default:
            value = .null
        }
        return (200, JSON.object(["value": value]).data())
    }
}
