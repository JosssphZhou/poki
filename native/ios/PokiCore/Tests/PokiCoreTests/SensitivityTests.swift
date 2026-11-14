import XCTest
@testable import PokiCore

final class SensitivityTests: XCTestCase {
    private func reason(_ label: String, type: String = "Button") -> String? {
        SensitivityRules().reason(
            touching: Element(type: type, label: label, value: nil, identifier: nil,
                              frame: Rect(x: 0, y: 0, width: 100, height: 44), depth: 1),
            typing: false, app: Foreground(bundleID: "com.apple.mobilemail", name: "Mail"),
            secureOnScreen: false)
    }

    func testLongActionButtonsStillRequireApproval() {
        for label in ["Complete purchase of 3 items", "Tap here to complete the payment",
                      "Open details and then pay", "Tap here to delete this photo permanently"] {
            XCTAssertNotNil(reason(label), label)
        }
    }

    func testTraditionalChineseActionsRequireApproval() {
        for label in ["購買", "訂閱", "轉賬", "轉帳", "刪除", "還原", "發送", "回覆", "發布", "撥打"] {
            XCTAssertNotNil(reason(label), label)
        }
    }

    func testDescriptiveRowsKeepTheirFalsePositiveGuards() {
        for (type, label) in [("Image", "Contact photo for Best Buy"),
                              ("Cell", "Best Buy, Your order has shipped, Yesterday"),
                              ("Cell", "Tap-here-to-see-this-payment-receipt"),
                              ("Cell", "Tap-here-to-see-the-buy-receipt")] {
            XCTAssertNil(reason(label, type: type), label)
        }
        for label in ["Display & Brightness", "PayPal", "buy1", "1pay", "repayment"] {
            XCTAssertNil(reason(label), label)
        }
    }

    func testLaterWholeWordMatchIsNotHiddenByAnEarlierSubstring() {
        XCTAssertNotNil(reason("Buying help: buy this item now"))
        XCTAssertNotNil(reason("Display details, then pay for this order"))
    }

    func testLongPaymentButtonSendsNothingBeforeApproval() async {
        let wda = FakeWDA()
        wda.source([("Button", "Complete purchase of 3 items")], app: "Shop")
        let (core, _, _) = makeCore(wda) { $0.approvalWait = 0 }
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.text.contains("approval_required"), result.text)
        XCTAssertNotNil(core.pendingApproval)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }
}
