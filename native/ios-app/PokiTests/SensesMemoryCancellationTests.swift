import XCTest
@testable import Poki

@MainActor
final class SensesMemoryCancellationTests: XCTestCase {
    func testClearDuringReadDoesNotAskModelOrRewriteClearedFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("memories.json")
        let started = expectation(description: "History read suspended")
        var finishRead: CheckedContinuation<[(start: Double, note: BacktapeNote)], Never>?
        var requests = 0
        let memories = SensesMemories(file: file, learning: { true }, readTopics: { _, _ in
            await withCheckedContinuation { continuation in
                finishRead = continuation
                started.fulfill()
            }
        }, ask: { _, _ in requests += 1; return "You grow tomatoes | Gardening on several days" })
        let task = Task { await memories.learnTopics(now: Date()) }
        await fulfillment(of: [started], timeout: 5)
        memories.forgetAll()
        let cleared = try Data(contentsOf: file)
        finishRead?.resume(returning: (0..<4).map { (Double($0), BacktapeNote(title: "Gardening", body: "Tomatoes")) })
        await task.value

        XCTAssertEqual(requests, 0)
        XCTAssertTrue(memories.topics.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), cleared)
    }

    func testNewLearningHonorsForgetAllFloor() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var readFrom: Date?
        let memories = SensesMemories(file: folder.appendingPathComponent("memories.json"), learning: { true },
                                     readTopics: { from, _ in readFrom = from; return [] })
        let beforeClear = Date()
        memories.forgetAll()
        await memories.learnTopics(now: Date())
        XCTAssertGreaterThanOrEqual(readFrom ?? .distantPast, beforeClear)
    }

    func testUninterruptedLearningPersistsTopics() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("memories.json")
        let memories = SensesMemories(file: file, learning: { true }, readTopics: { _, _ in
            (0..<4).map { (Double($0), BacktapeNote(title: "Gardening", body: "Tomatoes")) }
        }, ask: { _, _ in "You grow tomatoes | Gardening on several days" })
        await memories.learnTopics(now: Date())

        XCTAssertEqual(memories.topics.map(\.text), ["You grow tomatoes"])
        let reopened = SensesMemories(file: file, learning: { true })
        XCTAssertEqual(reopened.topics, memories.topics)
    }

    func testClearWhileModelAnswersDoesNotRestoreTopics() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("memories.json")
        let started = expectation(description: "Model request suspended")
        var reply: CheckedContinuation<String?, Never>?
        let memories = SensesMemories(file: file, learning: { true }, readTopics: { _, now in
            (0..<4).map { (now.addingTimeInterval(Double(-$0 * 86400)).timeIntervalSince1970,
                           BacktapeNote(title: "Gardening", body: "You read about growing tomatoes.")) }
        }, ask: { _, _ in
            await withCheckedContinuation { continuation in
                reply = continuation
                started.fulfill()
            }
        })
        let task = Task { await memories.learnTopics(now: Date()) }
        await fulfillment(of: [started], timeout: 5)
        memories.forgetAll()
        let cleared = try Data(contentsOf: file)
        reply?.resume(returning: "You grow tomatoes | Gardening on several days")
        await task.value

        XCTAssertTrue(memories.topics.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), cleared)
    }
}
