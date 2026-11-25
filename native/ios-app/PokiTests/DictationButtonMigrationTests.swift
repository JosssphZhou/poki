import XCTest
@testable import Poki

/// The dictation microphone is hidden by default, but earlier versions always showed it: the first launch
/// keeps it for someone who used the app before, once, and leaves a fresh install on the default.
@MainActor
final class DictationButtonMigrationTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "DictationButtonMigrationTests"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("DictationButtonMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @MainActor
    func testLatePermissionDenialDoesNotChangeNewRequest() async {
        let model = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let field = FieldDictation()
        var first: CheckedContinuation<Bool, Never>?
        var second: CheckedContinuation<Bool, Never>?
        field.start(model, after: "old", allowed: { await withCheckedContinuation { first = $0 } })
        for _ in 0..<100 where first == nil { await Task.yield() }
        field.stop(model)
        field.start(model, after: "new", allowed: { await withCheckedContinuation { second = $0 } })
        for _ in 0..<100 where second == nil { await Task.yield() }
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        first?.resume(returning: false)
        first = nil
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(field.problem)
        XCTAssertEqual(field.base, "new ")
        field.stop(model)
        second?.resume(returning: false)
    }

    private func launch() { FieldDictation.keepButtonForUpgrade(defaults: defaults, sessionsFolder: folder) }
    private var written: Bool? { defaults.object(forKey: FieldDictation.buttonKey) as? Bool }

    func testFreshInstallKeepsTheButtonHidden() {
        launch()
        XCTAssertNil(written, "nothing is written, so the default (hidden) stands")
    }

    func testSavedConversationsMeanAnUpgrade() throws {
        try Data("{}".utf8).write(to: folder.appendingPathComponent("old-1.json"))
        launch()
        XCTAssertEqual(written, true)
    }

    func testAnEarlierSettingMeansAnUpgradeEvenWithNoConversations() {
        defaults.set(Data([1]), forKey: "setup")
        launch()
        XCTAssertEqual(written, true)
    }

    func testItRunsOnce() throws {
        launch()
        // A fresh install that has since saved a conversation is not mistaken for an upgrade.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("new-1.json"))
        launch()
        XCTAssertNil(written)
    }

    func testAnUpgraderWhoTurnsItOffKeepsItOff() throws {
        try Data("{}".utf8).write(to: folder.appendingPathComponent("old-1.json"))
        launch()
        defaults.set(false, forKey: FieldDictation.buttonKey)
        launch()
        XCTAssertEqual(written, false)
    }

    func testDisabledButtonSurvivesSettingsVaultRestoration() {
        let button = FieldDictation.buttonKey
        let settled = FieldDictation.buttonSettledKey
        var backup: Data?

        defaults.set(false, forKey: button)
        defaults.set(true, forKey: settled)
        defaults.set(Data([1]), forKey: "setup")
        SettingsVault.save(defaults: defaults, read: { backup }, write: { backup = $0 })
        defaults.removeObject(forKey: button)
        defaults.removeObject(forKey: settled)
        defaults.removeObject(forKey: "setup")

        SettingsVault.restore(defaults: defaults, read: { backup })
        XCTAssertEqual(defaults.object(forKey: settled) as? Bool, true)
        XCTAssertEqual(defaults.data(forKey: "setup"), Data([1]))

        launch()
        XCTAssertEqual(written, false)
    }

    func testAChoiceAlreadyMadeIsNotOverwritten() throws {
        try Data("{}".utf8).write(to: folder.appendingPathComponent("old-1.json"))
        defaults.set(false, forKey: FieldDictation.buttonKey)
        launch()
        XCTAssertEqual(written, false)
    }
}
