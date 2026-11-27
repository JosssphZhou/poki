import XCTest
@testable import Poki

@MainActor
final class SensesSuggestionCancellationTests: XCTestCase {
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
