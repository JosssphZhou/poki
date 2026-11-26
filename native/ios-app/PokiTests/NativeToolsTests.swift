import XCTest
import UIKit
@testable import Poki

@MainActor
final class NativeToolsTests: XCTestCase {
    func testEveryNativeToolHasOneValidSchemaAndNoCoreName() throws {
        let names = NativeTools.specs.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "duplicate native tool name")
        let reserved: Set<String> = ["look", "do", "skills", "routines", "status", "screen_history", "ask_poki"]
        XCTAssertTrue(Set(names).isDisjoint(with: reserved))
        for spec in NativeTools.specs {
            XCTAssertFalse(spec.description.isEmpty, spec.name)
            let data = try JSONSerialization.data(withJSONObject: spec.schema)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["type"] as? String, "object", spec.name)
            XCTAssertNotNil(object["properties"] as? [String: Any], spec.name)
        }
        XCTAssertEqual(NativeTools.hostTools().count, NativeTools.specs.count)
        XCTAssertEqual(Set(NativeTools.hostTools().map(\.name)), Set(names))
    }

    func testReadAloudWithoutTextOrAnOpenPageIsEmpty() async {
        let answer = await SpeechTools.perform("{}")
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("empty:"))
    }

    func testClipboardReadReportsEmptyWhenTheClipboardHasNoText() async {
        UIPasteboard.general.items = []
        let answer = await ClipboardTools.perform("{}")
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("empty:"))
    }

    func testBatteryStatusAnswersWithAPercentageOrAnUnavailableReason() async {
        let answer = await BatteryTools.perform("{}")
        if answer.isError {
            XCTAssertTrue(answer.text.hasPrefix("unavailable: "), answer.text)
        } else {
            XCTAssertTrue(answer.text.contains("%"), answer.text)
        }
    }
}
