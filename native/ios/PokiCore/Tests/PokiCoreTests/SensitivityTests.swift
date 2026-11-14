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

    func testShortActionsWithAmountsAndDatedNamesRequireApproval() {
        for label in ["Tap to pay $12.00", "Tap to pay $1,200.00", "Please delete photo-2026-11-14"] {
            for type in ["Text", "Other"] {
                XCTAssertNotNil(reason(label, type: type), label)
            }
        }
    }

    func testNumberedOCRPaymentSendsNothingBeforeApproval() async {
        let (core, wda, host) = makeCore {
            $0.readTimeout = 0.5
            $0.approvalWait = 0
        }
        _ = await core.call("look", [:])
        host.texts.value = [RecognizedText(text: "Tap to pay $1,200.00",
                                          box: Rect(x: 0.25, y: 0.9, width: 0.5, height: 0.05))]
        wda.set("GET /source") { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return (200, ["value": .null])
        }
        let look = await core.call("look", [:])
        XCTAssertTrue(look.text.contains("1 Text"), look.text)
        XCTAssertTrue(look.text.contains("Tap to pay $1,200.00"), look.text)
        let tap = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(tap.text.contains("approval_required"), tap.text)
        XCTAssertNotNil(core.pendingApproval)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }

    func testVoicePaymentClearanceRequiresApproval() async {
        let (core, _, _) = makeCore()
        let clearance = await core.clearTap(on: "Tap to pay $12.00", inApp: "example.shop",
                                           named: "Shop", waiting: 0.2)
        guard case .unanswered = clearance else {
            return XCTFail("Expected a pending approval to time out, got \(clearance)")
        }
        XCTAssertFalse(clearance.mayTap)
        XCTAssertNil(core.pendingApproval)
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
