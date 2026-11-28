import AVFoundation
import XCTest
import UIKit
@testable import Poki

@MainActor
final class NativeToolsTests: XCTestCase {
    private struct FakeClipboard: ClipboardSource {
        var hasStrings: Bool
        var hasImages = false
        var string: String?
    }

    override func setUp() async throws {
        SpeechReader.shared.stop()
        PokiBrowser.shared.close()
        UIPasteboard.general.items = []
    }

    override func tearDown() async throws {
        SpeechReader.shared.stop()
        PokiBrowser.shared.close()
        UIPasteboard.general.items = []
    }

    /// Delegate callbacks hop to the main actor in a Task; let those tasks run before asserting.
    private func settleMainActor() async {
        for _ in 0..<10 { await Task.yield() }
    }

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

    func testRefreshHostToolsKeepsNativeToolsWhenAskPokiIsOff() {
        let key = AskPoki.onKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let tools = model.refreshHostTools()
        XCTAssertEqual(Set(tools.map(\.name)), NativeTools.names)
    }

    func testBatteryStatusReportsAPercentageOrAnUnavailableReason() async {
        let answer = await BatteryTools.perform("{}")
        if answer.isError {
            XCTAssertTrue(answer.text.hasPrefix("unavailable: "), answer.text)
        } else {
            XCTAssertTrue(answer.text.contains("%"), answer.text)
        }
    }

    func testBatteryStatusRestoresBatteryMonitoring() async {
        let device = UIDevice.current
        let original = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = false
        defer { device.isBatteryMonitoringEnabled = original }
        _ = await BatteryTools.perform("{}")
        XCTAssertFalse(device.isBatteryMonitoringEnabled)
    }

    func testClipboardReadReturnsCopiedText() async {
        UIPasteboard.general.string = "hello from the owner"
        let answer = await ClipboardTools.perform("{}")
        XCTAssertFalse(answer.isError)
        XCTAssertEqual(answer.text, "clipboard:\nhello from the owner")
    }

    func testClipboardRefusalIsUnavailableRatherThanEmpty() {
        let answer = ClipboardTools.read(FakeClipboard(hasStrings: true, string: nil))
        XCTAssertTrue(answer.isError)
        XCTAssertTrue(answer.text.hasPrefix("unavailable: "), answer.text)
        XCTAssertFalse(answer.text.hasPrefix("empty: "))
    }

    func testClipboardEmptyTextIsEmpty() {
        let answer = ClipboardTools.read(FakeClipboard(hasStrings: true, string: ""))
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.hasPrefix("empty: "), answer.text)
    }

    func testClipboardWithoutTextMentionsAnImage() {
        let answer = ClipboardTools.read(FakeClipboard(hasStrings: false, hasImages: true))
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("image"), answer.text)
    }

    func testReadAloudWithoutTextOrAnOpenPageIsEmpty() async {
        let answer = await SpeechTools.perform("{}")
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("empty:"))
    }

    func testReadAloudStartAndStop() async {
        let start = await SpeechTools.perform(#"{"text":"A short sentence to read aloud."}"#)
        XCTAssertFalse(start.isError, start.text)
        XCTAssertTrue(start.text.contains("reading:"))
        let stop = await SpeechTools.perform(#"{"action":"stop"}"#)
        XCTAssertTrue(stop.text.hasPrefix("stopped:"), stop.text)
    }

    func testReadAloudWhileReadingIsAmbiguous() async {
        let first = await SpeechTools.perform(#"{"text":"\#(String(repeating: "First reading. ", count: 30))"}"#)
        XCTAssertFalse(first.isError, first.text)
        let second = await SpeechTools.perform(#"{"text":"Second reading."}"#)
        XCTAssertTrue(second.text.hasPrefix("ambiguous:"), second.text)
    }

    func testReadAloudRejectsAnUnknownAction() async {
        let answer = await SpeechTools.perform(#"{"action":"dance"}"#)
        XCTAssertTrue(answer.isError)
        XCTAssertTrue(answer.text.hasPrefix("invalid:"), answer.text)
    }

    func testReadAloudRejectsTextOverTheLimit() async {
        let text = String(repeating: "a", count: 100_001)
        let answer = await SpeechTools.perform(#"{"text":"\#(text)"}"#)
        XCTAssertTrue(answer.isError)
        XCTAssertTrue(answer.text.hasPrefix("invalid:"), answer.text)
    }

    func testSpeechStartRejectsWhitespaceOnlyText() {
        let reader = SpeechReader.shared
        XCTAssertFalse(reader.start(.text(title: nil, url: nil, body: " \n\t "), rate: 0.5))
        XCTAssertFalse(reader.isReading)
    }

    func testSpeechCancelStopsTheRead() async throws {
        let reader = SpeechReader.shared
        XCTAssertTrue(reader.start(.text(title: nil, url: nil, body: "A short sentence for the cancellation test."), rate: 0.5))
        let utterance = try XCTUnwrap(reader.activeUtterance)
        reader.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)
        await settleMainActor()
        XCTAssertFalse(reader.isReading)
    }

    func testAStaleCompletionDoesNotAdvanceTheNextReading() async throws {
        let reader = SpeechReader.shared
        XCTAssertTrue(reader.start(.text(title: nil, url: nil, body: "First reading."), rate: 0.5))
        let first = try XCTUnwrap(reader.activeUtterance)
        reader.stop()
        XCTAssertTrue(reader.start(.text(title: nil, url: nil, body: "Second reading."), rate: 0.5))
        let second = try XCTUnwrap(reader.activeUtterance)
        reader.speechSynthesizer(AVSpeechSynthesizer(), didFinish: first)
        await settleMainActor()
        XCTAssertTrue(reader.isReading)
        XCTAssertEqual(reader.activeUtterance.map(ObjectIdentifier.init), ObjectIdentifier(second))
    }
}
