import XCTest
import UniformTypeIdentifiers
@testable import Poki

final class ShareInboxTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("poki-share-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testUnpublishedBatchIsInvisibleUntilPublish() throws {
        let id = UUID()
        let folder = try ShareInbox.staging(id, root: root)
        let name = try ShareInbox.store(data: Data("photo".utf8), originalName: "IMG_0001.jpg", type: .jpeg, in: folder)
        let item = ShareInbox.Item(kind: .image, storedName: name, originalName: "IMG_0001.jpg", byteCount: 5)
        let batch = ShareInbox.Batch(id: id, items: [item])
        try ShareInbox.writeManifest(batch, in: folder)
        XCTAssertTrue(ShareInbox.readyBatches(root: root).isEmpty)
        try ShareInbox.publish(id, root: root)
        let ready = try XCTUnwrap(ShareInbox.readyBatches(root: root).first)
        XCTAssertEqual(ready.id, id)
        XCTAssertEqual(ready.items.count, 1)
        let published = try XCTUnwrap(ShareInbox.batch(id, root: root))
        let url = try XCTUnwrap(ShareInbox.fileURL(for: ready.items[0], in: published.folder))
        XCTAssertEqual(try Data(contentsOf: url), Data("photo".utf8))
    }

    func testAMissingFileBlocksPublication() throws {
        let id = UUID()
        let folder = try ShareInbox.staging(id, root: root)
        let batch = ShareInbox.Batch(id: id, items: [
            ShareInbox.Item(kind: .file, storedName: "not-there.txt", originalName: "not-there.txt"),
        ])
        try ShareInbox.writeManifest(batch, in: folder)
        XCTAssertThrowsError(try ShareInbox.publish(id, root: root))
        XCTAssertTrue(ShareInbox.readyBatches(root: root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testClaimHappensOnceAndCanBeRestored() throws {
        let id = UUID()
        let folder = try ShareInbox.staging(id, root: root)
        try ShareInbox.writeManifest(ShareInbox.Batch(id: id, items: []), in: folder)
        try ShareInbox.publish(id, root: root)
        let claimed = try XCTUnwrap(ShareInbox.claim(id, root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimed.path))
        XCTAssertNil(ShareInbox.claim(id, root: root))
        ShareInbox.restore(id, root: root)
        XCTAssertEqual(ShareInbox.readyBatches(root: root).first?.id, id)
    }

    func testPathTraversalAndSymlinksAreRefused() throws {
        let folder = try ShareInbox.staging(UUID(), root: root)
        XCTAssertNil(ShareInbox.contained("../escape", in: folder))
        XCTAssertNil(ShareInbox.contained("/tmp/escape", in: folder))
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        let link = folder.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(ShareInbox.contained("link.txt", in: folder))
        XCTAssertEqual(ShareInbox.safeName("../../etc/passwd"), "passwd")
    }

    func testANameInsideTheFolderIsAccepted() throws {
        let folder = try ShareInbox.staging(UUID(), root: root)
        try Data("inside".utf8).write(to: folder.appendingPathComponent("inside.txt"))
        XCTAssertNotNil(ShareInbox.contained("inside.txt", in: folder))
    }
}
