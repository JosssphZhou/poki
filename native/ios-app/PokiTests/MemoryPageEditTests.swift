import PokiCore
import XCTest
@testable import Poki

@MainActor
final class MemoryPageEditTests: XCTestCase {
    func testLibraryRejectsStaleEditorDraftAndReloadsLatestPage() {
        let store = RoutineStore(url: nil)
        store.writePage(app: nil, text: "Original", by: "Poki")
        let library = MemoryLibrary(store: store)
        let original = library.pageForEditing(nil)
        store.writePage(app: nil, text: "Background update", by: "Poki")

        XCTAssertFalse(library.savePageEdit(nil, original: original, text: "Owner draft", locked: true))
        XCTAssertEqual(library.pageLines(nil).map(\.text), ["Background update"])
        XCTAssertFalse(library.pageLocked(nil))
    }

    func testLockOnlySavePreservesBackgroundText() {
        let store = RoutineStore(url: nil)
        store.writePage(app: nil, text: "Original", by: "Poki")
        let library = MemoryLibrary(store: store)
        let original = library.pageForEditing(nil)
        store.writePage(app: nil, text: "Background update", by: "Poki")

        XCTAssertTrue(library.savePageEdit(nil, original: original, text: "Original", locked: true))
        XCTAssertEqual(library.pageLines(nil).map(\.text), ["Background update"])
        XCTAssertTrue(library.pageLocked(nil))
    }
}
