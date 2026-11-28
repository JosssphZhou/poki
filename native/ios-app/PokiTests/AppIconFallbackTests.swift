import UIKit
import XCTest
@testable import Poki

/// When this iPhone gives no usable icon for an installed app, the app's carried icon shows, never the
/// placeholder; an app's other edition counts as installed. The owner's phone has Taobao, yet 0.3.1 (863)
/// showed its pill with the placeholder.
@MainActor
final class AppIconFallbackTests: XCTestCase {
    private func picture(_ color: UIColor?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format).image { context in
            if let color { color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 60)) }
        }
    }

    private func carried(_ file: String) -> Data? {
        Bundle.main.path(forResource: file, ofType: "png").flatMap { UIImage(contentsOfFile: $0)?.cgImage?.dataProvider?.data as Data? }
    }

    func testAnEmptyInstalledIconFallsBackToTheCarriedOne() {
        let empty = picture(nil)
        let store = AppIconStore(installed: { _, _ in empty })
        for app in KnownApps.all {
            guard let file = app.icon else { continue }
            let shown = store.icon(app.id)?.cgImage?.dataProvider?.data as Data?
            XCTAssertNotNil(shown, app.english)
            XCTAssertEqual(shown, carried(file), "\(app.english) shows the carried \(file).png")
        }
    }

    func testAnInstalledIconStillComesFirst() {
        let red = picture(.red)
        XCTAssertTrue(AppIconStore(installed: { id, _ in id == "com.taobao.taobao4iphone" ? red : nil }).icon("淘宝") === red)
    }

    func testAnotherEditionOfAnAppCountsAsInstalled() {
        let red = picture(.red)
        let store = AppIconStore(installed: { id, _ in id == "com.bilibili.inter" ? red : nil })
        XCTAssertTrue(store.icon("哔哩哔哩") === red)
        XCTAssertTrue(store.icon("bilibili") === red)
    }

    func testLookupDoesNotCacheArtworkUnderAReassignedDisplayName() async {
        let oldID = "test.poki." + UUID().uuidString
        let newID = "test.poki." + UUID().uuidString
        let name = "Icon Test App"
        let oldEntry = DynamicApps.Entry(id: oldID, name: name, user: true)
        let newEntry = DynamicApps.Entry(id: newID, name: name, user: true)
        let stale = picture(.red)
        let installed = picture(.green)
        DynamicApps.set([oldEntry])
        defer {
            DynamicApps.set([])
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: cache.appendingPathComponent("AppIcons/\(oldID).png"))
        }
        let store = AppIconStore(installed: { id, _ in id == newID ? installed : nil })
        XCTAssertNil(store.icon(name))

        await store.load(name) { id in
            XCTAssertEqual(id, oldID)
            DynamicApps.set([newEntry])
            store.directoryChanged()
            return .found(stale)
        }

        XCTAssertTrue(store.icon(name) === installed)
        XCTAssertNotNil(store.icon(oldID), "Artwork is still cached for the original bundle ID")
    }
}
