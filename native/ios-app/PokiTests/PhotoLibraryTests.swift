import Photos
import XCTest
@testable import Poki

/// Runs against the simulator's photo library after `simctl privacy grant photos`. The test photo is
/// added with `simctl addmedia`; the test removes only the asset and album it creates.
final class PhotoLibraryTests: XCTestCase {
    func testFindAnAssetExportItSaveItToAnAlbumAndRemoveIt() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized else {
            throw XCTSkip("The photo library is not fully allowed for this test host (status \(status.rawValue)); grant Photos access before running it.")
        }
        let found = await PhotoTools.find("{}")
        XCTAssertFalse(found.isError, found.text)
        let id = try XCTUnwrap(identifier(in: found.text), found.text)

        let exported = await PhotoTools.export(#"{"ids":["\#(id)"]}"#)
        XCTAssertFalse(exported.isError, exported.text)
        let path = try XCTUnwrap(filePath(in: exported.text), exported.text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let album = "Poki Native Tools Test \(UUID().uuidString.prefix(6))"
        let saved = await PhotoTools.save(#"{"path":"\#(path)","album":"\#(album)","request_id":"photo-test-\#(UUID().uuidString)"}"#)
        XCTAssertFalse(saved.isError, saved.text)
        let savedID = try XCTUnwrap(savedID(in: saved.text), saved.text)
        defer { cleanup(savedID: savedID, album: album) }

        let collection = try XCTUnwrap(albumCollection(named: album))
        let members = PHAsset.fetchAssets(in: collection, options: nil)
        XCTAssertGreaterThan(members.count, 0)
        var foundSaved = false
        members.enumerateObjects { asset, _, _ in
            if asset.localIdentifier == savedID { foundSaved = true }
        }
        XCTAssertTrue(foundSaved, "the saved asset is not in \(album)")
    }

    private func identifier(in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("- ") {
            let rest = line.dropFirst(2)
            if let end = rest.firstIndex(of: " ") { return String(rest[..<end]) }
        }
        return nil
    }

    private func filePath(in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("- /") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private func savedID(in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("id: ") {
            let id = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return id == "unknown" ? nil : id
        }
        return nil
    }

    private func albumCollection(named name: String) -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var found: PHAssetCollection?
        result.enumerateObjects { collection, _, _ in
            if collection.localizedTitle == name { found = collection }
        }
        return found
    }

    private func cleanup(savedID: String, album: String) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [savedID], options: nil)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var collection: PHAssetCollection?
        collections.enumerateObjects { item, _, _ in if item.localizedTitle == album { collection = item } }
        PHPhotoLibrary.shared().performChanges({
            if assets.count > 0 { PHAssetChangeRequest.deleteAssets(assets) }
            if let collection { PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray) }
        }, completionHandler: nil)
    }
}
