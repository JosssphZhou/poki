import XCTest
@testable import PokiCore

/// The app a routine is filed under (the Memory page's rows, the brief's "for this app", the app a
/// run launches first): the app its steps work in, not the app the phone was in before its launch.
final class RoutineAppTests: XCTestCase {
    static let wechat = "com.tencent.xin", xiaohongshu = "com.xingin.discover", trains = "cn.12306.rails12306"
    static let poki = "nz.zheha.poki", home = "com.apple.springboard"

    func step(_ action: JSON, in app: String?, target: String? = nil) -> RoutineStep {
        RoutineStep(action: action, target: target.map { RoutineTarget(type: "Button", label: $0) }, app: app, secret: nil)
    }

    // MARK: Worked out from the steps

    /// What 0.4.5 filed under WeChat: the launch was recorded in WeChat, where the task before had
    /// left the phone, and the taps after it are at points, with no element to go by.
    func testALaunchCountsForTheAppItOpensNotTheOneItWasSentFrom() {
        let steps = [step(["launch": .string(Self.xiaohongshu)], in: Self.wechat),
                     step(["tap": [200, 400]], in: Self.xiaohongshu), step(["type": "露营"], in: Self.xiaohongshu)]
        XCTAssertEqual(Routine.workingApp(of: steps), Self.xiaohongshu)
        // A launch given as {bundle}, sent from Poki.
        XCTAssertEqual(Routine.workingApp(of: [step(["launch": ["bundle": .string(Self.trains)]], in: Self.poki), step(["tap": [100, 300]], in: nil)]), Self.trains)
    }

    /// Steps sent in the same do as the launch are recorded in the app before it: the screen was not read in between.
    func testStepsSentWithTheLaunchCountForTheLaunchedApp() {
        let steps = [step(["launch": .string(Self.trains)], in: Self.wechat), step(["wait_until": "查询"], in: Self.wechat),
                     step(["tap": [195, 600]], in: Self.wechat)]
        XCTAssertEqual(Routine.workingApp(of: steps), Self.trains)
    }

    /// Home, then the home screen's search: the swipe and the typing go out before a read, so they are
    /// still recorded in the app Home left; the app the search opens is the routine's.
    func testStepsStillRecordedInTheAppHomeLeftArePassedOver() {
        let steps = [step(["button": "home"], in: Self.wechat), step(["swipe": "down"], in: Self.wechat), step(["type": "小红书"], in: Self.wechat),
                     step(["tap": "@"], in: Self.home, target: "小红书"), step(["tap": [200, 400]], in: Self.xiaohongshu)]
        XCTAssertEqual(Routine.workingApp(of: steps), Self.xiaohongshu)
        // Home and back into the same app by its icon: once a step is recorded on the home screen, the
        // app's own steps count again.
        let back = [step(["button": "home"], in: Self.wechat), step(["tap": "@"], in: Self.home, target: "微信"), step(["tap": "@"], in: Self.wechat, target: "通讯录")]
        XCTAssertEqual(Routine.workingApp(of: back), Self.wechat)
    }

    func testARoutineInOneAppIsThatAppsAndTheHomeScreenAndPokiAreNoAppsAtAll() {
        XCTAssertEqual(Routine.workingApp(of: [step(["tap": "@"], in: "com.apple.Preferences", target: "General"), step(["tap": "@"], in: "com.apple.Preferences", target: "About")]), "com.apple.Preferences")
        // The first step that acts decides: a routine that starts in Contacts and goes on in WeChat is Contacts', as a run starts there.
        XCTAssertEqual(Routine.workingApp(of: [step(["tap": "@"], in: "com.apple.MobileAddressBook", target: "Mama"), step(["launch": .string(Self.wechat)], in: "com.apple.MobileAddressBook")]), "com.apple.MobileAddressBook")
        XCTAssertNil(Routine.workingApp(of: [step(["tap": [10, 10]], in: Self.poki), step(["tap": [10, 10]], in: Self.poki + ".widgets"), step(["swipe": "left"], in: Self.home)]))
        XCTAssertNil(Routine.workingApp(of: [step(["tap": [10, 10]], in: nil)]))
        XCTAssertNil(Routine.workingApp(of: []))
    }

    // MARK: Saved from a task

    /// A phone whose front app the fake follows: a launch or an activate brings that app's screen forward.
    final class Phone: @unchecked Sendable {
        let wda = FakeWDA()
        let front = LockedBox(RoutineAppTests.wechat)
        let screens: [String: [Node]] = [
            RoutineAppTests.wechat: [Node("NavigationBar", "微信", [0, 50, 390, 44]), Node("Button", "通讯录", [100, 780, 80, 40])],
            RoutineAppTests.poki: [Node("StaticText", "Poki", [16, 100, 358, 44])],
            // Drawn in pictures: nothing a step can be named by, so the taps go to points.
            RoutineAppTests.xiaohongshu: [Node("StaticText", "发现", [16, 100, 80, 30])],
        ]
        init() {
            show(RoutineAppTests.wechat)
            wda.set("GET /wda/activeAppInfo") { [self] _ in (200, ["value": ["bundleId": .string(self.front.value)]]) }
            for path in ["POST /wda/apps/launch", "POST /wda/apps/activate"] {
                wda.set(path) { [self] body in
                    if let bundle = body?["bundleId"]?.string { self.show(bundle) }
                    return (200, ["value": .null])
                }
            }
        }
        func show(_ app: String) { front.value = app; wda.tree(screens[app] ?? [], app: app) }
    }

    func number(of label: String, in text: String) -> Int? {
        for line in text.split(separator: "\n") where line.contains("\"\(label)") {
            let digits = line.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
            if let n = Int(digits) { return n }
        }
        return nil
    }

    /// A task in WeChat, then back in Poki a task in Xiaohongshu by points: saved, it is Xiaohongshu's.
    func testATaskSavedAfterOneInAnotherAppIsFiledUnderTheAppItWorkedIn() async throws {
        let store = RoutineStore(url: nil)
        let phone = Phone()
        let (core, _, _) = makeCore(phone.wda) { $0.memory = store }
        let first = await core.call("look", [:])
        let contacts = try XCTUnwrap(number(of: "通讯录", in: first.text), first.text)
        _ = await core.call("do", ["actions": [["tap": .number(Double(contacts))]]])
        _ = await core.finishTask()
        // The owner is back in Poki's chat, where the next task begins; nothing has read the screen since.
        phone.show(Self.poki)

        let launched = await core.call("do", ["actions": [["launch": .string(Self.xiaohongshu)]]])
        XCTAssertFalse(launched.isError, launched.text)
        _ = await core.call("do", ["actions": [["tap": [200, 400]]]])
        _ = await core.call("do", ["actions": [["tap": [195, 120]]]])
        let saved = await core.call("routines", ["action": "save", "name": "搜索露营", "description": "在小红书搜索露营"])
        XCTAssertTrue(saved.text.contains("in \(Self.xiaohongshu)"), saved.text)

        let routine = try XCTUnwrap(store.routine(named: "搜索露营"))
        XCTAssertEqual(routine.steps.first?.app, Self.wechat, "a launch is still recorded where it began")
        XCTAssertEqual(routine.app, Self.xiaohongshu)
    }

    /// A run launches the routine's app first; its steps are recorded in that app, so the task saved
    /// again after the run keeps it. With approvals off, a step at a point is sent without reading the
    /// screen, so the last read is still WeChat's.
    func testARunsStepsAreRecordedInTheAppItLaunchedFirst() async throws {
        let store = RoutineStore(url: nil)
        let phone = Phone()
        let (core, _, _) = makeCore(phone.wda) { $0.memory = store; $0.sensitive.enabled = false }
        let now = Date()
        store.save(Routine(name: "发现页", description: "", app: Self.xiaohongshu, steps: [step(["tap": [200, 400]], in: Self.xiaohongshu)],
                           params: [:], expect: [], read: [], runs: 0, ok: 0, failuresInARow: 0, lastStop: nil, lastMs: nil,
                           savedBy: "Poki", created: now, updated: now))
        _ = await core.call("look", [:])
        let run = await core.call("do", ["actions": [["run": "发现页"]]])
        XCTAssertFalse(run.isError, run.text)
        XCTAssertEqual(phone.front.value, Self.xiaohongshu)
        XCTAssertEqual(core.computer.trace.map(\.step.app), [Self.xiaohongshu])
        _ = await core.call("routines", ["action": "save", "name": "发现页"])
        XCTAssertEqual(store.routine(named: "发现页")?.app, Self.xiaohongshu)
    }

    // MARK: Regrouped on upgrade

    /// A memory file as 0.4.5 wrote it: two skills filed under WeChat that work in Xiaohongshu and
    /// 12306, one that is WeChat's, one on the home screen, and the log's copy of a forgotten one.
    static let fileFrom045 = #"""
    {
      "changes" : [
        { "action" : "forgot", "at" : "2026-11-18T12:00:00Z", "by" : "owner", "id" : "c3", "routineApp" : "com.tencent.xin", "routineName" : "查车票",
          "routine" : { "app" : "com.tencent.xin", "created" : "2026-11-18T10:00:00Z", "description" : "", "expect" : [ ], "failuresInARow" : 0,
                        "name" : "查车票", "ok" : 0, "params" : { }, "read" : [ ], "runs" : 0, "savedBy" : "Poki", "updated" : "2026-11-18T10:00:00Z",
                        "steps" : [ { "action" : { "launch" : "cn.12306.rails12306" }, "app" : "com.tencent.xin" }, { "action" : { "tap" : [ 195, 600 ] }, "app" : "com.tencent.xin" } ] } },
        { "action" : "added", "at" : "2026-11-18T11:00:00Z", "by" : "Poki", "id" : "c2", "routineApp" : "com.tencent.xin", "routineName" : "搜索露营" },
        { "action" : "added", "at" : "2026-11-18T10:00:00Z", "by" : "Poki", "id" : "c1", "routineApp" : "com.tencent.xin", "routineName" : "查车票" }
      ],
      "notes" : [ ],
      "routines" : [
        { "app" : "com.tencent.xin", "created" : "2026-11-18T11:00:00Z", "description" : "在小红书搜索露营", "expect" : [ ], "failuresInARow" : 0,
          "name" : "搜索露营", "ok" : 1, "params" : { }, "read" : [ ], "runs" : 1, "savedBy" : "Poki", "updated" : "2026-11-18T11:00:00Z",
          "steps" : [ { "action" : { "launch" : "com.xingin.discover" }, "app" : "com.tencent.xin" }, { "action" : { "tap" : [ 200, 400 ] }, "app" : "com.xingin.discover" } ] },
        { "app" : "com.tencent.xin", "created" : "2026-11-17T09:00:00Z", "description" : "", "expect" : [ ], "failuresInARow" : 0, "locked" : true,
          "name" : "给妈妈发消息", "ok" : 3, "params" : { }, "read" : [ ], "runs" : 3, "savedBy" : "Poki", "updated" : "2026-11-17T09:00:00Z",
          "steps" : [ { "action" : { "tap" : "@" }, "app" : "com.tencent.xin", "target" : { "label" : "妈妈", "type" : "Cell", "x" : 195, "y" : 200 } } ] },
        { "app" : "com.apple.springboard", "created" : "2026-11-16T09:00:00Z", "description" : "", "expect" : [ ], "failuresInARow" : 0,
          "name" : "翻页", "ok" : 0, "params" : { }, "read" : [ ], "runs" : 0, "savedBy" : "Poki", "updated" : "2026-11-16T09:00:00Z",
          "steps" : [ { "action" : { "swipe" : "left" }, "app" : "com.apple.springboard" } ] }
      ],
      "runs" : [ ],
      "schema" : "poki.agent-backup/1"
    }
    """#

    func testAFileFrom045IsRegroupedOnceWhenItOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poki-memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("agent-memory.json")
        let backup = dir.appendingPathComponent("AgentBackup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data(Self.fileFrom045.utf8).write(to: url)
        // A restore Poki Setup put there and the app has not merged in yet stays as it is.
        let restore = Data(#"{"schema":"poki.agent-backup/1","routines":[],"notes":[],"runs":[]}"#.utf8)
        try restore.write(to: backup.appendingPathComponent(RoutineStore.backupName))

        let store = RoutineStore(url: url, backupDirectory: backup)
        // It was written back once, marked; the backup copy waiting to be merged was left alone.
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(written.contains("\"appRule\" : 1"), written)
        XCTAssertTrue(written.contains("\"app\" : \"com.xingin.discover\""), written)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(RoutineStore.backupName)), restore)

        let apps = Dictionary(uniqueKeysWithValues: store.routines.map { ($0.name, $0.app) })
        XCTAssertEqual(apps["搜索露营"], Self.xiaohongshu)
        XCTAssertEqual(apps["给妈妈发消息"], Self.wechat, "a WeChat skill stays WeChat's")
        XCTAssertEqual(apps["翻页"], .some(nil), "the home screen is no app: Other")
        XCTAssertEqual(store.routine(named: "给妈妈发消息")?.isLocked, true, "nothing else changes")
        XCTAssertEqual(store.routine(named: "搜索露营")?.runs, 1)
        // The log follows: Recent Updates shows the forgotten 12306 skill under 12306, and undo puts it back there.
        let log = Dictionary(uniqueKeysWithValues: store.changes.map { ($0.id, $0) })
        XCTAssertEqual(log["c3"]?.routine?.app, Self.trains)
        XCTAssertEqual(log["c3"]?.routineApp, Self.trains)
        XCTAssertEqual(log["c2"]?.routineApp, Self.xiaohongshu)
        XCTAssertTrue(store.undo("c3"))
        XCTAssertEqual(store.routine(named: "查车票")?.app, Self.trains)

        // Opened again, a file kept by this rule is taken as it is.
        let reopened = RoutineStore(url: url)
        XCTAssertEqual(reopened.routine(named: "搜索露营")?.app, Self.xiaohongshu)
        XCTAssertEqual(reopened.routine(named: "查车票")?.app, Self.trains)
    }

    func testAFileKeptByThisRuleIsNotWorkedOutAgain() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poki-memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("agent-memory.json")
        let kept = Self.fileFrom045.replacingOccurrences(of: #""schema" : "poki.agent-backup/1""#, with: #""schema" : "poki.agent-backup/1", "appRule" : 1"#)
        try Data(kept.utf8).write(to: url)
        let store = RoutineStore(url: url)
        XCTAssertEqual(store.routine(named: "搜索露营")?.app, Self.wechat)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), kept, "not written")
    }

    /// A backup exported by 0.4.5, restored or imported: its skills are regrouped as they come in.
    func testABackupFrom045IsRegroupedWhenImported() throws {
        let store = RoutineStore(url: nil)
        let summary = try store.importData(Data(Self.fileFrom045.utf8), by: "restore")
        XCTAssertTrue(summary.contains("3 routines added"), summary)
        XCTAssertEqual(store.routine(named: "搜索露营")?.app, Self.xiaohongshu)
        XCTAssertEqual(store.routine(named: "给妈妈发消息")?.app, Self.wechat)
        // This version's own export says it is kept by this rule.
        XCTAssertTrue(String(decoding: try store.exportData(), as: UTF8.self).contains("\"appRule\" : 1"))
    }

    /// An agent's edit that replaces the steps files the routine by its new steps.
    func testEditingTheStepsWorksTheAppOutAgain() async throws {
        let store = RoutineStore(url: nil)
        let (core, _, _) = makeCore(FakeWDA()) { $0.memory = store }
        let now = Date()
        store.save(Routine(name: "搜索露营", description: "", app: Self.wechat,
                           steps: [step(["launch": .string(Self.wechat)], in: nil)], params: [:], expect: [], read: [], runs: 0, ok: 0,
                           failuresInARow: 0, lastStop: nil, lastMs: nil, savedBy: "Poki", created: now, updated: now))
        let steps = #"[{"action":{"launch":"com.xingin.discover"},"app":"com.tencent.xin"},{"action":{"tap":[200,400]}}]"#
        let edited = await core.call("routines", ["action": "edit", "name": "搜索露营", "steps": .string(steps)])
        XCTAssertFalse(edited.isError, edited.text)
        XCTAssertEqual(store.routine(named: "搜索露营")?.app, Self.xiaohongshu)
    }
}
