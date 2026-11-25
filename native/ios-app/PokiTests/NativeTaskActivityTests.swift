import XCTest
@testable import Poki

@MainActor
final class NativeTaskActivityTests: XCTestCase {
    func testFinishedTaskOpensItsConversation() {
        let state = PokiState(phase: .done, headline: "Finished", thumbnailVersion: 0, session: "task-123")
        XCTAssertEqual(state.face.link, ActivityLink.session("task-123"))
    }

    func testAFailedTaskSaysErrorNotDone() {
        let state = PokiState(phase: .done, headline: "Finished", thumbnailVersion: 0, failed: true)
        let face = state.face
        XCTAssertEqual(face.symbol, "xmark.circle.fill")
        XCTAssertEqual(face.content, StatusWord.error.text)
        XCTAssertEqual(face.kicker, StatusWord.error.text)
    }

    func testStoppedTaskAlsoOpensItsConversation() {
        let state = PokiState(phase: .stopped, headline: "Stopped", thumbnailVersion: 0, session: "task-456")
        XCTAssertEqual(state.face.link, ActivityLink.session("task-456"))
    }

    func testANotificationLinkIsTakenOnce() {
        let url = URL(string: "poki://session/abc")!
        PokiNotificationLink.post(url)
        XCTAssertEqual(PokiNotificationLink.take(), url)
        XCTAssertNil(PokiNotificationLink.take())
    }
}
