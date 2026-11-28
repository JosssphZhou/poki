import XCTest
@testable import Poki

@MainActor
final class SensesSuggestionCancellationTests: XCTestCase {
    func testClearingHistoryDiscardsHomeRefreshAndAllowsFreshSuggestions() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = HistoryStore(folder: folder)
        defer { history.close() }
        var displayed: [HomeShortcut] = []
        let started = expectation(description: "Home refresh generating old suggestions")
        var finish: CheckedContinuation<[HomeShortcut], Never>?
        var requests = 0
        let fresh = HomeShortcut(key: "fresh", app: "com.apple.mobilenotes", appName: "Notes",
                                 text: "Fresh suggestion", prompt: "Fresh suggestion")
        let suggestions = SensesSuggestions(enabled: { true }, deliver: { displayed = $0 }, produce: {
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { finish = $0; started.fulfill() }
            }
            return [fresh]
        })
        let capture = HistoryCapture(deletionStore: history, suggestions: suggestions, memoriesCleared: { _ in })
        let old = Task { await suggestions.refresh() }
        await fulfillment(of: [started], timeout: 5)
        history.add(at: Date(), app: "com.apple.mobilenotes", title: "Old", text: "Old evidence")
        await capture.clearEverything()
        let remaining = await history.recent()
        XCTAssertTrue(remaining.isEmpty)
        // A new Home refresh must be able to finish before the old model request returns.
        await suggestions.refresh()
        XCTAssertEqual(displayed, [fresh])
        finish?.resume(returning: [HomeShortcut(key: "old", app: "com.apple.mobilenotes", appName: "Notes",
                                               text: "Old suggestion", prompt: "Old suggestion")])
        await old.value
        XCTAssertEqual(displayed, [fresh], "The late old request must not replace the fresh Home suggestion")
        XCTAssertEqual(requests, 2)
    }

    func testCancelledRefreshDoesNotDeliverLateSuggestions() async {
        var displayed: [HomeShortcut] = []
        let started = expectation(description: "Suggestion generation suspended")
        var finish: CheckedContinuation<[HomeShortcut], Never>?
        let suggestions = SensesSuggestions(enabled: { true }, deliver: { displayed = $0 }, produce: {
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        })
        let refresh = Task { await suggestions.refresh() }
        await fulfillment(of: [started], timeout: 5)
        refresh.cancel()
        finish?.resume(returning: [HomeShortcut(key: "gardening", app: "com.apple.mobilenotes",
                                               appName: "Notes", text: "Read gardening notes", prompt: "Read gardening notes")])
        await refresh.value
        XCTAssertTrue(displayed.isEmpty)
    }

    func testClearAllowsFreshSuggestionsWithoutWaitingForThrottle() async {
        var displayed: [HomeShortcut] = []
        var requests = 0
        let pill = HomeShortcut(key: "gardening", app: "com.apple.mobilenotes", appName: "Notes",
                                text: "Read gardening notes", prompt: "Read gardening notes")
        let suggestions = SensesSuggestions(enabled: { true }, deliver: { displayed = $0 }, produce: {
            requests += 1
            return [pill]
        })
        await suggestions.refresh()
        XCTAssertEqual(displayed, [pill])
        suggestions.clear()
        XCTAssertTrue(displayed.isEmpty)
        await suggestions.refresh()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(displayed, [pill])
    }

    func testClearedRefreshCannotPublishAfterSuggestionsAreEnabledAgain() async {
        var enabled = true
        var displayed: [HomeShortcut] = []
        let started = expectation(description: "Suggestion generation suspended")
        var finish: CheckedContinuation<[HomeShortcut], Never>?
        let suggestions = SensesSuggestions(enabled: { enabled }, deliver: { displayed = $0 }, produce: {
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        })
        let refresh = Task { await suggestions.refresh() }
        await fulfillment(of: [started], timeout: 5)
        enabled = false
        suggestions.clear()
        enabled = true
        finish?.resume(returning: [HomeShortcut(key: "gardening", app: "com.apple.mobilenotes",
                                               appName: "Notes", text: "Read gardening notes", prompt: "Read gardening notes")])
        await refresh.value
        XCTAssertTrue(displayed.isEmpty)
    }
}
