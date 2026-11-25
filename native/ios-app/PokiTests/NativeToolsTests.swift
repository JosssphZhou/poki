import XCTest
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

    func testNativeDateParsesLocalAndZonedInput() {
        let local = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = local
        let parsed = NativeDate.parse("2026-11-26 15:00")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(calendar.component(.hour, from: parsed!), 15)
        XCTAssertEqual(calendar.component(.minute, from: parsed!), 0)

        let zoned = NativeDate.parse("2026-11-26T07:00:00Z")
        XCTAssertNotNil(zoned)
        XCTAssertEqual(calendar.component(.hour, from: zoned!), 15)
    }

    func testNextAlarmTimeIsTheNextLocalOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 8, minute: 0))!
        let later = NativeDate.next(hhmm: "07:00", after: now)
        XCTAssertNotNil(later)
        XCTAssertEqual(calendar.component(.day, from: later!), 26)
        let today = NativeDate.next(hhmm: "09:30", after: now)
        XCTAssertEqual(calendar.component(.day, from: today!), 25)
        XCTAssertNil(NativeDate.next(hhmm: "25:00", after: now))
    }

    func testACalendarWriteWithAnEndBeforeItsStartIsRefusedBeforeAnyPermissionPrompt() async {
        let answer = await CalendarTools.createEvent(#"{"title":"Test","start":"2026-11-26 15:00","end":"2026-11-26 14:00"}"#)
        XCTAssertTrue(answer.isError)
        XCTAssertTrue(answer.text.contains("invalid:"))
        XCTAssertFalse(answer.text.contains("permission:"))
    }

    func testAPhotoSaveOutsideTheWorkspaceIsRefused() async {
        let answer = await PhotoTools.save(#"{"path":"/etc/passwd"}"#)
        XCTAssertTrue(answer.isError)
        XCTAssertTrue(answer.text.contains("outside the app's photo workspace"))
    }

    func testReadAloudWithoutTextOrAnOpenPageIsEmpty() async {
        let answer = await SpeechTools.perform("{}")
        XCTAssertFalse(answer.isError)
        XCTAssertTrue(answer.text.contains("empty:"))
    }

    func testWorkspaceContainmentRejectsTraversalAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("poki-native-tests-\(UUID().uuidString)", isDirectory: true)
        let inside = root.appendingPathComponent("inside.txt")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("poki-native-outside-\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("in".utf8).write(to: inside)
        try Data("out".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        XCTAssertTrue(NativeWorkspace.contains(inside, in: root))
        XCTAssertFalse(NativeWorkspace.contains(root.appendingPathComponent("../\(outside.lastPathComponent)"), in: root))
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(NativeWorkspace.contains(link, in: root))
    }

    func testNameChoicePrefersAnExactMatch() {
        let names = ["John Appleseed", "Johnny Doe", "Mary John"]
        XCTAssertEqual(NameChoice.matches(names, query: "John Appleseed"), [0])
        XCTAssertEqual(NameChoice.matches(names, query: "john"), [0, 1, 2])
        XCTAssertTrue(NameChoice.matches(names, query: "").isEmpty)
    }

    func testWriteLedgerRemembersACompletedRequestID() {
        let id = "test-\(UUID().uuidString)"
        XCTAssertNil(WriteLedger.completed(id))
        WriteLedger.record(id, value: "created: one")
        XCTAssertEqual(WriteLedger.completed(id), "created: one")
    }
}
