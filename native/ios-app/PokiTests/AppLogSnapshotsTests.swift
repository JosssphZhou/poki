import XCTest
@testable import Poki

final class AppLogSnapshotsTests: XCTestCase {
    func testClearCannotBeOverwrittenByAnOlderSnapshot() async throws {
        try await checkLastSnapshot("")
    }

    func testNewLinesCannotBeOverwrittenByAnOlderSnapshot() async throws {
        try await checkLastSnapshot("old line\nnew line")
    }

    private func checkLastSnapshot(_ latest: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("log.txt")
        let oldStarted = DispatchSemaphore(value: 0)
        let newWritten = DispatchSemaphore(value: 0)
        let saved = expectation(description: "Both snapshots finished writing")
        saved.expectedFulfillmentCount = 2
        let writer = AppLogSnapshots { text, file in
            if text == "old line" {
                oldStarted.signal()
                // With concurrent writes the newer snapshot finishes first. With serial writes
                // this bounded wait expires, then the newer snapshot runs after the old one.
                _ = newWritten.wait(timeout: .now() + 1)
            }
            try? text.write(to: file, atomically: true, encoding: .utf8)
            if text == latest { newWritten.signal() }
        }
        writer.save("old line", to: file) { saved.fulfill() }
        XCTAssertEqual(oldStarted.wait(timeout: .now() + 5), .success)
        writer.save(latest, to: file) { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 10)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), latest)
    }
}
