import XCTest

final class WardrobeCategoryUITests: XCTestCase {
    func testNativeCategoryControlTracksTapsAndPageSwipes() {
        let app = XCUIApplication()
        app.launchArguments += ["-pokiChat", "working", "-AppleLanguages", "(en)",
                                "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()

        let avatar = app.buttons["chat.header.avatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 15))
        avatar.tap()

        let categories = app.segmentedControls["wardrobe.pieces"]
        XCTAssertTrue(categories.waitForExistence(timeout: 10))
        let outfits = categories.buttons.element(boundBy: 2)
        outfits.tap()
        let outfitGrid = app.scrollViews["wardrobe.page.set"]
        XCTAssertTrue(app.buttons["wardrobe.set.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(outfits.isSelected)

        outfitGrid.swipeRight()
        XCTAssertTrue(app.buttons["wardrobe.clothes.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(categories.buttons.element(boundBy: 1).isSelected)
    }
}
