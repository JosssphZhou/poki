import PokiCore
import UIKit
import XCTest
@testable import Poki

final class NativeServicesWDATests: XCTestCase {
    func testNativeCoordinatesRejectOutOfViewportBeforeHID() throws {
        let native = NativeServicesWDA(screen: CGSize(width: 402, height: 874))
        for (x, y) in [(-1.0, 20.0), (402.0, 20.0), (20.0, -1.0), (20.0, 874.0), (Double.nan, 20.0), (20.0, Double.infinity)] {
            let source: JSON = ["type": "pointer", "parameters": ["pointerType": "touch"], "actions": [
                ["type": "pointerMove", "x": .number(x), "y": .number(y)],
                ["type": "pointerDown"], ["type": "pointerUp"],
            ]]
            XCTAssertThrowsError(try native.finger(source), "Invalid point \(x),\(y) must not become an edge tap")
        }
    }

    func testNativeCoordinateRejectionIncludesLaterDragPointsAndInvalidViewports() throws {
        let source: JSON = ["type": "pointer", "parameters": ["pointerType": "touch"], "actions": [
            ["type": "pointerMove", "x": 10, "y": 10], ["type": "pointerDown"],
            ["type": "pointerMove", "x": 402, "y": 20, "duration": 50], ["type": "pointerUp"],
        ]]
        XCTAssertThrowsError(try NativeServicesWDA(screen: CGSize(width: 402, height: 874)).finger(source))
        let tap: JSON = ["type": "pointer", "parameters": ["pointerType": "touch"], "actions": [
            ["type": "pointerMove", "x": 0, "y": 0], ["type": "pointerDown"], ["type": "pointerUp"],
        ]]
        for size in [CGSize.zero, CGSize(width: 1, height: 874), CGSize(width: CGFloat.nan, height: 874)] {
            XCTAssertThrowsError(try NativeServicesWDA(screen: size).finger(tap))
        }
    }

    func testNativeCoordinateEndpointsAndFractionalPositionsRemainSupported() throws {
        let native = NativeServicesWDA(screen: CGSize(width: 402, height: 874))
        let source: JSON = ["type": "pointer", "parameters": ["pointerType": "touch"], "actions": [
            ["type": "pointerMove", "x": 0, "y": 0], ["type": "pointerDown"],
            ["type": "pointerMove", "x": 200.5, "y": 436.5, "duration": 25],
            ["type": "pointerMove", "x": 401, "y": 873, "duration": 25], ["type": "pointerUp"],
        ]]
        let points = try native.finger(source)
        XCTAssertEqual(points[0]["x"] as? Int, 0)
        XCTAssertEqual(points[1]["x"] as? Int, 32768)
        XCTAssertEqual(points[1]["y"] as? Int, 32768)
        XCTAssertEqual(points[2]["x"] as? Int, 65535)
        XCTAssertEqual(points[2]["y"] as? Int, 65535)
    }

    @MainActor
    func testChineseInputVerificationRejectsUnknownAndOtherLanguages() {
        for language in ["zh", "zh-Hans", "zh-Hant", "zh_CN"] {
            XCTAssertTrue(InProcessProbe.isChineseInputLanguage(language))
        }
        let otherLanguages: [String?] = [nil, "", "en-US", "ja-JP", "zhongwen"]
        for language in otherLanguages {
            XCTAssertFalse(InProcessProbe.isChineseInputLanguage(language))
        }
    }

    func testUnicodeEditingPreservesBackspaceCountAndControlOrder() {
        let requests = NativeServicesWDA.typingRequests("\u{8}\u{8}中文\t姓名\n", frequency: 55)
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[0]["text"] as? String, "\u{8}\u{8}")
        XCTAssertEqual(requests[0]["op"] as? String, "type_keys")
        XCTAssertEqual(requests[0]["frequency"] as? Int, 55)
        XCTAssertEqual(requests[1]["text"] as? String, "中文")
        XCTAssertEqual(requests[1]["clear"] as? Bool, false)
        XCTAssertEqual(requests[1]["submit"] as? Bool, false)
        XCTAssertEqual(requests[2]["text"] as? String, "\t")
        XCTAssertEqual(requests[3]["text"] as? String, "姓名")
        XCTAssertEqual(requests[4]["text"] as? String, "\n")
    }

    func testUnicodeRunsStayBatchedAndASCIIKeepsCadence() {
        let unicode = NativeServicesWDA.typingRequests("Hello 中文 👨‍👩‍👧", frequency: nil)
        XCTAssertEqual(unicode.count, 1)
        XCTAssertEqual(unicode[0]["text"] as? String, "Hello 中文 👨‍👩‍👧")
        let ascii = NativeServicesWDA.typingRequests("AbC!?\n", frequency: 120)
        XCTAssertEqual(ascii.count, 1)
        XCTAssertEqual(ascii[0]["frequency"] as? Int, 120)
    }

    func testUnconfirmedPasteIsNotReportedAsSuccessfulTyping() {
        XCTAssertThrowsError(try NativeServicesWDA.checkTypingResult(["isError": true, "instruction": "Read the field before retrying"]))
        XCTAssertNoThrow(try NativeServicesWDA.checkTypingResult(["text_verified": true]))
    }

    func testCompactStatusAndGlyphShareEventColor() {
        var state = PokiState(phase: .idle, headline: "Ready", thumbnailVersion: 0)
        state.event = .init(kind: .started, text: "Started")
        let face = state.face
        guard case .text(_, let tone) = face.compact else { return XCTFail("Expected compact status") }
        XCTAssertEqual(tone, face.tone)
    }

    func testDragVelocityUsesScreenPointsNotHIDCoordinates() {
        let body: JSON = ["fromX": 201, "fromY": 300, "toX": 201, "toY": 480, "velocity": 800]
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(body), 225)
        let diagonal: JSON = ["fromX": 0, "fromY": 0, "toX": 300, "toY": 400, "velocity": 1000]
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(diagonal), 500)
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(nil), 80)
    }

    func testHumanizedPointerActionsKeepEveryPointAndRelativeTime() throws {
        let wda = NativeServicesWDA(screen: CGSize(width: 401, height: 801))
        let source: JSON = [
            "type": "pointer",
            "parameters": ["pointerType": "touch"],
            "actions": [
                ["type": "pointerMove", "duration": 0, "x": 100.25, "y": 200.25],
                ["type": "pointerDown", "button": 0],
                ["type": "pause", "duration": 30],
                ["type": "pointerMove", "duration": 45, "x": 101.75, "y": 201.75],
                ["type": "pointerUp", "button": 0],
            ],
        ]

        let points = try wda.finger(source)

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0]["x"] as? Int, 16_424)
        XCTAssertEqual(points[0]["y"] as? Int, 16_404)
        XCTAssertEqual(points[0]["time_ms"] as? Double, 0)
        XCTAssertEqual(points[1]["x"] as? Int, 16_424)
        XCTAssertEqual(points[1]["time_ms"] as? Double, 30)
        XCTAssertEqual(points[2]["x"] as? Int, 16_671)
        XCTAssertEqual(points[2]["y"] as? Int, 16_527)
        XCTAssertEqual(points[2]["time_ms"] as? Double, 75)
    }
}
