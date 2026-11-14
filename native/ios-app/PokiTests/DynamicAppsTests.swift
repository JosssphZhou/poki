import UIKit
import XCTest
@testable import Poki

/// Apps Poki does not list by name still show with their name and icon once the phone's app list has
/// them: the list's names give the bundle id, the id gives the iPhone's icon or the App Store's.
@MainActor
final class DynamicAppsTests: XCTestCase {
    private let strava = DynamicApps.Entry(id: "com.strava.stravaride", name: "Strava", user: true)
    private let chagee = DynamicApps.Entry(id: "com.chagee.application.cn", name: "霸王茶姬", user: true)

    override func setUp() async throws { DynamicApps.set([]) }
    override func tearDown() async throws { DynamicApps.set([]) }

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

    func testTheIconComesOnceTheListArrives() {
        let red = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        let store = AppIconStore(installed: { id, _ in id == "com.strava.stravaride" ? red : nil })
        XCTAssertNil(store.icon("Strava"), "no id for the name yet")
        DynamicApps.set([strava])
        store.directoryChanged()
        XCTAssertTrue(store.icon("Strava") === red)
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

    func testTheListsTypeAndNameReachTheIndex() async {
        let apps = InstalledApps()
        apps.phone = { [:] }
        apps.fetch = { _ in [.init(id: "com.strava.stravaride", name: "Strava", bundleName: "StravaRide", type: "User")] }
        let list = await apps.list()
        XCTAssertEqual(list?.first?.type, "User")
        XCTAssertNil(DynamicApps.id(forName: "Strava"), "only the shared finder publishes")
    }
}
