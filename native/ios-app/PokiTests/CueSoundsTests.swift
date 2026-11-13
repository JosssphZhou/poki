import XCTest
@testable import Poki

@MainActor
final class CueSoundsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "cue-sounds-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTaskAndApprovalEventsPlayTheSelectedFilesOnce() {
        let output = RecordingCueOutput()
        let sounds = CueSounds(output: output, defaults: defaults)
        let first = UUID(), second = UUID()
        sounds.taskStarted(first)
        sounds.taskStarted(first)
        sounds.approvalPresented("first-approval")
        sounds.approvalPresented("first-approval")
        sounds.taskEnded(first, succeeded: true)
        sounds.taskEnded(first, succeeded: true)
        sounds.taskStarted(second)
        sounds.taskEnded(second, succeeded: false)
        sounds.taskEnded(second, succeeded: false)
        XCTAssertEqual(output.files, ["start", "notification", "complete", "start", "blocked"])
    }

    func testDisablingSoundsPersistsAndDoesNotReplayMissedEvents() {
        let output = RecordingCueOutput()
        let sounds = CueSounds(output: output, defaults: defaults)
        XCTAssertTrue(sounds.enabled)
        sounds.enabled = false
        let reloaded = CueSounds(output: output, defaults: defaults)
        XCTAssertFalse(reloaded.enabled)
        let task = UUID()
        reloaded.taskStarted(task)
        reloaded.approvalPresented("muted-approval")
        reloaded.taskEnded(task, succeeded: false)
        XCTAssertEqual(output.files, [])
        reloaded.enabled = true
        reloaded.approvalPresented("muted-approval")
        XCTAssertEqual(output.files, [])
        reloaded.approvalPresented("new-approval")
        XCTAssertEqual(output.files, ["notification"])
    }
}

@MainActor
final class RecordingCueOutput: CueSoundOutput {
    private(set) var files: [String] = []
    func play(_ cue: TaskCue) { files.append(cue.rawValue) }
}
